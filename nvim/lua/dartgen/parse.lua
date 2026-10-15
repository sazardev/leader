-- ── build_runner output, line by line ────────────────────────────────────────
-- Pure. Reads what `dart run build_runner watch|build` prints and says when a build starts, ends well or fails, and
-- which errors it reported (file, line, message). Two formats:
--   · build_runner ≥ 2.5: "Starting build #2.", "Built with build_runner in 2s; wrote 3 outputs.",
--     "Failed to build with build_runner in 0s; …", "E json_serializable on lib/user.dart:" + indented lines
--     (the message, then a location such as "package:app/user.dart:13:19" or "11:1: message")
--   · older: "[INFO] Starting Build", "[INFO] Succeeded after 2.1s …", "[SEVERE] Failed after …",
--     "[SEVERE] json_serializable on lib/user.dart:" + lines
local M = {}

---@class DartgenError
---@field file string relative to the package root
---@field lnum integer? 1-based
---@field col integer? 1-based
---@field msg string
---@field builder string

---@class DartgenState
---@field errors DartgenError[] of the build in progress
---@field current DartgenError? the error whose lines are being read
---@field outputs integer? files written by the last build

---@return DartgenState
function M.new()
  return { errors = {} }
end

local function close(state)
  if state.current then
    state.errors[#state.errors + 1] = state.current
    state.current = nil
  end
end

--- Feeds one line. Returns "start" | "ok" | "fail" when the build changes state, nil otherwise; a "fail" leaves the
--- build's errors in `state.errors` (cleared on the next "start").
---@param state DartgenState
---@param line string
---@return string? event
function M.feed(state, line)
  line = line:gsub("\27%[[%d;]*m", "") -- colors, when the terminal asks for them

  if
    line:match "^%s*Starting build"
    or line:match "%[INFO%] Starting Build"
    or line:match "^%s*%d*s? ?compiling builders"
  then
    state.errors, state.current = {}, nil
    return "start"
  end
  if line:match "^%s*Built with build_runner" or line:match "%[INFO%] Succeeded after" then
    close(state)
    state.outputs = tonumber(line:match "wrote (%d+) output" or line:match "with (%d+) output")
    return "ok"
  end
  if line:match "^%s*Failed to build with build_runner" or line:match "%[SEVERE%] Failed after" then
    close(state)
    return "fail"
  end

  -- an error starts: "E builder on file:" / "[SEVERE] builder on file:"
  local builder, file = line:match "^E (%S+) on (.-):%s*$"
  if not builder then
    builder, file = line:match "^%[SEVERE%] (%S+) on (.-):%s*$"
  end
  if builder then
    close(state)
    state.current = { builder = builder, file = file, msg = "" }
    return
  end

  local current = state.current
  if not current then
    return
  end
  -- anything that is not indented ends the error (a warning, the next builder's progress line, a blank line)
  if not line:match "^%s" or line:match "^%s*$" then
    close(state)
    return
  end
  local text = vim.trim(line)
  -- "package:app/user.dart:13:19": where it points in the file
  local lnum, col = text:match "^package:[^:]+:(%d+):(%d+)$"
  if lnum then
    current.lnum, current.col = tonumber(lnum), tonumber(col)
    return
  end
  -- "11:1: Expected a method…": location and message on one line
  local l2, c2, rest = text:match "^(%d+):(%d+): (.+)$"
  if l2 and current.msg == "" then
    current.lnum, current.col, current.msg = tonumber(l2), tonumber(c2), rest
    return
  end
  -- the first line is the message; the rest (hints, links, the code excerpt) is detail for the log
  if current.msg == "" and not text:match "^[│╷╵%d]" then
    current.msg = text
  end
end

--- The generated files a Dart source expects (`part 'x.g.dart';`, `part 'x.freezed.dart';`…), relative to its folder
---@param lines string[]
---@return string[]
function M.generated_parts(lines)
  local parts = {}
  for _, line in ipairs(lines) do
    local part = line:match "^%s*part%s+['\"]([^'\"]+%.%w+%.dart)['\"]%s*;"
    if part then
      parts[#parts + 1] = part
    end
  end
  return parts
end

--- Does the package generate code? (build_runner among its dependencies)
---@param pubspec string text of pubspec.yaml
---@return boolean
function M.uses_codegen(pubspec)
  return pubspec:match "\n%s+build_runner%s*:" ~= nil
end

return M
