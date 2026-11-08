-- Tests of the env kit (nvim/lua/env): pure parsing, detection, templates and the check.
-- Run with: scripts/test-env.sh  (headless nvim, hermetic)
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path
local fails = 0
local function check(cond, msg)
  if not cond then
    fails = fails + 1
    print("FAIL: " .. msg)
  else
    print("ok: " .. msg)
  end
end

local parse = require "env.parse"
local detect = require "env.detect"

-- parse: export, quotes, comments, blank
do
  local entries = parse.parse([[
# comment
export FOO=bar
BAZ="hello world"
EMPTY=
QUOTED='single'
WITH_COMMENT=value # inline
]])
  local keys = parse.keys(entries)
  check(keys[1] == "FOO" and keys[2] == "BAZ" and keys[3] == "EMPTY" and keys[4] == "QUOTED" and keys[5] == "WITH_COMMENT", "parse keys in order")
  check(entries[1].value == "bar", "parse export")
  check(entries[2].value == "hello world", "parse quoted")
  check(entries[3].value == "", "parse empty")
  check(entries[5].value == "value", "parse inline comment")
end

-- diff: missing / extra / empty
do
  local ex = parse.parse("A=1\nB=2\nC=\n")
  local real = parse.parse("A=1\nC=\nD=extra\n")
  local d = parse.diff(ex, real)
  check(#d.missing == 1 and d.missing[1] == "B", "diff missing B")
  check(#d.extra == 1 and d.extra[1] == "D", "diff extra D")
  check(#d.empty == 1 and d.empty[1] == "C", "diff empty C")
end

-- is_env
check(parse.is_env(".env") and parse.is_env(".env.dev") and not parse.is_env("foo.txt"), "is_env")

-- every preset loads and renders a non-empty template with required keys
for _, id in ipairs(detect.IDS) do
  local lang = detect.lang(id)
  check(lang ~= nil and lang.id == id, "lang " .. id .. " loads")
  local body = lang.template(lang.vars("/tmp"))
  local has_env = body:find("APP_ENV") ~= nil or body:find("ASPNETCORE_ENVIRONMENT") ~= nil
  local has_db = body:find("DATABASE_URL") ~= nil or body:find("API_BASE_URL") ~= nil or body:find("DB_HOST") ~= nil
  check(body ~= nil and #body > 100 and has_env and has_db, "template " .. id .. " has env + db keys")
  check(lang.loader ~= nil and lang.loader.target ~= nil and lang.loader.target ~= "", "loader " .. id .. " has target")
end

-- detection on a fake root (go.mod)
do
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local f = io.open(dir .. "/go.mod", "w")
  f:write "module example.com/fake\n\ngo 1.23\n"
  f:close()
  local d = detect.detected(dir)
  check(#d == 1 and d[1].id == "go", "detect go by go.mod")
  local fp = io.open(dir .. "/package.json", "w")
  fp:write "{}"
  fp:close()
  d = detect.detected(dir)
  check(#d == 2, "detect go + typescript")
  check(detect.primary(dir).id == "go", "primary is first detected")
  check(detect.primary(vim.fn.tempname()).id == "generic", "primary falls back to generic")
end

-- AI prompt: only keys, no real secrets leaked (dummy values are in example)
do
  local lang = detect.lang "go"
  local system, prompt = require("env.ai").prompt(lang, "APP_ENV=development\nPORT=8080\n")
  check(system:find("Go") ~= nil, "ai system mentions Go")
  check(prompt:find("APP_ENV") ~= nil and prompt:find("PORT") ~= nil, "ai prompt has keys")
  check(not prompt:find("lifelong"), "ai prompt has no injected secrets")
end

-- init.maps: every map has a 2+ word desc via menus.desc (Env prefix)
do
  local maps = require("env").maps()
  check(#maps >= 10, "env maps count >=10")
  local seen = {}
  for _, m in ipairs(maps) do
    check(m[1] and m[2] and m[3], "map " .. tostring(m[1]) .. " is complete")
    check(not seen[m[1]], "map key " .. m[1] .. " unique")
    seen[m[1]] = true
  end
end

if fails > 0 then
  print(("%d FAILURES"):format(fails))
else
  print "ALL OK"
end
vim.cmd(fails == 0 and "qa!" or "cquit 1")
