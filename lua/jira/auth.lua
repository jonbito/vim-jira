-- Credential management for vim-jira

local M = {}
local config = require("jira.config")

--- Check if credentials file exists
---@return boolean
function M.credentials_exist()
  local path = config.options.credentials_file
  return vim.fn.filereadable(path) == 1
end

--- Load credentials from JSON file
---@return table|nil credentials table or nil on error
---@return string|nil error message if failed
function M.load_credentials()
  local path = config.options.credentials_file

  if not M.credentials_exist() then
    return nil, "Credentials file not found: " .. path
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return nil, "Credentials file is empty"
  end

  local content = table.concat(lines, "\n")
  local ok, creds = pcall(vim.json.decode, content)
  if not ok then
    return nil, "Failed to parse credentials JSON: " .. tostring(creds)
  end

  -- Validate required fields
  if not creds.email or not creds.domain or not creds.api_key then
    return nil, "Credentials file missing required fields (email, domain, api_key)"
  end

  return creds, nil
end

--- Save credentials to JSON file with 600 permissions
---@param creds table credentials to save
---@return boolean success
---@return string|nil error message if failed
function M.save_credentials(creds)
  local path = config.options.credentials_file

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok = vim.fn.mkdir(dir, "p")
    if ok == 0 then
      return false, "Failed to create directory: " .. dir
    end
  end

  -- Encode to JSON
  local ok, json = pcall(vim.json.encode, creds)
  if not ok then
    return false, "Failed to encode credentials: " .. tostring(json)
  end

  -- Write file
  local write_ok = vim.fn.writefile({ json }, path)
  if write_ok ~= 0 then
    return false, "Failed to write credentials file"
  end

  -- Set permissions to 600 (owner read/write only)
  vim.fn.setfperm(path, "rw-------")

  return true, nil
end

--- Trim whitespace from string
---@param s string
---@return string
local function trim(s)
  return s:match("^%s*(.-)%s*$") or s
end

--- Prompt for credentials using vim.ui.input
---@param callback function called with credentials table or nil on cancel
function M.prompt_credentials(callback)
  vim.ui.input({ prompt = "JIRA Email: " }, function(email)
    if not email or email == "" then
      vim.notify("Setup cancelled", vim.log.levels.WARN)
      callback(nil)
      return
    end
    email = trim(email)

    vim.ui.input({ prompt = "JIRA Domain (e.g., company.atlassian.net): " }, function(domain)
      if not domain or domain == "" then
        vim.notify("Setup cancelled", vim.log.levels.WARN)
        callback(nil)
        return
      end

      -- Clean up domain: trim whitespace, remove protocol and trailing slashes
      domain = trim(domain)
      domain = domain:gsub("^https?://", "")
      domain = domain:gsub("/+$", "")

      vim.ui.input({
        prompt = "JIRA API Key: ",
        secret = true, -- Mask input (Neovim 0.9+)
      }, function(api_key)
        if not api_key or api_key == "" then
          vim.notify("Setup cancelled", vim.log.levels.WARN)
          callback(nil)
          return
        end
        api_key = trim(api_key)

        callback({
          email = email,
          domain = domain,
          api_key = api_key,
        })
      end)
    end)
  end)
end

-- Curl exit code descriptions
local curl_errors = {
  [6] = "Could not resolve host. Check the domain name.",
  [7] = "Failed to connect to host. Check network connection.",
  [28] = "Operation timed out.",
  [35] = "SSL connect error.",
  [60] = "SSL certificate problem.",
}

--- Validate credentials against JIRA API
---@param creds table credentials to validate
---@param callback function called with (success: boolean, message: string)
function M.validate_credentials(creds, callback)
  local url = string.format("https://%s/rest/api/%s/myself", creds.domain, config.options.api_version)

  -- Build Basic auth header
  local auth_header = vim.base64.encode(creds.email .. ":" .. creds.api_key)

  local cmd = {
    "curl",
    "-s",
    "-w",
    "\n%{http_code}",
    "-H",
    "Authorization: Basic " .. auth_header,
    "-H",
    "Content-Type: application/json",
    "--max-time",
    tostring(math.floor(config.options.timeout / 1000)),
    url,
  }

  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      vim.schedule(function()
        if exit_code ~= 0 then
          local msg = curl_errors[exit_code] or ("curl error code " .. exit_code)
          if #stderr > 0 then
            msg = msg .. " (" .. table.concat(stderr, " ") .. ")"
          end
          msg = msg .. " [domain: " .. creds.domain .. "]"
          callback(false, msg)
          return
        end

        if #stdout < 1 then
          callback(false, "No response from server")
          return
        end

        -- Last line is HTTP status code
        local status_code = tonumber(stdout[#stdout])
        if not status_code then
          callback(false, "Failed to parse HTTP status code")
          return
        end

        if status_code == 200 then
          -- Parse response to get display name
          local body = table.concat(stdout, "\n", 1, #stdout - 1)
          local ok, data = pcall(vim.json.decode, body)
          if ok and data.displayName then
            callback(true, "Authenticated as: " .. data.displayName)
          else
            callback(true, "Authentication successful")
          end
        elseif status_code == 401 then
          callback(false, "Authentication failed: Invalid email or API key")
        elseif status_code == 403 then
          callback(false, "Access forbidden: Check API key permissions")
        elseif status_code == 404 then
          callback(false, "Domain not found: Check JIRA domain")
        else
          callback(false, "HTTP error: " .. status_code)
        end
      end)
    end,
  })
end

--- Complete interactive setup flow
---@param callback function|nil optional callback when complete
function M.setup_interactive(callback)
  vim.notify("Starting JIRA credential setup...", vim.log.levels.INFO)

  M.prompt_credentials(function(creds)
    if not creds then
      if callback then
        callback(false)
      end
      return
    end

    vim.notify("Validating credentials...", vim.log.levels.INFO)

    M.validate_credentials(creds, function(valid, message)
      if not valid then
        vim.notify("Validation failed: " .. message, vim.log.levels.ERROR)
        if callback then
          callback(false)
        end
        return
      end

      local ok, err = M.save_credentials(creds)
      if not ok then
        vim.notify("Failed to save credentials: " .. err, vim.log.levels.ERROR)
        if callback then
          callback(false)
        end
        return
      end

      vim.notify(message, vim.log.levels.INFO)
      vim.notify("Credentials saved to: " .. config.options.credentials_file, vim.log.levels.INFO)

      if callback then
        callback(true)
      end
    end)
  end)
end

return M
