-- ── Desktop app: is everything installed? ────────────────────────────────────
-- The checks the setup shows (gui/wizard.lua, its Install and Review steps). Each one is cheap
-- (no network, no process except `executable()`), says what it found and, when
-- something is missing, how to get it: `fix` is an Ex command the screen runs
-- with Enter, `hint` is advice when there is nothing safe to run from here.
local M = {}

---@class GuiCheck
---@field id string
---@field label string
---@field ok boolean
---@field detail string
---@field fix string?  Ex command that installs what is missing
---@field hint string? what to do when there is no command

---@param list string[]
---@param n integer
---@return string
local function some(list, n)
  local shown = table.concat(list, ", ", 1, math.min(n, #list))
  return #list > n and (shown .. ", …") or shown
end

---@return GuiCheck[]
function M.run()
  ---@type GuiCheck[]
  local out = {}
  local function add(c)
    out[#out + 1] = c
  end

  local v = vim.version()
  add {
    id = "nvim",
    label = "Neovim",
    ok = vim.version.ge(v, { 0, 11, 0 }),
    detail = ("%d.%d.%d"):format(v.major, v.minor, v.patch),
    hint = "0.11 or newer: ./install.sh brings it",
  }

  local okl, config = pcall(require, "lazy.core.config")
  if okl then
    local total, missing = 0, {}
    for name, p in pairs(config.plugins) do
      total = total + 1
      if not (p._ and p._.installed) then
        missing[#missing + 1] = name
      end
    end
    table.sort(missing)
    add {
      id = "plugins",
      label = "Plugins",
      ok = #missing == 0,
      detail = #missing == 0 and (total .. " installed") or (#missing .. " missing: " .. some(missing, 3)),
      fix = "Lazy! restore",
    }
  end

  local okn, languages = pcall(require, "languages")
  if okn then
    local missing = {}
    for _, lang in ipairs(languages.treesitter()) do
      if #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) == 0 then
        missing[#missing + 1] = lang
      end
    end
    add {
      id = "treesitter",
      label = "Syntax parsers",
      ok = #missing == 0,
      detail = #missing == 0 and (#languages.treesitter() .. " compiled")
        or (#missing .. " missing: " .. some(missing, 4)),
      fix = "lua require('nvim-treesitter').install(require('languages').treesitter())",
    }
    local okr, registry = pcall(require, "mason-registry")
    if okr then
      local want, gone = languages.mason(), {}
      for _, name in ipairs(want) do
        local pkg = name:gsub("@.*$", "")
        if not registry.is_installed(pkg) then
          gone[#gone + 1] = pkg
        end
      end
      add {
        id = "mason",
        label = "Language tools",
        ok = #gone == 0,
        detail = #gone == 0 and (#want .. " installed (LSPs, formatters, linters)")
          or (#gone .. " missing: " .. some(gone, 3)),
        fix = "MasonToolsInstall",
      }
    end
  end

  local font = vim.g.leader_gui_font or ""
  add {
    id = "font",
    label = "Font",
    ok = font:find "Nerd" ~= nil or font:find "NF" ~= nil,
    detail = font ~= "" and font or "unknown",
    hint = "icons need a Nerd Font: GeistMono Nerd Font (nerdfonts.com), then gui.font in core/settings.lua",
  }

  local gpu = vim.g.leader_gui_gpu or ""
  local software = gpu:lower():find "llvmpipe" or gpu:lower():find "software"
  add {
    id = "gpu",
    label = "GPU",
    ok = gpu ~= "" and not software,
    detail = gpu ~= "" and gpu:gsub(",.*$", "") or "starting…",
    hint = "drawing on the CPU: install your GPU's Mesa/Vulkan driver (on WSL: a recent WSL with WSLg)",
  }

  local clip = type(vim.g.clipboard) == "table" and vim.g.clipboard.name or ""
  add { id = "clipboard", label = "Clipboard", ok = clip == "Leader", detail = clip ~= "" and clip or "none" }

  local tools = {
    { "git", "git" },
    { "rg", "ripgrep" },
    { "node", "node" },
    { { "cc", "gcc", "clang" }, "C compiler" },
  }
  local missing = {}
  for _, t in ipairs(tools) do
    local names = type(t[1]) == "table" and t[1] or { t[1] }
    local found = vim.iter(names):any(function(n)
      return vim.fn.executable(n) == 1
    end)
    if not found then
      missing[#missing + 1] = t[2]
    end
  end
  add {
    id = "tools",
    label = "System tools",
    ok = #missing == 0,
    detail = #missing == 0 and "git, ripgrep, node, C compiler" or ("missing: " .. table.concat(missing, ", ")),
    hint = "./install.sh installs them with your package manager",
  }

  local agents = vim.tbl_filter(function(c)
    return vim.fn.executable(c) == 1
  end, { "claude", "opencode", "ollama" })
  add {
    id = "agent",
    label = "AI agent",
    ok = #agents > 0,
    detail = #agents > 0 and table.concat(agents, ", ") or "no backend found",
    hint = "optional: <Space>am → Setup finds or installs one",
  }

  return out
end

---@param checks GuiCheck[]
---@return integer missing how many are not ok
function M.missing(checks)
  return #vim.tbl_filter(function(c)
    return not c.ok
  end, checks)
end

return M
