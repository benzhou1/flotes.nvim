local Path = require("plenary.path")
local utils = require("flotes.utils")
local M = { notes = { actions = {} }, templates = { actions = {} } }

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
  local title = filter.search
  return require("flotes").new_note(title, opts)
end

--- Delete the selected note
function M.notes.actions.delete(picker)
  local item = picker:current()
  if not item then
    return
  end

  local path = Path:new(item.file)
  local choice = vim.fn.confirm("Are you sure you want to delete this note?", "&Yes\n&No")
  if choice == 1 then
    path:rm()
    vim.notify("Deleted note: " .. item.file, "info")
    picker:close()
    vim.schedule(function()
      picker:resume()
    end)
  end
end

--- Switch to the list view in snacks picker
function M.notes.actions.swtich_to_list(picker)
  require("snacks.picker.actions").cycle_win(picker)
  require("snacks.picker.actions").cycle_win(picker)
end

--- Snacks picker for notes
---@param opts snacks.picker.Config?
function M.notes.finder(opts)
  opts = opts or {}
  local flotes = require("flotes")

  local function notes_finder(finder_opts, ctx)
    local cwd = flotes.config.notes_dir
    local cmd = "rg"
    local args = {
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
    }
    local pattern, pargs = Snacks.picker.util.parse(ctx.filter.search)
    vim.list_extend(args, pargs)
    args[#args + 1] = "--"
    table.insert(args, pattern)
    table.insert(args, cwd)

    -- If the search is empty, show all notes
    if ctx.filter.search == "" then
      args = { "^#", "-m", "1", table.unpack(args) }
      table.insert(args, ctx.filter.search)
    end
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
            local title = utils.os.read_first_line(file)
            item.line = line
            item.title = title
            item.gtext = text
            item.file = file
            item.pos = { tonumber(line), tonumber(col) - 1 }
          end
        end,
      },
    }, ctx)
  end

  local picker_opts = vim.tbl_deep_extend("keep", opts, {
    finder = notes_finder,
    format = function(item, ctx)
      local parts = {}
      table.insert(parts, { item.title, "SnacksPickerFile" })
      if ctx.filter.search ~= "" then
        if item.title ~= item.gtext then
          table.insert(parts, { " " })
          table.insert(parts, { item.gtext, "Normal" })
        end
      end
      return parts
    end,
    confirm = M.notes.actions.confirm,
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
    show_empty = true,
    live = true,
    supports_live = true,
    actions = {
      delete = M.notes.actions.delete,
      create_new_note = M.notes.actions.create,
      create_new_note_template = M.notes.actions.create_template,
      switch_to_list = M.notes.actions.swtich_to_list,
    },
  })
  require("snacks.picker").pick(picker_opts)
end

--- Creates a new note from a template
function M.templates.actions.create(picker)
  local item = picker:selected({ fallback = true })[1]
  if item == nil then
    return
  end
  picker:close()
  require("flotes.notes").create_template({ template = item.text })
end

--- Snacks picker for templates
---@param opts snacks.picker.Config?
function M.templates.finder(opts)
  opts = opts or {}
  local flotes = require("flotes")
  local function templates_finder(finder_opts, ctx)
    local items = {}
    for name, template in pairs(flotes.config.templates.templates) do
      table.insert(items, {
        text = name,
        template = template.template,
        preview = { text = template.template },
        file = "flotes.templates.finder." .. name,
      })
    end
    return ctx.filter:filter(items)
  end

  local picker_opts = vim.tbl_deep_extend("keep", opts, {
    finder = templates_finder,
    confirm = M.templates.actions.create,
    format = function(item, _)
      return { { item.text } }
    end,
    preview = "preview",
    matcher = {
      sort_empty = true,
      filename_bonus = false,
      file_pos = false,
      frecency = true,
    },
    sort = {
      fields = { "score:desc" },
    },
    show_empty = true,
    actions = {
      switch_to_list = M.notes.actions.swtich_to_list,
    },
  })
  require("snacks.picker").pick(picker_opts)
end

return M
