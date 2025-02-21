local Path = require("plenary.path")
local pickers = require("flotes.pickers")
local utils = require("flotes.utils")
local M = {
  states = {
    note = nil,
    float = nil,
    zoomed = nil,
  },
  utils = utils,
}

---@class Flotes.Config.Float
---@field quit_action "close" | "hide" Action to take when the float is closed. Defaults to "close"
---@field float_opts Flotes.Float.Opts Options for the floating window

---@class Flotes.Config
---@field notes_dir string Absolute path to the notes directory
---@field journal_dir string? Absolute path to the journal directory. Defaults to {notes_dir}/journal.
---@field float Flotes.Config.Float? Configuration for the floating window
M.config = {
  journal_dir = nil,
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
    local entries =
      vim.split(vim.fn.glob(M.config.journal_dir .. "/*"), "\n", { trimempty = true })

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

--- Create a new note
---@param name string
---@param title string
---@param dir? string
---@param opts? Flotes.NewNoteOpts
---@return string
local function new_note(name, title, dir, opts)
  opts = opts or {}
  dir = dir or M.config.notes_dir
  local note_path = Path:new(dir):joinpath(name)
  if note_path:exists() then
    M.show({ note_path = note_path.filename })
    return note_path.filename
  end

  -- Create a new note
  local new_notes_path = Path:new(dir):joinpath(name)
  new_notes_path:write("# " .. title .. "\n", "w")
  if opts.content ~= nil then
    opts.content(new_notes_path)
  end
  if opts.show ~= false then
    M.show({ note_path = new_notes_path.filename })
  end
  return new_notes_path.filename
end

--- Bind default keymaps to notes
---@param bufnr integer
local function def_keymaps(bufnr)
  -- Hide instead of closing
  if M.config.float.quit_action == "hide" then
    vim.keymap.set("n", "q", function()
      M.hide()
    end, { noremap = true, buffer = bufnr })
  end

  -- Journal navigation, only if current buffer is a journal
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if is_journal(filepath) then
    vim.keymap.set("n", "]j", function()
      M.journal({ direction = "next" })
    end, { noremap = true, buffer = bufnr })

    vim.keymap.set("n", "[j", function()
      M.journal({ direction = "prev" })
    end, { noremap = true, buffer = bufnr })
  end

  -- Remap [[ to [h instead for moving between headings
  vim.keymap.set("x", "[h", "[[", { noremap = true, buffer = bufnr })
  vim.keymap.set("x", "]h", "]]", { noremap = true, buffer = bufnr })

  -- Insert link to note
  vim.keymap.set("i", "[[", function()
    require("flotes.actions").add_note_link()
  end, { noremap = true, buffer = bufnr })

  -- Convert visual selection to link
  vim.keymap.set("v", "[[", function()
    require("flotes.actions").replace_with_link()
  end, { noremap = true, buffer = bufnr })
end

--- Setup configurationk
---@param opts Flotes.Config
M.setup = function(opts)
  M.config = vim.tbl_deep_extend("keep", {}, opts or {}, M.config)
  -- Notes dir is required
  if M.config.notes_dir == nil then
    return vim.api.nvim_err_writeln("flotes: notes_dir is not set")
  end
  if not Path:new(M.config.notes_dir):exists() == false then
    return vim.api.nvim_err_writeln(
      "flotes: notes_dir=" .. M.config.notes_dir .. " does not exist"
    )
  end
  M.config.notes_dir = vim.fn.expand(M.config.notes_dir)

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
---@param opts Flotes.ShowOpts
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

---@class Flotes.NewNoteOpts
---@field show boolean? Show the note after creation. Defaults to true
---@field content fun(Path) Function to write content to the note
--- Creates a new note and shows it
---@param title string Title of the note
---@param opts Flotes.NewNoteOpts?
---@return string Path to the created note
function M.new_note(title, opts)
  opts = opts or {}
  local name = utils.timestamp() .. ".md"
  return new_note(name, title, nil, opts)
end

---@class Flotes.FindNotesOpts
---@field picker_opts table? Options for the snacks picker
--- Search for notes by name
---@param opts Flotes.FindNotesOpts?
function M.find_notes(opts)
  pickers.notes.finder(opts)
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
    print("here")
    if not opts.create then
      return
    end
    print("here1")
    local title = "Journal: " .. utils.dates.to_human_friendly(journal_ts)
    print(journal_name, title, M.config.journal_dir)
    new_note(journal_name, tostring(title), M.config.journal_dir)
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

return M
