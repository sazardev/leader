-- ── Quitar keymaps de NvChad que no usamos ───────────────────────────────────
-- Se borran (no <Nop>): un mapeo que además es prefijo de otros obliga a
-- which-key a esperar `timeoutlen` y a ejecutarlo/cerrar el popup. <leader>h
-- (terminal horizontal) chocaba con Harpoon <leader>h1..4; <leader>w con wk/wK.
local M = {}

local REMOVED = {
  "<leader>h",
  "<leader>v",
  "<leader>pt",
  "<leader>fa",
  "<leader>fz",
  "<leader>ma",
  "<leader>cm",
  "<leader>fh",
  "<leader>rn",
  "<leader>n",
  "<leader>th",
  "<leader>ch",
  "<leader>wK",
  "<leader>wk",
  "<leader>xb",
  "<leader>oa",
  "<leader>oA",
  "<leader>fc",
  "<leader>gd",
  "<leader>ds",
  "<leader>qs",
  "<leader>qS",
  "<leader>qd",
  "<leader>gt", -- telescope git_status: ahora <leader>Gt (menú Git contextual)
}

-- <A-h> (terminal horizontal de NvChad) pisaba a mini.move (Alt+hjkl mueve líneas/bloques)
local REMOVED_MODES = {
  { { "n", "t" }, "<A-h>" },
}

function M.setup()
  for _, lhs in ipairs(REMOVED) do
    pcall(vim.keymap.del, "n", lhs)
  end
  for _, r in ipairs(REMOVED_MODES) do
    for _, mode in ipairs(r[1]) do
      pcall(vim.keymap.del, mode, r[2])
    end
  end
end

return M
