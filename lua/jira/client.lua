-- JIRA REST API client for vim-jira

local M = {}
local config = require("jira.config")
local auth = require("jira.auth")

-- Curl exit code descriptions (shared with auth module pattern)
local curl_errors = {
  [6] = "Could not resolve host. Check the domain name.",
  [7] = "Failed to connect to host. Check network connection.",
  [28] = "Operation timed out.",
  [35] = "SSL connect error.",
  [60] = "SSL certificate problem.",
}

-- Default fields to return for issue searches
local default_fields = { "summary", "status", "assignee", "priority", "issuetype", "created", "updated", "description" }

--- Build full URL from domain and endpoint
---@param domain string JIRA domain (e.g., "company.atlassian.net")
---@param endpoint string API endpoint (e.g., "/rest/api/3/search/jql")
---@return string url
local function build_url(domain, endpoint)
  return string.format("https://%s%s", domain, endpoint)
end

--- Build Basic auth header value
---@param creds table credentials with email and api_key
---@return string base64 encoded auth header
local function build_auth_header(creds)
  return vim.base64.encode(creds.email .. ":" .. creds.api_key)
end

--- Build curl command for HTTP request
---@param method string HTTP method (GET, POST, etc.)
---@param url string full URL
---@param auth_header string base64 encoded auth
---@param body string|nil JSON body for POST/PUT
---@param timeout number timeout in seconds
---@return table curl command array
local function build_curl_cmd(method, url, auth_header, body, timeout)
  local cmd = {
    "curl",
    "-s",
    "-w", "\n%{http_code}",
    "-X", method,
    "-H", "Authorization: Basic " .. auth_header,
    "-H", "Content-Type: application/json",
    "--max-time", tostring(timeout),
  }

  if body then
    table.insert(cmd, "-d")
    table.insert(cmd, body)
  end

  table.insert(cmd, url)
  return cmd
end

--- Parse response from curl output (body + status code on last line)
---@param stdout table array of output lines
---@return number|nil status_code
---@return string body
local function parse_response(stdout)
  if #stdout < 1 then
    return nil, ""
  end

  local status_code = tonumber(stdout[#stdout])
  local body = table.concat(stdout, "\n", 1, #stdout - 1)
  return status_code, body
end

--- Format JIRA API error response
---@param status_code number HTTP status code
---@param body string response body
---@return string error message
local function format_jira_error(status_code, body)
  -- Try to parse JIRA error format
  local ok, data = pcall(vim.json.decode, body)
  if ok then
    local parts = {}
    if data.errorMessages and #data.errorMessages > 0 then
      table.insert(parts, table.concat(data.errorMessages, "; "))
    end
    if data.errors then
      for field, msg in pairs(data.errors) do
        if type(msg) == "table" then
          -- Handle nested error objects
          table.insert(parts, field .. ": " .. vim.inspect(msg))
        else
          table.insert(parts, field .. ": " .. tostring(msg))
        end
      end
    end
    if data.message then
      table.insert(parts, data.message)
    end
    -- Include error code if present
    if data.error then
      table.insert(parts, "Error: " .. tostring(data.error))
    end
    if #parts > 0 then
      return table.concat(parts, "; ")
    end
  end

  -- Fallback to generic messages
  local messages = {
    [400] = "Bad request: Invalid parameters",
    [401] = "Authentication failed: Invalid email or API key",
    [403] = "Access forbidden: Check API key permissions",
    [404] = "Not found: Check JIRA domain or resource",
    [429] = "Rate limited: Too many requests",
    [500] = "JIRA server error",
    [502] = "Bad gateway",
    [503] = "Service unavailable",
  }

  return messages[status_code] or ("HTTP error: " .. status_code .. " - " .. body:sub(1, 200))
end

--- Core HTTP request function
---@param method string HTTP method
---@param endpoint string API endpoint
---@param opts table options: body (table), timeout (number)
---@param callback function called with (success: boolean, result: table|string)
local function request(method, endpoint, opts, callback)
  opts = opts or {}

  -- Load credentials
  local creds, err = auth.load_credentials()
  if not creds then
    vim.schedule(function()
      callback(false, err or "Failed to load credentials")
    end)
    return
  end

  local url = build_url(creds.domain, endpoint)
  local auth_header = build_auth_header(creds)
  local timeout = math.floor((opts.timeout or config.options.timeout) / 1000)

  -- Encode body if provided
  local body_json = nil
  if opts.body then
    local ok, encoded = pcall(vim.json.encode, opts.body)
    if not ok then
      vim.schedule(function()
        callback(false, "Failed to encode request body: " .. tostring(encoded))
      end)
      return
    end
    body_json = encoded
  end

  local cmd = build_curl_cmd(method, url, auth_header, body_json, timeout)

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
        -- Handle curl errors
        if exit_code ~= 0 then
          local msg = curl_errors[exit_code] or ("curl error code " .. exit_code)
          if #stderr > 0 then
            msg = msg .. " (" .. table.concat(stderr, " ") .. ")"
          end
          msg = msg .. " [domain: " .. creds.domain .. "]"
          callback(false, msg)
          return
        end

        -- Parse response
        local status_code, body = parse_response(stdout)
        if not status_code then
          callback(false, "Failed to parse HTTP status code")
          return
        end

        -- Handle HTTP errors
        if status_code < 200 or status_code >= 300 then
          callback(false, format_jira_error(status_code, body))
          return
        end

        -- Parse successful JSON response
        if body == "" then
          callback(true, {})
          return
        end

        local ok, data = pcall(vim.json.decode, body)
        if not ok then
          callback(false, "Failed to parse response JSON: " .. tostring(data))
          return
        end

        callback(true, data)
      end)
    end,
  })
end

