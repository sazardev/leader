-- ── Build check, when you save ───────────────────────────────────────────────
-- The LSP judges the buffer as it is; a compiler reads the DISK. So the build runs when you save the code you accepted
-- (never on its own: saving can trigger formatters, and that is yours to decide). Only the errors that land on or next to
-- what was accepted are blamed on it; errors elsewhere are reported as a count, not guessed at.
local anchor = require "agent.anchor"
local parse = require "agent.errors.parse"

local M = {}

---@type table<string, string[]>
local DEFAULTS = {
  go = { "go", "build", "./..." },
  rust = { "cargo", "check", "--quiet" },
}

local ROOT_MARKER = { go = "go.mod", rust = "Cargo.toml", dart = "pubspec.yaml" }

local MARGIN = 2 -- lines around an accepted range that still count as "in it"

--- How to build the project of `path`, or nil + why
---@param path string absolute
---@param lang string filetype
---@param setting string|false|table<string, string[]> settings.agent.verify.command
---@return { cmd: string[], cwd: string, label: string }?, string? why
function M.command_for(path, lang, setting)
  if setting == false or setting == nil then
    return nil, "build check is off"
  end
  local cmd
  if type(setting) == "table" then
    cmd = setting[lang]
  elseif lang == "python" then
    cmd = { "python3", "-m", "py_compile", path }
  elseif lang == "dart" then
    -- only the saved file (a second or two, Flutter included); exits != 0 only on errors, machine format = absolute paths
    cmd = { "dart", "analyze", "--no-fatal-warnings", "--format=machine", path }
  else
    cmd = DEFAULTS[lang]
  end
  if not cmd then
    return nil, ("no build command known for %s"):format(lang)
  end
  local marker = ROOT_MARKER[lang]
  local cwd = (marker and vim.fs.root(path, marker)) or vim.fs.root(path, ".git") or vim.fs.dirname(path)
  return { cmd = cmd, cwd = cwd, label = table.concat(cmd, " ") }
end

--- Which errors are on the accepted code: same file, inside a range (± margin)
---@param errors AgentToolError[]
---@param path string absolute path of the accepted file
---@param ranges { first: integer, last: integer }[]
---@return AgentToolError[] mine, integer elsewhere
function M.attribute(errors, path, ranges)
  local mine, elsewhere = {}, 0
  for _, e in ipairs(errors) do
    local inside = false
    if vim.fn.fnamemodify(e.file, ":p") == vim.fn.fnamemodify(path, ":p") then
      for _, r in ipairs(ranges) do
        if e.lnum >= r.first - MARGIN and e.lnum <= r.last + MARGIN then
          inside = true
          break
        end
      end
    end
    if inside then
      mine[#mine + 1] = e
    else
      elsewhere = elsewhere + 1
    end
  end
  return mine, elsewhere
end

--- Arms the check: the next time `buf` is written, builds the project and calls `on_result` with what it found.
---@param buf integer
---@param ranges { first: integer, last: integer }[] where the accepted code is NOW
---@param cfg table settings.agent.verify
---@param on_result fun(mine: AgentToolError[], elsewhere: integer, output: string)
function M.arm(buf, ranges, cfg, on_result)
  local path = vim.api.nvim_buf_get_name(buf)
  local run, why = M.command_for(path, vim.bo[buf].filetype, cfg.command)
  if not run then
    return false, why
  end
  -- anchors follow the code if you keep editing before saving
  local anchors = {}
  for _, r in ipairs(ranges) do
    anchors[#anchors + 1] = anchor.create(buf, r.first, r.last)
  end
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = buf,
    once = true,
    callback = function()
      local live = {}
      for _, id in ipairs(anchors) do
        local first, last = anchor.range(buf, id)
        if first then
          live[#live + 1] = { first = first, last = last }
        end
        anchor.delete(buf, id)
      end
      if #live == 0 then
        return
      end
      require("agent.tests.run").exec(run, function(ok, output, err)
        if ok or err then
          return -- it builds (or cannot be run here): nothing to blame
        end
        -- only errors are blamed: an analyzer also lists warnings and hints, which never fail a build
        local errors = vim.tbl_filter(function(e)
          return e.severity == "error"
        end, parse.parse(output, { root = run.cwd }))
        local mine, elsewhere = M.attribute(errors, path, live)
        if #mine > 0 or elsewhere > 0 then
          on_result(mine, elsewhere, output)
        end
      end, { raw = true, timeout_ms = cfg.timeout_ms })
    end,
  })
  return true
end

return M
