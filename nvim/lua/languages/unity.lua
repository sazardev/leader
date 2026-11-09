-- Unity: the scripts are plain C# under Assets/ (Roslyn, the C# menu), the scenes/prefabs/meta are Unity's
-- YAML dialect (*.unity, *.prefab, *.meta, *.anim, *.controller, *.mat, *.asset). There is no `unity` parser,
-- so `vim.treesitter.language.register` maps the `unity` filetype onto the `yaml` parser (see
-- ftdetect/unity.lua). The index (utils/csharpindex.lua) skips Library/, Temp/, Logs/ and the other
-- generated folders, and utils/csharpproj.lua recognises a Unity root (Assets/ + ProjectSettings/).
return {
  filetypes = { "unity" },
  treesitter = { "yaml" },
  mason = { full = { "prettier" } },
  formatters = { unity = { "prettier" } },
  menu = {
    name = "Unity",
    prefix = "U",
    maps = require "languages.actions.unity",
    groups = { S = "setup" },
  },
}
