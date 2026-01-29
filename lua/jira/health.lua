-- Health checks for vim-jira (:checkhealth jira)

local M = {}
local config = require("jira.config")
local auth = require("jira.auth")

function M.check()
  vim.health.start("vim-jira")

  -- Check which-key integration
  local whichkey = require("jira.whichkey")
  local wk_available, wk_version = whichkey.is_available()
  if wk_available then
    vim.health.ok("which-key.nvim detected (" .. wk_version .. ")")
  else
    vim.health.info("which-key.nvim not installed (optional)")
  end

  -- Check curl is installed
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl is installed")
  else
    vim.health.error("curl is not installed", { "Install curl to make API requests" })
  end

  -- Check Neovim version for secret input support
  local version = vim.version()
  local version_str = string.format("%d.%d.%d", version.major, version.minor, version.patch)
  if version.major > 0 or (version.major == 0 and version.minor >= 9) then
    vim.health.ok("Neovim version " .. version_str .. " supports secret input")
  else
    vim.health.warn("Neovim version " .. version_str .. " does not support secret input", {
      "Upgrade to Neovim 0.9+ for masked API key input",
    })
  end

  -- Check credentials file exists
  local creds_path = config.options.credentials_file
  if auth.credentials_exist() then
    vim.health.ok("Credentials file exists: " .. creds_path)

    -- Check file permissions
    local perms = vim.fn.getfperm(creds_path)
    if perms == "rw-------" then
      vim.health.ok("Credentials file has correct permissions (600)")
    else
      vim.health.warn("Credentials file permissions are " .. perms, {
        "Run: chmod 600 " .. creds_path,
      })
    end

    -- Check credentials are valid JSON with required fields
    local creds, err = auth.load_credentials()
    if creds then
      vim.health.ok("Credentials file is valid JSON with required fields")

      -- Validate against API
      vim.health.info("Validating credentials against JIRA API...")

      -- For synchronous health check, we'll do a blocking curl
      local cmd = string.format(
        'curl -s -w "\\n%%{http_code}" -H "Authorization: Basic %s" -H "Content-Type: application/json" --max-time 10 "https://%s/rest/api/%s/myself"',
        vim.base64.encode(creds.email .. ":" .. creds.api_key),
        creds.domain,
        config.options.api_version
      )

      local output = vim.fn.system(cmd)
      local lines = vim.split(output, "\n", { trimempty = true })

      if #lines >= 1 then
        local status_code = tonumber(lines[#lines])
        if status_code == 200 then
          local body = table.concat(lines, "\n", 1, #lines - 1)
          local ok, data = pcall(vim.json.decode, body)
          if ok and data.displayName then
            vim.health.ok("API authentication successful: " .. data.displayName)
          else
            vim.health.ok("API authentication successful")
          end
        elseif status_code == 401 then
          vim.health.error("API authentication failed: Invalid email or API key", {
            "Run :JiraSetup to reconfigure credentials",
          })
        elseif status_code == 403 then
          vim.health.error("API access forbidden", {
            "Check that your API key has the required permissions",
          })
        elseif status_code == 404 then
          vim.health.error("JIRA domain not found: " .. creds.domain, {
            "Run :JiraSetup to reconfigure credentials",
          })
        else
          vim.health.warn("API returned status: " .. (status_code or "unknown"))
        end
      else
        vim.health.warn("Could not validate API credentials", {
          "Check your network connection",
        })
      end
    else
      vim.health.error("Failed to load credentials: " .. err, {
        "Run :JiraSetup to reconfigure credentials",
      })
    end
  else
    vim.health.warn("Credentials file not found: " .. creds_path, {
      "Run :JiraSetup to configure credentials",
    })
  end
end

return M
