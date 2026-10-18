-- ── Build with agent · use: a terminal UI, driven in tmux ───────────────────
-- The app runs in a private tmux server (its own socket, no user config) at the scenario's size; keys are sent one at a
-- time like a person types (a burst of characters reaches Bubble Tea as ONE key message, which no binding matches, so
-- typing "12" at once is not what a user does); after each step the screen is read when it has stopped changing. The app
-- runs under `sh -c`, which prints `[exited with N]` when it ends, so a crash or a quit stays on screen.
local async = require "agent.kit.build.use.async"

local M = {}

M.SETTLE_MS = 160 -- the screen must stay the same this long
M.MAX_WAIT_MS = 2500
M.TYPE_GAP_MS = 35

M.KEYS = {
  enter = "Enter",
  ["return"] = "Enter",
  esc = "Escape",
  escape = "Escape",
  tab = "Tab",
  btab = "BTab",
  up = "Up",
  down = "Down",
  left = "Left",
  right = "Right",
  backspace = "BSpace",
  bspace = "BSpace",
  delete = "DC",
  del = "DC",
  space = "Space",
  home = "Home",
  ["end"] = "End",
  pageup = "PPage",
  pagedown = "NPage",
}

--- tmux's name of a key ("Enter", "C-c", "F5"); nil when it is not one
---@param key string
---@return string?
function M.key(key)
  local k = vim.trim(key or "")
  local named = M.KEYS[k:lower()]
  if named then
    return named
  end
  local ctrl = k:match "^[Cc][%-%+](%a)$" or k:match "^[Cc]trl[%-%+](%a)$"
  if ctrl then
    return "C-" .. ctrl:lower()
  end
  if k:match "^[Ff]%d%d?$" then
    return k:upper()
  end
  if #k == 1 then
    return k
  end
end

---@param ctx table
---@param args string[]
---@return { code: integer, stdout: string, stderr: string }
local function tmux(ctx, args)
  local cmd = { "tmux", "-L", ctx.socket }
  vim.list_extend(cmd, args)
  return async.system(cmd)
end

---@return boolean, string?
function M.available()
  if vim.fn.executable "tmux" ~= 1 then
    return false, "tmux is not installed (the terminal UI runs in it)"
  end
  return true
end

---@param ctx table { root, launch, dir }
---@return string? error
function M.prepare(ctx)
  ctx.socket = ("agentbuild-%d-%d"):format(vim.fn.getpid(), vim.uv.hrtime() % 100000)
  ctx.conf = ctx.dir .. "/tmux.conf"
  local f = io.open(ctx.conf, "w")
  if not f then
    return "cannot write " .. ctx.conf
  end
  f:write "set -g status off\nset -g escape-time 0\n"
  f:close()
end

--- The screen now (trailing spaces and blank rows at the bottom out)
---@param ctx table
---@param name string
---@return string
local function capture(ctx, name)
  local res = tmux(ctx, { "capture-pane", "-p", "-t", name })
  local lines = vim.split(res.stdout or "", "\n", { plain = true })
  for i, l in ipairs(lines) do
    lines[i] = l:gsub("%s+$", "")
  end
  while #lines > 0 and lines[#lines] == "" do
    lines[#lines] = nil
  end
  return table.concat(lines, "\n")
end

--- Waits until the screen stops changing (or MAX_WAIT_MS), then returns it
---@param ctx table
---@param name string
---@param first boolean? the app is starting: an empty screen is not settled yet
---@return string
local function settle(ctx, name, first)
  local last, same_since, waited = nil, nil, 0
  local every = 40
  local limit = first and M.MAX_WAIT_MS * 2 or M.MAX_WAIT_MS
  while waited < limit do
    local now = capture(ctx, name)
    if now == last and (not first or now ~= "") then
      same_since = same_since or waited
      if waited - same_since >= M.SETTLE_MS then
        return now
      end
    else
      last, same_since = now, nil
    end
    async.sleep(every)
    waited = waited + every
  end
  return last or ""
end

--- One scenario: frames[1] is the screen it starts on, then one per step
---@param ctx table
---@param scenario UseScenario
---@return UseFrame[]?, string?
function M.play(ctx, scenario)
  local w, h = (scenario.size or "80x24"):match "^(%d+)x(%d+)$"
  local name = ("s%d"):format(vim.uv.hrtime() % 1000000)
  local argv = vim.tbl_map(vim.fn.shellescape, ctx.launch.argv)
  local shell = table.concat(argv, " ") .. '; printf "\\n[exited with %s]\\n" "$?"; sleep 600'
  local args = { "-f", ctx.conf, "new-session", "-d", "-s", name, "-x", w, "-y", h, "-c", ctx.root }
  for k, v in pairs(vim.tbl_extend("force", { TERM = "xterm-256color", COLORTERM = "truecolor" }, ctx.launch.env or {})) do
    vim.list_extend(args, { "-e", k .. "=" .. v })
  end
  vim.list_extend(args, { "sh", "-c", shell })
  local res = tmux(ctx, args)
  if res.code ~= 0 then
    return nil, "tmux could not start the app: " .. vim.trim(res.stderr)
  end
  local frames = { { step = 0, did = ("start at %sx%s"):format(w, h), screen = settle(ctx, name, true) } }
  for i, step in ipairs(scenario.steps) do
    local err
    local d = step["do"]
    if d == "type" then
      for _, ch in ipairs(vim.fn.split(step.text, "\\zs")) do
        tmux(ctx, { "send-keys", "-t", name, "-l", ch })
        async.sleep(M.TYPE_GAP_MS)
      end
    elseif d == "key" then
      local k = M.key(step.key)
      if k then
        tmux(ctx, { "send-keys", "-t", name, k })
      else
        err = ("unknown key %q"):format(step.key)
      end
    elseif d == "resize" then
      local rw, rh = step.size:match "^(%d+)x(%d+)$"
      tmux(ctx, { "resize-window", "-t", name, "-x", rw, "-y", rh })
    elseif d == "wait" then
      async.sleep(step.ms or 300)
    end
    frames[#frames + 1] = {
      step = i,
      did = require("agent.kit.build.use.scenario").describe(step),
      screen = settle(ctx, name),
      error = err,
    }
  end
  tmux(ctx, { "kill-session", "-t", name })
  return frames
end

---@param ctx table
function M.finish(ctx)
  if ctx.socket then
    vim.system({ "tmux", "-L", ctx.socket, "kill-server" }):wait(2000)
  end
end

return M
