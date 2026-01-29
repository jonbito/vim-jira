-- Atlassian Document Format (ADF) parser for vim-jira
-- Converts ADF JSON tree structure to plain text lines

local M = {}

-- Maximum recursion depth to prevent infinite loops
local MAX_DEPTH = 20

--- Apply inline formatting marks to text
---@param text string the text content
---@param marks table|nil array of mark objects
---@return string formatted text
local function apply_marks(text, marks)
  if not marks or #marks == 0 then
    return text
  end

  for _, mark in ipairs(marks) do
    local mark_type = mark.type
    if mark_type == "strong" then
      text = "*" .. text .. "*"
    elseif mark_type == "em" then
      text = "_" .. text .. "_"
    elseif mark_type == "code" then
      text = "`" .. text .. "`"
    elseif mark_type == "strike" then
      text = "~" .. text .. "~"
    elseif mark_type == "link" then
      local href = mark.attrs and mark.attrs.href or ""
      if href ~= "" then
        text = text .. " (" .. href .. ")"
      end
    end
    -- Ignore unknown marks
  end

  return text
end

-- Forward declaration for mutual recursion
local render_node

--- Render an array of content nodes
---@param content table|nil array of nodes
---@param ctx table rendering context
---@return table lines array of strings
local function render_content(content, ctx)
  if not content then
    return {}
  end

  local lines = {}
  for _, node in ipairs(content) do
    local node_lines = render_node(node, ctx)
    for _, line in ipairs(node_lines) do
      table.insert(lines, line)
    end
  end
  return lines
end

--- Render inline content (text, mentions, etc.) as a single string
---@param content table|nil array of inline nodes
---@param ctx table rendering context
---@return string concatenated inline text
local function render_inline(content, ctx)
  if not content then
    return ""
  end

  local parts = {}
  for _, node in ipairs(content) do
    if node.type == "text" then
      local text = node.text or ""
      text = apply_marks(text, node.marks)
      table.insert(parts, text)
    elseif node.type == "hardBreak" then
      table.insert(parts, "\n")
    elseif node.type == "mention" then
      local name = node.attrs and node.attrs.text or "@user"
      table.insert(parts, name)
    elseif node.type == "emoji" then
      local shortName = node.attrs and node.attrs.shortName or ":emoji:"
      table.insert(parts, shortName)
    elseif node.type == "inlineCard" then
      local url = node.attrs and node.attrs.url or ""
      table.insert(parts, url)
    else
      -- Try to render unknown inline nodes
      if node.content then
        table.insert(parts, render_inline(node.content, ctx))
      elseif node.text then
        table.insert(parts, node.text)
      end
    end
  end

  return table.concat(parts, "")
end