--- Search for issues using JQL
---@param params table search parameters
---   - jql: string (required) JQL query string
---   - fields: table (optional) fields to return, defaults to common fields
---   - maxResults: number (optional) 1-100, default 50
---   - nextPageToken: string (optional) pagination token
---   - fieldsByKeys: boolean (optional) reference fields by keys
---   - expand: string (optional) expand options
---   - properties: table (optional) issue properties to return
---@param callback function called with (success: boolean, result: table|string)
---   On success: result = { issues = {...}, nextPageToken = "...", total = N }
---   On failure: result = "error message"
function M.search_jql(params, callback)
  if not params or not params.jql then
    vim.schedule(function()
      callback(false, "Missing required parameter: jql")
    end)
    return
  end

  local body = {
    jql = params.jql,
    fields = params.fields or default_fields,
    maxResults = params.maxResults or 50,
  }

  -- Optional parameters
  if params.nextPageToken then
    body.nextPageToken = params.nextPageToken
  end
  if params.fieldsByKeys ~= nil then
    body.fieldsByKeys = params.fieldsByKeys
  end
  if params.expand then
    body.expand = params.expand
  end
  if params.properties then
    body.properties = params.properties
  end

  request("POST", "/rest/api/" .. config.options.api_version .. "/search/jql", {
    body = body,
  }, callback)
end

--- Search for all issues matching JQL, fetching all pages
---@param params table search parameters (same as search_jql, but maxResults per page)
---@param callback function called with (success: boolean, result: table|string)
---   On success: result = { issues = {...}, total = N }
---   On failure: result = "error message"
---@param opts table|nil options
---   - max_pages: number (optional) maximum pages to fetch, default unlimited
---   - on_page: function (optional) called with (page_num, issues) for progress
function M.search_jql_all(params, callback, opts)
  opts = opts or {}
  local all_issues = {}
  local page_num = 0
  local max_pages = opts.max_pages

  local function fetch_page(page_token)
    page_num = page_num + 1

    -- Check max pages limit
    if max_pages and page_num > max_pages then
      callback(true, { issues = all_issues, total = #all_issues, pages = page_num - 1 })
      return
    end

    local page_params = vim.tbl_extend("force", {}, params)
    if page_token then
      page_params.nextPageToken = page_token
    end

    M.search_jql(page_params, function(success, result)
      if not success then
        callback(false, result)
        return
      end

      -- Accumulate issues
      if result.issues then
        for _, issue in ipairs(result.issues) do
          table.insert(all_issues, issue)
        end
      end

      -- Progress callback
      if opts.on_page then
        opts.on_page(page_num, result.issues or {})
      end

      -- Check for more pages
      if result.nextPageToken then
        fetch_page(result.nextPageToken)
      else
        callback(true, { issues = all_issues, total = #all_issues, pages = page_num })
      end
    end)
  end

  fetch_page(nil)
end

--- Update an issue's fields
---@param issue_key string JIRA issue key (e.g., "PROJ-123")
---@param fields table fields to update (e.g., { description = adf_doc })
---@param callback function called with (success: boolean, result: table|string)
---   On success: result = {} (empty for 204 No Content)
---   On failure: result = "error message"
function M.update_issue(issue_key, fields, callback)
  if not issue_key or issue_key == "" then
    vim.schedule(function()
      callback(false, "Missing required parameter: issue_key")
    end)
    return
  end

  request("PUT", "/rest/api/" .. config.options.api_version .. "/issue/" .. issue_key, {
    body = { fields = fields },
  }, callback)
end

--- Get available status transitions for an issue
---@param issue_key string JIRA issue key (e.g., "PROJ-123")
---@param callback function called with (success: boolean, result: table|string)
---   On success: result = { transitions = [{ id, name, to = { name } }, ...] }
---   On failure: result = "error message"
function M.get_transitions(issue_key, callback)
  if not issue_key or issue_key == "" then
    vim.schedule(function()
      callback(false, "Missing required parameter: issue_key")
    end)
    return
  end

  request("GET", "/rest/api/" .. config.options.api_version .. "/issue/" .. issue_key .. "/transitions", {}, callback)
end

--- Transition an issue to a new status
---@param issue_key string JIRA issue key (e.g., "PROJ-123")
---@param transition_id string transition ID from get_transitions
---@param callback function called with (success: boolean, result: table|string)
---   On success: result = {} (empty for 204 No Content)
---   On failure: result = "error message"
function M.transition_issue(issue_key, transition_id, callback)
  if not issue_key or issue_key == "" then
    vim.schedule(function()
      callback(false, "Missing required parameter: issue_key")
    end)
    return
  end

  if not transition_id or transition_id == "" then
    vim.schedule(function()
      callback(false, "Missing required parameter: transition_id")
    end)
    return
  end

  request("POST", "/rest/api/" .. config.options.api_version .. "/issue/" .. issue_key .. "/transitions", {
    body = { transition = { id = transition_id } },
  }, callback)
end

--- Get users who can be assigned to an issue
---@param issue_key string JIRA issue key (e.g., "PROJ-123")
---@param query string|nil optional search query to filter users
---@param callback function called with (success: boolean, result: table|string)
---   On success: result = array of user objects { accountId, displayName, emailAddress, ... }
---   On failure: result = "error message"
function M.get_assignable_users(issue_key, query, callback)
  if not issue_key or issue_key == "" then
    vim.schedule(function()
      callback(false, "Missing required parameter: issue_key")
    end)
    return
  end

  local endpoint = "/rest/api/" .. config.options.api_version .. "/user/assignable/search?issueKey=" .. issue_key
  if query and query ~= "" then
    endpoint = endpoint .. "&query=" .. vim.uri_encode(query)
  end

  request("GET", endpoint, {}, callback)
end

return M
