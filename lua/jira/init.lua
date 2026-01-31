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

  vim.api.nvim_create_user_command("JiraFields", function(cmd_opts)
    local filter = cmd_opts.args ~= "" and cmd_opts.args:lower() or nil
    M.show_fields(filter)
  end, {
    desc = "Browse JIRA fields (optional filter argument)",
    nargs = "?",
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

--- Show JIRA fields in a Telescope picker
---@param filter string|nil optional filter to pre-filter fields by name
function M.show_fields(filter)
  local client = require("jira.client")

  vim.notify("Fetching JIRA fields...", vim.log.levels.INFO)

  client.get_fields(function(success, result)
    if not success then
      vim.notify("Failed to fetch fields: " .. tostring(result), vim.log.levels.ERROR)
      return
    end

    local fields = result or {}

    -- Pre-filter if filter argument provided
    if filter then
      local filtered = {}
      for _, field in ipairs(fields) do
        local name_lower = (field.name or ""):lower()
        if name_lower:find(filter, 1, true) then
          table.insert(filtered, field)
        end
      end
      fields = filtered
    end

    if #fields == 0 then
      vim.notify("No fields found" .. (filter and (" matching '" .. filter .. "'") or ""), vim.log.levels.WARN)
      return
    end

    -- Sort: custom fields first, then alphabetically by name
    table.sort(fields, function(a, b)
      if a.custom ~= b.custom then
        return a.custom
      end
      return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers
      .new({}, {
        prompt_title = "JIRA Fields" .. (filter and (" (filtered: " .. filter .. ")") or ""),
        finder = finders.new_table({
          results = fields,
          entry_maker = function(field)
            local prefix = field.custom and "[custom] " or "[system] "
            local display = prefix .. (field.name or "?") .. "  →  " .. (field.id or "?")
            return {
              value = field,
              display = display,
              ordinal = (field.name or "") .. " " .. (field.id or ""),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          -- Enter: yank field ID to clipboard
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            if selection then
              local field_id = selection.value.id
              vim.fn.setreg("+", field_id)
              vim.fn.setreg('"', field_id)
              actions.close(prompt_bufnr)
              vim.notify("Copied field ID: " .. field_id, vim.log.levels.INFO)
            end
          end)

          -- Ctrl-y: yank field ID without closing
          map("i", "<C-y>", function()
            local selection = action_state.get_selected_entry()
            if selection then
              local field_id = selection.value.id
              vim.fn.setreg("+", field_id)
              vim.fn.setreg('"', field_id)
              vim.notify("Copied: " .. field_id, vim.log.levels.INFO)
            end
          end)

          return true
        end,
      })
      :find()
  end)
end

return M
