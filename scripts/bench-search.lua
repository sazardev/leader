-- Benchmark probe: how long the code-search index takes to build for this folder (the state dir decides whether a
-- stored index exists: the first session builds it, later ones load it).
--   nvim --headless -c "luafile scripts/bench-search.lua"  → prints "search_ms=<ms> read=<files read>"
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(function()
      local t0 = vim.uv.hrtime()
      require("codesearch.index").build(vim.fn.getcwd(), function(_, stats)
        io.stdout:write(("search_ms=%.0f read=%d\n"):format((vim.uv.hrtime() - t0) / 1e6, stats.read))
        vim.defer_fn(function()
          vim.cmd "qa!"
        end, 400) -- the index is written just after the build
      end)
    end, 300)
  end,
})
