-- ── JUnit XML reports (pure) ─────────────────────────────────────────────────
-- What pytest (`--junitxml`) and bun (`--reporter=junit`) write: one <testcase> per test with its name, class (module
-- or describe block), file and line, and a <failure>/<error> or <skipped> child. Only what the marks need is read.
local M = {}

local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

--- XML text with its entities decoded
---@param s string
---@return string
function M.decode(s)
  return (
    s:gsub("&(#?x?)(%w+);", function(kind, name)
      if kind == "#" then
        return vim.fn.nr2char(tonumber(name))
      elseif kind == "#x" then
        return vim.fn.nr2char(tonumber(name, 16))
      end
      return ENTITIES[name] or ("&" .. name .. ";")
    end)
  )
end

---@param attrs string
---@return table<string, string>
local function attributes(attrs)
  local out = {}
  for k, v in attrs:gmatch '([%w_:%-]+)%s*=%s*"([^"]*)"' do
    out[k] = M.decode(v)
  end
  return out
end

---@class JunitCase
---@field name string
---@field classname string?
---@field file string?
---@field line integer?
---@field status "pass"|"fail"|"skip"
---@field message string?   the failure's message attribute
---@field text string?      the failure's body (the traceback)

--- Every test case of a report
---@param xml string
---@return JunitCase[]
function M.cases(xml)
  local out = {}
  local pos = 1
  while true do
    local s, e, attrs, selfclose = (xml or ""):find("<testcase%s+([^>]-)(/?)>", pos)
    if not s then
      break
    end
    local a = attributes(attrs)
    local case = {
      name = a.name or "",
      classname = a.classname,
      file = a.file,
      line = tonumber(a.line or ""),
      status = "pass",
    }
    local body = ""
    if selfclose ~= "/" then
      local close = xml:find("</testcase>", e + 1, true)
      body = close and xml:sub(e + 1, close - 1) or ""
      pos = close and (close + 11) or (e + 1)
    else
      pos = e + 1
    end
    local fattrs, ftext = body:match "<failure([^>]*)>(.-)</failure>"
    if not fattrs then
      fattrs, ftext = body:match "<error([^>]*)>(.-)</error>"
    end
    if not fattrs and (body:match "<failure([^>]*)/>" or body:match "<error([^>]*)/>") then
      fattrs, ftext = body:match "<failure([^>]*)/>" or body:match "<error([^>]*)/>", ""
    end
    if fattrs then
      case.status = "fail"
      case.message = attributes(fattrs).message
      case.text = M.decode(ftext or ""):gsub("^<!%[CDATA%[", ""):gsub("%]%]>$", "")
    elseif body:find "<skipped" then
      case.status = "skip"
    end
    out[#out + 1] = case
  end
  return out
end

return M
