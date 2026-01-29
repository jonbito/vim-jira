-- Query history management for vim-jira

local M = {}

local config = require("jira.config")

--- Get history file path (same directory as credentials)
---@return string path to history file
local function get_history_path()
  local creds_path = config.options.credentials_file
  local dir = vim.fn.fnamemodify(creds_path, ":h")
  return dir .. "/history.json"
end

--- Load history from JSON file
---@return table array of JQL strings (most recent first)
function M.load()
  local path = get_history_path()

  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then
    return {}
  end

  local content = table.concat(lines, "\n")
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return {}
  end

  -- Ensure it's an array of strings
  local history = {}
  for _, item in ipairs(data) do
    if type(item) == "string" and item ~= "" then
      table.insert(history, item)
    end
  end

  return history
end

--- Save history to JSON file
---@param history table array of JQL strings
---@return boolean success
function M.save(history)
  local path = get_history_path()

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    local ok = vim.fn.mkdir(dir, "p")
    if ok == 0 then
      return false
    end
  end

  local ok, json = pcall(vim.json.encode, history)
  if not ok then
    return false
  end

  local write_ok = vim.fn.writefile({ json }, path)
  return write_ok == 0
end

--- Add a query to history (deduplicates, moves to top)
---@param jql string JQL query to add
function M.add(jql)
  if not jql or jql == "" then
    return
  end

  local history = M.load()
  local limit = config.options.history_limit or 25

  -- Remove existing occurrence (if any)
  local new_history = { jql }
  for _, item in ipairs(history) do
    if item ~= jql then
      table.insert(new_history, item)
    end
  end

  -- Trim to limit
  while #new_history > limit do
    table.remove(new_history)
  end

  M.save(new_history)
end

--- Get all history entries
---@return table array of JQL strings (most recent first)
function M.get_all()
  return M.load()
end

--- Clear all history
function M.clear()
  M.save({})
end

--- Remove a specific query from history
---@param jql string JQL query to remove
---@return boolean true if removed, false if not found
function M.remove(jql)
  if not jql or jql == "" then
    return false
  end

  local hist = M.load()
  local new_history = {}
  local found = false

  for _, item in ipairs(hist) do
    if item == jql then
      found = true
    else
      table.insert(new_history, item)
    end
  end

  if found then
    M.save(new_history)
  end

  return found
end

return M
