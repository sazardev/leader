-- ── Debugging per language (<leader>pD, rD, iD) ──────────────────────────────
-- nvim-dap with the adapter each language needs, configured the first time it is used (nothing loads before):
--   python  debugpy (Mason's), the project's interpreter: the file, or the test under the cursor through pytest
--   rust    codelldb (Mason's): the crate's binary after `cargo build`, or the test under the cursor (its test binary
--           from `cargo test --no-run`)
--   csharp  netcoredbg (Mason's): the assembly `dotnet build` produced (ASP.NET Core starts with Development and its
--           launchSettings.json URL)
--   swift   lldb-dap from the toolchain: the package's executable after `swift build`
-- The keys are the same in every menu, under `D`: d the program, t the test under the cursor, b breakpoint, B with a
-- condition, c continue, n step over, i step into, o step out, u the panel (nvim-dap-view, as for Dart).
local log = require "utils.log"

local M = {}

local configured = {}

---@param path string
---@return string?
local function mason_bin(path)
  local full = vim.fn.stdpath "data" .. "/mason/packages/" .. path
  return vim.fn.executable(full) == 1 and full or nil
end

--- A Mason binary by its name (mason/bin/<name>), else the same name on PATH
---@param name string
---@return string?
local function mason_exec(name)
  local bin = vim.fn.stdpath "data" .. "/mason/bin/" .. name
  if vim.fn.executable(bin) == 1 then
    return bin
  end
  local path = vim.fn.exepath(name)
  return path ~= "" and path or nil
end

--- The adapter of a language, registered once; false when its debugger is not installed
---@param lang string
---@return boolean
local function adapter(lang)
  if configured[lang] then
    return true
  end
  local dap = require "dap"
  if lang == "python" then
    local py = mason_bin "debugpy/venv/bin/python" or mason_bin "debugpy/venv/Scripts/python.exe"
    if not py then
      log.warn "Debug: debugpy is not installed (:MasonInstall debugpy)"
      return false
    end
    dap.adapters.python = { type = "executable", command = py, args = { "-m", "debugpy.adapter" } }
  elseif lang == "rust" then
    local codelldb = mason_bin "codelldb/extension/adapter/codelldb" or mason_bin "codelldb/codelldb"
    if not codelldb then
      log.warn "Debug: codelldb is not installed (:MasonInstall codelldb)"
      return false
    end
    dap.adapters.codelldb = {
      type = "server",
      port = "${port}",
      executable = { command = codelldb, args = { "--port", "${port}" } },
    }
  elseif lang == "csharp" then
    local dbg = mason_exec "netcoredbg"
    if not dbg then
      log.warn "Debug: netcoredbg is not installed (:MasonInstall netcoredbg)"
      return false
    end
    dap.adapters.netcoredbg = { type = "executable", command = dbg, args = { "--interpreter=vscode" } }
  elseif lang == "swift" then
    local lldb = vim.fn.exepath "lldb-dap"
    if lldb == "" then
      log.warn "Debug: lldb-dap is not on PATH (it comes with the Swift toolchain)"
      return false
    end
    dap.adapters.lldb = { type = "executable", command = lldb, name = "lldb" }
  end
  configured[lang] = true
  return true
end

---@param root string
---@return string
local function python_of(root)
  for _, p in ipairs { "/.venv/bin/python", "/venv/bin/python", "/.venv/Scripts/python.exe" } do
    if vim.fn.executable(root .. p) == 1 then
      return root .. p
    end
  end
  return vim.fn.exepath "python3"
end

--- The executables a cargo build produced, from its JSON messages (pure)
---@param lines string[]
---@param want "bin"|"test"
---@return string[]
function M.cargo_executables(lines, want)
  local out = {}
  for _, line in ipairs(lines) do
    local ok, msg = pcall(vim.json.decode, line)
    if ok and type(msg) == "table" and msg.reason == "compiler-artifact" and type(msg.executable) == "string" then
      local kinds = msg.target and msg.target.kind or {}
      local is_test = msg.profile and msg.profile.test
      if (want == "test" and is_test) or (want == "bin" and not is_test and vim.tbl_contains(kinds, "bin")) then
        out[#out + 1] = msg.executable
      end
    end
  end
  return out
end

--- The first .csproj under `root`
---@param root string
---@return string?
local function csproj(root)
  return vim.fs.find(function(name)
    return name:match "%.csproj$" ~= nil
  end, { path = root, type = "file", limit = 1 })[1]
end

--- The application URL of the first launchSettings profile, if the project has one
---@param dir string
---@return string?
local function aspnet_url(dir)
  local text = require("utils.project").read(dir .. "/Properties/launchSettings.json")
  if not text then
    return nil
  end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return nil
  end
  for _, profile in pairs(data.profiles or {}) do
    if type(profile) == "table" and type(profile.applicationUrl) == "string" then
      local url = profile.applicationUrl:match "https?://[^;]+"
      if url then
        return url
      end
    end
  end
end

--- Builds the project and debugs the assembly dotnet produced
---@param root string
local function csharp(root)
  local file = csproj(root)
  if not file then
    return log.warn "Debug: no .csproj around this file"
  end
  local dir = vim.fs.dirname(file)
  log.info "Debug: dotnet build"
  vim.system({ "dotnet", "build", file }, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        return log.warn "Debug: dotnet build failed (<leader>cT shows why)"
      end
      local prop = vim
        .system({ "dotnet", "msbuild", file, "-getProperty:TargetPath", "-nologo" }, { cwd = root, text = true })
        :wait()
      local dll = vim.trim(prop.stdout or "")
      if dll ~= "" and not dll:match "^/" then
        dll = dir .. "/" .. dll
      end
      if prop.code ~= 0 or dll == "" or vim.uv.fs_stat(dll) == nil then
        return log.warn "Debug: could not find the built assembly"
      end
      local env = { ASPNETCORE_ENVIRONMENT = "Development" }
      local url = aspnet_url(dir)
      if url then
        env.ASPNETCORE_URLS = url
      end
      require("dap").run {
        type = "netcoredbg",
        request = "launch",
        name = vim.fs.basename(dll),
        program = dll,
        cwd = root,
        env = env,
        stopOnEntry = false,
      }
    end)
  end)
end

--- Builds with cargo (JSON messages) and debugs the executable it made
---@param root string
---@param test LangTestDef?
local function rust(root, test)
  local cmd = test and { "cargo", "test", "--no-run", "--message-format=json" }
    or { "cargo", "build", "--message-format=json" }
  log.info("Debug: " .. table.concat(cmd, " "))
  vim.system(cmd, { cwd = root, text = true }, function(res)
    vim.schedule(function()
      local exes = M.cargo_executables(vim.split(res.stdout or "", "\n", { plain = true }), test and "test" or "bin")
      if res.code ~= 0 or #exes == 0 then
        return log.warn(
          "Debug: the build failed or made no executable (" .. (vim.trim(res.stderr or ""):match "[^\n]+$" or "") .. ")"
        )
      end
      local function go(program)
        require("dap").run {
          type = "codelldb",
          request = "launch",
          name = test and ("test " .. test.id) or vim.fs.basename(program),
          program = program,
          args = test and { test.id, "--exact", "--nocapture" } or {},
          cwd = root,
          stopOnEntry = false,
        }
      end
      if #exes == 1 then
        return go(exes[1])
      end
      vim.ui.select(exes, { prompt = "Which executable" }, function(choice)
        if choice then
          go(choice)
        end
      end)
    end)
  end)
end

--- Debugs the program (`d`) or the test under the cursor (`t`)
---@param lang string
---@param what "program"|"test"
function M.start(lang, what)
  if not adapter(lang) then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local test
  if what == "test" then
    local a = require("langtest").adapter(buf)
    test = a and require("langtest.ts").nearest(a.tests(buf), vim.api.nvim_win_get_cursor(0)[1])
    if not test or test.kind ~= "test" then
      return log.info "Debug: no test under the cursor"
    end
  end
  if lang == "python" then
    local root = require("langtest.adapters.pytest").root(file) or vim.fs.dirname(file)
    local cfg = { type = "python", request = "launch", cwd = root, python = python_of(root), justMyCode = true }
    if test then
      cfg.name, cfg.module = "pytest " .. test.id, "pytest"
      cfg.args = { file:sub(#root + 2) .. "::" .. test.id, "-q", "-p", "no:cacheprovider" }
    else
      cfg.name, cfg.program = vim.fs.basename(file), file
    end
    return require("dap").run(cfg)
  elseif lang == "rust" then
    local root = vim.fs.root(file, "Cargo.toml")
    if not root then
      return log.warn "Debug: no Cargo.toml around this file"
    end
    return rust(root, test)
  elseif lang == "csharp" then
    local root = vim.fs.root(file, function(name)
      return name:match "%.slnx?$" ~= nil or name:match "%.csproj$" ~= nil
    end) or vim.fs.dirname(file)
    return csharp(root)
  elseif lang == "swift" then
    local root = vim.fs.root(file, "Package.swift")
    if not root then
      return log.warn "Debug: no Package.swift around this file"
    end
    log.info "Debug: swift build"
    vim.system({ "swift", "build" }, { cwd = root, text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return log.warn "Debug: swift build failed (<leader>ib shows why)"
        end
        local name = (require("utils.project").read(root .. "/Package.swift") or ""):match 'Package%(%s*name:%s*"([^"]+)"'
        require("dap").run {
          type = "lldb",
          request = "launch",
          name = name or "swift",
          program = root .. "/.build/debug/" .. (name or vim.fs.basename(root)),
          cwd = root,
        }
      end)
    end)
  end
end

--- The `D…` entries of a language menu
---@param lang string
---@return table[]
function M.maps(lang)
  local function dap(fn, ...)
    local args = { ... }
    return function()
      require("dap")[fn](unpack(args))
    end
  end
  local out = {
    {
      "Dd",
      "debug program",
      function()
        M.start(lang, "program")
      end,
    },
  }
  -- C# has no test adapter yet (langtest); Swift is single-binary
  if lang ~= "swift" and lang ~= "csharp" then
    out[#out + 1] = {
      "Dt",
      "debug test under cursor",
      function()
        M.start(lang, "test")
      end,
    }
  end
  vim.list_extend(out, {
    { "Db", "debug breakpoint toggle", dap "toggle_breakpoint" },
    {
      "DB",
      "debug breakpoint condition",
      function()
        require("dap").set_breakpoint(vim.fn.input "Condition: ")
      end,
    },
    { "Dc", "debug continue", dap "continue" },
    { "Dn", "debug step over", dap "step_over" },
    { "Di", "debug step into", dap "step_into" },
    { "Do", "debug step out", dap "step_out" },
    { "Du", "debug panel", "<cmd>DapViewToggle<cr>" },
  })
  return out
end

return M
