-- go.nvim: no se carga en modo ligero (residente y pesado) y no se instala si desactivas Go
-- (`languages.disabled`): su `build` descarga las herramientas de Go.
return {
  "ray-x/go.nvim",
  enabled = not vim.tbl_contains(require("core.settings").languages.disabled, "go"),
  dependencies = { "ray-x/guihua.lua" },
  ft = { "go", "gomod", "gowork" },
  cond = function()
    return not require("core.light").enabled
  end,
  build = ':lua require("go.install").update_all_sync()',
  config = function()
    -- GoAddTag: json:"sent_at" (snake_case); omitempty se pide aparte (<leader>gA)
    require("go").setup { tag_transform = "snakecase", tag_options = false }
  end,
}
