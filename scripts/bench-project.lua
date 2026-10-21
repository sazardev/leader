-- Benchmark probe: what a real project costs. Opens BENCH_FILE (a path inside the cwd's project) with the real config and
-- prints, in milliseconds since the open: each LSP client attaching, each diagnostics source's first result, the first
-- answers of the language server (document symbols, hover, references: the first one pays the project load, the second
-- is the warm one), the formatter cold and warm, a Telescope find_files and the code search index. A 1 ms ticker marks
-- every time the main loop could not run it (`blocked` = what scrolling or typing would have felt, `worst` = the longest
-- stall), and typing is timed per key at the end with everything attached. Nothing is written to the project's files.
--   cd <project> && BENCH_FILE=src/a.ts nvim --headless -c "luafile scripts/bench-project.lua"
local uv = vim.uv
local function now()
  return uv.hrtime() / 1e6
end
local function out(fmt, ...)
  io.stdout:write(fmt:format(...) .. "\n")
end

vim.ui_attach(vim.api.nvim_create_namespace "bench", { ext_messages = true }, function() end)

local gap = { total = 0, worst = 0, last = now(), on = false, n = 0 }
local ticker = uv.new_timer()
ticker:start(
  1,
  1,
  vim.schedule_wrap(function()
    local t = now()
    if gap.on then
      local g = t - gap.last
      if g > 16 then
        gap.total = gap.total + (g - 1)
        gap.n = gap.n + 1
      end
      gap.worst = math.max(gap.worst, g)
    end
    gap.last = t
  end)
)
local function gap_reset()
  gap.total, gap.worst, gap.n, gap.last, gap.on = 0, 0, 0, now(), true
end

-- Sampling profiler: every ms the VM records the Lua stack that is running; C work (treesitter, regex) counts for the
-- Lua function that called it. BENCH_PROF=1 prints the heaviest stacks of each marked window.
local prof = { on = false, counts = {} }
local function prof_start()
  if vim.env.BENCH_PROF ~= "1" then
    return
  end
  prof.counts = {}
  require("jit.profile").start("li1", function(th, n)
    local st = require("jit.profile").dumpstack(th, "pl;", 6)
    prof.counts[st] = (prof.counts[st] or 0) + n
  end)
end
local function prof_stop(label)
  if vim.env.BENCH_PROF ~= "1" then
    return
  end
  require("jit.profile").stop()
  local rows, total = {}, 0
  for k, v in pairs(prof.counts) do
    rows[#rows + 1] = { k, v }
    total = total + v
  end
  table.sort(rows, function(a, b)
    return a[2] > b[2]
  end)
  out("  profile %s (%d samples):", label, total)
  for i = 1, math.min(8, #rows) do
    out("    %4d  %s", rows[i][2], (rows[i][1]:gsub("\n", " < "):gsub("%s+", " ")))
  end
end

local T0
local function since()
  return now() - T0
end

local seen_diag = {}
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(a)
    local c = vim.lsp.get_client_by_id(a.data.client_id)
    out("  +%6.0f ms  lsp attached: %s", since(), c and c.name or "?")
  end,
})
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  callback = function(a)
    local per = {}
    for _, d in ipairs(a.data and a.data.diagnostics or vim.diagnostic.get(a.buf)) do
      local k = (d.source or "?") .. "/ns" .. tostring(d.namespace)
      per[k] = (per[k] or 0) + 1
    end
    local ns = {}
    for _, d in ipairs(vim.diagnostic.get(a.buf)) do
      ns[d.namespace] = true
    end
    for id in pairs(ns) do
      local name = (vim.diagnostic.get_namespace(id) or {}).name or tostring(id)
      if not seen_diag[name] then
        seen_diag[name] = true
        out("  +%6.0f ms  first diagnostics from: %s (%d in buffer)", since(), name, #vim.diagnostic.get(a.buf, { namespace = id }))
      end
    end
  end,
})

