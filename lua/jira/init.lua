-- vim-jira: Neovim plugin for JIRA integration
-- Main module

local M = {}
local config = require("jira.config")
local auth = require("jira.auth")

--- Setup the plugin with user options
---@param opts table|nil user configuration options
function M.setup(opts)
  -- Initialize config
  config.setup(opts)

  -- Register commands
  vim.api.nvim_create_user_command("JiraSetup", function()
    auth.setup_interactive()
  end, {
    desc = "Configure JIRA credentials",
  })

  vim.api.nvim_create_user_command("JiraHealth", function()
    vim.cmd("checkhealth jira")
  end, {
    desc = "Run JIRA health checks",
  })
end

return M
