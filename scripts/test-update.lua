-- Tests of nvim/lua/update: versions, the changelog, the status, the lookup against a fake "GitHub" made of files, the
-- interval, the one announcement per version and skipping. No network.
local ROOT = vim.env.AGENT_TEST_ROOT
vim.opt.rtp:prepend(ROOT .. "/nvim")
local failures = 0
local function check(name, cond, detail)
  if cond then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name .. (detail and (": " .. vim.inspect(detail)) or ""))
  end
end

local semver = require "update.semver"
check(
  "parse",
  vim.deep_equal(semver.parse "v1.8.0", { 1, 8, 0 }) and semver.parse "nope" == nil and semver.parse(nil) == nil
)
check(
  "compare numbers, not text",
  semver.compare("1.10.0", "1.9.0") == 1
    and semver.compare("1.8.0", "1.8.0") == 0
    and semver.compare("0.9.9", "1.0.0") == -1
)
check(
  "a pre-release is before its release",
  semver.compare("1.9.0-rc1", "1.9.0") == -1 and semver.newer("1.9.0", "1.9.0-rc1")
)
check("newer: nothing is newer than junk", not semver.newer("2.0.0", "junk") and not semver.newer(nil, "1.0.0"))
check("clean", semver.clean "v1.2.3\n" == "1.2.3")

local changelog = require "update.changelog"
local f = io.open(ROOT .. "/CHANGELOG.md")
local real = f:read "*a"
f:close()
local sections = changelog.sections(real)
check(
  "the real CHANGELOG has sections, newest first",
  #sections > 3 and semver.newer(sections[1].version, sections[2].version),
  sections[1]
)
check("a section has its date and lines", sections[1].date ~= nil and #sections[1].lines > 3)
local text =
  "# Changelog\n\n## [1.9.0] - 2026-11-01\n\n### Features\n\n- **x:** a thing (abc1234)\n\n## [1.8.0] - 2026-10-20\n\n- old\n\n## [1.7.0] - 2026-10-19\n\n- older\n"
local secs = changelog.sections(text)
check(
  "sections split on version headings",
  #secs == 3 and secs[1].version == "1.9.0" and secs[3].date == "2026-10-19",
  secs
)
check(
  "between: newer than the installed, up to the latest",
  vim.deep_equal(
    vim.tbl_map(function(s)
      return s.version
    end, changelog.between(secs, "1.7.0", "1.9.0")),
    { "1.9.0", "1.8.0" }
  )
)
check("between: nothing when up to date", #changelog.between(secs, "1.9.0") == 0)
local rendered = changelog.render(secs[1], 60)
local flat = table.concat(
  vim.tbl_map(function(l)
    return table.concat(vim.tbl_map(function(seg)
      return seg[1]
    end, l))
  end, rendered),
  "\n"
)
check(
  "render: heading, bullet without markdown or the commit hash",
  flat:find("FEATURES", 1, true)
    and flat:find("• x: a thing", 1, true)
    and not flat:find("abc1234", 1, true)
    and not flat:find("**", 1, true),
  flat
)

-- status over fake targets, without I/O
local update = require "update"
local function target(id, current, latest_of)
  return {
    id = id,
    label = id,
    current = function()
      return current
    end,
    latest = latest_of,
  }
end
local cfg_t = target("config", "1.8.0", function(i)
  return i.version
end)
local app_t = target("app", "1.7.0", function(i)
  return i.release
end)
local st = update.status({ latest = "1.9.0", release = "1.8.0" }, { cfg_t, app_t })
check(
  "status: both behind",
  st.available and st.targets[1].available and st.targets[2].available and st.latest == "1.9.0",
  st
)
st = update.status({ latest = "1.8.0", release = "1.7.0" }, { cfg_t, app_t })
check("status: up to date", not st.available and not st.targets[2].available, st)
st = update.status({ latest = "1.9.0", release = "1.7.0", skipped = "1.9.0" }, { cfg_t, app_t })
check("status: a skipped version is not offered", st.available and st.skipped)
st = update.status({}, { cfg_t })
check("status: nothing known yet means nothing to offer", not st.available and st.latest == nil)
st = update.status({ latest = "1.9.0" }, { target("config", nil, cfg_t.latest) })
check("status: a target with no known version is not behind", not st.available)

-- the real lookup, against files
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "9.9.9" }, dir .. "/VERSION")
vim.fn.writefile(vim.split(text:gsub("1%.9%.0", "9.9.9"), "\n"), dir .. "/CHANGELOG.md")
local settings = require "core.settings"
settings.update = {
  enabled = true,
  check_hours = 12,
  notify = true,
  repo = "x/y",
  branch = "master",
  base = "file://" .. dir,
  releases = false,
}
local store = require "update.store"
local state = vim.fn.tempname()
store.FILE = state
store.reset()

local notes = {}
local orig_notify = vim.notify
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
local results = {}
update.check {
  force = true,
  done = function(s)
    results[#results + 1] = s
  end,
}
vim.wait(8000, function()
  return #results > 0
end)
local saved_json = table.concat(vim.fn.readfile(state), "")
check("a good lookup leaves no null in the saved file", not saved_json:find("null", 1, true), saved_json)
store.reset()
check(
  "an old null reads as nothing",
  (function()
    vim.fn.writefile({ '{"error":null,"latest":"1.0.0"}' }, state)
    store.reset()
    return store.get().error == nil and store.get().latest == "1.0.0"
  end)()
)
store.reset()
vim.fn.writefile({ saved_json }, state)
store.reset()
check("lookup finds a newer version", results[1] and results[1].available and results[1].latest == "9.9.9", results[1])
check("the changelog is fetched with it", (store.get().changelog or ""):find("9.9.9", 1, true) ~= nil)
check("it is announced once", #notes == 1 and notes[1]:find("9.9.9", 1, true) ~= nil, notes)
update.check {
  force = true,
  done = function(s)
    results[#results + 1] = s
  end,
}
vim.wait(8000, function()
  return #results > 1
end)
check("not announced again for the same version", #notes == 1, notes)
check("not due right after a look", not update.due())
store.set { checked_at = os.time() - 13 * 3600 }
check("due after the interval", update.due())
settings.update.enabled = false
check("never due when turned off", not update.due())
settings.update.enabled = true
local offered, latest = update.offer()
check("offer: the version on offer", offered and latest == "9.9.9")
update.skip()
check("skip hides it", not (update.offer()))
-- an offline lookup fails quietly and is retried after an hour, not after twelve
settings.update.base = "file://" .. dir .. "/missing"
local failed
update.check {
  force = true,
  done = function(s)
    failed = s
  end,
}
vim.wait(8000, function()
  return failed ~= nil
end)
check("offline: an error is kept, no message", failed and failed.error ~= nil and #notes == 1, failed)
store.set { checked_at = os.time() - 2 * 3600 }
check("offline: tried again after an hour", update.due())
vim.notify = orig_notify
store.reset()

print(failures == 0 and "ALL OK" or ("FAILURES: " .. failures))
vim.cmd(failures == 0 and "qa!" or "cq!")
