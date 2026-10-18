-- ── Build with agent · use: an Android app on a device or emulator (adb) ───
-- Needs one device in `adb devices` (an emulator started by you: `emulator -avd <name>`; the build never starts one).
-- The APK the build compiled is installed, the app starts fresh for every scenario (`pm clear`), and each step is done
-- the way a finger would: the element is found in the screen's hierarchy (uiautomator) and tapped at its center. A
-- frame is that hierarchy as text (role, text, id, place) and a screenshot is kept next to it.
local async = require "agent.kit.build.use.async"

local M = {}

M.SETTLE_MS = 400
M.MAX_WAIT_MS = 6000

---@param ctx table
---@param args string[]
---@param opts table?
---@return { code: integer, stdout: string, stderr: string }
local function adb(ctx, args, opts)
  local cmd = { "adb" }
  if ctx.serial then
    vim.list_extend(cmd, { "-s", ctx.serial })
  end
  vim.list_extend(cmd, args)
  return async.system(cmd, opts)
end

--- The devices `adb devices` lists as ready (pure)
---@param text string
---@return string[]
function M.devices(text)
  local out = {}
  for serial, state in (text or ""):gmatch "\n([%w%-%._:]+)%s+(%a+)" do
    if state == "device" then
      out[#out + 1] = serial
    end
  end
  return out
end

---@param ctx table
---@return boolean, string?
function M.available(ctx)
  if vim.fn.executable "adb" ~= 1 then
    return false, "adb is not installed (Android platform-tools)"
  end
  local res = vim.system({ "adb", "devices" }, { text = true }):wait(5000)
  local list = M.devices(res.stdout)
  local setting = (((require("core.settings").agent.kit or {}).build or {}).drive or {}).android_serial
  if #list == 0 then
    return false, "no Android device or emulator connected (start one: emulator -avd <name>)"
  end
  ctx.serial = setting or list[1]
  if not ctx.launch.package then
    return false, "the application id was not found (applicationId in app/build.gradle)"
  end
  return true
end

---@class AndroidNode
---@field text string
---@field id string
---@field desc string
---@field class string
---@field x1 integer
---@field y1 integer
---@field x2 integer
---@field y2 integer
---@field clickable boolean
---@field focused boolean
---@field checked boolean

--- The visible nodes of a uiautomator dump (pure)
---@param xml string
---@return AndroidNode[]
function M.nodes(xml)
  local out = {}
  local function attr(tag, name)
    local v = tag:match(" " .. name .. '="([^"]*)"')
    return v and v:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#10;", " ") or ""
  end
  for tag in (xml or ""):gmatch "<node%s[^>]*>" do
    local x1, y1, x2, y2 = attr(tag, "bounds"):match "%[(%d+),(%d+)%]%[(%d+),(%d+)%]"
    if x1 and tonumber(x2) > tonumber(x1) and tonumber(y2) > tonumber(y1) then
      out[#out + 1] = {
        text = attr(tag, "text"),
        id = attr(tag, "resource%-id"),
        desc = attr(tag, "content%-desc"),
        class = attr(tag, "class"):match "[%w_]+$" or "",
        x1 = tonumber(x1),
        y1 = tonumber(y1),
        x2 = tonumber(x2),
        y2 = tonumber(y2),
        clickable = attr(tag, "clickable") == "true",
        focused = attr(tag, "focused") == "true",
        checked = attr(tag, "checked") == "true",
      }
    end
  end
  return out
end

--- The screen as a reader would list it: one line per element with something to say (pure)
---@param nodes AndroidNode[]
---@return string
function M.screen(nodes)
  local out = {}
  for _, n in ipairs(nodes) do
    if n.text ~= "" or n.desc ~= "" or (n.clickable and n.id ~= "") then
      local parts = { n.class }
      if n.text ~= "" then
        parts[#parts + 1] = ("%q"):format(n.text)
      end
      if n.desc ~= "" and n.desc ~= n.text then
        parts[#parts + 1] = ("(%s)"):format(n.desc)
      end
      if n.id ~= "" then
        parts[#parts + 1] = "#" .. (n.id:match "[^/]+$" or n.id)
      end
      local flags = {}
      if n.clickable then
        flags[#flags + 1] = "clickable"
      end
      if n.focused then
        flags[#flags + 1] = "focused"
      end
      if n.checked then
        flags[#flags + 1] = "checked"
      end
      local w, h = n.x2 - n.x1, n.y2 - n.y1
      parts[#parts + 1] = ("@%d,%d %dx%d"):format(n.x1, n.y1, w, h)
      if #flags > 0 then
        parts[#parts + 1] = table.concat(flags, " ")
      end
      out[#out + 1] = table.concat(parts, " ")
    end
  end
  return table.concat(out, "\n")
end

--- The node a target names: exact text/desc/id first, then one that contains it (pure)
---@param nodes AndroidNode[]
---@param t table
---@return AndroidNode?
function M.find(nodes, t)
  local want = t.text or t.desc or t.id or t.name
  if not want then
    return nil
  end
  local function value(n)
    return (t.text and n.text) or (t.desc and n.desc) or (t.id and n.id) or n.text
  end
  for _, n in ipairs(nodes) do
    local v = value(n)
    if v == want or (t.id and v:match "[^/]+$" == want) then
      return n
    end
  end
  for _, n in ipairs(nodes) do
    if value(n):lower():find(want:lower(), 1, true) then
      return n
    end
  end
end

---@param ctx table
---@return AndroidNode[], string xml
local function dump(ctx)
  local res = adb(ctx, { "exec-out", "uiautomator", "dump", "/dev/tty" })
  local xml = (res.stdout or ""):gsub("UI hierch?a?r?chy dumped to.*$", "")
  return M.nodes(xml), xml
end

---@param ctx table
---@return AndroidNode[]
local function settle(ctx)
  local last, waited = nil, 0
  while waited < M.MAX_WAIT_MS do
    local nodes, xml = dump(ctx)
    if xml == last and #nodes > 0 then
      return nodes
    end
    last = xml
    async.sleep(M.SETTLE_MS)
    waited = waited + M.SETTLE_MS
  end
  return (dump(ctx))
end

--- Text for `adb shell input text` (spaces as %s, shell characters escaped)
---@param text string
---@return string
function M.input_text(text)
  return (text:gsub("([\\'\"`$&|;<>()%[%]*?~#!{}])", "\\%1"):gsub(" ", "%%s"))
end

---@param ctx table
---@return string?
function M.prepare(ctx)
  local apks = vim.fn.glob(ctx.root .. "/" .. ctx.launch.apk, false, true)
  if #apks == 0 then
    return "the build wrote no APK (" .. ctx.launch.apk .. ")"
  end
  local res = adb(ctx, { "install", "-r", "-t", apks[1] }, { timeout = 120000 })
  if res.code ~= 0 then
    return "adb install failed: " .. vim.trim(res.stdout .. res.stderr):sub(-400)
  end
end

---@param ctx table
---@param scenario UseScenario
---@param index integer
---@return UseFrame[]?, string?
function M.play(ctx, scenario, index)
  local pkg = ctx.launch.package
  local shots = ("%s/scenario-%02d"):format(ctx.dir, index)
  vim.fn.mkdir(shots, "p")
  adb(ctx, { "shell", "pm", "clear", pkg })
  adb(ctx, { "shell", "monkey", "-p", pkg, "-c", "android.intent.category.LAUNCHER", "1" })
  local function frame(i, did, err)
    local nodes = settle(ctx)
    local image = ("%s/step-%02d.png"):format(shots, i)
    local png = adb(ctx, { "exec-out", "screencap", "-p" }, { text = false })
    local f = png.code == 0 and io.open(image, "wb")
    if f then
      f:write(png.stdout)
      f:close()
    end
    return { step = i, did = did, screen = M.screen(nodes), image = f and image or nil, error = err, nodes = nodes }
  end
  local frames = { frame(0, "start") }
  for i, step in ipairs(scenario.steps) do
    local err
    local d = step["do"]
    if d == "tap" then
      local n = M.find(frames[#frames].nodes or {}, step.target)
      if n then
        adb(
          ctx,
          { "shell", "input", "tap", tostring(math.floor((n.x1 + n.x2) / 2)), tostring(math.floor((n.y1 + n.y2) / 2)) }
        )
      else
        err = "no element matches " .. vim.json.encode(step.target)
      end
    elseif d == "type" then
      adb(ctx, { "shell", "input", "text", M.input_text(step.text) })
    elseif d == "key" then
      adb(ctx, { "shell", "input", "keyevent", "KEYCODE_" .. step.key:upper():gsub("^KEYCODE_", "") })
    elseif d == "swipe" then
      local sw, sh = adb(ctx, { "shell", "wm", "size" }).stdout:match "(%d+)x(%d+)"
      local w, h = tonumber(sw) or 1080, tonumber(sh) or 1920
      local cx, cy = math.floor(w / 2), math.floor(h / 2)
      local moves = {
        up = { cx, math.floor(h * 0.75), cx, math.floor(h * 0.25) },
        down = { cx, math.floor(h * 0.25), cx, math.floor(h * 0.75) },
        left = { math.floor(w * 0.8), cy, math.floor(w * 0.2), cy },
        right = { math.floor(w * 0.2), cy, math.floor(w * 0.8), cy },
      }
      local m = moves[step.direction]
      if m then
        adb(ctx, { "shell", "input", "swipe", tostring(m[1]), tostring(m[2]), tostring(m[3]), tostring(m[4]), "250" })
      else
        err = "unknown direction " .. step.direction
      end
    elseif d == "wait" then
      async.sleep(step.ms or 500)
    end
    frames[#frames + 1] = frame(i, require("agent.kit.build.use.scenario").describe(step), err)
  end
  for _, f in ipairs(frames) do
    f.nodes = nil
  end
  adb(ctx, { "shell", "am", "force-stop", pkg })
  return frames
end

---@param ctx table
function M.finish(ctx) end

return M
