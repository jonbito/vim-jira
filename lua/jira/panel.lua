-- Floating panel for JIRA issue details

local M = {}

local config = require("jira.config")
local auth = require("jira.auth")
local adf = require("jira.adf")
local md_to_adf = require("jira.md_to_adf")
local client = require("jira.client")

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
  -- Handle nil, vim.NIL (JSON null), or missing user
  if not user or user == vim.NIL then
    return "Unassigned"
  end
  return user.displayName or user.name or "Unknown"
end

--- Format a sprint field value
---@param value any sprint field value
---@return string formatted sprint name(s) or "None"
local function format_sprint(value)
  -- Handle nil, vim.NIL (JSON null), or empty
  if not value or value == vim.NIL then
    return "None"
  end

  -- Sprint data is typically an array of sprint objects
  if type(value) == "table" then
    local names = {}
    for _, sprint in ipairs(value) do
      if type(sprint) == "table" and sprint.name then
        -- Show state indicator for active/future sprints
        local name = sprint.name
        if sprint.state == "active" then
          name = name .. " (active)"
        elseif sprint.state == "future" then
          name = name .. " (future)"
        end
        table.insert(names, name)
      elseif type(sprint) == "string" then
        -- Some JIRA instances return sprint as a string
        table.insert(names, sprint)
      end
    end
    if #names > 0 then
      return table.concat(names, ", ")
    end
  elseif type(value) == "string" then
    return value
  end

  return "None"
end

--- Format a user field value
---@param value any user field value
---@return string formatted user name or "None"
local function format_user(value)
  if not value or value == vim.NIL then
    return "None"
  end
  if type(value) == "table" then
    return value.displayName or value.name or "Unknown"
  elseif type(value) == "string" then
    return value
  end
  return "None"
end

--- Format a generic custom field value
---@param value any field value
---@return string formatted value or "None"
local function format_default(value)
  -- Handle nil, vim.NIL (JSON null), or empty
  if value == nil or value == vim.NIL then
    return "None"
  end

  -- Numbers: format as integer if whole, otherwise with decimals
  if type(value) == "number" then
    if value == math.floor(value) then
      return tostring(math.floor(value))
    else
      return string.format("%.1f", value)
    end
  end

  -- Strings: return as-is
  if type(value) == "string" then
    return value ~= "" and value or "None"
  end

  -- Tables with name property (common JIRA pattern)
  if type(value) == "table" then
    if value.name then
      return value.name
    end
    if value.value then
      return tostring(value.value)
    end
    -- Array of values: join them
    if #value > 0 then
      local parts = {}
      for _, v in ipairs(value) do
        if type(v) == "table" and v.name then
          table.insert(parts, v.name)
        elseif type(v) == "string" then
          table.insert(parts, v)
        end
      end
      if #parts > 0 then
        return table.concat(parts, ", ")
      end
    end
  end

  return "None"
end

