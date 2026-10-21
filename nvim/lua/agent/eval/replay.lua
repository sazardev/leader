-- ── Cassettes: a model's answers on tape ─────────────────────────────────────
-- A live eval costs tokens and varies from run to run. A cassette is the answer a model gave to one case, saved
-- (`evals/cassettes/<case id>/<model>.json`: { text, usage }), and the `replay` backend plays it back through the whole
-- pipeline, so the parsers, the presenters and the judges are regression-tested for free, offline, and identically every
-- time. Two models are built in and need no file: `noop` (answers with nothing useful: every case must FAIL it) and
-- `golden` (the hand-written good answer: every case must pass it).
local M = {}

---@type { case: AgentEvalCase?, model: string?, target_lines: string[]?, root: string? }
M.current = {}

---@param s string
---@return string
local function slug(s)
  return (s:gsub("[^%w%.%-]+", "_"))
end

---@param root string
---@param case_id string
---@param model string
---@return string
function M.path(root, case_id, model)
  return ("%s/cassettes/%s/%s.json"):format(root, case_id, slug(model))
end

---@param root string
---@param case_id string
---@param model string
---@return { text: string, usage: table? }?
function M.load(root, case_id, model)
  local path = M.path(root, case_id, model)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, tape = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and type(tape) == "table" and tape or nil
end

---@param root string
---@param case_id string
---@param model string
---@param tape { text: string, usage: table? }
function M.save(root, case_id, model, tape)
  local path = M.path(root, case_id, model)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(vim.json.encode(tape), "\n", { plain = true }), path)
end

--- What a model that does nothing useful says: the target back untouched, or "all good"
---@param action table
---@param target_lines string[]
---@return string
function M.noop_text(action, target_lines)
  if action.output == "findings" then
    return "OK"
  end
  return "```\n" .. table.concat(target_lines, "\n") .. "\n```"
end

--- The answer for what is being run now
---@return string? text, table? usage, string? err
function M.answer()
  local cur = M.current
  if not cur.case then
    return nil, nil, "replay: nothing is being run"
  end
  if cur.model == "noop" then
    return M.noop_text(require("agent.actions").get(cur.case.action), cur.target_lines or {}),
      { tokens_in = 0, tokens_out = 0 }
  end
  local tape = M.load(cur.root, cur.case.id, cur.model)
  if not tape then
    return nil, nil, ("no cassette for %s with %s"):format(cur.case.id, cur.model)
  end
  return tape.text, tape.usage or { tokens_in = 0, tokens_out = 0 }
end

--- Registers the `replay` backend (idempotent)
function M.register()
  require("agent.backends").register("replay", {
    name = "replay",
    label = "Replay",
    available = function()
      return true
    end,
    models = function(cb)
      cb { { id = "golden" }, { id = "noop" } }
    end,
    build = function()
      local text, _, err = M.answer()
      if not text then
        return { cmd = { "sh", "-c", 'echo "$1" >&2; exit 3', "sh", err }, cwd = "/tmp" }
      end
      return { cmd = { "printf", "%s", text }, cwd = "/tmp" }
    end,
    parser = function()
      local buf = {}
      return {
        feed = function(chunk)
          buf[#buf + 1] = chunk
          return chunk
        end,
        finish = function(code, stderr)
          if code ~= 0 then
            return { ok = false, err = vim.trim(stderr or "") ~= "" and vim.trim(stderr) or "replay failed" }
          end
          local _, usage = M.answer()
          return { ok = true, text = table.concat(buf), usage = usage }
        end,
      }
    end,
  })
end

return M
