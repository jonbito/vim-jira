# vim-jira

A Neovim plugin for JIRA integration with JQL-based issue search via Telescope.

## Features

- **JQL Search**: Search issues using JIRA Query Language with live Telescope picker
- **Issue Panel**: Floating panel with issue details, inline editing support
- **Inline Editing**: Edit summary, description, status, assignee, and priority directly from Neovim
- **Query Management**: Save frequently used queries, browse history, quick access keys
- **Custom Fields**: Configure and display custom fields (Sprint, Story Points, etc.)
- **which-key Integration**: Automatic which-key.nvim registration (v2/v3)
- **Async Operations**: Non-blocking API calls via curl

## Requirements

- Neovim 0.9+ (for secret input support)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- curl (for API requests)
- [which-key.nvim](https://github.com/folke/which-key.nvim) (optional)

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/vim-jira",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("jira").setup({
      -- Keymap prefix (default: <leader>j)
      keys = {
        prefix = "<leader>j",
      },

      -- which-key integration
      which_key = {
        enabled = true,
        group_name = "JIRA",
        icon = "",
      },

      -- Default JQL for new queries
      default_jql = "project = MYPROJ ORDER BY updated DESC",

      -- Maximum queries to keep in history
      history_limit = 25,

      -- Quick queries (instant access, no prompt)
      quick_queries = {
        m = { jql = "assignee = currentUser() ORDER BY updated DESC", desc = "My issues" },
        o = { jql = "assignee = currentUser() AND status != Done ORDER BY updated DESC", desc = "My open issues" },
      },

      -- Saved queries (appear in query picker)
      saved_queries = {
        backlog = {
          jql = "project = MYPROJ AND status = Backlog ORDER BY priority DESC",
          desc = "Backlog items by priority",
        },
        sprint = {
          jql = "project = MYPROJ AND sprint in openSprints()",
          desc = "Current sprint issues",
        },
      },

      -- Issue panel settings
      panel = {
        width = 0.6,       -- Width as fraction of screen
        max_height = 0.6,  -- Max height as fraction of screen
        border = "rounded", -- Border style
      },

      -- Edit buffer settings
      edit = {
        auto_close = true, -- Auto-close edit buffer after save
      },

      -- Custom fields to display in issue panel
      -- Use :JiraFields to discover field IDs for your instance
      custom_fields = {
        { id = "customfield_10020", label = "Sprint", type = "sprint" },
        { id = "customfield_10016", label = "Story Pts" },
      },
    })
  end,
}
```

### With [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/vim-jira",
  requires = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("jira").setup({
      -- Keymap prefix (default: <leader>j)
      keys = {
        prefix = "<leader>j",
      },

      -- which-key integration
      which_key = {
        enabled = true,
        group_name = "JIRA",
        icon = "",
      },

      -- Default JQL for new queries
      default_jql = "project = MYPROJ ORDER BY updated DESC",

      -- Maximum queries to keep in history
      history_limit = 25,

      -- Quick queries (instant access, no prompt)
      quick_queries = {
        m = { jql = "assignee = currentUser() ORDER BY updated DESC", desc = "My issues" },
        o = { jql = "assignee = currentUser() AND status != Done ORDER BY updated DESC", desc = "My open issues" },
      },

      -- Saved queries (appear in query picker)
      saved_queries = {
        backlog = {
          jql = "project = MYPROJ AND status = Backlog ORDER BY priority DESC",
          desc = "Backlog items by priority",
        },
        sprint = {
          jql = "project = MYPROJ AND sprint in openSprints()",
          desc = "Current sprint issues",
        },
      },

      -- Issue panel settings
      panel = {
        width = 0.6,       -- Width as fraction of screen
        max_height = 0.6,  -- Max height as fraction of screen
        border = "rounded", -- Border style
      },

      -- Edit buffer settings
      edit = {
        auto_close = true, -- Auto-close edit buffer after save
      },

      -- Custom fields to display in issue panel
      -- Use :JiraFields to discover field IDs for your instance
      custom_fields = {
        { id = "customfield_10020", label = "Sprint", type = "sprint" },
        { id = "customfield_10016", label = "Story Pts" },
      },
    })
  end,
}
```

## Setup

After installation, configure your JIRA credentials:

```vim
:JiraSetup
```

This will prompt for:

