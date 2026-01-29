-- vim-jira: Neovim plugin for JIRA integration
-- Entry point

-- Guard against double-loading
if vim.g.loaded_jira then
  return
end
vim.g.loaded_jira = true

-- Initialize the plugin
require("jira").setup()
