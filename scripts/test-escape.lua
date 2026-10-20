-- Tests of nvim/lua/utils/escape.lua: what Esc closes (pure rules, then real windows).
local ROOT = vim.env.AGENT_TEST_ROOT
vim.opt.rtp:prepend(ROOT .. "/nvim")
local failures = 0
local function check(name, cond, detail)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. vim.inspect(detail)) or ""))
	end
end

local escape = require("utils.escape")
local function w(over)
	return vim.tbl_extend(
		"force",
		{ floating = false, focusable = true, buftype = "", filetype = "lua", windows = 2, tabs = 1, modified = false },
		over or {}
	)
end
check("a file you edit stays", escape.classify(w()) == nil)
check("a help split closes", escape.classify(w({ buftype = "help", filetype = "help" })) == "close")
check("the quickfix closes", escape.classify(w({ buftype = "quickfix", filetype = "qf" })) == "close")
check("a panel by filetype closes", escape.classify(w({ filetype = "aerial", buftype = "nofile" })) == "close")
check("a scratch split closes", escape.classify(w({ buftype = "nofile" })) == "close")
check("a float closes", escape.classify(w({ floating = true, buftype = "nofile" })) == "close")
check(
	"a float is closed even when it is the only window of the tab",
	escape.classify(w({ floating = true, windows = 1 })) == "close"
)
check(
	"the last window is never closed",
	escape.classify(w({ buftype = "help", filetype = "help", windows = 1 })) == nil
)
check(
	"an extra page alone in its tab closes the tab",
	escape.classify(w({ buftype = "nofile", filetype = "checkhealth", windows = 1, tabs = 2 })) == "close_tab"
)
check("the last tab stays", escape.classify(w({ buftype = "nofile", windows = 1, tabs = 1 })) == nil)
check(
	"the tree only gives the focus back",
	escape.classify(w({ filetype = "NvimTree", buftype = "nofile" })) == "focus_back"
)
check("a modified buffer is never thrown away", escape.classify(w({ buftype = "nofile", modified = true })) == nil)
check("an overlay marked to stay stays", escape.classify(w({ floating = true, keep = true })) == nil)
check(
	"windows with their own Esc are left to them",
	escape.classify(w({ floating = true, filetype = "market", buftype = "nofile" })) == nil
)

-- real windows
vim.cmd("edit /tmp/test-escape-a.txt")
local file = vim.api.nvim_get_current_win()
vim.cmd("help")
local helpwin = vim.api.nvim_get_current_win()
check("setup: help is open", helpwin ~= file and vim.bo.buftype == "help")
check("Esc closes the help you are in", escape.close_current() and not vim.api.nvim_win_is_valid(helpwin))
check("and you are back in the file", vim.api.nvim_get_current_win() == file)
check("Esc in a file does nothing to it", not escape.close_current() and vim.api.nvim_win_is_valid(file))
local buf = vim.api.nvim_create_buf(false, true)
local float = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 10, height = 3 })
check("Esc closes a focused float", escape.close_current() and not vim.api.nvim_win_is_valid(float))
-- a float elsewhere, focus in the file
local other = vim.api.nvim_open_win(
	vim.api.nvim_create_buf(false, true),
	false,
	{ relative = "editor", row = 1, col = 1, width = 10, height = 3 }
)
local quiet = vim.api.nvim_open_win(
	vim.api.nvim_create_buf(false, true),
	false,
	{ relative = "editor", row = 5, col = 1, width = 10, height = 1, focusable = false }
)
check("stray focusable floats close from the file", escape.close_floats() and not vim.api.nvim_win_is_valid(other))
check("overlays that cannot take focus stay", vim.api.nvim_win_is_valid(quiet))
vim.api.nvim_win_close(quiet, true)
vim.cmd("tabnew")
vim.bo.buftype = "nofile"
check("a lone extra tab closes", escape.close_current() and #vim.api.nvim_list_tabpages() == 1)
check("the file window is still there", vim.api.nvim_win_is_valid(file))
vim.cmd("copen")
local qf = vim.api.nvim_get_current_win()
escape.close_current()
check("the quickfix goes too", not vim.api.nvim_win_is_valid(qf))

print(failures == 0 and "ALL OK" or ("FAILURES: " .. failures))
vim.cmd(failures == 0 and "qa!" or "cq!")
