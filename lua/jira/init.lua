-- vim-jira: Neovim plugin for JIRA integration
-- Main module

local M = {}
local config = require("jira.config")
local auth = require("jira.auth")

-- Export submodules
M.client = require("jira.client")
M.telescope = require("jira.telescope")
M.panel = require("jira.panel")

-- Centralized keymapping definitions
local mappings = {
  {
    key = "s",
    desc = "Search issues (JQL)",
    fn = function()
      require("jira.telescope").search_issues()
    end,
  },
  {
    key = "m",
    desc = "My issues",
    fn = function()
      require("jira.telescope").quick_query("m")
    end,
  },
  {
    key = "o",
    desc = "My open issues",
    fn = function()
      require("jira.telescope").quick_query("o")
    end,
  },
  {
    key = "l",
    desc = "Last search",
    fn = function()
      require("jira.telescope").repeat_last()
    end,
  },
}

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

  -- Register keymappings
  local prefix = config.options.keys.prefix
  for _, mapping in ipairs(mappings) do
    vim.keymap.set("n", prefix .. mapping.key, mapping.fn, {
      desc = "JIRA: " .. mapping.desc,
    })
  end

  -- Register with which-key (handles availability internally)
  require("jira.whichkey").register(mappings)
end

return M
