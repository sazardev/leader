-- Multi-file diff and history (per file or for the whole repo).
-- Only loads when a command is invoked; the shortcuts live in the <leader>G menu (menus/git.lua).
return {
	"sindrets/diffview.nvim",
	cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewRefresh" },
	opts = {
		enhanced_diff_hl = true, -- better highlighting of added/deleted lines
	},
	config = function(_, opts)
		require("diffview").setup(opts)
	end,
}
