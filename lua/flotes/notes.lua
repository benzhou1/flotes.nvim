local Path = require("plenary.path")
local Popup = require("nui.popup")
local utils = require("flotes.utils")
local event = require("nui.utils.autocmd").event
local autocmds = require("nui.utils.autocmd")
local M = {}

---@class Flotes.notes.Opts
---@field name string?
---@field title string?
---@field dir string?
---@field content fun(Path: Path)?

--- Create a new note
---@param opts? Flotes.notes.Opts
---@return string
function M.create(opts)
  opts = opts or {}
  local flotes = require("flotes")
  local name = opts.name or utils.timestamp() .. ".md"
  local dir = opts.dir or flotes.config.notes_dir

  -- A note with the same name already exists
  local note_path = Path:new(dir):joinpath(name)
  if note_path:exists() then
    return note_path.filename
  end

  -- Create a new note
  local new_notes_path = Path:new(dir):joinpath(name)
  if opts.title ~= nil then
    new_notes_path:write("# " .. opts.title .. "\n", "w")
  end
  if opts.content ~= nil then
    opts.content(new_notes_path)
  end
  return new_notes_path.filename
end

---@class Flotes.templates.Opts
---@field name string?
---@field template string
---@field cb fun(path: string)?

--- Create a new note from a template
---@param opts Flotes.templates.Opts
function M.create_template(opts)
  local flotes = require("flotes")
  local template = flotes.config.templates.templates[opts.template]
  if template == nil then
    error("Template not found: " .. opts.template)
  end

  local path = M.create({
    name = opts.name,
    content = function(path)
      path:write("", "w")
    end,
  })
  flotes.show({ note_path = path })
  vim.schedule(function()
    vim.api.nvim_win_call(flotes.states.float.win_id, function()
      flotes.config.templates.expand(template.template)
    end)
  end)
end

return M
