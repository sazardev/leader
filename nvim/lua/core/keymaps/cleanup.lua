-- ── Remove NvChad keymaps we do not use ──────────────────────────────────────
-- They are deleted (not <Nop>): a mapping that is also a prefix of others forces
-- which-key to wait for `timeoutlen` and then run it / close the popup. <leader>h
-- (horizontal terminal) clashed with Harpoon <leader>h1..4; <leader>w with wk/wK.
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
  "<leader>gt", -- telescope git_status: now <leader>Gt (contextual Git menu)
}

-- <A-h> (NvChad horizontal terminal) overrode mini.move (Alt+hjkl moves lines/blocks)
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
