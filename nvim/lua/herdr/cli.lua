-- ── Herdr CLI ─────────────────────────────────────────────────────────────────
-- The only place that knows HOW herdr is called: which binary (the one Herdr handed us inside a pane, the one on PATH
-- outside), the JSON it answers with and the timeout of every call. Everything else in lua/herdr/ goes through it.
--
-- The CLI talks to the running server through the local socket (HERDR_SOCKET_PATH inside a pane, the default one
-- outside), so the calls work from a plain terminal too.
local M = {}

local TIMEOUT_MS = 8000

---@return string? the binary to call
function M.bin()
  if (vim.env.HERDR_BIN_PATH or "") ~= "" then
    return vim.env.HERDR_BIN_PATH
  end
  if vim.fn.executable "herdr" == 1 then
    return "herdr"
  end
  return nil
end

---@return boolean
function M.installed()
  return M.bin() ~= nil
end

--- Are we running inside a Herdr pane?
---@return boolean
function M.inside()
  return vim.env.HERDR_ENV == "1" and (vim.env.HERDR_PANE_ID or "") ~= ""
end

---@param args string[]
---@return string[]
local function cmd(args)
  return vim.list_extend({ M.bin() }, args)
end

--- What to say when a call fails: what herdr said, or what it could not do
---@param out vim.SystemCompleted
---@param args string[]
---@return string
function M.error(out, args)
  local err = (out.stderr or ""):gsub("%s+$", "")
  if err == "" then
    err = (out.stdout or ""):gsub("%s+$", "") -- some commands answer with the error in stdout
  end
  -- herdr answers with a JSON error: { "error": { "code": …, "message": … } }
  local message = err:match '"message"%s*:%s*"(.-)"'
  if message then
    err = message
  end
  if err == "" then
    err = ("herdr %s failed (code %s)"):format(args[1] or "", tostring(out.code))
  end
  return err
end

--- The answer of a command: the parsed JSON, or an empty table when it said NOTHING (it did its job:
--- `pane report-agent` and `pane release-agent` answer with no output at all).
---@param stdout string?
---@return table? data, string? err
function M.parse(stdout)
  local text = (stdout or ""):gsub("%s+$", "")
  if text == "" then
    return {}, nil
  end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil, "herdr answered with something that is not JSON"
  end
  return data, nil
end

--- Runs herdr and parses the JSON it answers with.
---@param args string[]
---@param cb fun(ok: boolean, data: table?, err: string?)
function M.json(args, cb)
  if not M.bin() then
    return cb(false, nil, "herdr is not installed")
  end
  vim.system(cmd(args), { text = true, timeout = TIMEOUT_MS }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        return cb(false, nil, M.error(out, args))
      end
      local data, err = M.parse(out.stdout)
      if err then
        return cb(false, nil, err)
      end
      cb(true, data, nil)
    end)
  end)
end

--- Runs herdr and gives back its plain text (the transcripts, the version).
---@param args string[]
---@param cb fun(ok: boolean, text: string?, err: string?)
function M.text(args, cb)
  if not M.bin() then
    return cb(false, nil, "herdr is not installed")
  end
  vim.system(cmd(args), { text = true, timeout = TIMEOUT_MS }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        return cb(false, nil, M.error(out, args))
      end
      cb(true, out.stdout or "", nil)
    end)
  end)
end

--- Runs herdr and waits for it: only when nvim is on its way out and the answer is needed before it goes.
---@param args string[]
---@return boolean
function M.sync(args)
  if not M.bin() then
    return false
  end
  local ok, handle = pcall(vim.system, cmd(args), { text = true, timeout = 2000 })
  if not ok then
    return false
  end
  handle:wait(2000)
  return true
end

return M
