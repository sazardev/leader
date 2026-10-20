-- Benchmark probe: how long the first `find_files` of a session takes to show results (the idle preload has run).
--   nvim --headless -c "luafile scripts/bench-picker.lua"  → prints "picker_ms=<ms>"
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    -- after the idle preload (settings.preload.delay_ms) has finished
    vim.defer_fn(function()
      require("lazy").load { plugins = { "telescope.nvim" } }
      local t0 = vim.uv.hrtime()
      require("telescope.builtin").find_files()
      local timer = vim.uv.new_timer()
      timer:start(
        1,
        1,
        vim.schedule_wrap(function()
          local shown = false
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[b].filetype == "TelescopeResults" then
              shown = vim.trim(table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "")) ~= ""
            end
          end
          if shown or (vim.uv.hrtime() - t0) / 1e6 > 5000 then
            timer:stop()
            io.stdout:write(("picker_ms=%.0f\n"):format((vim.uv.hrtime() - t0) / 1e6))
            vim.cmd "qa!"
          end
        end)
      )
    end, (require("core.settings").preload.delay_ms or 600) + 900)
  end,
})
