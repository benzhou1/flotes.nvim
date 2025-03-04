local autocmd = require("nui.utils.autocmd")
local path_utils = require("utils.paths")
local event = require("nui.utils.autocmd").event
local Buffer = require("flotes.buffer").Buffer

local M = {}

---@class Flotes.Float
---@field win_id number?
---@field prev_win_id number?
---@field bufnrs Float.Buffer[]
---@field hidden boolean
---@field zoomed boolean
---@field set_title_filename boolean
---@field set_win_opts_cb function?
---@field del_bufs_on_close boolean?
---@field close_on_leave boolean?
---@field buf_keymap_cb function?(bufnr: number)
---@field buf_event_cb function?(bufnr: number, group: string)
---@field show_buf_cb fun(bufnr: integer)?
---@field opts table
M.Float = {}
M.Float.__index = M.Float

---@class Flotes.Float.Opts
---@field x number
---@field y number
---@field w number
---@field h number
---@field relative string?
---@field border (string | table)?
---@field zindex number?
---@field title string?
---@field buf_cb function?
---@field set_title_filename boolean?
---@field set_win_opts_cb function?
---@field buf_keymap_cb function?(bufnr: number)
---@field buf_event_cb function?(bufnr: number, group: string)
---@field del_bufs_on_close boolean?
---@field close_on_leave boolean?
---@field win_opts table?
---@field show_buf_cb fun(bufnr: integer)?

--- Creates a new Float class
---@param opts Flotes.Float.Opts
---@return Flotes.Float
function M.Float:new(opts)
  local f = {}
  setmetatable(f, M.Float)

  f.win_id = nil
  f.prev_win_id = nil
  f.bufnrs = {}
  f.hidden = false
  f.zoomed = false
  f.set_title_filename = true
  if opts.set_title_filename ~= nil then
    f.set_title_filename = opts.set_title_filename
  end
  self.buf_cb = opts.buf_cb
  if self.buf_cb == nil then
    self.buf_cb = function()
      return vim.api.nvim_create_buf(false, false)
    end
  end
  f.set_win_opts_cb = opts.set_win_opts_cb
  f.del_bufs_on_close = opts.del_bufs_on_close
  f.close_on_leave = opts.close_on_leave
  f.buf_keymap_cb = opts.buf_keymap_cb
  f.buf_event_cb = opts.buf_event_cb
  f.show_buf_cb = opts.show_buf_cb

  f.opts = {
    row = opts.y,
    col = opts.x,
    width = opts.w,
    height = opts.h,
    relative = opts.relative or "editor",
    border = opts.border,
    zindex = opts.zindex,
    title = opts.title,
  }
  if opts.win_opts ~= nil then
    for k, v in pairs(opts.win_opts) do
      f.opts[k] = v
    end
  end
  return f
end

--- Custom autocmd group for window
---@return string
function M.Float:_get_autocmd_group()
  return "Float.Float(" .. self.win_id .. ")"
end

--- Checks if current float is valid as in does it still exist
---@return boolean
function M.Float:_check_win_valid()
  local valid = true
  -- Window has not been created
  -- Window no longer exists
  if self.win_id == nil or not vim.api.nvim_win_is_valid(self.win_id) then
    valid = false
  end

  if not valid then
    self:_reset()
  end
  return valid
end

--- Resets the state of the float
function M.Float:_reset()
  self:_clean_bufs()
  self:_clear_autocmd_track_bufs()
  self.win_id = nil
  self.bufnrs = {}
  self.zoomed = false
  self.prev_win_id = nil
  self.hidden = true
end

--- Cleans up all buffers entered in float
function M.Float:_clean_bufs()
  if not self.del_bufs_on_close then
    return
  end

  for _, buf in ipairs(self.bufnrs) do
    pcall(autocmd.buf.remove, buf.bufnr, self:_get_autocmd_group())
    buf:clean()
  end
end

--- Creates default autocmds on current window
function M.Float:_init_autocmd_track_bufs()
  local group = self:_get_autocmd_group()
  autocmd.create_group(group, {})

  -- Listen for any buffers opened in the float window and track them
  autocmd.create(event.BufRead, {
    group = group,
    callback = function(opts)
      -- Filter out reads from other windows
      local curr_buf = vim.api.nvim_win_get_buf(self.win_id)
      if curr_buf ~= opts.buf then
        return
      end

      if self.del_bufs_on_close then
        local newbuf = Buffer:new(opts.buf)
        table.insert(self.bufnrs, newbuf)
      end
      -- Map same key maps and events on this new buffer
      self:bind_keymaps_to_buf(opts.buf)
      self:bind_autocmds_on_buf(opts.buf)
      self:set_title()
    end,
  })
  if self.close_on_leave then
    -- Listen for when we leave the buffer and then close
    autocmd.create(event.BufLeave, {
      group = group,
      callback = function(_)
        self:close()
      end,
    })
  end
  -- Listen for win window is closed and clean up
  autocmd.create(event.WinClosed, {
    group = group,
    callback = function(opts)
      if opts.match == tostring(self.win_id) then
        self:close()
      end
    end,
  })
end

--- Removes default autocmds on current window
function M.Float:_clear_autocmd_track_bufs()
  if self.win_id ~= nil then
    autocmd.delete_group(self:_get_autocmd_group())
  end
end

--- Gets the current float window buffer file name
---@return string
function M.Float:_get_current_filename()
  local bufnr = vim.api.nvim_win_get_buf(self.win_id)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local filename = path_utils.basename(bufname)
  return filename
end

