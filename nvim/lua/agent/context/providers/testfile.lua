-- What needs to be known about the test file WITHOUT sending it whole: its header (package/imports), the names of
-- what it already tests (to avoid repeating cases), the tests that already mention what is under test (to add only what is
-- missing) or, if there are none, ONE example (style and helpers). Small cap: it is the most expensive context of the tests.
local scopes = require "agent.context.scopes"

local HEADER_MAX = 25

---@param path string
---@return string[]?
local function read(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

---@param name string?
---@param text string
---@return boolean
local function mentions(name, text)
  return name ~= nil and name ~= "" and text:find(name, 1, true) ~= nil
end

return {
  cap = 2600,
  stability = 2,
  ---@param target AgentTarget the object under test (with `tests`)
  ---@param done fun(text: string?)
  collect = function(target, done)
    local info = target.tests
    if not info or not info.exists then
      return done(nil)
    end
    local lines = read(info.path)
    if not lines or #lines == 0 then
      return done(nil)
    end
    local text = table.concat(lines, "\n")
    local fns = scopes.functions(text, target.lang)
    local out = {}

    -- header: what precedes the first function
    local head_end = math.min(fns[1] and fns[1].first - 1 or #lines, HEADER_MAX)
    local header = vim.tbl_filter(function(l)
      return l:match "%S"
    end, vim.list_slice(lines, 1, head_end))
    if #header > 0 then
      out[#out + 1] = table.concat(header, "\n")
    end

    -- what it already tests
    local names, picked, example = {}, {}, nil
    for _, f in ipairs(fns) do
      if f.name then
        names[#names + 1] = f.name
      end
      local body = table.concat(vim.list_slice(lines, f.first, f.last), "\n")
      if #picked < 2 and mentions(target.name, body) and #body < 1200 then
        picked[#picked + 1] = body
      end
      local size = f.last - f.first + 1
      if size >= 3 and size <= 30 and (not example or size < example.size) then
        example = { body = body, size = size }
      end
    end
    if #names > 0 then
      out[#out + 1] = "-- existing tests: " .. table.concat(vim.list_slice(names, 1, 40), ", ")
    end
    if #picked > 0 then
      out[#out + 1] = "-- existing tests that already cover "
        .. target.name
        .. " (add only what is missing):\n"
        .. table.concat(picked, "\n\n")
    elseif example then
      out[#out + 1] = "-- one existing test, for style and helpers:\n" .. example.body
    end
    done(#out > 0 and table.concat(out, "\n\n") or nil)
  end,
}
