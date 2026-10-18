-- ── Build with agent · use: a web app (or an Electron app) in Playwright ───
-- The app's server starts once (its dev script, a static folder, or the server the project builds, asked to use a free
-- PORT; the URL it prints wins), each scenario runs in a fresh browser page through web_runner.cjs, and the server stops
-- at the end. Playwright comes from the project, else from a global install (npm -g, mise), else
-- `settings.agent.kit.build.drive.playwright`; its Chromium must be installed (`npx playwright install chromium`).
local async = require "agent.kit.build.use.async"

local M = {}

M.START_TIMEOUT_MS = 60000
M.SCENARIO_TIMEOUT_MS = 120000

local RUNNER = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/web_runner.cjs"

--- Where the `playwright` package is: the project's node_modules, the setting, npm's global root, mise's install
---@param root string
---@return string?
function M.module(root)
  local setting = (((require("core.settings").agent.kit or {}).build or {}).drive or {}).playwright
  local candidates = {
    root .. "/node_modules/playwright",
    root .. "/node_modules/@playwright/test/node_modules/playwright",
    setting,
  }
  local function add_from(cmd, suffix)
    if vim.fn.executable(cmd[1]) == 1 then
      local res = vim.system(cmd, { text = true }):wait(5000)
      local dir = res.code == 0 and vim.trim(res.stdout or "") or ""
      if dir ~= "" then
        candidates[#candidates + 1] = dir .. suffix
      end
    end
  end
  add_from({ "npm", "root", "-g" }, "/playwright")
  add_from({ "mise", "where", "npm:playwright" }, "/node_modules/playwright")
  for _, c in ipairs(candidates) do
    if c and vim.uv.fs_stat(c .. "/package.json") then
      return c
    end
  end
end

---@return boolean, string?
function M.available(ctx)
  if vim.fn.executable "node" ~= 1 then
    return false, "node is not installed (Playwright drives the browser from it)"
  end
  local mod = M.module(ctx.root)
  if not mod then
    return false, "Playwright is not installed (npm i -g playwright && npx playwright install chromium)"
  end
  -- the browser this Playwright version expects starts (a new Playwright needs its own Chromium download)
  local probe = vim
    .system({
      "node",
      "-e",
      "require(process.argv[1]).chromium.launch().then(b=>b.close()).then(()=>process.stdout.write('ok'),e=>process.stdout.write(String(e.message).split('\\n')[0]))",
      mod,
    }, { text = true })
    :wait(15000)
  if vim.trim(probe.stdout or "") ~= "ok" then
    return false,
      ("Playwright's Chromium is not installed (%s install chromium)"):format(
        mod:find "node_modules/playwright$" and ("node " .. mod .. "/cli.js") or "npx playwright"
      )
  end
  ctx.playwright = mod
  return true
end

--- The first local URL a server printed (`Local: http://localhost:5173/`), its colors gone
---@param text string
---@return string?
function M.url_in(text)
  text = (text or ""):gsub("\27%[[%d;]*m", "")
  local url = text:match "(https?://localhost:%d+[%w%-%._~/]*)"
    or text:match "(https?://127%.0%.0%.1:%d+[%w%-%._~/]*)"
    or text:match "(https?://%[::1%]:%d+[%w%-%._~/]*)"
  if not url then
    local port = text:match "https?://0%.0%.0%.0:(%d+)"
    url = port and ("http://127.0.0.1:" .. port .. "/") or nil
  end
  return url
end

--- Does the URL answer (any HTTP status)?
---@param url string
---@return boolean
local function answers(url)
  local res = async.system { "curl", "-s", "-o", "/dev/null", "-m", "2", "-w", "%{http_code}", url }
  return res.code == 0 and (tonumber(res.stdout) or 0) > 0
end

---@param ctx table { root, launch, dir }
---@return string? error
function M.prepare(ctx)
  if ctx.launch.kind == "electron" then
    return nil
  end
  local port = require("agent.kit.build.use.launch").free_port()
  local argv
  if ctx.launch.static then
    argv = { "python3", "-m", "http.server", tostring(port), "--bind", "127.0.0.1", "--directory", ctx.launch.static }
  else
    argv = ctx.launch.argv
  end
  local printed = {}
  local function collect(_, data)
    if data then
      printed[#printed + 1] = data
    end
  end
  local env = vim.tbl_extend(
    "force",
    { PORT = tostring(port), HOST = "127.0.0.1", BROWSER = "none", CI = "1" },
    ctx.launch.env or {}
  )
  local ok, proc = pcall(
    vim.system,
    argv,
    { cwd = ctx.root, env = env, stdout = collect, stderr = collect, text = true, detach = true }
  )
  if not ok then
    return "could not start the server: " .. tostring(proc)
  end
  ctx.server = proc
  local guess = "http://127.0.0.1:" .. port .. "/"
  ctx.url = async.until_(function()
    local said = M.url_in(table.concat(printed))
    if said and answers(said) then
      return said
    end
    if answers(guess) then
      return guess
    end
  end, M.START_TIMEOUT_MS, 300)
  if not ctx.url then
    return ("the server did not answer in %ds (%s): %s"):format(
      M.START_TIMEOUT_MS / 1000,
      table.concat(argv, " "),
      vim.trim(table.concat(printed)):sub(-600)
    )
  end
end

---@param ctx table
---@param scenario UseScenario
---@param index integer
---@return UseFrame[]?, string?
function M.play(ctx, scenario, index)
  local input = vim.json.encode {
    mode = ctx.launch.kind == "electron" and "electron" or "web",
    url = ctx.url,
    root = ctx.root,
    viewport = scenario.viewport,
    steps = scenario.steps,
    shots = ("%s/scenario-%02d"):format(ctx.dir, index),
  }
  local res = async.system({ "node", RUNNER }, {
    cwd = ctx.root,
    stdin = input,
    timeout = M.SCENARIO_TIMEOUT_MS,
    env = { PLAYWRIGHT_MODULE = ctx.playwright },
  })
  if res.code ~= 0 then
    return nil, "the browser could not run the scenario: " .. vim.trim(res.stderr):sub(1, 600)
  end
  local ok, frames = pcall(vim.json.decode, res.stdout, { luanil = { object = true, array = true } })
  if not ok or type(frames) ~= "table" then
    return nil, "the browser runner answered no frames"
  end
  return frames
end

---@param ctx table
function M.finish(ctx)
  if ctx.server then
    -- the whole group: `npm run dev` leaves its vite child running otherwise (started detached = its own group)
    pcall(vim.uv.kill, -ctx.server.pid, "sigterm")
    pcall(function()
      ctx.server:kill(15)
    end)
    ctx.server = nil
  end
end

return M
