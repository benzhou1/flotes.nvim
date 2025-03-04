local Path = require("plenary.path")
local notes = require("flotes.notes")
local pickers = require("flotes.pickers")
local utils = require("flotes.utils")
local M = {
  states = {
    note = nil,
    ---@type Flotes.Float
    float = nil,
    zoomed = nil,
  },
  utils = utils,
}

---@class Flotes.Config.Float
---@field quit_action "close" | "hide" Action to take when the float is closed. Defaults to "close"
---@field float_opts Flotes.Float.Opts Options for the floating window

---@class Flotes.Config.Keymaps
---@field prev_journal string | false? Keymap to navigate to the previous journal note
---@field next_journal string | false? Keymap to navigate to the next journal note
---@field add_note_link string | false? Keymap to add a link to a note
---@field add_note_link_visual string | false? Keymap to add a link to a note from visual selection
---@field journal_keys fun(bufnr: integer)? Callback to create custom keymaps for journal files
---@field note_keys fun(bufnr: integer)? Callback to create custom keymaps for note files

---@class Flotes.Config.Templates.template
---@field template string Template for creating notes. Supports snippet syntax.

---@class Flotes.Config.Templates
---@field templates table<string, Flotes.Config.Templates.template> Templates for creating notes
---@field expand fun(...) Function to expand a template

---@class Flotes.Config.Pickers
---@field notes snacks.picker.Config? Snack picker options for notes picker
---@field insert_link snacks.picker.Config? Snack picker options for insert link picker
---@field templates snacks.picker.Config? Snack picker options for templates picker

---@class Flotes.Config
---@field notes_dir string Absolute path to the notes directory
---@field journal_dir string? Absolute path to the journal directory. Defaults to {notes_dir}/journal.
---@field float Flotes.Config.Float? Configuration for the floating window
---@field keymaps Flotes.Config.Keymaps? Keymaps for the notes and journal files
---@field templates Flotes.Config.Templates? Templates for creating notes
---@field pickers Flotes.Config.Pickers? Configuration for the snacks pickers
---@type Flotes.Config
M.config = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  notes_dir = nil,
  journal_dir = nil,
  keymaps = {
    prev_journal = false,
    next_journal = false,
    add_note_link = false,
    add_note_link_visual = false,
    journal_keys = nil,
    note_keys = nil,
  },
  float = {
    quit_action = "close",
    float_opts = {
      x = 0.25,
      y = 0.25,
      w = 0.5,
      h = 0.5,
      border = "rounded",
      del_bufs_on_close = true,
    },
  },
  pickers = {
    notes = {
      win = {
        input = {
          keys = {
            ["<esc>"] = {
              "switch_to_list",
              mode = { "i" },
              desc = "Switch to the list view",
            },
            ["<S-CR>"] = {
              "create_new_note",
              mode = { "n", "i" },
            },
            ["<c-x>"] = {
              "delete",
              mode = { "n", "i" },
            },
          },
        },
        list = {
          keys = {
            ["a"] = {
              "toggle_focus",
              desc = "Focus input",
            },
            ["i"] = {
              "toggle_focus",
              desc = "Focus input",
            },
            ["<S-CR>"] = {
              "create_new_note",
              mode = { "n" },
            },
            ["dd"] = {
              "delete",
              mode = { "n" },
            },
          },
        },
      },
    },
    insert_link = {
      win = {
        input = {
          keys = {
            ["<esc>"] = {
              "switch_to_list",
              mode = { "i" },
              desc = "Switch to the list view",
            },
            ["<S-CR>"] = {
              "create_new_note",
              mode = { "n", "i" },
            },
          },
        },
        list = {
          keys = {
            ["a"] = {
              "toggle_focus",
              desc = "Focus input",
            },
            ["i"] = {
              "toggle_focus",
              desc = "Focus input",
            },
            ["<S-CR>"] = {
              "create_new_note",
              mode = { "n" },
            },
          },
        },
      },
    },
    templates = {
      win = {
        input = {
          keys = {
            ["<esc>"] = {
              "switch_to_list",
              mode = { "i" },
              desc = "Switch to the list view",
            },
          },
        },
        list = {
          keys = {
            ["a"] = {
              "toggle_focus",
              desc = "Focus input",
            },
            ["i"] = {
              "toggle_focus",
              desc = "Focus input",
            },
          },
        },
      },
    },
  },
  templates = {
    expand = function(...)
      vim.snippet.expand(...)
    end,
    templates = {},
  },
}

