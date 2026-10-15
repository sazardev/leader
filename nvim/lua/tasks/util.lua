-- ── Small helpers shared by the task providers ───────────────────────────────
-- Finding a file upwards, running a tool without blocking the editor, quoting a command for the shell. Nothing here knows
-- about a particular runner.
local M = {}

--- Where an upward search stops: the directory ABOVE the git root (so a monorepo's own files are found but not the
--- `~/Makefile` of the machine); without a repo, the home directory
---@param dir string
---@return string?
function M.stop(dir)
  local git = vim.fs.root(dir, ".git")
  if git then
    local parent = vim.fs.dirname(git)
    return parent ~= git and parent or nil
  end
  return vim.uv.os_homedir()
end

--- The nearest of `names` at or above `dir` (never above `stop`)
---@param names string[]
---@param dir string
---@param stop string?
---@return string? absolute path
function M.find_up(names, dir, stop)
  return vim.fs.find(names, { upward = true, path = dir, stop = stop, type = "file", limit = 1 })[1]
end

--- The project a directory belongs to: its git root, else itself
---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, ".git") or dir
end

---@param path string
---@return string[]
function M.lines(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local out = {}
  for line in f:lines() do
    out[#out + 1] = (line:gsub("\r$", ""))
  end
  f:close()
  return out
end

---@param path string
---@return string?
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

--- A string that changes when any of the files does (mtime + size): the key of the task cache
---@param paths string[]
---@return string
function M.stamp(paths)
  local parts = {}
  for _, p in ipairs(paths) do
    local st = vim.uv.fs_stat(p)
    parts[#parts + 1] = st and ("%s:%d.%d:%d"):format(p, st.mtime.sec, st.mtime.nsec, st.size) or (p .. ":-")
  end
  return table.concat(parts, "|")
end

--- Runs a tool in the background; `cb` always runs on the main loop, also when the tool is missing or times out
---@param cmd string[]
---@param opts { cwd: string?, env: table?, timeout: integer? }
---@param cb fun(res: { code: integer, stdout: string, stderr: string })
function M.run(cmd, opts, cb)
  local ok = pcall(vim.system, cmd, {
    cwd = opts.cwd,
    env = opts.env,
    text = true,
    timeout = opts.timeout or require("core.settings").tasks.timeout_ms,
  }, function(res)
    vim.schedule(function()
      cb { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "" }
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb { code = -1, stdout = "", stderr = "could not run " .. tostring(cmd[1]) }
    end)
  end
end

--- Decodes JSON, or nil
---@param text string
---@return any
function M.json(text)
  local ok, data = pcall(vim.json.decode, text)
  return ok and data or nil
end

--- `vim.NIL` and "" are no text
---@param v any
---@return string?
function M.text(v)
  if type(v) == "string" and vim.trim(v) ~= "" then
    return vim.trim(v)
  end
end

--- One shell word: plain words stay as they are (what the terminal echoes stays readable), anything else is quoted
---@param arg string
---@return string
function M.word(arg)
  if arg:match "^[%w_@%%+=:,./%-]+$" then
    return arg
  end
  return vim.fn.shellescape(arg)
end

---@param argv string[]
---@return string
function M.quote(argv)
  return table.concat(vim.tbl_map(M.word, argv), " ")
end

return M
