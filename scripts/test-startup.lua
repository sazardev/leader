-- Smoke test of the REAL config: what a normal start loads (lazy's VeryLazy plugins: statusline, which-key…) and the
-- language plugins, by opening one file of each language, must not raise a single error. Catches what unit suites miss:
-- a statusline component that breaks at setup, a plugin spec that fails to load, an ftplugin error.
-- Run by scripts/test-startup.sh (real config, temp files, no network).
local errors = {}
local function record(msg)
  errors[#errors + 1] = tostring(msg):gsub("\n", " ⏎ "):sub(1, 400)
end
local notify = vim.notify
vim.notify = function(msg, level, opts)
  if level == vim.log.levels.ERROR then
    record(msg)
  end
  return notify(msg, level, opts)
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local FILES = {
  ["main.go"] = { "package main", "", "func main() {}" },
  ["main.dart"] = { "void main() {}" },
  ["app.ts"] = { "export const x = 1" },
  ["app.py"] = { "x = 1" },
  ["lib.rs"] = { "fn main() {}" },
  ["init.lua"] = { "local x = 1" },
  ["README.md"] = { "# Title" },
  ["data.json"] = { "{}" },
  ["app_en.arb"] = { "{}" },
  ["style.css"] = { "a {}" },
}

local function step(fn)
  local ok, err = pcall(fn)
  if not ok then
    record(err)
  end
end

vim.defer_fn(function()
  -- what UIEnter would trigger in a real start (headless has no UI)
  step(function()
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  end)
  vim.wait(500, function()
    return false
  end)
  for name, lines in pairs(FILES) do
    vim.fn.writefile(lines, dir .. "/" .. name)
    step(function()
      vim.cmd("silent edit " .. vim.fn.fnameescape(dir .. "/" .. name))
    end)
    vim.wait(150, function()
      return false
    end)
  end
  vim.wait(1500, function()
    return false
  end)
  -- the statusline renders without errors in every one of them
  step(function()
    local ok, lualine = pcall(require, "lualine")
    if ok then
      lualine.refresh { place = { "statusline" } }
    end
  end)
  -- (not v:errmsg: errors caught on purpose, such as deleting NvChad maps that may not exist, also set it)
  local messages = vim.api.nvim_exec2("messages", { output = true }).output
  for line in messages:gmatch "[^\n]+" do
    if
      line:match "^E%d+:"
      or line:match "Error executing"
      or line:match "Failed to run `config`"
      or line:match "We tried to open this file"
    then
      record("message: " .. line)
    end
  end
  vim.fn.delete(dir, "rf")
  for _, e in ipairs(errors) do
    io.stdout:write("FAIL " .. e .. "\n")
  end
  io.stdout:write(#errors == 0 and "ALL OK (config loads cleanly)\n" or ("FAILURES: " .. #errors .. "\n"))
  vim.cmd(#errors == 0 and "qa!" or "cquit 1")
end, 300)
