-- Pruebas de scripts/install-local.lua: los ajustes por máquina que escriben install.sh e install.ps1.
-- Hermético: escribe en un directorio temporal, sin tocar nvim/lua/local.lua.
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
  "nombres: salen del registro de lenguajes (lua primero, 19 en total)",
  { names[1], names[2], #names },
  { "lua", "go", 19 }
)

local settings = il.plan({ langs = "go, typescript" }, names)
eq("--lang: se desactiva todo lo que no es lua ni lo pedido", {
  vim.tbl_contains(settings.languages.disabled, "go"),
  vim.tbl_contains(settings.languages.disabled, "typescript"),
  vim.tbl_contains(settings.languages.disabled, "lua"),
  vim.tbl_contains(settings.languages.disabled, "rust"),
  #settings.languages.disabled,
}, { false, false, false, true, 16 })
local bad, err = il.plan({ langs = "go,cobol" }, names)
eq(
  "--lang: uno desconocido es un error con la lista de los disponibles",
  { bad, err:match "^lenguaje desconocido: cobol" ~= nil, err:find("rust", 1, true) ~= nil },
  { nil, true, true }
)
eq("--theme", il.plan({ theme = "catppuccin" }, names), { theme = { name = "catppuccin" } })
eq(
  "--light / --no-light",
  { il.plan({ light = "1" }, names), il.plan({ light = "0" }, names) },
  { { light = { force = true } }, { light = { force = false } } }
)
eq("sin opciones no hay nada que escribir", il.plan({}, names), {})
eq(
  "render: tabla de Lua estable (claves ordenadas)",
  il.render { theme = { name = "x" }, light = { force = true }, languages = { disabled = { "go", "rust" } } },
  'return { languages = { disabled = { "go", "rust" } }, light = { force = true }, theme = { name = "x" } }'
)

-- el script completo (como lo llama el instalador): escribe, no pisa uno existente, y falla con exit 2
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
  "dry-run: no escribe y lo dice",
  { code, vim.uv.fs_stat(target), out:find("[dry-run]", 1, true) ~= nil },
  { 0, nil, true }
)
code, out = run { NVIM_INSTALL_LANGS = "go", NVIM_INSTALL_THEME = "gruvbox" }
eq("escribe lua/local.lua", {
  code,
  out:find "^OK lua/local.lua" ~= nil,
  vim.fn.readfile(target)[2]:find('theme = { name = "gruvbox" }', 1, true) ~= nil,
}, { 0, true, true })
local before = vim.fn.readfile(target)
code, out = run { NVIM_INSTALL_THEME = "tokyonight" }
eq(
  "si ya existe, NO lo toca y dice qué añadir",
  { code, out:find "^WARN lua/local.lua ya existe" ~= nil, vim.fn.readfile(target) },
  { 0, true, before }
)
code, out = run { NVIM_INSTALL_LANGS = "cobol" }
eq("lenguaje desconocido: ERR y salida 2", { code, out:find "^ERR lenguaje desconocido: cobol" ~= nil }, { 2, true })
vim.fn.delete(tmp, "rf")

print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
