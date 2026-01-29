-- which-key.nvim integration for vim-jira

local M = {}

--- Check if which-key is available and return version info
---@return boolean available
---@return string|nil version "v2", "v3", or nil
function M.is_available()
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return false, nil
  end

  -- v3 has wk.add(), v2 only has wk.register()
  if type(wk.add) == "function" then
    return true, "v3"
  elseif type(wk.register) == "function" then
    return true, "v2"
  end

  return false, nil
end

--- Register mappings with which-key
---@param mappings table[] Array of {key, desc, fn} tables
function M.register(mappings)
  local config = require("jira.config")
  local wk_opts = config.options.which_key

  -- Check if which-key integration is enabled
  if not wk_opts.enabled then
    return
  end

  local available, version = M.is_available()
  if not available then
    return
  end

  local wk = require("which-key")
  local prefix = config.options.keys.prefix

  if version == "v3" then
    M._register_v3(wk, mappings, prefix, wk_opts)
  else
    M._register_v2(wk, mappings, prefix, wk_opts)
  end
end

--- Register using which-key v3 API
---@param wk table which-key module
---@param mappings table[] mappings array
---@param prefix string key prefix
---@param opts table which_key config options
function M._register_v3(wk, mappings, prefix, opts)
  local specs = {}

  -- Add group definition
  local group_spec = { prefix, group = opts.group_name }
  if opts.icon and opts.icon ~= "" then
    group_spec.icon = opts.icon
  end
  table.insert(specs, group_spec)

  -- Add individual mappings
  for _, mapping in ipairs(mappings) do
    table.insert(specs, {
      prefix .. mapping.key,
      desc = mapping.desc,
    })
  end

  wk.add(specs)
end

--- Register using which-key v2 API
---@param wk table which-key module
---@param mappings table[] mappings array
---@param prefix string key prefix
---@param opts table which_key config options
function M._register_v2(wk, mappings, prefix, opts)
  local specs = {}

  -- Add group definition with + prefix convention
  local group_name = "+" .. opts.group_name
  if opts.icon and opts.icon ~= "" then
    group_name = opts.icon .. " " .. group_name
  end
  specs[prefix] = { name = group_name }

  -- Add individual mappings
  for _, mapping in ipairs(mappings) do
    specs[prefix .. mapping.key] = { mapping.desc }
  end

  wk.register(specs)
end

return M
