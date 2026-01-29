-- Configuration defaults for vim-jira

local M = {}

M.defaults = {
  credentials_file = vim.fn.expand("~/.config/vim-jira/credentials.json"),
  api_version = "3",
  timeout = 30000,
  keys = {
    prefix = "<leader>j",
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
