local utils = require("flotes.utils")
local M = {}

local add_link_finder_layout = {
  width = 40,
  height = 10,
  min_width = 40,
  min_height = 10,
  preview = false,
  relative = "cursor",
  backdrop = false,
  box = "vertical",
  border = "rounded",
  title = "{title} {live} {flags}",
  title_pos = "center",
  { win = "input", height = 1, border = "bottom" },
  { win = "list", border = "none" },
}

--- Make sure to focus back the float after closing the picker
local function add_link_finder_close(picker)
  local flotes = require("flotes")
  picker:close()
  ---@diagnostic disable-next-line: undefined-field
  flotes.states.float:focus()
end

local function add_link_at_cursor(item_path)
  local filename = utils.path.basename(item_path)
  vim.api.nvim_put({ "[](" .. filename .. ")" }, "c", false, true)
  local pos = vim.api.nvim_win_get_cursor(0)
  local offset = string.len(filename) + 2
  vim.api.nvim_win_set_cursor(0, { pos[1], pos[2] - offset })
  vim.schedule(function()
    vim.cmd("startinsert")
  end)
end

local function replace_with_link(line, s, e, item_path)
  local left = string.sub(line, 1, s - 1)
  local right = string.sub(line, e + 1)
  local middle = string.sub(line, s, e)
  local new_middle = "[" .. middle .. "](" .. utils.path.basename(item_path) .. ")"
  vim.api.nvim_set_current_line(left .. new_middle .. right)
end

--- Adds a link to a note at the cursor
function M.add_note_link()
  local flotes = require("flotes")
  local pickers = require("flotes.pickers")

  flotes.find_notes({
    picker_opts = {
      layout = {
        layout = add_link_finder_layout,
      },
      confirm = function(picker)
        picker:close()
        local item = picker:current()
        if not item then
          return
        end
        ---@diagnostic disable-next-line: undefined-field
        flotes.states.float:focus()
        add_link_at_cursor(item.file)
      end,
      actions = {
        close = add_link_finder_close,
        create_new_note = function(picker)
          local note_path = pickers.notes.actions.create(picker, { show = false })
          ---@diagnostic disable-next-line: undefined-field
          flotes.states.float:focus()
          add_link_at_cursor(note_path)
        end,
      },
    },
  })
end

--- Replace selection with a link to a note
function M.replace_with_link()
  -- Get the current visual selection
  local s, e = utils.nvim.get_visual_selection_range()
  local line = vim.api.nvim_get_current_line()
  local pickers = require("flotes.pickers")
  local flotes = require("flotes")

  flotes.find_notes({
    picker_opts = {
      layout = {
        layout = add_link_finder_layout,
      },
      confirm = function(picker)
        picker:close()
        local item = picker:current()
        if not item then
          return
        end
        ---@diagnostic disable-next-line: undefined-field
        flotes.states.float:focus()
        replace_with_link(line, s, e, item.file)
      end,
      actions = {
        close = add_link_finder_close,
        create_new_note = function(picker)
          local note_path = pickers.notes.actions.create(picker, { show = false })
          M.states.float:focus()
          replace_with_link(line, s, e, note_path)
        end,
      },
    },
  })
end

return M
