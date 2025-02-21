local M = {
  path = {},
  nvim = {},
  patterns = {
    markdown_link = "%[.-%]%b()",
    http_link = "^https?://",
  },
}

--- Get the last part of a path
---@param path string
---@return string
function M.path.basename(path)
  local name = string.gsub(path, "(.*/)(.*)", "%2")
  return name
end

--- Splits a file name into its name and extension
---@param path string
---@return string, string
function M.path.splitext(path)
  local name = string.gsub(path, "(.*)(%..*)", "%1")
  local ext = string.gsub(path, "(.*)(%..*)", "%2")
  return name, ext
end

--- Creates a timestamp based on various parameters
---@param opts {day?: number|function, hour?: number|function, min?: number|function, sec?: number|function}?
---@return integer
function M.timestamp(opts)
  opts = opts or {}
  local now = os.date("*t")
  if opts.day ~= nil then
    if type(opts.day) == "function" then
      now.day = opts.day(now)
    else
      now.day = now.day + opts.day
    end
  end
  if opts.hour ~= nil then
    if type(opts.hour) == "function" then
      now.hour = opts.hour(now)
    else
      local hour = opts.hour
      ---@cast hour integer
      now.hour = hour
    end
  end
  if opts.min ~= nil then
    if type(opts.min) == "function" then
      now.min = opts.min(now)
    else
      local min = opts.min
      ---@cast min integer
      now.min = min
    end
  end
  if opts.sec ~= nil then
    if type(opts.sec) == "function" then
      now.sec = opts.sec(now)
    else
      local sec = opts.sec
      ---@cast sec integer
      now.sec = sec
    end
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  return os.time(now)
end

--- Get the text that is selected
---@return string
function M.nvim.get_visual_selection()
  return table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos(".")), "\n")
end

--- Get the row range of the visual selection
---@return integer, integer
function M.nvim.get_visual_selection_range()
  local start_col = vim.fn.getpos("v")[3]
  local end_col = vim.fn.getpos(".")[3]
  return start_col, end_col
end

--- If cursor is under a markdown link, return the text and url
---@return boolean, string?, string?
function M.get_md_link_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  local text, url
  local is_link, start_pos, end_pos = M.patterns.contains_markdown_link(line)
  if not is_link or start_pos == nil or end_pos == nil then
    return false, text, url
  end

  local md_link_text = line:sub(start_pos, end_pos)
  text, url = md_link_text:match("%[(.-)%]%((.-)%)")
  while start_pos do
    if col >= start_pos and col <= end_pos then
      return true, text, url
    end
    start_pos, end_pos = line:find(M.patterns.markdown_link, end_pos + 1)
  end

  return false, text, url
end

--- Check whether text contains a markdown link
---@param text string
---@return boolean, integer?, integer?
function M.patterns.contains_markdown_link(text)
  local start_pos, end_pos = text:find(M.patterns.markdown_link)
  return start_pos ~= nil, start_pos, end_pos
end

--- Check whether text contains a http link
---@param text string
---@return boolean, integer?, integer?
function M.patterns.contains_http_link(text)
  local start_pos, end_pos = text:match(M.patterns.http_link)
  return start_pos ~= nil, start_pos, end_pos
end

return M
