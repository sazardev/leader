-- ── Contexto Git: solo en archivos que viven dentro de un repositorio ────────
local ex = require("utils.actions").ex

return {
	name = "Git",
	prefix = "G",
	where = "archivos dentro de un repo git",
	detect = function(buf)
		return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" and vim.fs.root(buf, ".git") ~= nil
	end,
	maps = {
		-- commits convencionales: UN panel (commit/panel.lua) con tres entradas
		{
			"c",
			"commit",
			function()
				require("commit").open()
			end,
		},
		{
			"m",
			"commit + AI draft",
			function()
				require("commit").ai()
			end,
		},
		{
			"a",
			"amend",
			function()
				require("commit").amend()
			end,
		},
		{ "t", "status", ex("Telescope git_status") },
		{ "b", "blame", ex("GitBlameToggle") },
		{ "d", "diff", ex("DiffviewOpen") },
		{ "f", "file history", ex("DiffviewFileHistory %") },
		{ "r", "repo history", ex("DiffviewFileHistory") },
		{ "q", "close diff", ex("DiffviewClose") },
		-- conflictos de merge (git-conflict.nvim)
		{ "o", "conflict ours", ex("GitConflictChooseOurs") },
		{ "T", "conflict theirs", ex("GitConflictChooseTheirs") },
		{ "B", "conflict both", ex("GitConflictChooseBoth") },
		{ "N", "conflict none", ex("GitConflictChooseNone") },
		{ "n", "conflict next", ex("GitConflictNextConflict") },
		{ "p", "conflict previous", ex("GitConflictPrevConflict") },
		{ "l", "conflict list", ex("GitConflictListQf") },
	},
}
