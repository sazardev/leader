-- ── Unity actions (Assets/, ProjectSettings/) ─────────────────────────────────
-- Scripts are C# (the <leader>c menu); this menu is for the Unity YAML files (*.unity, *.prefab, *.meta)
-- and the project itself: open the project in Unity, refresh the Asset Database, generate the .slnx the
-- C# tools need. No scene preview in Neovim (Rider has one): the Editor is the preview; these actions
-- just take you there.
local log = require "utils.log"
local proj = require "utils.csharpproj"
local terminal = require "utils.terminal"

local function unity_binary()
  for _, cmd in ipairs { "unity", "unity-editor", "/opt/unity/Unity", "/usr/local/bin/unity" } do
    if vim.fn.executable(cmd) == 1 then
      return cmd
    end
  end
  return nil
end

local function open_project(args)
  local dir = proj.unity_root() or proj.root()
  local bin = unity_binary()
  if not bin then
    return log.warn "Unity: no Unity binary found (install Unity Hub or add `unity` to PATH)"
  end
  terminal.run(("%s -projectPath %s%s"):format(bin, vim.fn.shellescape(dir), args and (" " .. args) or ""), dir)
end

return {
  {
    "f",
    "format (prettier)",
    function()
      require("conform").format { lsp_format = "fallback" }
    end,
  },
  {
    "o",
    "open project in Unity",
    function()
      open_project()
    end,
  },
  {
    "R",
    "refresh Asset Database",
    function()
      open_project "-quit -batchmode -refresh"
    end,
  },
  {
    "S",
    "generate .sln (C# tools)",
    function()
      local dir = proj.unity_root() or proj.root()
      terminal.run("dotnet new sln --force", dir)
      log.info "Unity: solution generated; restart the C# server (:LspRestart) to load it"
    end,
  },
  {
    "I",
    "project info",
    function()
      local dir = proj.unity_root()
      if not dir then
        return log.warn "Unity: no Unity project around this file (Assets/ + ProjectSettings/)"
      end
      terminal.run("ls Assets ProjectSettings 2>/dev/null; cat ProjectSettings/ProjectVersion.txt 2>/dev/null", dir)
    end,
  },
}
