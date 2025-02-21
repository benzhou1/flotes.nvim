local M = { notes = { actions = {} } }

--- Confirm the selected note and open it in a new buffer.
function M.notes.actions.confirm(picker)
  picker:close()
  local item = picker:current()
  if not item then
    return
  end
  require("flotes").show({ note_path = item.file })
end

--- Confirm the selected note and open it in a new buffer.
function M.notes.actions.create(picker, opts)
  opts = opts or {}
  picker:close()
  local filter = picker.input.filter:clone({ trim = true })
  local title = filter.pattern
  return require("flotes").new_note(title, opts)
end

---@param opts Flotes.FindNotesOpts?
function M.notes.finder(opts)
  opts = opts or {}
  local flotes = require("flotes")

  local function notes_finder(finder_opts, ctx)
    local cwd = flotes.config.notes_dir
    local cmd = "rg"
    local args = {
      "^#",
      "-m",
      "1",
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--smart-case",
      "--max-columns=500",
      "--max-columns-preview",
      "-g",
      "!.git",
      cwd,
    }
    return require("snacks.picker.source.proc").proc({
      finder_opts,
      {
        notify = false, -- never notify on grep errors, since it's impossible to know if the error is due to the search pattern
        cmd = cmd,
        args = args,
        ---@param item snacks.picker.finder.Item
        transform = function(item)
          local file, line, col, text = item.text:match("^(.+):(%d+):(%d+):(.*)$")
          if not file then
            if not item.text:match("WARNING") then
              Snacks.notify.error("invalid grep output:\n" .. item.text)
            end
            return false
          else
            item.line = text
            item.file = file
            item.pos = { tonumber(line), tonumber(col) - 1 }
          end
        end,
      },
    }, ctx)
  end

  local picker_opts = vim.tbl_deep_extend("keep", opts.picker_opts or {}, {
    finder = notes_finder,
    format = function(item, _)
      local parts = {}
      local _, _, _, text = item.text:match("^(.+):(%d+):(%d+):(.*)$")
      table.insert(parts, { string.sub(text, 3), "Normal" })
      return parts
    end,
    confirm = M.notes.actions.confirm,
    actions = {
      create_new_note = M.notes.actions.create,
    },
    matcher = {
      sort_empty = true,
      filename_bonus = false,
      file_pos = false,
      frecency = true,
    },
    sort = {
      fields = { "score:desc" },
    },
    regex = true,
    search = "^#",
    show_empty = true,
    live = false,
    layout = {},
    win = {
      input = {
        keys = {
          ["<S-CR>"] = {
            "create_new_note",
            mode = { "n", "i" },
          },
        },
      },
    },
  })
  require("snacks.picker").pick(picker_opts)
end

return M
