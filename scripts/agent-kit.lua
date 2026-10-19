-- Helpers shared by the agent test suites that run whole flows (agent-flow, agent-batch, agent-review...): a temporary
-- project, a fake backend that answers with whatever the test says, in-memory state, canned answers for the modals and
-- notifications captured instead of shown. Hermetic: no network, no tokens, no user config.
--   local K = dofile(root .. "/scripts/agent-kit.lua")
local K = { fails = 0, total = 0 }

function K.print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end

function K.eq(name, got, want)
  K.total = K.total + 1
  if vim.deep_equal(got, want) then
    K.print("ok   " .. name)
  else
    K.fails = K.fails + 1
    K.print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

function K.ok(name, cond)
  K.eq(name, not not cond, true)
end

function K.wait(fn, ms)
  return vim.wait(ms or 8000, fn, 20)
end

--- A temporary git project with `files = { name = { lines } }`, made the cwd
---@param files table<string, string[]>
---@return string dir
function K.project(files)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for name, lines in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. name), "p")
    vim.fn.writefile(lines, dir .. "/" .. name)
  end
  vim.cmd.cd(dir)
  local git = { "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false" }
  vim.fn.system { "git", "-C", dir, "init", "-q" }
  -- the diff parsers run under a repo that uses mnemonic prefixes (c/ i/ w/), like a global `diff.mnemonicPrefix`
  vim.fn.system { "git", "-C", dir, "config", "diff.mnemonicPrefix", "true" }
  vim.fn.system(vim.list_extend(vim.deepcopy(git), { "add", "-A" }))
  vim.fn.system(vim.list_extend(vim.deepcopy(git), { "commit", "-qm", "base" }))
  K.dir = dir
  return dir
end

--- No language server ever starts: a real gopls on the machine would add diagnostics of its own to the test buffers (and
--- stopping one after it attached would itself fire diagnostic events at random moments)
function K.no_lsp()
  vim.lsp.start = function()
    return nil
  end
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end
end

--- Fake agent backend + in-memory state. `FAKE.text` is what the "model" answers (a string, or a function of the request).
---@return { text: string|fun(req: table): string, calls: integer, req: table?, notes: string[], asked: table[], answer: string }
function K.fake()
  K.no_lsp()
  local state = require "agent.state"
  local store = { backend = "fakeagent" }
  state.get = function(k)
    return store[k]
  end
  state.set = function(k, v)
    store[k] = v
  end
  require("agent.runs.store").use(vim.fn.tempname() .. ".jsonl")
  require("agent.cache").use(vim.fn.tempname() .. ".json") -- never the real answers: a hit would hide the call a test counts
  require("agent.persist").use(vim.fn.tempname() .. ".json")

  local FAKE = { text = "", calls = 0, notes = {}, asked = {}, answer = "yes", reqs = {} }
  require("agent.backends").register("fakeagent", {
    name = "fakeagent",
    label = "Fake",
    available = function()
      return true
    end,
    models = function(cb)
      cb {}
    end,
    build = function(req)
      FAKE.req, FAKE.calls = req, FAKE.calls + 1
      FAKE.reqs[#FAKE.reqs + 1] = req
      local text = type(FAKE.text) == "function" and FAKE.text(req) or FAKE.text
      if FAKE.slow then -- writes the first half, then keeps going for a while: a job that is still running with text on screen
        local half = math.ceil(#text / 2)
        return {
          cmd = {
            "sh",
            "-c",
            'printf "%s" "$1"; sleep 8; printf "%s" "$2"',
            "sh",
            text:sub(1, half),
            text:sub(half + 1),
          },
          cwd = "/tmp",
        }
      end
      return { cmd = { "printf", "%s", text }, cwd = "/tmp" }
    end,
    parser = function()
      local buf = {}
      return {
        feed = function(chunk)
          buf[#buf + 1] = chunk
          return chunk
        end,
        finish = function(code)
          if code ~= 0 then
            return { ok = false, err = "boom" }
          end
          return { ok = true, text = table.concat(buf), usage = { tokens_in = 100, tokens_out = 20, cost = 0.0004 } }
        end,
      }
    end,
  })

  -- the instruction field answers by itself (empty = run without an instruction)
  require("agent.ui.prompt").ask = function(action, _, _, cb)
    FAKE.asked = { skippable = action.input_optional and not action.input_needed, field = action.input }
    cb(FAKE.input or "")
  end
  -- notifications are captured
  vim.notify = function(msg)
    FAKE.notes[#FAKE.notes + 1] = msg
  end
  -- modals: the test says what the user would answer ("yes" | "no"); what was asked is recorded
  require("utils.modal").confirm = function(lines, opts, on_yes)
    FAKE.asked[#FAKE.asked + 1] = { lines = lines, title = opts and opts.title }
    if FAKE.answer == "yes" then
      on_yes()
    elseif opts and opts.on_cancel then
      opts.on_cancel()
    end
  end
  return FAKE
end

function K.idle()
  return K.wait(function()
    return #require("agent.jobs").running() == 0
  end)
end

--- Opens `dir/name` as a Go (or other) buffer and returns it
function K.open(name, ft)
  vim.cmd("silent edit " .. K.dir .. "/" .. name)
  vim.bo.filetype = ft or "go"
  return vim.api.nvim_get_current_buf()
end

function K.at(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

--- Last notification
function K.note(FAKE)
  return FAKE.notes[#FAKE.notes] or ""
end

--- Prints the verdict and ends the process the way the harness (test-agent.sh) expects
function K.finish()
  K.print(K.fails == 0 and "\nALL OK" or ("\nFAILURES: " .. K.fails))
  vim.cmd(K.fails == 0 and "qa!" or "cquit 1")
end

return K