--- Checks whether a path a file under the journal directory
---@param path string
---@return boolean
local function is_journal(path)
  if path == nil then
    return false
  end
  return string.find(path, M.config.journal_dir) ~= nil
end

--- Gets the timestamp used for a journal file
---@param opts {days: number}?
---@return integer
local function get_journal_timestamp(opts)
  opts = opts or {}
  -- Create timestamp out of date only, ignore time
  local ts_opts = { hour = 0, min = 0, sec = 0 }
  if opts.days ~= nil then
    ts_opts.day = function(d)
      return d.day + opts.days
    end
  end
  local timestamp = utils.timestamp(ts_opts)
  return timestamp
end

--- Finds a journal file
---@param opts Flotes.JournalFindOpts?
---@return integer
local function find_journal(opts)
  opts = opts or {}
  local today = get_journal_timestamp()
  -- Find by human readable description
  if opts.desc then
    if opts.desc == "today" then
      return today
    elseif opts.desc == "yesterday" then
      return get_journal_timestamp({ days = -1 })
    elseif opts.desc == "tomorrow" then
      return get_journal_timestamp({ days = 1 })
    end
    return today
  end

  -- Find relative to currently opened note
  if opts.direction ~= nil then
    local entries = vim.split(vim.fn.glob(M.config.journal_dir .. "/*"), "\n", { trimempty = true })

    local journal_entries = {}
    for _, entry in ipairs(entries) do
      local filename = utils.path.basename(entry)
      local timestamp = tonumber(string.match(filename, "^(%d+)"))
      table.insert(journal_entries, timestamp)
    end
    -- Sort by recent descending
    table.sort(journal_entries, function(a, b)
      return a > b
    end)

    local curr_idx = nil
    local current_note = vim.api.nvim_buf_get_name(0)
    if current_note == nil or not is_journal(current_note) then
      return today
    end

    -- Extract file name without extension
    local curr_base = utils.path.basename(current_note)
    local curr_ts = tonumber(string.match(curr_base, "^(%d+)"))
    -- Find the current ts
    for i, entry in ipairs(journal_entries) do
      if curr_ts == entry then
        curr_idx = i
        break
      end
    end

    if opts.direction == "next" then
      return journal_entries[curr_idx - 1]
    else
      return journal_entries[curr_idx + 1]
    end
  end
  return today
end

--- Bind default keymaps to notes
---@param bufnr integer
local function def_keymaps(bufnr)
  -- Hide instead of closing
  if M.config.float.quit_action == "hide" then
    vim.keymap.set("n", "q", function()
      M.hide()
    end, { noremap = true, buffer = bufnr })
  -- False to disable quit action
  elseif M.config.float.quit_action == false then
    pcall(vim.keymap.del, "n", "q", { buffer = bufnr })
  end

  -- Journal navigation, only if current buffer is a journal
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if is_journal(filepath) then
    if M.config.keymaps.prev_journal ~= false then
      vim.keymap.set("n", M.config.keymaps.prev_journal, function()
        M.journal({ direction = "prev" })
      end, { noremap = true, buffer = bufnr, desc = "Previous journal" })
    end

    if M.config.keymaps.next_journal ~= false then
      vim.keymap.set("n", M.config.keymaps.next_journal, function()
        M.journal({ direction = "next" })
      end, { noremap = true, buffer = bufnr, desc = "Next journal" })
    end

    -- Custom keymaps for journal files only
    if M.config.keymaps.journal_keys then
      M.config.keymaps.journal_keys(bufnr)
    end
  end

  -- Insert link to note
  if M.config.keymaps.add_note_link ~= false then
    vim.keymap.set("i", M.config.keymaps.add_note_link, function()
      require("flotes.actions").add_note_link()
    end, { noremap = true, buffer = bufnr })
  end

  -- Convert visual selection to link
  if M.config.keymaps.add_note_link_visual ~= false then
    vim.keymap.set("v", M.config.keymaps.add_note_link_visual, function()
      require("flotes.actions").replace_with_link()
    end, { noremap = true, buffer = bufnr })
  end

  -- Custom keymaps for note files only
  if M.config.keymaps.note_keys then
    M.config.keymaps.note_keys(bufnr)
  end