--- Format a custom field value based on type
---@param value any field value
---@param field_type string|nil field type hint
---@return string formatted value
local function format_custom_field(value, field_type)
  if field_type == "sprint" then
    return format_sprint(value)
  elseif field_type == "user" then
    return format_user(value)
  else
    return format_default(value)
  end
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

  -- Add custom fields from config
  local custom_fields = config.options.custom_fields or {}
  for _, cf in ipairs(custom_fields) do
    if cf.id and cf.label then
      local value = fields[cf.id]
      local formatted = format_custom_field(value, cf.type)
      -- Pad label to align values (12 chars like other fields)
      local label = cf.label .. ":"
      local padding = string.rep(" ", math.max(1, 12 - #label))
      table.insert(lines, "  " .. label .. padding .. formatted)
    end
  end
  table.insert(lines, "")

  -- Dates
  table.insert(lines, "  Created:     " .. format_date(fields.created))
  table.insert(lines, "  Updated:     " .. format_date(fields.updated))
  table.insert(lines, "")

  -- Description
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, "  Description:")
  table.insert(lines, "")

  local desc_lines = adf.to_lines(fields.description)
  if #desc_lines == 0 then
    table.insert(lines, "  (no description)")
  else
    for _, line in ipairs(desc_lines) do
      table.insert(lines, "  " .. line)
    end
  end
  table.insert(lines, "")

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

--- Open edit buffer for description in a new buffer
function M.edit_description()
  if not M._issue then
    vim.notify("No issue to edit", vim.log.levels.WARN)
    return
  end

  -- Store issue data for the edit buffer
  local issue_key = M._issue.key
  local issue = M._issue

  -- Get description as markdown lines
  local desc_lines = adf.to_lines(issue.fields.description)
  if #desc_lines == 0 then
    desc_lines = { "" }
  end

  -- Close the panel first
  M.close()

  -- Create edit buffer
  local edit_bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer content
  vim.api.nvim_buf_set_lines(edit_bufnr, 0, -1, false, desc_lines)

  -- Buffer options - set buftype before opening to avoid write prompts
  vim.bo[edit_bufnr].buftype = "acwrite"
  vim.bo[edit_bufnr].filetype = "markdown"

  -- Set buffer name for display
  vim.api.nvim_buf_set_name(edit_bufnr, "jira://" .. issue_key .. "/description")

  -- Open the buffer in current window BEFORE setting bufhidden
  vim.api.nvim_set_current_buf(edit_bufnr)

  -- Now safe to set bufhidden since buffer is displayed
  vim.bo[edit_bufnr].bufhidden = "wipe"
  vim.bo[edit_bufnr].modified = false

  -- Helper to close edit buffer and reopen panel
  local function close_edit_buffer_and_reopen()
    if not vim.api.nvim_buf_is_valid(edit_bufnr) then
      M.open(issue)
      return
    end
    local alt = vim.fn.bufnr("#")
    if alt ~= -1 and alt ~= edit_bufnr and vim.api.nvim_buf_is_valid(alt) then
      vim.api.nvim_set_current_buf(alt)
    else
      vim.cmd("bprevious")
    end
    -- Reopen panel after switching buffer
    vim.schedule(function()
      M.open(issue)
    end)
  end

  -- Keymap to discard and close
  vim.keymap.set("n", "q", close_edit_buffer_and_reopen, { buffer = edit_bufnr, noremap = true, silent = true })

  -- Intercept :w to submit to JIRA
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = edit_bufnr,
    callback = function()
      -- Get markdown lines from edit buffer
      local lines = vim.api.nvim_buf_get_lines(edit_bufnr, 0, -1, false)

      -- Convert to ADF
      local adf_doc = md_to_adf.from_lines(lines)

      -- Debug: write ADF to temp file for inspection
      local debug_path = vim.fn.stdpath("cache") .. "/jira_adf_debug.json"
      local ok, json = pcall(vim.json.encode, adf_doc)
      if ok then
        local f = io.open(debug_path, "w")
        if f then
          f:write(json)
          f:close()
        end
      end

      -- Show saving indicator
      vim.notify("Saving description for " .. issue_key .. "... (debug: " .. debug_path .. ")", vim.log.levels.INFO)

      -- Update via API
      client.update_issue(issue_key, { description = adf_doc }, function(success, result)
        if success then
          vim.notify("Description updated for " .. issue_key, vim.log.levels.INFO)

          -- Update stored issue data
          issue.fields.description = adf_doc

          -- Mark buffer as not modified
          if vim.api.nvim_buf_is_valid(edit_bufnr) then
            vim.bo[edit_bufnr].modified = false
          end

          -- Auto-close edit buffer if configured
          local opts = config.options.edit or {}
          if opts.auto_close ~= false and vim.api.nvim_buf_is_valid(edit_bufnr) then
            -- Switch to alternate buffer - bufhidden=wipe will auto-delete the edit buffer
            local alt = vim.fn.bufnr("#")
            if alt ~= -1 and alt ~= edit_bufnr and vim.api.nvim_buf_is_valid(alt) then
              vim.api.nvim_set_current_buf(alt)
            else
              vim.cmd("bprevious")
            end
            -- Reopen panel with updated issue
            vim.schedule(function()
              M.open(issue)
            end)
          end
        else
          vim.notify("Failed to update description: " .. tostring(result), vim.log.levels.ERROR)
        end
      end)
    end,
  })

  vim.notify("Editing " .. issue_key .. " description - :w to save, q to discard", vim.log.levels.INFO)
