local M = { path = {} }

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

return M
