-- Tests for scripts/install-local.lua: the per-machine settings written by install.sh and install.ps1.
-- Hermetic: writes to a temporary directory, without touching nvim/lua/local.lua.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

local root = os.getenv "AGENT_TEST_ROOT" or vim.fn.getcwd()
vim.g.install_local_test = true
local il = dofile(root .. "/scripts/install-local.lua")

local names = il.language_names(root)
eq(
  "names: come from the language registry (lua first, 19 in total)",
  { names[1], names[2], #names },
  { "lua", "go", 19 }
)

local settings = il.plan({ langs = "go, typescript" }, names)
eq("--lang: everything that is neither lua nor requested gets disabled", {
  vim.tbl_contains(settings.languages.disabled, "go"),
  vim.tbl_contains(settings.languages.disabled, "typescript"),
  vim.tbl_contains(settings.languages.disabled, "lua"),
  vim.tbl_contains(settings.languages.disabled, "rust"),
  #settings.languages.disabled,
}, { false, false, false, true, 16 })
local bad, err = il.plan({ langs = "go,cobol" }, names)
eq(
  "--lang: an unknown one is an error with the list of available ones",
  { bad, err:match "^unknown language: cobol" ~= nil, err:find("rust", 1, true) ~= nil },
  { nil, true, true }
)
eq("--theme", il.plan({ theme = "catppuccin" }, names), { theme = { name = "catppuccin" } })
eq(
  "--light / --no-light",
  { il.plan({ light = "1" }, names), il.plan({ light = "0" }, names) },
  { { light = { force = true } }, { light = { force = false } } }
)
eq("with no options there is nothing to write", il.plan({}, names), {})
eq(
  "render: stable Lua table (sorted keys)",
  il.render { theme = { name = "x" }, light = { force = true }, languages = { disabled = { "go", "rust" } } },
  'return { languages = { disabled = { "go", "rust" } }, light = { force = true }, theme = { name = "x" } }'
)

-- the full script (as the installer calls it): writes, does not overwrite an existing one, and fails with exit 2
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local target = tmp .. "/local.lua"
local function run(env)
  local res = vim
    .system({ "nvim", "-u", "NONE", "--headless", "-l", root .. "/scripts/install-local.lua" }, {
      text = true,
      env = vim.tbl_extend("force", { NVIM_INSTALL_LOCAL = target }, env),
    })
    :wait()
  return res.code, (res.stdout or "") .. (res.stderr or "")
end
local code, out = run { NVIM_INSTALL_LANGS = "go", NVIM_INSTALL_THEME = "gruvbox", NVIM_INSTALL_DRY = "1" }
eq(
  "dry-run: does not write and says so",
  { code, vim.uv.fs_stat(target), out:find("[dry-run]", 1, true) ~= nil },
  { 0, nil, true }
)
code, out = run { NVIM_INSTALL_LANGS = "go", NVIM_INSTALL_THEME = "gruvbox" }
eq("writes lua/local.lua", {
  code,
  out:find "^OK lua/local.lua" ~= nil,
  vim.fn.readfile(target)[2]:find('theme = { name = "gruvbox" }', 1, true) ~= nil,
}, { 0, true, true })
local before = vim.fn.readfile(target)
code, out = run { NVIM_INSTALL_THEME = "tokyonight" }
eq(
  "if it already exists, does NOT touch it and says what to add",
  { code, out:find "^WARN lua/local.lua already exists" ~= nil, vim.fn.readfile(target) },
  { 0, true, before }
)
code, out = run { NVIM_INSTALL_LANGS = "cobol" }
eq("unknown language: ERR and exit 2", { code, out:find "^ERR unknown language: cobol" ~= nil }, { 2, true })
vim.fn.delete(tmp, "rf")

print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
