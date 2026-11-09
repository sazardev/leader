-- Unity YAML (*.unity, *.prefab, *.meta, *.anim, *.controller, *.mat, *.asset): Unity's scene/prefab dialect.
-- There is no `unity` parser in nvim-treesitter, so the `unity` filetype is registered onto the `yaml`
-- parser (the `yaml` parser is declared by languages/unity.lua).
vim.filetype.add {
  extension = {
    unity = "unity",
    prefab = "unity",
    anim = "unity",
    controller = "unity",
    mat = "unity",
    asset = "unity",
    meta = "unity",
  },
}
pcall(vim.treesitter.language.register, "yaml", "unity")