end

--- Open inline prompt to edit summary
function M.edit_summary()
  if not M._issue then
    vim.notify("No issue to edit", vim.log.levels.WARN)
    return
  end

  local issue_key = M._issue.key
  local issue = M._issue
  local current_summary = issue.fields.summary or ""

  -- Use vim.ui.input for single-line summary editing
  vim.ui.input({
    prompt = "Summary: ",
    default = current_summary,
  }, function(new_summary)
    -- User cancelled
    if new_summary == nil then
      return
    end

    -- No change
    if new_summary == current_summary then
      vim.notify("Summary unchanged", vim.log.levels.INFO)
      return
    end

    -- Validate non-empty
    if new_summary == "" then
      vim.notify("Summary cannot be empty", vim.log.levels.WARN)
      return
    end

    vim.notify("Saving summary for " .. issue_key .. "...", vim.log.levels.INFO)

    client.update_issue(issue_key, { summary = new_summary }, function(success, result)
      if success then
        vim.notify("Summary updated for " .. issue_key, vim.log.levels.INFO)
        -- Update stored issue data
        issue.fields.summary = new_summary
        -- Refresh panel display
        M.refresh()
      else
        vim.notify("Failed to update summary: " .. tostring(result), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Change issue status via transition picker
function M.change_status()
  if not M._issue then
    vim.notify("No issue to update", vim.log.levels.WARN)
    return
  end

  local issue_key = M._issue.key
  local issue = M._issue

  vim.notify("Fetching available statuses...", vim.log.levels.INFO)

  client.get_transitions(issue_key, function(success, result)
    if not success then
      vim.notify("Failed to get transitions: " .. tostring(result), vim.log.levels.ERROR)
      return
    end

    local transitions = result.transitions or {}
    local current_status = issue.fields.status and issue.fields.status.name or nil

    -- Build items for picker, excluding current status
    local items = {}
    for _, t in ipairs(transitions) do
      local to_name = t.to and t.to.name or t.name
      if to_name ~= current_status then
        table.insert(items, { id = t.id, name = t.name, to_name = to_name })
      end
    end

    if #items == 0 then
      vim.notify("No status transitions available", vim.log.levels.WARN)
      return
    end

    -- Show picker
    vim.ui.select(items, {
      prompt = "Select status:",
      format_item = function(item)
        return item.name
      end,
    }, function(selected)
      if not selected then
        return
      end

      vim.notify("Changing status to " .. selected.to_name .. "...", vim.log.levels.INFO)

      client.transition_issue(issue_key, selected.id, function(ok, err)
        if ok then
          vim.notify("Status changed to " .. selected.to_name, vim.log.levels.INFO)
          -- Update local issue data
          issue.fields.status = { name = selected.to_name }
          M.refresh()
        else
          vim.notify("Failed to change status: " .. tostring(err), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

--- Change issue assignee via Telescope picker
function M.change_assignee()
  if not M._issue then
    vim.notify("No issue to update", vim.log.levels.WARN)
    return
  end

  local issue_key = M._issue.key
  local issue = M._issue

  vim.notify("Fetching assignable users...", vim.log.levels.INFO)

  client.get_assignable_users(issue_key, nil, function(success, result)
    if not success then
      vim.notify("Failed to get assignable users: " .. tostring(result), vim.log.levels.ERROR)
      return
    end

    local users = result or {}

    -- Build items for Telescope picker
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    -- Create entries with "Unassigned" option first
    local entries = {
      { accountId = nil, displayName = "Unassigned", emailAddress = nil },
    }
    for _, user in ipairs(users) do
      table.insert(entries, user)
    end

    pickers
      .new({}, {
        prompt_title = "Select Assignee for " .. issue_key,
        finder = finders.new_table({
          results = entries,
          entry_maker = function(user)
            local display
            if user.emailAddress then
              display = user.displayName .. " (" .. user.emailAddress .. ")"
            else
              display = user.displayName
            end
            return {
              value = user,
              display = display,
              ordinal = user.displayName .. " " .. (user.emailAddress or ""),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          -- Handle cancel - reopen panel
          local function cancel_and_reopen()
            actions.close(prompt_bufnr)
            vim.schedule(function()
              M.open(issue)
            end)
          end
          map("i", "<Esc>", cancel_and_reopen)
          map("n", "<Esc>", cancel_and_reopen)
          map("n", "q", cancel_and_reopen)
          map("i", "<C-c>", cancel_and_reopen)

          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if not selection then
              vim.schedule(function()
                M.open(issue)
              end)
              return
            end

            local selected_user = selection.value
            local assignee_field

            if selected_user.accountId == nil then
              -- Unassign: set assignee to null
              assignee_field = vim.NIL
              vim.notify("Unassigning " .. issue_key .. "...", vim.log.levels.INFO)
            else
              assignee_field = { accountId = selected_user.accountId }
              vim.notify("Assigning " .. issue_key .. " to " .. selected_user.displayName .. "...", vim.log.levels.INFO)
            end

            client.update_issue(issue_key, { assignee = assignee_field }, function(ok, err)
              if ok then
                if selected_user.accountId == nil then
                  vim.notify("Unassigned " .. issue_key, vim.log.levels.INFO)
                  issue.fields.assignee = nil
                else
                  vim.notify("Assigned " .. issue_key .. " to " .. selected_user.displayName, vim.log.levels.INFO)
                  issue.fields.assignee = {
                    accountId = selected_user.accountId,
                    displayName = selected_user.displayName,
                    emailAddress = selected_user.emailAddress,
                  }
                end
                -- Reopen panel with updated issue
                M.open(issue)
              else
                vim.notify("Failed to change assignee: " .. tostring(err), vim.log.levels.ERROR)
                -- Reopen panel even on failure
                M.open(issue)
              end
            end)
          end)
          return true
        end,
      })
      :find()
  end)
end

--- Change issue priority via picker
function M.change_priority()
  if not M._issue then
    vim.notify("No issue to update", vim.log.levels.WARN)
    return
  end

  local issue_key = M._issue.key
  local issue = M._issue

  vim.notify("Fetching available priorities...", vim.log.levels.INFO)

  client.get_priorities(function(success, result)
    if not success then
      vim.notify("Failed to get priorities: " .. tostring(result), vim.log.levels.ERROR)
      return
    end

    local priorities = result or {}
    if #priorities == 0 then
      vim.notify("No priorities available", vim.log.levels.WARN)
      return
    end

    -- Show picker
    vim.ui.select(priorities, {
      prompt = "Select priority:",
      format_item = function(item)
        return item.name
      end,
    }, function(selected)
      if not selected then
        return
      end

      vim.notify("Changing priority to " .. selected.name .. "...", vim.log.levels.INFO)

      client.update_issue(issue_key, { priority = { id = selected.id } }, function(ok, err)
        if ok then
          vim.notify("Priority changed to " .. selected.name, vim.log.levels.INFO)
          -- Update local issue data
          issue.fields.priority = { id = selected.id, name = selected.name }
          M.refresh()
        else
          vim.notify("Failed to change priority: " .. tostring(err), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

--- Refresh panel content with current issue data
function M.refresh()
  if not M._issue or not M._bufnr or not vim.api.nvim_buf_is_valid(M._bufnr) then
    return
  end

  local content = build_content(M._issue)
  vim.bo[M._bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(M._bufnr, 0, -1, false, content)
  vim.bo[M._bufnr].modifiable = false
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
    footer = " [a]Assignee [p]Priority [S]Summary [d]Desc [s]Status [o]Open [y]URL [Y]Key [q]Close ",
    footer_pos = "center",
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

  -- Edit description
  vim.keymap.set("n", "d", M.edit_description, keymap_opts)

  -- Edit summary
  vim.keymap.set("n", "S", M.edit_summary, keymap_opts)

  -- Change status
  vim.keymap.set("n", "s", M.change_status, keymap_opts)

  -- Change assignee
  vim.keymap.set("n", "a", M.change_assignee, keymap_opts)

  -- Change priority
  vim.keymap.set("n", "p", M.change_priority, keymap_opts)

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