--- Gets the window options for the float window
---@return table
function M.Float:get_win_opts()
  if self.zoomed then
    local opts = vim.tbl_deep_extend("keep", {
      col = math.floor(vim.o.columns * 0.05),
      row = math.floor(vim.o.lines * 0.05),
      width = math.floor(vim.o.columns * 0.9),
      height = math.floor(vim.o.lines * 0.9),
    }, self.opts)
    return opts
  end
  return self.opts
end

--- Create a new floating window
function M.Float:_create_win()
  if self.win_id ~= nil then
    return
  end

  local bufnr = self.buf_cb()
  self:_create_buf(bufnr)
  local win_opts = self:get_win_opts()
  local win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
  if self.set_win_opts_cb ~= nil then
    vim.api.nvim_win_call(self.win_id, function()
      self.set_win_opts_cb()
    end)
  end
  self.win_id = win_id
  self.hidden = false
  self:_init_autocmd_track_bufs()
end

--- Creates a float with buffer
function M.Float:_create_buf(bufnr)
  local newbuf = Buffer:new(bufnr)
  table.insert(self.bufnrs, newbuf)
  if not self.del_bufs_on_close then
    self:bind_keymaps_to_buf(bufnr)
    self:bind_autocmds_on_buf(bufnr)
  end
end

--- Calls callback function to map keymaps to buffer
---@param bufnr number
function M.Float:bind_keymaps_to_buf(bufnr)
  -- Default keymaps
  vim.keymap.set("n", "q", "<Cmd>q<CR>", { buffer = bufnr })

  if self.buf_keymap_cb ~= nil then
    self.buf_keymap_cb(bufnr)
    return
  end
end

--- Calls callback function to map events to buffer
---@param bufnr number
function M.Float:bind_autocmds_on_buf(bufnr)
  if self.buf_event_cb ~= nil then
    self.buf_event_cb(bufnr, self:_get_autocmd_group())
  end
end

--- Focus float window
function M.Float:focus()
  if not self:_check_win_valid() then
    return self:show()
  end

  local current_win_id = vim.api.nvim_get_current_win()
  if current_win_id ~= self.win_id then
    self.prev_win_id = current_win_id
  end

  -- self:unhide()
  vim.api.nvim_set_current_win(self.win_id)
end

--- Return to previous window before focussing float
function M.Float:unfocus()
  -- If for some reason we dont have a prev window or prev window is the current window
  -- just cycle to the next window
  if self.prev_win_id == nil or self.prev_win_id == self.win_id then
    local key = vim.api.nvim_replace_termcodes("<C-w>", true, false, true)
    vim.api.nvim_feedkeys(key, "n", false)
    vim.api.nvim_feedkeys("w", "n", false)
    self.prev_win_id = nil
    return
  end
  vim.api.nvim_set_current_win(self.prev_win_id)
end

--- Toggle focus on float
function M.Float:toggle_focus()
  if not self:_check_win_valid() then
    return self:show()
  end

  local current_win_id = vim.api.nvim_get_current_win()
  local float_is_focused = current_win_id == self.win_id
  if float_is_focused then
    self:unfocus()
  else
    self:focus()
  end
end

--- Zoom into float
function M.Float:zoom()
  self.zoomed = true
  if not self:_check_win_valid() then
    return
  end
  local win_opts = self:get_win_opts()
  vim.api.nvim_win_set_config(self.win_id, win_opts)
end

--- Return window to original size
function M.Float:unzoom()
  self.zoomed = false
  if not self:_check_win_valid() then
    return
  end
  vim.api.nvim_win_set_config(self.win_id, self.opts)
end

--- Toggles zoom on float
function M.Float:toggle_zoom()
  if self.zoomed then
    self:unzoom()
  else
    self:zoom()
  end
end

--- Sets title of window to current buffer file name
function M.Float:set_title()
  if self.set_title_filename then
    local filename = self:_get_current_filename()
    vim.api.nvim_win_set_config(self.win_id, { title = filename })
  end
end

--- Unhides floating window if hidden
function M.Float:unhide()
  if not self:_check_win_valid() then
    self.hidden = false
    return self:show()
  end
  vim.api.nvim_win_set_config(self.win_id, { hide = false })
  self.hidden = false
end

--- Hides floating window
function M.Float:hide()
  if not self:_check_win_valid() then
    self.hidden = true
    return
  end
  vim.api.nvim_win_set_config(self.win_id, { hide = true })
  self:unfocus()
  self.hidden = true
end

--- Toggle hidden state of float
function M.Float:toggle_hidden()
  if self.hidden then
    self:unhide()
  else
    self:hide()
  end
end

--- Show float create it if it doesnt exist
---@param path string?
function M.Float:show(path)
  local curr_win_id = vim.api.nvim_get_current_win()
  self:_check_win_valid()

  -- Save current window before floating window is shown if it is not already the floating window
  if curr_win_id ~= self.win_id then
    self.prev_win_id = curr_win_id
  end

  -- Create a new float window, if it doesn't exist exists
  self:_create_win()

  -- Show float window
  self:unhide()
  self:focus()

  -- Open a file in the float window if path is provided
  if path ~= nil then
    vim.schedule(function()
      vim.api.nvim_win_call(self.win_id, function()
        vim.api.nvim_command("e " .. path)
        -- Add new buffer to buf list
        local newbuf = vim.api.nvim_get_current_buf()
        self:_create_buf(newbuf)
        if self.show_buf_cb ~= nil then
          self.show_buf_cb(newbuf)
        end
      end)
      self:set_title()
    end)
  end
end

--- Closes float window and clean up
function M.Float:close()
  if self.win_id ~= nil then
    pcall(vim.api.nvim_win_close, self.win_id, true)
  end
  self:_reset()
end

--- Returns whether float is showing
---@return boolean
function M.Float:is_showing()
  return self.win_id ~= nil and not self.hidden
end

return M