1. **JIRA Domain**: Your Atlassian domain (e.g., `yourcompany.atlassian.net`)
2. **Email**: Your JIRA account email
3. **API Key**: Your JIRA API token ([create one here](https://id.atlassian.com/manage-profile/security/api-tokens))

Credentials are stored at `~/.config/vim-jira/credentials.json` with 600 permissions.

Verify setup with:

```vim
:JiraHealth
```

## Commands

| Command                | Description                                              |
| ---------------------- | -------------------------------------------------------- |
| `:JiraSetup`           | Interactive credential configuration with validation     |
| `:JiraHealth`          | Run health checks (credentials, API connection)          |
| `:JiraFields [filter]` | Browse JIRA fields (useful for finding custom field IDs) |

## Keymaps

### Global Keymaps

Default prefix is `<leader>j`. All keymaps work in normal mode.

| Keymap       | Description                               |
| ------------ | ----------------------------------------- |
| `<leader>js` | Search issues (opens query picker)        |
| `<leader>jm` | My issues (quick query, no prompt)        |
| `<leader>jo` | My open issues (quick query, no prompt)   |
| `<leader>jl` | Last search (cached results, no API call) |

### Query Picker

| Key     | Action                    |
| ------- | ------------------------- |
| `<CR>`  | Run selected query        |
| `<C-e>` | Edit query before running |
| `<C-d>` | Delete history entry      |

### Issue Picker

| Key     | Action                      |
| ------- | --------------------------- |
| `<CR>`  | Open issue details panel    |
| `<C-y>` | Yank issue URL to clipboard |
| `<C-k>` | Yank issue key to clipboard |

### Issue Panel

| Key           | Action                             |
| ------------- | ---------------------------------- |
| `q` / `<Esc>` | Close panel                        |
| `o`           | Open issue in browser              |
| `y`           | Yank issue URL                     |
| `Y`           | Yank issue key                     |
| `S`           | Edit summary (inline prompt)       |
| `d`           | Edit description (markdown buffer) |
| `s`           | Change status (transition picker)  |
| `a`           | Change assignee (Telescope picker) |
| `p`           | Change priority (picker)           |

### Field Browser (`:JiraFields`)

| Key     | Action                               |
| ------- | ------------------------------------ |
| `<CR>`  | Copy field ID to clipboard and close |
| `<C-y>` | Copy field ID without closing        |

## Configuration Reference

```lua
require("jira").setup({
  -- Path to credentials file
  credentials_file = vim.fn.expand("~/.config/vim-jira/credentials.json"),

  -- JIRA REST API version
  api_version = "3",

  -- Request timeout in milliseconds
  timeout = 30000,

  -- Default JQL for new query prompt
  default_jql = "",

  -- Maximum queries to store in history
  history_limit = 25,

  -- Named queries for quick access
  saved_queries = {},

  -- Instant-access queries (bound to keys)
  quick_queries = {
    m = { jql = "assignee = currentUser() ORDER BY updated DESC", desc = "My issues" },
    o = { jql = "assignee = currentUser() AND status != Done ORDER BY updated DESC", desc = "My open issues" },
  },

  -- Keymap configuration
  keys = {
    prefix = "<leader>j",
  },

  -- which-key.nvim integration
  which_key = {
    enabled = true,   -- Auto-register if which-key is available
    group_name = "JIRA",
    icon = "",       -- Nerd Font icon (optional)
  },

  -- Floating panel settings
  panel = {
    width = 0.6,       -- Width as fraction of editor
    max_height = 0.6,  -- Maximum height as fraction
    border = "rounded", -- none, single, double, rounded, solid, shadow
  },

  -- Edit buffer settings
  edit = {
    auto_close = true, -- Close edit buffer after successful save
  },

  -- Custom fields to display in issue panel
  -- type: "sprint" | "user" | nil (generic)
  custom_fields = {},
})
```

## Custom Fields

To display custom fields like Sprint or Story Points in the issue panel:

1. Run `:JiraFields` to browse available fields
2. Search for your field and copy its ID (e.g., `customfield_10020`)
3. Add to your config:

```lua
custom_fields = {
  { id = "customfield_10020", label = "Sprint", type = "sprint" },
  { id = "customfield_10016", label = "Story Pts" },
  { id = "customfield_10024", label = "Team Lead", type = "user" },
},
```

**Field types:**

- `sprint`: Formats sprint array with active/future state indicators
- `user`: Formats user objects to display name
- `nil` (default): Generic formatting for strings, numbers, arrays

## Troubleshooting

### Check plugin health

```vim
:checkhealth jira
```

This verifies:

- curl is installed
- Neovim version supports secret input
- Credentials file exists with correct permissions
- API authentication works

### Common issues

**"JIRA credentials not configured"**
Run `:JiraSetup` to configure credentials.

**"API authentication failed"**

- Verify your email is correct
- Generate a new API token at <https://id.atlassian.com/manage-profile/security/api-tokens>
- Ensure your JIRA domain is correct (e.g., `company.atlassian.net`)

**"No issues found"**

- Check your JQL syntax
- Verify you have permission to view the issues
- Try a simpler query like `project = PROJ`

**Telescope not found**
Install [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and ensure it loads before vim-jira.

## License

MIT
