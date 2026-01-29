-- Configuration defaults for vim-jira

local M = {}

M.defaults = {
  credentials_file = vim.fn.expand("~/.config/vim-jira/credentials.json"),
  api_version = "3",
  timeout = 30000,
  default_jql = "", -- Optional default JQL for search prompt
  history_limit = 25, -- Maximum number of queries to store in history
  saved_queries = {}, -- User-defined named queries: { name = { jql = "...", desc = "..." } }
  quick_queries = {
    m = { jql = "assignee = currentUser() ORDER BY updated DESC", desc = "My issues" },
    o = { jql = "assignee = currentUser() AND status != Done ORDER BY updated DESC", desc = "My open issues" },
  },
  keys = {
    prefix = "<leader>j",
  },
  which_key = {
    enabled = true, -- Auto-register with which-key if available
    group_name = "JIRA", -- Group label in popup
    icon = "", -- Optional Nerd Font icon
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
