-- Pins the line of the current function/class/block at the top when scrolling.
-- Reuses the treesitter tree (no extra parsing); `:TSContext toggle` turns it off.
return {
	"nvim-treesitter/nvim-treesitter-context",
	event = { "BufReadPost", "BufNewFile" },
	cmd = "TSContext",
	opts = {
		max_lines = 3, -- at most 3 pinned lines: it does not eat the screen
		multiline_threshold = 1, -- long signatures: only the first line
		trim_scope = "outer", -- if there are more than max_lines, drops the outer scopes
	},
	config = function(_, opts)
		require("treesitter-context").setup(opts)
	end,
}
