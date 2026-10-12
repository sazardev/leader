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
		{ "t", "status", ex("Telescope git_status") },
		{ "b", "blame toggle", ex("GitBlameToggle") },
		{ "d", "diff of all changes (Diffview)", ex("DiffviewOpen") },
		{ "f", "history of this file", ex("DiffviewFileHistory %") },
		{ "r", "history of the repo", ex("DiffviewFileHistory") },
		{ "q", "close Diffview", ex("DiffviewClose") },
		-- conflictos de merge (git-conflict.nvim)
		{ "o", "conflict: keep ours", ex("GitConflictChooseOurs") },
		{ "T", "conflict: keep theirs", ex("GitConflictChooseTheirs") },
		{ "B", "conflict: keep both", ex("GitConflictChooseBoth") },
		{ "N", "conflict: keep none", ex("GitConflictChooseNone") },
		{ "n", "conflict: next", ex("GitConflictNextConflict") },
		{ "p", "conflict: previous", ex("GitConflictPrevConflict") },
		{ "l", "conflicts of the repo (quickfix)", ex("GitConflictListQf") },
	},
}
