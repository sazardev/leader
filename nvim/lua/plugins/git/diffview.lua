-- Multi-file diff and history (per file or for the whole repo).
-- Only loads when a command is invoked; the shortcuts live in the <leader>G menu (menus/git.lua).
-- Flat: like the demo's diff view, a soft `Changes` panel (status letter + name, no icons or hints) and two
-- columns headed HEAD / WORKING TREE, without diagnostics in between.
local HEADERS = { a = " HEAD", b = " WORKING TREE" }

return {
	"sindrets/diffview.nvim",
	cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewRefresh" },
	opts = {
		enhanced_diff_hl = true, -- better highlighting of added/deleted lines
		use_icons = false,
		show_help_hints = false,
		file_panel = {
			listing_style = "list",
			win_config = { position = "left", width = 26 },
		},
		view = {
			default = { disable_diagnostics = true },
			file_history = { disable_diagnostics = true },
		},
		hooks = {
			-- each column says which side it is (the demo's HEAD / WORKING TREE)
			diff_buf_win_enter = function(_, winid, ctx)
				local title = ctx and HEADERS[ctx.symbol]
				if title and require("ui.flat").enabled() then
					vim.wo[winid].winbar = "%#DiffviewPaneTitle#" .. title
				end
			end,
		},
	},
	config = function(_, opts)
		require("diffview").setup(opts)
	end,
}