end

--- Setup configurationk
---@param opts Flotes.Config
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("keep", {}, opts or {}, M.config)
  -- Notes dir is required
  if M.config.notes_dir == nil then
    return vim.api.nvim_err_writeln("flotes: notes_dir is not set")
  end
  local notes_dir = vim.fn.expand(M.config.notes_dir)
  if not Path:new(notes_dir):exists() then
    return vim.api.nvim_err_writeln("flotes: notes_dir=" .. notes_dir .. " does not exist")
  end
  M.config.notes_dir = notes_dir

  -- Journals dir defaults to notes_dir/journal, create it if it doesn't exist
  if M.config.journal_dir == nil then
    M.config.journal_dir = Path:new(opts.notes_dir):joinpath("journal").filename
  end
  M.config.journal_dir = vim.fn.expand(M.config.journal_dir)
  local journal_dir = Path:new(M.config.journal_dir)
  if not journal_dir:exists() then
    journal_dir:mkdir()
  end

  -- Support percentage values for float_opts
  local float_opts = vim.tbl_deep_extend("keep", {}, opts, M.config.float.float_opts)
  if float_opts.x < 1 then
    float_opts.x = math.floor(vim.o.columns * float_opts.x)
  end
  if float_opts.y < 1 then
    float_opts.y = math.floor(vim.o.lines * float_opts.y)
  end
  if float_opts.w < 1 then
    float_opts.w = math.floor(vim.o.columns * float_opts.w)
  end
  if float_opts.h < 1 then
    float_opts.h = math.floor(vim.o.lines * float_opts.h)
  end
  -- Keymaps per buffer
  float_opts.buf_keymap_cb = function(bufnr)
    def_keymaps(bufnr)
  end
  -- Add buf to frecency on show
  float_opts.show_buf_cb = function(bufnr)
    require("snacks.picker.core.frecency").visit_buf(bufnr)
  end
  -- Initialize float window
  M.states.float = require("flotes.float").Float:new(float_opts)
end

---@class Flotes.ShowOpts
---@field note_name string? Name of the note to show
---@field note_path string? Path to the note to show

--- Show floating window with the note
---@param opts Flotes.ShowOpts?
function M.show(opts)
  opts = opts or {}

  local note_path = M.states.note
  if opts.note_name ~= nil then
    note_path = Path:new(M.config.notes_dir):joinpath(opts.note_name).filename
  end
  if opts.note_path ~= nil then
    note_path = opts.note_path
  end
  -- Save currently opened note
  M.states.note = note_path
  M.states.float:show(note_path)
  -- If zoomed, apply to float
  if M.states.zoom then
    M.states.float:zoom()
  end
end

--- Hide the floating window without closing it
function M.hide()
  if M.states.float ~= nil then
    M.states.float:hide()
  end
end

--- Close the floating window
function M.close()
  if M.states.float ~= nil then
    M.states.float:close()
  end
end