--- Render a single ADF node
---@param node table ADF node object
---@param ctx table rendering context (depth, list_prefix, indent)
---@return table lines array of strings
render_node = function(node, ctx)
  if not node or type(node) ~= "table" then
    return {}
  end

  ctx = ctx or {}
  local depth = ctx.depth or 0
  local indent = ctx.indent or ""

  -- Prevent infinite recursion
  if depth > MAX_DEPTH then
    return { indent .. "[content truncated: max depth exceeded]" }
  end

  local next_ctx = { depth = depth + 1, indent = indent }
  local node_type = node.type

  -- Document root
  if node_type == "doc" then
    return render_content(node.content, next_ctx)
  end

  -- Paragraph
  if node_type == "paragraph" then
    local text = render_inline(node.content, next_ctx)
    if text == "" then
      return { "" }
    end
    -- Split by newlines from hardBreak
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, indent .. line)
    end
    return lines
  end

  -- Headings
  if node_type == "heading" then
    local level = node.attrs and node.attrs.level or 1
    local prefix = string.rep("#", level) .. " "
    local text = render_inline(node.content, next_ctx)
    return { "", indent .. prefix .. text, "" }
  end

  -- Bullet list
  if node_type == "bulletList" then
    local lines = {}
    if node.content then
      for _, item in ipairs(node.content) do
        local item_ctx = {
          depth = depth + 1,
          indent = indent,
          list_type = "bullet",
        }
        local item_lines = render_node(item, item_ctx)
        for _, line in ipairs(item_lines) do
          table.insert(lines, line)
        end
      end
    end
    return lines
  end

  -- Ordered list
  if node_type == "orderedList" then
    local lines = {}
    if node.content then
      local start = node.attrs and node.attrs.order or 1
      for i, item in ipairs(node.content) do
        local item_ctx = {
          depth = depth + 1,
          indent = indent,
          list_type = "ordered",
          list_index = start + i - 1,
        }
        local item_lines = render_node(item, item_ctx)
        for _, line in ipairs(item_lines) do
          table.insert(lines, line)
        end
      end
    end
    return lines
  end

  -- List item
  if node_type == "listItem" then
    local lines = {}
    local prefix
    if ctx.list_type == "ordered" then
      prefix = tostring(ctx.list_index or 1) .. ". "
    else
      prefix = "- "
    end

    -- Render list item content
    if node.content then
      local first = true
      for _, child in ipairs(node.content) do
        local child_ctx = {
          depth = depth + 1,
          indent = indent .. "   ",
        }
        local child_lines = render_node(child, child_ctx)
        for j, line in ipairs(child_lines) do
          if first and j == 1 then
            -- First line gets the bullet/number prefix
            if line:match("^%s*$") then
              table.insert(lines, indent .. prefix)
            else
              table.insert(lines, indent .. prefix .. line:gsub("^%s+", ""))
            end
            first = false
          else
            table.insert(lines, line)
          end
        end
      end
    end
    return lines
  end

  -- Code block
  if node_type == "codeBlock" then
    local lines = {}
    local lang = node.attrs and node.attrs.language or ""
    table.insert(lines, indent .. "```" .. lang)

    if node.content then
      for _, child in ipairs(node.content) do
        if child.type == "text" then
          -- Preserve code formatting, split by newlines
          local text = child.text or ""
          for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, indent .. line)
          end
          -- Remove trailing empty line added by pattern
          if lines[#lines] == indent then
            table.remove(lines)
          end
        end
      end
    end

    table.insert(lines, indent .. "```")
    return lines
  end

  -- Blockquote
  if node_type == "blockquote" then
    local child_ctx = { depth = depth + 1, indent = indent .. "> " }
    return render_content(node.content, child_ctx)
  end

  -- Rule (horizontal line)
  if node_type == "rule" then
    return { indent .. "---" }
  end

  -- Media/mediaSingle (images, attachments)
  if node_type == "media" or node_type == "mediaSingle" then
    if node.content then
      return render_content(node.content, next_ctx)
    end
    local alt = node.attrs and node.attrs.alt or "[media]"
    return { indent .. alt }
  end

  -- Table
  if node_type == "table" then
    local lines = { "" }
    if node.content then
      for _, row in ipairs(node.content) do
        local row_lines = render_node(row, next_ctx)
        for _, line in ipairs(row_lines) do
          table.insert(lines, line)
        end
      end
    end
    table.insert(lines, "")
    return lines
  end

  -- Table row
  if node_type == "tableRow" then
    local cells = {}
    if node.content then
      for _, cell in ipairs(node.content) do
        local cell_text = render_inline(cell.content, next_ctx)
        table.insert(cells, cell_text)
      end
    end
    return { indent .. "| " .. table.concat(cells, " | ") .. " |" }
  end

  -- Panel (info/warning/error boxes)
  if node_type == "panel" then
    local panel_type = node.attrs and node.attrs.panelType or "info"
    local lines = { indent .. "[" .. panel_type:upper() .. "]" }
    local child_lines = render_content(node.content, next_ctx)
    for _, line in ipairs(child_lines) do
      table.insert(lines, line)
    end
    return lines
  end

  -- Expand (collapsible section)
  if node_type == "expand" then
    local title = node.attrs and node.attrs.title or "Details"
    local lines = { indent .. "▸ " .. title }
    local child_ctx = { depth = depth + 1, indent = indent .. "  " }
    local child_lines = render_content(node.content, child_ctx)
    for _, line in ipairs(child_lines) do
      table.insert(lines, line)
    end
    return lines
  end

  -- Task list
  if node_type == "taskList" then
    local lines = {}
    if node.content then
      for _, item in ipairs(node.content) do
        local item_lines = render_node(item, next_ctx)
        for _, line in ipairs(item_lines) do
          table.insert(lines, line)
        end
      end
    end
    return lines
  end

  -- Task item
  if node_type == "taskItem" then
    local state = node.attrs and node.attrs.state or "TODO"
    local checkbox = state == "DONE" and "[x] " or "[ ] "
    local text = render_inline(node.content, next_ctx)
    return { indent .. checkbox .. text }
  end

  -- Decision list
  if node_type == "decisionList" then
    return render_content(node.content, next_ctx)
  end

  -- Decision item
  if node_type == "decisionItem" then
    local state = node.attrs and node.attrs.state or "DECIDED"
    local prefix = state == "DECIDED" and "✓ " or "? "
    local text = render_inline(node.content, next_ctx)
    return { indent .. prefix .. text }
  end

  -- Status (lozenge)
  if node_type == "status" then
    local text = node.attrs and node.attrs.text or "STATUS"
    return { "[" .. text .. "]" }
  end

  -- Date
  if node_type == "date" then
    local timestamp = node.attrs and node.attrs.timestamp
    if timestamp then
      -- Convert ms timestamp to date
      local date = os.date("%Y-%m-%d", timestamp / 1000)
      return { tostring(date) }
    end
    return { "[date]" }
  end

  -- Unknown node type - try to render content if present
  if node.content then
    return render_content(node.content, next_ctx)
  end

  -- No content, skip
  return {}
end

--- Remove excessive blank lines (more than 2 consecutive)
---@param lines table array of strings
---@return table cleaned lines
function M.clean_lines(lines)
  local result = {}
  local blank_count = 0

  for _, line in ipairs(lines) do
    if line:match("^%s*$") then
      blank_count = blank_count + 1
      if blank_count <= 2 then
        table.insert(result, "")
      end
    else
      blank_count = 0
      table.insert(result, line)
    end
  end

  -- Trim leading/trailing blank lines
  while #result > 0 and result[1] == "" do
    table.remove(result, 1)
  end
  while #result > 0 and result[#result] == "" do
    table.remove(result)
  end

  return result
end

--- Convert ADF document to plain text lines
---@param adf table|string|nil ADF document or plain text
---@return table lines array of strings
function M.to_lines(adf)
  -- Handle nil
  if adf == nil then
    return {}
  end

  -- Handle plain text string (legacy format)
  if type(adf) == "string" then
    local lines = {}
    for line in (adf .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
    return M.clean_lines(lines)
  end

  -- Handle non-table (shouldn't happen, but be safe)
  if type(adf) ~= "table" then
    return {}
  end

  -- Parse ADF with error handling
  local ok, lines = pcall(function()
    return render_node(adf, { depth = 0, indent = "" })
  end)

  if not ok then
    return { "[Error parsing description]" }
  end

  return M.clean_lines(lines or {})
end

return M
