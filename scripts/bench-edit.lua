-- Benchmark probe: heavy everyday edits on the real config, in a Lua buffer (treesitter, LSP, linters, completion and the
-- other buffer plugins all see the text). Each scenario prints its own time and the jank it causes: `blocked` is the total
-- time the main loop could not run a 1 ms timer while it was busy (what typing or scrolling would have felt) and `worst`
-- the longest single stall. A UI is attached (a Lua one, ext_messages) so redraws really happen.
--   nvim --headless -c "luafile scripts/bench-edit.lua"  → lines "edit: <scenario> <ms> blocked <ms> worst <ms>"
local uv = vim.uv
local function now()
  return uv.hrtime() / 1e6
end

vim.ui_attach(vim.api.nvim_create_namespace "bench", { ext_messages = true }, function() end)

local gap = { total = 0, worst = 0, last = now(), on = false }
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
      end
      gap.worst = math.max(gap.worst, g)
    end
    gap.last = t
  end)
)

--- Runs `fn` (the action), then lets the loop settle for `settle` ms, and reports.
local function scenario(label, fn, settle, done)
  gap.total, gap.worst, gap.on = 0, 0, true
  gap.last = now()
  local t0 = now()
  fn()
  pcall(vim.cmd, "redraw")
  local action = now() - t0
  vim.defer_fn(function()
    gap.on = false
    io.stdout:write(("edit: %-34s %6.0f ms   blocked %6.0f ms   worst %6.0f ms\n"):format(label, action, gap.total, gap.worst))
    done()
  end, settle or 1200)
end

local function lua_lines(n)
  local out = {}
  for i = 1, n do
    out[#out + 1] = ("local function f%d(a, b)\n  return a + b * %d\nend\n"):format(i, i)
  end
  return vim.split(table.concat(out), "\n", { plain = true })
end

local steps = {
  function(done)
    scenario("idle (the noise floor)", function() end, 400, done)
  end,
  function(done)
    vim.cmd "enew | setfiletype lua"
    vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. ".lua")
    local text = lua_lines(5000) -- ~15k lines
    scenario("paste 15k lines (~0.4 MB)", function()
      vim.api.nvim_paste(table.concat(text, "\n"), false, -1)
    end, 1500, done)
  end,
  function(done)
    scenario("undo that paste", function()
      vim.cmd "silent undo"
    end, 800, done)
  end,
  function(done)
    scenario("redo", function()
      vim.cmd "silent redo"
    end, 800, done)
  end,
  function(done)
    scenario("copy everything (yank 15k lines)", function()
      vim.cmd "silent normal! ggVGy"
    end, 400, done)
  end,
  function(done)
    scenario("reindent everything (gg=G)", function()
      vim.cmd "silent normal! gg=G"
    end, 800, done)
  end,
  function(done)
    scenario("replace all (:%s on 15k lines)", function()
      vim.cmd "silent %s/local/LOCAL/ge"
    end, 800, done)
  end,
  function(done)
    scenario("go to end and back (G, gg)", function()
      vim.cmd "silent normal! Ggg"
    end, 300, done)
  end,
  function(done)
    local list = {}
    for i = 1, 5000 do
      list[#list + 1] = {
        lnum = (i * 3) % 14000,
        col = 0,
        message = "unused local 'f" .. i .. "'",
        severity = (i % 3) + 1,
        source = "bench",
      }
    end
    local ns = vim.api.nvim_create_namespace "bench-diag"
    scenario("5000 diagnostics arrive at once", function()
      vim.diagnostic.set(ns, 0, list)
    end, 1200, function()
      vim.diagnostic.reset(ns, 0)
      done()
    end)
  end,
  function(done)
    scenario("300 notifications in a burst", function()
      for i = 1, 300 do
        vim.notify(("message %d: something happened"):format(i), vim.log.levels.INFO)
      end
    end, 1500, done)
  end,
  function(done)
    -- the file is written to disk first, so :w has something real to compare against; the formatter is the config's
    local path = vim.fn.tempname() .. ".py"
    local lines = {}
    for i = 1, 5000 do
      lines[#lines + 1] = ("def f%d(a,b): return a+b*%d"):format(i, i)
    end
    vim.fn.writefile(lines, path)
    vim.cmd("edit " .. path)
    vim.cmd "normal! Gotail"
    scenario("save a 5000-line file (:w)", function()
      vim.cmd "silent write"
    end, 1500, done)
  end,
  function(done)
    -- one key at a time with a redraw after each: what typing feels like. The buffer is the 15k-line one from above.
    vim.cmd "enew | setfiletype lua"
    vim.api.nvim_buf_set_name(0, vim.fn.tempname() .. ".lua")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lua_lines(5000))
    vim.cmd "normal! 7000G"
    vim.defer_fn(function()
      local text, d = "print(function_name(argument, other)) -- words ", {}
      vim.cmd "normal! Go"
      vim.cmd "startinsert!"
      for i = 1, 300 do
        local c = text:sub((i - 1) % #text + 1, (i - 1) % #text + 1)
        local t = now()
        vim.api.nvim_feedkeys(c, "xt", false)
        vim.cmd "redraw"
        d[#d + 1] = now() - t
      end
      vim.cmd "stopinsert"
      table.sort(d)
      local function q(x)
        return d[math.max(1, math.floor(#d * x))]
      end
      io.stdout:write(("edit: %-34s p50 %5.2f  p95 %5.2f  p99 %5.2f  max %5.2f ms per key\n"):format("typing in a 15k-line file", q(0.5), q(0.95), q(0.99), d[#d]))
      done()
    end, 1500)
  end,
}

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- let the startup work (lazy loads, LSP) settle first
    vim.defer_fn(function()
      local i = 0
      local function nxt()
        i = i + 1
        if steps[i] then
          steps[i](nxt)
        else
          vim.cmd "qa!"
        end
      end
      nxt()
    end, 1500)
  end,
})
