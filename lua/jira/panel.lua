-- Floating panel for JIRA issue details

local M = {}

local config = require("jira.config")
local auth = require("jira.auth")

-- Track current panel state
M._bufnr = nil
M._winnr = nil
M._issue = nil

--- Open URL in browser (cross-platform)
---@param url string URL to open
local function open_url(url)
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = { "open", url }
  elseif vim.fn.has("unix") == 1 then
    cmd = { "xdg-open", url }
  elseif vim.fn.has("win32") == 1 then
    cmd = { "cmd", "/c", "start", "", url }
  else
    vim.notify("Unable to open browser on this platform", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(cmd, { detach = true })
end

--- Build issue URL from credentials and issue key
---@param issue table JIRA issue object
---@return string|nil URL or nil if credentials unavailable
local function build_issue_url(issue)
  local creds = auth.load_credentials()
  if not creds then
    return nil
  end
  return string.format("https://%s/browse/%s", creds.domain, issue.key)
end

--- Format a date string (ISO 8601 to readable format)
---@param iso_date string|nil ISO date string
---@return string formatted date or "N/A"
local function format_date(iso_date)
  if not iso_date then
    return "N/A"
  end
  -- Extract date portion (YYYY-MM-DD)
  local date = iso_date:match("^(%d%d%d%d%-%d%d%-%d%d)")
  return date or iso_date
end

--- Get display name from JIRA user object
---@param user table|nil JIRA user object
---@return string display name or "Unassigned"
local function get_user_name(user)
  if not user then
    return "Unassigned"
  end
  return user.displayName or user.name or "Unknown"
end

--- Build panel content lines
---@param issue table JIRA issue object
---@return table lines array of strings
local function build_content(issue)
  local fields = issue.fields or {}
  local lines = {}

  -- Summary
  table.insert(lines, "")
  table.insert(lines, "  Summary: " .. (fields.summary or "N/A"))
  table.insert(lines, "")

  -- Status, Type, Priority
  local status = fields.status and fields.status.name or "N/A"
  local issue_type = fields.issuetype and fields.issuetype.name or "N/A"
  local priority = fields.priority and fields.priority.name or "N/A"

  table.insert(lines, "  Status:      " .. status)
  table.insert(lines, "  Type:        " .. issue_type)
  table.insert(lines, "  Priority:    " .. priority)
  table.insert(lines, "  Assignee:    " .. get_user_name(fields.assignee))
  table.insert(lines, "")

  -- Dates
  table.insert(lines, "  Created:     " .. format_date(fields.created))
  table.insert(lines, "  Updated:     " .. format_date(fields.updated))
  table.insert(lines, "")

  -- Separator and keybindings hint
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, "  [o] Open  [y] URL  [Y] Key  [q] Close")

  return lines
end

--- Calculate window dimensions
---@return table with width, height, row, col
local function calc_window_dims(content_lines)
  local opts = config.options.panel or {}
  local width_pct = opts.width or 0.6
  local max_height_pct = opts.max_height or 0.6

  local ui = vim.api.nvim_list_uis()[1]
  local screen_width = ui.width
  local screen_height = ui.height

  local width = math.floor(screen_width * width_pct)
  local max_height = math.floor(screen_height * max_height_pct)

  -- Height based on content, capped at max
  local height = math.min(#content_lines + 2, max_height)
  height = math.max(height, 10) -- minimum height

  -- Center the window
  local row = math.floor((screen_height - height) / 2)
  local col = math.floor((screen_width - width) / 2)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

--- Close the panel
function M.close()
  if M._winnr and vim.api.nvim_win_is_valid(M._winnr) then
    vim.api.nvim_win_close(M._winnr, true)
  end
  if M._bufnr and vim.api.nvim_buf_is_valid(M._bufnr) then
    vim.api.nvim_buf_delete(M._bufnr, { force = true })
  end
  M._winnr = nil
  M._bufnr = nil
  M._issue = nil
end

--- Open current issue in browser
function M.open_in_browser()
  if not M._issue then
    vim.notify("No issue to open", vim.log.levels.WARN)
    return
  end

  local url = build_issue_url(M._issue)
  if url then
    open_url(url)
    vim.notify("Opening " .. M._issue.key .. " in browser", vim.log.levels.INFO)
  else
    vim.notify("Failed to build issue URL: credentials not found", vim.log.levels.ERROR)
  end
end

--- Yank current issue URL to clipboard
function M.yank_url()
  if not M._issue then
    vim.notify("No issue to yank", vim.log.levels.WARN)
    return
  end

  local url = build_issue_url(M._issue)
  if url then
    vim.fn.setreg("+", url)
    vim.fn.setreg('"', url)
    vim.notify("Yanked URL: " .. url, vim.log.levels.INFO)
  else
    vim.notify("Failed to build issue URL: credentials not found", vim.log.levels.ERROR)
  end
end

--- Yank current issue key to clipboard
function M.yank_key()
  if not M._issue then
    vim.notify("No issue to yank", vim.log.levels.WARN)
    return
  end

  vim.fn.setreg("+", M._issue.key)
  vim.fn.setreg('"', M._issue.key)
  vim.notify("Yanked key: " .. M._issue.key, vim.log.levels.INFO)
end

--- Open the floating panel for an issue
---@param issue table JIRA issue object
function M.open(issue)
  -- Close existing panel if any
  M.close()

  M._issue = issue
  local content = build_content(issue)
  local dims = calc_window_dims(content)

  -- Create buffer
  M._bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(M._bufnr, 0, -1, false, content)

  -- Buffer options
  vim.bo[M._bufnr].modifiable = false
  vim.bo[M._bufnr].buftype = "nofile"
  vim.bo[M._bufnr].bufhidden = "wipe"
  vim.bo[M._bufnr].filetype = "jira-panel"

  -- Get border style from config
  local opts = config.options.panel or {}
  local border = opts.border or "rounded"

  -- Create floating window
  M._winnr = vim.api.nvim_open_win(M._bufnr, true, {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    row = dims.row,
    col = dims.col,
    style = "minimal",
    border = border,
    title = " " .. issue.key .. " ",
    title_pos = "center",
  })

  -- Window options
  vim.wo[M._winnr].wrap = true
  vim.wo[M._winnr].cursorline = false

  -- Set up keymaps
  local keymap_opts = { buffer = M._bufnr, noremap = true, silent = true }

  -- Close
  vim.keymap.set("n", "q", M.close, keymap_opts)
  vim.keymap.set("n", "<Esc>", M.close, keymap_opts)

  -- Open in browser
  vim.keymap.set("n", "o", M.open_in_browser, keymap_opts)

  -- Yank URL
  vim.keymap.set("n", "y", M.yank_url, keymap_opts)

  -- Yank key
  vim.keymap.set("n", "Y", M.yank_key, keymap_opts)

  -- Auto-close on buffer leave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = M._bufnr,
    once = true,
    callback = function()
      vim.schedule(M.close)
    end,
  })
end

return M
