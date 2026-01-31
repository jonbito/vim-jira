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
  panel = {
    width = 0.6, -- Width as fraction of screen
    max_height = 0.6, -- Max height as fraction of screen
    border = "rounded", -- Border style
  },
  edit = {
    auto_close = true, -- Auto-close edit buffer after successful save
  },
  -- Custom fields to display in the issue panel
  -- Each entry: { id = "customfield_XXXXX", label = "Display Label", type = "sprint"|"user"|nil }
  -- Use :JiraFields to discover field IDs for your instance
  -- Example:
  --   custom_fields = {
  --     { id = "customfield_10020", label = "Sprint", type = "sprint" },
  --     { id = "customfield_10016", label = "Story Pts" },
  --   },
  custom_fields = {},
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