--- Toggles the floating window depending on quit_action
---@param opts Flotes.ShowOpts?
function M.toggle(opts)
  opts = opts or {}
  if M.states.float ~= nil then
    if M.states.float:is_showing() then
      if M.config.float.quit_action == "close" then
        return M.close()
      elseif M.config.float.quit_action == "hide" then
        return M.hide()
      end
    end
  end
  M.show(opts)
end

--- Toggles the focus between floating window
function M.toggle_focus()
  if M.states.float ~= nil then
    M.states.float:toggle_focus()
  else
    M.show()
  end
end

--- Zoom the floating window
function M.zoom()
  M.states.zoom = true
  if M.states.float ~= nil then
    M.states.float:zoom()
  end
end

--- Unzoom the floating window
function M.unzoom()
  M.states.zoom = false
  if M.states.float ~= nil then
    M.states.float:unzoom()
  end
end

--- Toggle zoom
function M.toggle_zoom()
  if M.states.zoom then
    M.unzoom()
  else
    M.zoom()
  end
end

--- Creates a new note and shows it
---@param title string Title of the note
---@param opts {show: boolean?}
---@return string Path to the created note
function M.new_note(title, opts)
  opts = opts or {}
  local path = notes.create({ title = title })
  if opts.show ~= false then
    M.show({ note_path = path })
  end
  return path
end

--- Search for notes by name
---@param opts snacks.picker.Config? Options for the picker
function M.find_notes(opts)
  local pick_opts = vim.tbl_deep_extend("keep", opts or {}, M.config.pickers.notes)
  pickers.notes.finder(pick_opts)
end

---@class Flotes.JournalFindOpts
---@field desc "today"|"yesterday"|"tomorrow"? Description of the journal to open
---@field direction "next"|"prev"? Get previous or next journal relative to current note
---@class Flotes.JournalOpts
---@field create boolean? Create a new journal note if it doesnt exist

--- Opens or creates a journal note
---@param opts Flotes.JournalOpts | Flotes.JournalFindOpts?
function M.journal(opts)
  opts = opts or { desc = "today" }
  local find_opts = opts
  ---@cast find_opts Flotes.JournalFindOpts
  local journal_ts = find_journal(find_opts)
  local journal_name = tostring(journal_ts) .. ".md"
  local journal_path = Path:new(M.config.journal_dir):joinpath(journal_name)

  if not journal_path:exists() then
    if not opts.create then
      return
    end
    local title = "Journal: " .. utils.dates.to_human_friendly(journal_ts)
    notes.create({ name = journal_name, title = tostring(title), dir = M.config.journal_dir })
  else
    M.show({ note_path = journal_path.filename })
  end
end

--- Follows the markdown link under the cursor
function M.follow_link()
  if vim.bo.filetype ~= "markdown" then
    return false
  end

  local under_md_link, _, url = utils.get_md_link_under_cursor()
  if not under_md_link or url == nil then
    return false
  end

  local is_http, _, _ = utils.patterns.contains_http_link(url)
  if is_http then
    vim.fn.jobstart("open " .. url)
  else
    M.show({ note_name = url })
  end
  return true
end

---@class Flotes.NewNoteTemplateOpts
---@field picker_opts snacks.picker.Config? Options for the template picker
---@field template_opts Flotes.templates.Opts? Options for the template creation
--- Create a new note with template
---@param template_name string? Name of the template, empty to show picker
---@param opts Flotes.NewNoteTemplateOpts Options for the picker or template creation
function M.new_note_from_template(template_name, opts)
  opts = opts or {}
  if template_name == nil then
    local picker_opts = vim.tbl_deep_extend("keep", opts.picker_opts or {}, M.config.pickers.templates)
    return pickers.templates.finder(picker_opts)
  end

  local template_opts = vim.tbl_deep_extend("keep", opts.template_opts, {
    template = template_name,
  })
  ---@diagnostic disable-next-line: param-type-mismatch
  require("flotes.notes").create_template(template_opts)
end

return M