local function request(method, params, cb)
  local t = now()
  local clients = vim.lsp.get_clients { bufnr = 0, method = method, name = vim.env.BENCH_CLIENT or "vtsls" }
  if #clients == 0 then
    return cb(nil, "no client")
  end
  clients[1]:request(method, params, function(err, res)
    cb(now() - t, err and "error" or (res == nil or (type(res) == "table" and #res == 0 and vim.tbl_isempty(res))) and "empty" or "ok", clients[1].name)
  end, 0)
end

local steps = {}
local function add(f)
  steps[#steps + 1] = f
end

-- find a position on an identifier in the middle of the file
local function symbol_pos()
  local n = vim.api.nvim_buf_line_count(0)
  for l = math.floor(n / 2), n do
    local line = vim.api.nvim_buf_get_lines(0, l - 1, l, false)[1] or ""
    local s = line:find "%a[%w_]+%("
    if s then
      return { line = l - 1, character = s + 1 }
    end
  end
  return { line = 0, character = 0 }
end

local function wait_for_lsp(done)
  -- up to 60 s for the first document symbols answer (the TypeScript server loads the project before it can answer)
  local tries = 0
  local function try()
    tries = tries + 1
    request("textDocument/documentSymbol", { textDocument = vim.lsp.util.make_text_document_params() }, function(ms, st, name)
      if ms and st == "ok" then
        out("  +%6.0f ms  %s first documentSymbol answered (%.0f ms to answer)", since(), name, ms)
        done()
      elseif tries > 240 then
        out("  +%6.0f ms  no documentSymbol answer after 60 s (%s)", since(), tostring(st))
        done()
      else
        vim.defer_fn(try, 250)
      end
    end)
  end
  try()
end

add(function(done)
  -- BENCH_INIT="<lua>" runs before the file opens: swap or tune a language server for an A/B
  if vim.env.BENCH_INIT and vim.env.BENCH_INIT ~= "" then
    local ok, err = pcall(loadstring(vim.env.BENCH_INIT))
    out("init: %s", ok and "ok" or tostring(err))
  end
  vim.cmd.edit(vim.env.BENCH_FILE)
  local lines = vim.api.nvim_buf_line_count(0)
  out("opened %s (%d lines), filetype=%s", vim.env.BENCH_FILE, lines, vim.bo.filetype)
  T0 = now()
  gap_reset()
  prof_start()
  wait_for_lsp(function()
    prof_stop "project load"
    out("  loop blocked while the project loaded: %.0f ms in %d stalls, worst %.0f ms", gap.total, gap.n, gap.worst)
    done()
  end)
end)

-- let every server finish (eslint, tailwind, biome answer after the project loads)
add(function(done)
  vim.defer_fn(function()
    local names = {}
    for _, c in ipairs(vim.lsp.get_clients { bufnr = 0 }) do
      names[#names + 1] = c.name
    end
    out("  +%6.0f ms  settled; clients: %s", since(), table.concat(names, ", "))
    done()
  end, 4000)
end)

for _, label in ipairs { "cold", "warm" } do
  add(function(done)
    local pos = symbol_pos()
    local p = vim.tbl_extend("force", { textDocument = vim.lsp.util.make_text_document_params() }, { position = pos })
    gap_reset()
    request("textDocument/hover", p, function(ms, st, name)
      out("lsp: hover %-4s %6s ms (%s, %s)", label, ms and ("%.0f"):format(ms) or "-", name or "-", tostring(st))
      done()
    end)
  end)
  add(function(done)
    local pos = symbol_pos()
    local p = { textDocument = vim.lsp.util.make_text_document_params(), position = pos, context = { includeDeclaration = true } }
    request("textDocument/references", p, function(ms, st, name)
      out("lsp: references %-4s %6s ms (%s, %s)", label, ms and ("%.0f"):format(ms) or "-", name or "-", tostring(st))
      done()
    end)
  end)
  add(function(done)
    local pos = symbol_pos()
    local p = { textDocument = vim.lsp.util.make_text_document_params(), position = pos }
    request("textDocument/definition", p, function(ms, st, name)
      out("lsp: definition %-4s %6s ms (%s, %s)", label, ms and ("%.0f"):format(ms) or "-", name or "-", tostring(st))
      done()
    end)
  end)
  add(function(done)
    -- completion in the middle of the file, at the end of a line's first word
    local pos = symbol_pos()
    local p = { textDocument = vim.lsp.util.make_text_document_params(), position = pos, context = { triggerKind = 1 } }
    request("textDocument/completion", p, function(ms, st, name)
      out("lsp: completion %-4s %6s ms (%s, %s)", label, ms and ("%.0f"):format(ms) or "-", name or "-", tostring(st))
      done()
    end)
  end)
end

-- formatter, cold then warm (buffer only; the file on disk is never written)
for _, label in ipairs { "cold", "warm" } do
  add(function(done)
    local ok, conform = pcall(require, "conform")
    if not ok then
      out("format: conform not available")
      return done()
    end
    local before = vim.api.nvim_buf_get_changedtick(0)
    gap_reset()
    local t = now()
    conform.format({ async = true, lsp_format = "fallback", timeout_ms = 20000 }, function(err)
      out("format: %-4s %6.0f ms %s  (loop blocked %.0f ms, worst %.0f)", label, now() - t, err and "ERR" or "ok", gap.total, gap.worst)
      if vim.api.nvim_buf_get_changedtick(0) ~= before then
        vim.cmd "silent undo"
      end
      done()
    end)
  end)
end

-- the linter (nvim-lint) apart from the language server
add(function(done)
  local ok, lint = pcall(require, "lint")
  if not ok then
    return done()
  end
  local names = lint._resolve_linter_by_ft and lint._resolve_linter_by_ft(vim.bo.filetype) or lint.linters_by_ft[vim.bo.filetype] or {}
  local t = now()
  local ns = vim.diagnostic.get_namespaces()
  gap_reset()
  lint.try_lint()
  local tries = 0
  local function poll()
    tries = tries + 1
    local running = false
    for _, n in ipairs(names) do
      local ln = lint.get_running and lint.get_running(0)
      if ln and #ln > 0 then
        running = true
      end
    end
    if (not running and tries > 2) or tries > 200 then
      out("lint:   %s %6.0f ms to finish (loop blocked %.0f ms)", table.concat(names, ","), now() - t, gap.total)
      done()
    else
      vim.defer_fn(poll, 25)
    end
  end
  poll()
end)

-- the pickers
add(function(done)
  require("lazy").load { plugins = { "telescope.nvim" } }
  gap_reset()
  local t0 = now()
  require("telescope.builtin").find_files()
  local tm = uv.new_timer()
  tm:start(
    1,
    1,
    vim.schedule_wrap(function()
      local shown = false
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[b].filetype == "TelescopeResults" then
          shown = vim.trim(table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "")) ~= ""
        end
      end
      if shown or now() - t0 > 8000 then
        tm:stop()
        out("picker: find_files first results %6.0f ms (loop blocked %.0f ms, worst %.0f)", now() - t0, gap.total, gap.worst)
        vim.cmd "stopinsert | close"
        done()
      end
    end)
  )
end)

add(function(done)
  local ok, idx = pcall(require, "codesearch.index")
  if not ok then
    return done()
  end
  gap_reset()
  local t0 = now()
  prof_start()
  idx.build(vim.fn.getcwd(), function(_, stats)
    out("search: code index %6.0f ms, %d files read (loop blocked %.0f ms, worst %.0f)", now() - t0, stats.read or -1, gap.total, gap.worst)
    prof_stop "code index"
    vim.defer_fn(done, 500)
  end)
end)

-- typing with every server attached. BENCH_PRE="<lua>" runs first (an A/B switch: turn a plugin off and compare).
add(function(done)
  if vim.env.BENCH_PRE and vim.env.BENCH_PRE ~= "" then
    local ok, err = pcall(loadstring(vim.env.BENCH_PRE))
    out("pre: %s", ok and "ok" or tostring(err))
  end
  vim.cmd "normal! 30%"
  vim.cmd "normal! o"
  vim.cmd "startinsert!"
  local text = "const value = await this.service.findAll({ where: { id } }); // words "
  local d, per = {}, {}
  gap_reset()
  prof_start()
  for i = 1, 300 do
    local c = text:sub((i - 1) % #text + 1, (i - 1) % #text + 1)
    local t = now()
    vim.api.nvim_feedkeys(c, "xt", false)
    vim.cmd "redraw"
    local ms = now() - t
    d[#d + 1] = ms
    local e = per[c] or { n = 0, sum = 0, max = 0 }
    e.n, e.sum, e.max = e.n + 1, e.sum + ms, math.max(e.max, ms)
    per[c] = e
  end
  local rows = {}
  for c, e in pairs(per) do
    rows[#rows + 1] = { c, e.sum / e.n, e.max }
  end
  table.sort(rows, function(a, b)
    return a[2] > b[2]
  end)
  local top = {}
  for i = 1, math.min(6, #rows) do
    top[#top + 1] = ("%q avg %.1f max %.1f"):format(rows[i][1], rows[i][2], rows[i][3])
  end
  out("typing slowest keys: %s", table.concat(top, " | "))
  vim.cmd "stopinsert"
  prof_stop "typing"
  table.sort(d)
  local function q(x)
    return d[math.max(1, math.floor(#d * x))]
  end
  out("typing: p50 %5.2f  p95 %5.2f  p99 %5.2f  max %5.2f ms per key  (blocked %.0f ms)", q(0.5), q(0.95), q(0.99), d[#d], gap.total)
  vim.cmd "silent undo"
  done()
end)

-- scrolling a long file
add(function(done)
  local n = vim.api.nvim_buf_line_count(0)
  vim.cmd "normal! gg"
  local d = {}
  gap_reset()
  for _ = 1, math.min(60, math.floor(n / 10)) do
    local t = now()
    vim.cmd "silent normal! 10\x05" -- ctrl-e ... ten lines
    vim.cmd "redraw"
    d[#d + 1] = now() - t
  end
  table.sort(d)
  if #d > 0 then
    out("scroll: p50 %5.2f  p95 %5.2f  max %5.2f ms per frame", d[math.max(1, math.floor(#d * 0.5))], d[math.max(1, math.floor(#d * 0.95))], d[#d])
  end
  done()
end)

-- the cost of the servers still running: every process under this nvim, by command
add(function(done)
  local p = io.popen("ps -eo pid=,ppid=,rss=,args= 2>/dev/null")
  local procs, kids = {}, {}
  for l in p:lines() do
    local pid, ppid, rss, args = l:match "^%s*(%d+)%s+(%d+)%s+(%d+)%s+(.*)$"
    if pid then
      procs[tonumber(pid)] = { rss = tonumber(rss), args = args }
      local k = kids[tonumber(ppid)] or {}
      k[#k + 1] = tonumber(pid)
      kids[tonumber(ppid)] = k
    end
  end
  p:close()
  local total = 0
  local function walk(pid, depth)
    for _, c in ipairs(kids[pid] or {}) do
      local pr = procs[c]
      if pr.rss > 20000 then
        out("  %6.0f MB  %s", pr.rss / 1024, pr.args:sub(1, 90))
      end
      total = total + pr.rss
      walk(c, depth + 1)
    end
  end
  out("memory: nvim itself %.0f MB; children:", procs[uv.os_getpid()].rss / 1024)
  walk(uv.os_getpid(), 1)
  out("memory TOTAL language servers: %.0f MB", total / 1024)
  done()
end)

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      local i = 0
      local function nxt()
        i = i + 1
        if steps[i] then
          local ok, err = pcall(steps[i], nxt)
          if not ok then
            out("step %d failed: %s", i, tostring(err))
            nxt()
          end
        else
          vim.cmd "qa!"
        end
      end
      nxt()
    end, 1500)
  end,
})
vim.defer_fn(function()
  out("TIMEOUT: probe killed after 150 s")
  vim.cmd "qa!"
end, 150000)
