-- ── Build with agent · use: the app, used like its user would ──────────────
-- Green checks say the code agrees with its own tests. This phase asks the user's question: does it do what SPEC.md
-- promises, and can I tell? The app is recognized (launch.lua), its scenarios are written once from SPEC.md and
-- DESIGN.md (scenario.lua), a driver per kind of app performs them and reads the screen after each step (drivers/: tui in
-- tmux, cli by running it, web and Electron in Playwright, android over adb), the free checks score every frame and one
-- request judges the whole experience (judge.lua). The frames and screenshots stay in the state dir for you to open.
-- A driver = one file with available(ctx), prepare(ctx), play(ctx, scenario, i), finish(ctx), + its line in DRIVERS.
local async = require "agent.kit.build.use.async"
local judge = require "agent.kit.build.use.judge"

local M = {}

--- The driver of each kind of app (Electron shares the browser's)
M.DRIVERS = { tui = "tui", cli = "cli", web = "web", electron = "web", android = "android" }

---@param kind string
---@return table
function M.driver(kind)
  return require("agent.kit.build.use.drivers." .. M.DRIVERS[kind])
end

--- The folder of this project's use runs (state dir): the binary, and one folder per round with frames and screenshots
---@param root string
---@return string
function M.home(root)
  return vim.fn.stdpath "state" .. "/agent-build/" .. vim.fn.sha256(root):sub(1, 16) .. "-use"
end

--- What kind of app is at `root` and whether it can be driven here, before any token is spent
---@param root string
---@param stack string?
---@param pm string?
---@return table? ctx { root, launch }, string? why not
function M.ready(root, stack, pm)
  local home = M.home(root)
  vim.fn.mkdir(home, "p")
  local launch, why = require("agent.kit.build.use.launch").detect(root, stack, home .. "/app", pm)
  if not launch then
    return nil, why
  end
  local ctx = { root = root, launch = launch }
  local ok, missing = M.driver(launch.kind).available(ctx)
  if not ok then
    return nil, ("%s · %s"):format(launch.what, missing)
  end
  return ctx
end

---@class UsePlayOpts
---@field round integer
---@field cancelled fun(): boolean
---@field progress fun(text: string)

--- Builds the app, then performs every scenario; `done(results)` or `done(nil, why)`. The driver always finishes (the
--- server stops, tmux goes) whatever happened.
---@param ctx table from ready()
---@param scenarios UseScenario[]
---@param opts UsePlayOpts
---@param done fun(results: UseResult[]?, err: string?)
function M.play(ctx, scenarios, opts, done)
  ctx.dir = ("%s/round-%d"):format(M.home(ctx.root), opts.round)
  vim.fn.delete(ctx.dir, "rf")
  vim.fn.mkdir(ctx.dir, "p")
  local driver = M.driver(ctx.launch.kind)
  async.run(function()
    if ctx.launch.build then
      opts.progress("building the app · " .. table.concat(ctx.launch.build, " "))
      local res = async.system(ctx.launch.build, { cwd = ctx.root, timeout = 600000 })
      if res.code ~= 0 then
        return nil, "the app does not build: " .. vim.trim(res.stdout .. "\n" .. res.stderr):sub(-1500)
      end
    end
    local err = driver.prepare(ctx)
    if err then
      return nil, err
    end
    local results = {}
    for i, sc in ipairs(scenarios) do
      if opts.cancelled() then
        break
      end
      opts.progress(("%d/%d · %s"):format(i, #scenarios, sc.name))
      local frames, perr = driver.play(ctx, sc, i)
      local r = { scenario = sc, frames = frames or {}, error = perr, failures = perr and 1 or 0 }
      if frames then
        r.failures = judge.score(sc, frames)
      end
      results[#results + 1] = r
    end
    return results
  end, function(ok, results, err)
    pcall(driver.finish, ctx)
    if not ok then
      return done(nil, tostring(results))
    end
    if results then
      local f = io.open(ctx.dir .. "/frames.json", "w")
      if f then
        f:write(vim.json.encode(results))
        f:close()
      end
    end
    done(results, err)
  end)
end

--- One line per scenario for the feed: "✓ add two numbers" / "✗ chain operations · step 4: "14" is not on the screen"
---@param results UseResult[]
---@return { ok: boolean, text: string }[]
function M.lines(results)
  local out = {}
  for _, r in ipairs(results) do
    if r.error then
      out[#out + 1] = { ok = false, text = ("✗ %s · %s"):format(r.scenario.name, r.error) }
    elseif r.failures == 0 then
      out[#out + 1] = { ok = true, text = "✓ " .. r.scenario.name }
    else
      local first
      for _, f in ipairs(r.frames) do
        if f.failures and #f.failures > 0 then
          first = ("step %d (%s): %s"):format(f.step, f.did, f.failures[1])
          break
        end
      end
      out[#out + 1] = { ok = false, text = ("✗ %s · %s"):format(r.scenario.name, first or "failed") }
    end
  end
  return out
end

return M
