-- Tests of the integrated terminal helpers (utils/terminal.lua): picker rows, focusing without re-sending,
-- Ctrl-C routing and the shared command terminal. toggleterm and the picker are stubs; stopping a real `sleep`
-- proves the current-buffer path. Hermetic: only local processes, killed afterwards, no network.
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function pack(...)
  return { n = select("#", ...), ... }
end
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

package.loaded["toggleterm"] = { exec = function() end }
local exec_calls = {}
local terms = {}
package.loaded["toggleterm.terminal"] = {
  get_all = function()
    return terms
  end,
  get = function(id)
    for _, t in ipairs(terms) do
      if t.id == id then
        return t
      end
    end
    return nil
  end,
  Terminal = {
    new = function(_, opts)
      _G._term_opts = opts
      local term = {
        id = 7,
        bufnr = 4242,
        job_id = nil,
        direction = opts and opts.direction,
        opened_with = nil,
        sent = nil,
        is_open = function()
          return false
        end,
        open = function(self, size, direction)
          self.opened_with = { size, direction }
        end,
        send = function(self, cmd)
          self.sent = cmd
        end,
      }
      terms[#terms + 1] = term
      return term
    end,
  },
}
package.loaded["tasks.picker"] = {
  choose = function(items, opts, on_select)
    _G._picked = { items, opts }
    _G._on_select = on_select
  end,
}
local term = require("utils.terminal")

-- ── picker rows (pure) ───────────────────────────────────────────────────────

eq(
  "item: label, state, dir and command",
  term.item({
    id = 3,
    name = "noodle",
    dir = "/p/Api",
    cmd = "noodle --collection x",
    busy = true,
    open = true,
  }, {}),
  {
    label = "noodle #3",
    desc = "●running · /p/Api · noodle --collection x",
    value = {},
  }
)
eq("item: idle and closed states", {
  term.item({ id = 1, name = "terminal", busy = false, open = true }, {}).desc,
  term.item({ id = 2, name = "terminal", busy = false, open = false }, {}).desc,
}, {
  "○idle ·  · shell",
  "○closed ·  · shell",
})

-- ── busy (dead jobs are never busy) ──────────────────────────────────────────

eq(
  "busy: nothing, no job, dead job",
  { term.busy(nil), term.busy({}), term.busy({ job_id = 999999 }) },
  { false, false, false }
)

-- ── focus: opens when closed, goes to its window, sends nothing ─────────────

_G._term_opts = nil
term.focus()
local created = terms[#terms]
ok("focus: a shell terminal is created when none exists", created ~= nil and _G._term_opts ~= nil)
eq("focus: created without a command (sends nothing)", { created.sent, created.opened_with ~= nil }, { nil, true })

-- ── new_shell: an explicit direction wins over the configured one (Alt+V / Alt+H are panes now) ──
terms = {}
term.new_shell "vertical"
eq(
  "new_shell: the requested vertical direction is used",
  { _G._term_opts.direction, terms[#terms].opened_with },
  { "vertical", { nil, "vertical" } }
)
terms = {}
term.new_shell "horizontal"
eq("new_shell: horizontal too", terms[#terms].opened_with, { nil, "horizontal" })

-- ── pick: choices and focusing ───────────────────────────────────────────────

terms = {
  {
    id = 1,
    display_name = "terminal",
    dir = "/p",
    cmd = "dotnet run",
    job_id = nil,
    is_open = function()
      return true
    end,
  },
}
_G._picked = nil
term.pick()
ok(
  "pick: the shared terminal is listed",
  _G._picked ~= nil and #_G._picked[1] == 1 and _G._picked[1][1].label == "terminal #1"
)
_G._on_select(terms[1])
terms = {}
_G._picked = nil
term.pick()
eq("pick: empty shows a hint instead of an empty picker", { _G._picked, terms }, { nil, {} })

-- ── run: the cursor stays in the terminal (Esc closes it there) ──────────────

package.loaded["toggleterm"].exec = function(...)
  exec_calls[#exec_calls + 1] = pack(...)
end
terms = {}
term.run("go run ./cmd/api", "/p")
eq(
  "run: cmd, dir and direction reach toggleterm, go_back = false",
  exec_calls[1],
  pack("go run ./cmd/api", nil, nil, "/p", term.direction(), nil, false)
)
-- going into an already open terminal only moves the window, so terminal mode is entered explicitly
local term_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(term_buf)
local term_job = vim.fn.termopen "cat"
local real_cmd, seen_cmds = vim.cmd, {}
vim.cmd = function(c)
  seen_cmds[#seen_cmds + 1] = c
end
term.run("go run ./cmd/api", "/p")
vim.cmd = real_cmd
eq("run: the focused terminal is put in terminal mode", seen_cmds, { "startinsert" })
pcall(vim.fn.jobstop, term_job)
vim.api.nvim_buf_delete(term_buf, { force = true })

-- ── tui: a running TUI is focused, never typed into ──────────────────────────

local real_named, real_busy, real_run_in, real_focus = term.named, term.busy, term.run_in, term.focus_term
local tui_calls = {}
term.named = function()
  return { id = 9 }
end
term.busy = function()
  return true
end
term.focus_term = function()
  tui_calls[#tui_calls + 1] = "focus"
end
term.run_in = function()
  tui_calls[#tui_calls + 1] = "run_in"
end
term.tui("gh-dash", "gh dash", "/p")
eq("tui: an already running TUI is only focused", tui_calls, { "focus" })
term.busy = function()
  return false
end
tui_calls = {}
term.tui("gh-dash", "gh dash", "/p")
eq("tui: a stopped one is started", tui_calls, { "run_in" })
term.named, term.busy, term.run_in, term.focus_term = real_named, real_busy, real_run_in, real_focus

-- ── stop: current terminal buffer first ──────────────────────────────────────

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
local job = vim.fn.termopen("sleep 60")
ok("stop: sends Ctrl-C to the terminal under the cursor", term.stop() == true)
local waits = vim.fn.jobwait({ job }, 2000)
eq("stop: the process is gone afterwards", waits[1] ~= -1, true)
pcall(vim.fn.jobstop, job)
vim.api.nvim_buf_delete(buf, { force = true })
local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(scratch)
eq("stop: nothing running anywhere says so and sends nothing", term.stop(), false)
vim.api.nvim_buf_delete(scratch, { force = true })

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print("ALL OK")
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd("qa!")
