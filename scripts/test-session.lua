-- Tests of lua/utils/session.lua: when a bare start restores a session (pure) and what `close_auxiliary` leaves
-- alone before saving (terminals stay; help/quickfix/scratch windows go). No plugins, no persistence.
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

local session = require "utils.session"

-- ── when a bare start restores ───────────────────────────────────────────────
local base = {
  enabled = true,
  ui = true,
  gui = false,
  args = 0,
  stdin = false,
  diff = false,
  home = false,
  start_screen = true,
  session = true,
}
ok("restore: a bare start inside a project", session.should_restore(base))
ok(
  "restore: a folder argument is a project start",
  session.should_restore(vim.tbl_extend("force", base, { args = 1, dir_arg = true }))
)
ok("restore: disabled by the setting", not session.should_restore(vim.tbl_extend("force", base, { enabled = false })))
ok("restore: never without a UI", not session.should_restore(vim.tbl_extend("force", base, { ui = false })))
ok("restore: the app restores it itself", not session.should_restore(vim.tbl_extend("force", base, { gui = true })))
ok("restore: a file on the command line wins", not session.should_restore(vim.tbl_extend("force", base, { args = 1 })))
ok("restore: stdin is not a project start", not session.should_restore(vim.tbl_extend("force", base, { stdin = true })))
ok("restore: not in diff mode", not session.should_restore(vim.tbl_extend("force", base, { diff = true })))
ok("restore: not in the home folder", not session.should_restore(vim.tbl_extend("force", base, { home = true })))
ok(
  "restore: the start screen must still be there",
  not session.should_restore(vim.tbl_extend("force", base, { start_screen = false }))
)
ok("restore: there must be a session", not session.should_restore(vim.tbl_extend("force", base, { session = false })))

-- ── the fast session-file lookup (persistence.nvim's names, no plugin) ───────
local proj = vim.fn.tempname()
vim.fn.mkdir(proj .. "/.git", "p")
local sessions = vim.fn.stdpath "state" .. "/sessions"
vim.fn.mkdir(sessions, "p")
local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
  return path
end
local function esc(path)
  return (path:gsub("[\\/:]+", "%%"))
end
vim.cmd.cd(vim.fn.fnameescape(proj))
local base_file = sessions .. "/" .. esc(proj) .. ".vim"
write(base_file, "let g:from_session = 1\n")
eq("session file: the base one", session.file(), base_file)
eq("session file: exists without the plugin", session.exists(), true)

write(proj .. "/.git/HEAD", "ref: refs/heads/main\n")
eq("session file: main uses the base", session.file(), base_file)
write(proj .. "/.git/HEAD", "ref: refs/heads/feature/x\n")
local branch_file = sessions .. "/" .. esc(proj) .. "%%" .. esc "feature/x" .. ".vim"
write(branch_file, "let g:from_session = 2\n")
eq("session file: the branch one wins", session.file(), branch_file)

local opened = write(proj .. "/opened.lua", "local opened = true\n")
write(branch_file, "let g:from_session = 2\nedit " .. vim.fn.fnameescape(opened) .. "\n")
eq("load_file: sources it", session.load_file(branch_file), true)
eq("load_file: opens its file", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "opened.lua")
eq("load_file: the session variable is set", vim.g.from_session, 2)

-- ── what close_auxiliary closes before saving ────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local file = dir .. "/a.lua"
local f = assert(io.open(file, "w"))
f:write "local a = 1\n"
f:close()
vim.cmd("edit " .. vim.fn.fnameescape(file))
local file_win = vim.api.nvim_get_current_win()

vim.cmd "split"
vim.cmd "terminal"
local term_win = vim.api.nvim_get_current_win()
vim.cmd "stopinsert"

-- A nofile window (what help, quickfix and the tree look like) is auxiliary: it must go.
local aux = vim.api.nvim_create_buf(false, true)
vim.bo[aux].buftype = "nofile"
vim.cmd "vsplit"
local aux_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(aux_win, aux)

eq("close_auxiliary: three windows first", #vim.api.nvim_tabpage_list_wins(0), 3)
session.close_auxiliary()
ok("close_auxiliary: the file window stays", vim.api.nvim_win_is_valid(file_win))
ok("close_auxiliary: the terminal stays", vim.api.nvim_win_is_valid(term_win))
ok("close_auxiliary: the nofile window goes", not vim.api.nvim_win_is_valid(aux_win))
eq("close_auxiliary: two windows left", #vim.api.nvim_tabpage_list_wins(0), 2)

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd(fails == 0 and "qa!" or "cq!")
