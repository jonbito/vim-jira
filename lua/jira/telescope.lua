-- Telescope integration for vim-jira
-- Provides a Telescope picker for searching JIRA issues via JQL

local M = {}

local config = require("jira.config")
local auth = require("jira.auth")
local client = require("jira.client")

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

--- Open issue in browser
---@param issue table JIRA issue object
function M.open_issue_in_browser(issue)
  local url = build_issue_url(issue)
  if url then
    open_url(url)
    vim.notify("Opening " .. issue.key .. " in browser", vim.log.levels.INFO)
  else
    vim.notify("Failed to build issue URL: credentials not found", vim.log.levels.ERROR)
  end
end

--- Yank issue URL to clipboard
---@param issue table JIRA issue object
function M.yank_issue_url(issue)
  local url = build_issue_url(issue)
  if url then
    vim.fn.setreg("+", url)
    vim.fn.setreg('"', url)
    vim.notify("Yanked URL: " .. url, vim.log.levels.INFO)
  else
    vim.notify("Failed to build issue URL: credentials not found", vim.log.levels.ERROR)
  end
end

--- Yank issue key to clipboard
---@param issue table JIRA issue object
function M.yank_issue_key(issue)
  vim.fn.setreg("+", issue.key)
  vim.fn.setreg('"', issue.key)
  vim.notify("Yanked key: " .. issue.key, vim.log.levels.INFO)
end

--- Display issues in Telescope picker
---@param issues table array of JIRA issue objects
---@param opts table|nil optional Telescope options
function M.show_issues_picker(issues, opts)
  opts = opts or {}

  local ok, telescope = pcall(require, "telescope")
  if not ok then
    vim.notify("Telescope is required for JIRA issue picker", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  -- Create entry displayer with column widths
  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 12 }, -- key
      { width = 12 }, -- type
      { width = 14 }, -- status
      { remaining = true }, -- summary
    },
  })

  local make_display = function(entry)
    return displayer({
      entry.key,
      "[" .. (entry.issue_type or "?") .. "]",
      entry.status or "?",
      entry.summary or "",
    })
  end

  pickers.new(opts, {
    prompt_title = "JIRA Issues",
    finder = finders.new_table({
      results = issues,
      entry_maker = function(issue)
        local fields = issue.fields or {}
        return {
          value = issue,
          display = make_display,
          ordinal = issue.key .. " " .. (fields.summary or ""),
          key = issue.key,
          summary = fields.summary,
          status = fields.status and fields.status.name,
          issue_type = fields.issuetype and fields.issuetype.name,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      -- Default action: open in browser
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          M.open_issue_in_browser(selection.value)
        end
      end)

      -- Ctrl-y: yank URL
      map("i", "<C-y>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          M.yank_issue_url(selection.value)
        end
      end)
      map("n", "<C-y>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          M.yank_issue_url(selection.value)
        end
      end)

      -- Ctrl-k: yank key
      map("i", "<C-k>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          M.yank_issue_key(selection.value)
        end
      end)
      map("n", "<C-k>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          M.yank_issue_key(selection.value)
        end
      end)

      return true
    end,
  }):find()
end

--- Main entry point: prompt for JQL and search issues
---@param opts table|nil optional configuration
---   - jql: string (optional) skip prompt and use this JQL directly
function M.search_issues(opts)
  opts = opts or {}

  -- Check Telescope is available
  local ok = pcall(require, "telescope")
  if not ok then
    vim.notify("Telescope is required for JIRA issue search", vim.log.levels.ERROR)
    return
  end

  -- Check credentials exist
  if not auth.credentials_exist() then
    vim.notify("JIRA credentials not configured. Run :JiraSetup first.", vim.log.levels.ERROR)
    return
  end

  -- If JQL provided directly, skip prompt
  if opts.jql then
    M._do_search(opts.jql, opts)
    return
  end

  -- Prompt for JQL
  local default_jql = config.options.default_jql or ""
  vim.ui.input({
    prompt = "JQL Query: ",
    default = default_jql,
  }, function(jql)
    if not jql or jql == "" then
      vim.notify("Search cancelled", vim.log.levels.WARN)
      return
    end
    M._do_search(jql, opts)
  end)
end

--- Internal: perform the search and show results
---@param jql string JQL query
---@param opts table options
function M._do_search(jql, opts)
  vim.notify("Searching JIRA...", vim.log.levels.INFO)

  client.search_jql_all({ jql = jql, maxResults = 100 }, function(success, result)
    if not success then
      vim.notify("JIRA search failed: " .. tostring(result), vim.log.levels.ERROR)
      return
    end

    local issues = result.issues or {}
    if #issues == 0 then
      vim.notify("No issues found", vim.log.levels.WARN)
      return
    end

    local pages_msg = result.pages and result.pages > 1 and string.format(" (%d pages)", result.pages) or ""
    vim.notify(string.format("Found %d issue(s)%s", #issues, pages_msg), vim.log.levels.INFO)
    M.show_issues_picker(issues, opts)
  end, {
    on_page = function(page_num, page_issues)
      if page_num > 1 then
        vim.notify(string.format("Fetching page %d...", page_num), vim.log.levels.INFO)
      end
    end,
  })
end

return M
