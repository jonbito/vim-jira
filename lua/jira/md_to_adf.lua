-- Markdown to Atlassian Document Format (ADF) converter for vim-jira
-- Converts plain text/markdown lines to ADF JSON structure

local M = {}

-- Initialize random seed for UUID generation
math.randomseed(os.time())

--- Parse inline marks from text
--- Returns text with marks stripped and an array of mark ranges
---@param text string input text with markdown formatting
---@return table content array of ADF inline nodes
local function parse_inline(text)
  local content = {}

  -- Pattern for inline elements: **bold**, *italic*, `code`, ~strike~, [text](url)
  local pos = 1
  local len = #text

  while pos <= len do
    local found = false

    -- Check for link: [text](url)
    local link_start, link_end, link_text, link_url = text:find("%[([^%]]+)%]%(([^%)]+)%)", pos)
    if link_start == pos then
      -- Check for special inlineCard marker
      if link_text == "jira:inlineCard" then
        table.insert(content, {
          type = "inlineCard",
          attrs = { url = link_url },
        })
      else
        table.insert(content, {
          type = "text",
          text = link_text,
          marks = { { type = "link", attrs = { href = link_url } } },
        })
      end
      pos = link_end + 1
      found = true
    end

    -- Check for bold: *text* (single asterisk for strong, matching ADF output)
    if not found then
      local bold_start, bold_end, bold_text = text:find("^%*([^%*]+)%*", pos)
      if bold_start then
        table.insert(content, {
          type = "text",
          text = bold_text,
          marks = { { type = "strong" } },
        })
        pos = pos + bold_end
        found = true
      end
    end

    -- Check for italic: _text_
    if not found then
      local em_start, em_end, em_text = text:find("^_([^_]+)_", pos)
      if em_start then
        table.insert(content, {
          type = "text",
          text = em_text,
          marks = { { type = "em" } },
        })
        pos = pos + em_end
        found = true
      end
    end

    -- Check for code: `text`
    if not found then
      local code_start, code_end, code_text = text:find("^`([^`]+)`", pos)
      if code_start then
        table.insert(content, {
          type = "text",
          text = code_text,
          marks = { { type = "code" } },
        })
        pos = pos + code_end
        found = true
      end
    end

    -- Check for strikethrough: ~text~
    if not found then
      local strike_start, strike_end, strike_text = text:find("^~([^~]+)~", pos)
      if strike_start then
        table.insert(content, {
          type = "text",
          text = strike_text,
          marks = { { type = "strike" } },
        })
        pos = pos + strike_end
        found = true
      end
    end

    -- Plain text - consume until next potential mark or end
    if not found then
      local next_mark = len + 1
      for _, pattern in ipairs({ "%*", "_", "`", "~", "%[" }) do
        local mark_pos = text:find(pattern, pos + 1)
        if mark_pos and mark_pos < next_mark then
          next_mark = mark_pos
        end
      end

      local plain_text = text:sub(pos, next_mark - 1)
      if #plain_text > 0 then
        -- Merge with previous text node if it has no marks
        if #content > 0 and content[#content].type == "text" and not content[#content].marks then
          content[#content].text = content[#content].text .. plain_text
        else
          table.insert(content, { type = "text", text = plain_text })
        end
      end
      pos = next_mark
    end
  end

  return content
end

--- Create a paragraph node from text
---@param text string paragraph text
---@return table ADF paragraph node
local function make_paragraph(text)
  if text == "" then
    return { type = "paragraph", content = {} }
  end
  return { type = "paragraph", content = parse_inline(text) }
end

--- Create a heading node
---@param level number heading level (1-6)
---@param text string heading text
---@return table ADF heading node
local function make_heading(level, text)
  return {
    type = "heading",
    attrs = { level = level },
    content = parse_inline(text),
  }
end

--- Create a code block node
---@param language string|nil language identifier
---@param lines table array of code lines
---@return table ADF codeBlock node
local function make_code_block(language, lines)
  local text = table.concat(lines, "\n")
  local node = {
    type = "codeBlock",
    content = { { type = "text", text = text } },
  }
  if language and language ~= "" then
    node.attrs = { language = language }
  end
  return node
end

--- Create a blockquote node
---@param content table array of ADF nodes
---@return table ADF blockquote node
local function make_blockquote(content)
  return { type = "blockquote", content = content }
end

--- Create a bullet list node
---@param items table array of list item contents
---@return table ADF bulletList node
local function make_bullet_list(items)
  local list_items = {}
  for _, item_content in ipairs(items) do
    table.insert(list_items, {
      type = "listItem",
      content = item_content,
    })
  end
  return { type = "bulletList", content = list_items }
end

--- Create an ordered list node
---@param items table array of list item contents
---@return table ADF orderedList node
local function make_ordered_list(items)
  local list_items = {}
  for _, item_content in ipairs(items) do
    table.insert(list_items, {
      type = "listItem",
      content = item_content,
    })
  end
  return { type = "orderedList", content = list_items }
end

--- Generate a random UUID-like string for localId
---@return string UUID-like identifier
local function generate_local_id()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end

--- Create a task list node
---@param items table array of {checked, text, localId} items
---@return table ADF taskList node
local function make_task_list(items)
  local task_items = {}
  for _, item in ipairs(items) do
    local attrs = { state = item.checked and "DONE" or "TODO" }
    -- Preserve or generate localId
    attrs.localId = (item.localId and item.localId ~= "") and item.localId or generate_local_id()
    local inline_content = parse_inline(item.text)
    -- Ensure content is not empty
    if #inline_content == 0 then
      inline_content = { { type = "text", text = "" } }
    end
    table.insert(task_items, {
      type = "taskItem",
      attrs = attrs,
      content = inline_content,
    })
  end
  return {
    type = "taskList",
    attrs = { localId = generate_local_id() },
    content = task_items,
  }
end

--- Create a horizontal rule node
---@return table ADF rule node
local function make_rule()
  return { type = "rule" }
end

--- Parse a table row into cells
---@param line string table row like "| cell1 | cell2 |"
---@return table array of cell text strings
local function parse_table_row(line)
  local cells = {}
  -- Remove leading pipe
  local content = line:match("^|(.*)$")
  if not content then
    return cells
  end
  -- Remove trailing pipe if present
  content = content:gsub("|%s*$", "")
  -- Split by | using vim.split (avoids empty string matches from gmatch)
  local parts = vim.split(content, "|", { plain = true })
  for _, cell in ipairs(parts) do
    local trimmed = cell:match("^%s*(.-)%s*$")
    table.insert(cells, trimmed or "")
  end
  return cells
end

--- Create a table node
---@param rows table array of row data, each row is array of cell strings
---@param header_row boolean whether first row is header
---@return table ADF table node
local function make_table(rows, header_row)
  local table_rows = {}
  for i, row in ipairs(rows) do
    local cells = {}
    local is_header = header_row and i == 1
    for _, cell_text in ipairs(row) do
      local cell_type = is_header and "tableHeader" or "tableCell"
      local inline_content = parse_inline(cell_text)
      -- Ensure content is not empty
      if #inline_content == 0 then
        inline_content = { { type = "text", text = "" } }
      end
      table.insert(cells, {
        type = cell_type,
        attrs = vim.empty_dict(),
        content = { { type = "paragraph", content = inline_content } },
      })
    end
    table.insert(table_rows, { type = "tableRow", content = cells })
  end
  return { type = "table", content = table_rows }
end

--- Convert markdown lines to ADF document
---@param lines table array of markdown lines
---@return table ADF document object
function M.from_lines(lines)
  local doc = {
    type = "doc",
    version = 1,
    content = {},
  }

  local i = 1
  local n = #lines

  while i <= n do
    local line = lines[i]

    -- Skip empty lines at document start
    if line:match("^%s*$") and #doc.content == 0 then
      i = i + 1
      goto continue
    end

    -- Horizontal rule: ---
    if line:match("^%-%-%-+%s*$") then
      table.insert(doc.content, make_rule())
      i = i + 1
      goto continue
    end

    -- Media marker: <!-- jira:media {...} --> or <!-- jira:mediaSingle {...} -->
    local media_type, media_json = line:match("^<!%-%-%s*jira:(media[^%s]*)%s+(.-)%s*%-%->%s*$")
    if media_type and media_json then
      local ok, node = pcall(vim.json.decode, media_json)
      if ok and node then
        table.insert(doc.content, node)
      end
      i = i + 1
      goto continue
    end

    -- Heading: # to ######
    local heading_level, heading_text = line:match("^(#+)%s+(.*)$")
    if heading_level then
      local level = math.min(#heading_level, 6)
      table.insert(doc.content, make_heading(level, heading_text))
      i = i + 1
      goto continue
    end

    -- Code block: ```
    local code_lang = line:match("^```(%w*)%s*$")
    if code_lang ~= nil then
      local code_lines = {}
      i = i + 1
      while i <= n and not lines[i]:match("^```%s*$") do
        table.insert(code_lines, lines[i])
        i = i + 1
      end
      table.insert(doc.content, make_code_block(code_lang, code_lines))
      i = i + 1 -- skip closing ```
      goto continue
    end

    -- Table row: | cell | cell |
    if line:match("^|") then
      local table_rows = {}
      while i <= n and lines[i]:match("^|") do
        local cells = parse_table_row(lines[i])
        if #cells > 0 then
          table.insert(table_rows, cells)
        end
        i = i + 1
      end
      if #table_rows > 0 then
        -- Check if first row looks like a header (cells wrapped in *bold*)
        local first_row = table_rows[1]
        local is_header = first_row[1] and first_row[1]:match("^%*.*%*$")
        table.insert(doc.content, make_table(table_rows, is_header))
      end
      goto continue
    end

    -- Task list item: [ ] or [x] or [ |id] or [x|id]
    -- Try format with localId first: [x|localId] text
    local task_check, task_id, task_text = line:match("^%[([%sx])%|([^%]]+)%]%s+(.*)$")
    if not task_check then
      -- Try standard format: [x] text
      task_check, task_text = line:match("^%[([%sx])%]%s+(.*)$")
      task_id = nil
    end
    if task_check then
      local task_items = {}
      while i <= n do
        local check, localId, text = lines[i]:match("^%[([%sx])%|([^%]]+)%]%s+(.*)$")
        if not check then
          check, text = lines[i]:match("^%[([%sx])%]%s+(.*)$")
          localId = nil
        end
        if not check then
          break
        end
        table.insert(task_items, { checked = check == "x", text = text, localId = localId })
        i = i + 1
      end
      table.insert(doc.content, make_task_list(task_items))
      goto continue
    end

    -- Bullet list item: -
    local bullet_text = line:match("^%-%s+(.*)$")
    if bullet_text then
      local items = {}
      while i <= n do
        -- Skip blank lines between list items
        while i <= n and lines[i]:match("^%s*$") do
          i = i + 1
        end
        if i > n then
          break
        end
        local item_text = lines[i]:match("^%-%s+(.*)$")
        if not item_text then
          break
        end
        table.insert(items, { make_paragraph(item_text) })
        i = i + 1
      end
      table.insert(doc.content, make_bullet_list(items))
      goto continue
    end

    -- Ordered list item: 1.
    local ordered_text = line:match("^%d+%.%s+(.*)$")
    if ordered_text then
      local items = {}
      while i <= n do
        -- Skip blank lines between list items
        while i <= n and lines[i]:match("^%s*$") do
          i = i + 1
        end
        if i > n then
          break
        end
        local item_text = lines[i]:match("^%d+%.%s+(.*)$")
        if not item_text then
          break
        end
        table.insert(items, { make_paragraph(item_text) })
        i = i + 1
      end
      table.insert(doc.content, make_ordered_list(items))
      goto continue
    end

    -- Blockquote: >
    local quote_text = line:match("^>%s*(.*)$")
    if quote_text then
      local quote_lines = {}
      while i <= n do
        local q_text = lines[i]:match("^>%s*(.*)$")
        if not q_text then
          break
        end
        table.insert(quote_lines, q_text)
        i = i + 1
      end
      -- Recursively parse blockquote content
      local quote_content = M.from_lines(quote_lines).content
      table.insert(doc.content, make_blockquote(quote_content))
      goto continue
    end

    -- Empty line - paragraph separator
    if line:match("^%s*$") then
      i = i + 1
      goto continue
    end

    -- Regular paragraph - collect consecutive non-special lines
    local para_lines = {}
    while i <= n do
      local l = lines[i]
      -- Stop at special lines
      if
        l:match("^%s*$")
        or l:match("^#+%s")
        or l:match("^```")
        or l:match("^%-%-%-+%s*$")
        or l:match("^%-%s")
        or l:match("^%d+%.%s")
        or l:match("^>%s")
        or l:match("^%[[ x]%]%s")
        or l:match("^|")
        or l:match("^<!%-%-%s*jira:")
      then
        break
      end
      table.insert(para_lines, l)
      i = i + 1
    end
    if #para_lines > 0 then
      table.insert(doc.content, make_paragraph(table.concat(para_lines, " ")))
    end

    ::continue::
  end

  return doc
end

return M
