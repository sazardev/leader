-- Inline color preview (hex, rgb, Tailwind classes)
return {
  "brenoprata10/nvim-highlight-colors",
  event = { "BufReadPost", "BufNewFile" },
  opts = {
    render = "background",
    enable_named_colors = true,
    enable_tailwind = true,
  },
  config = function(_, opts)
    require("nvim-highlight-colors").setup(opts)

    -- The plugin clears and repaints the window on TextChanged / TextChangedP (every key while the completion menu is
    -- open) and WinScrolled, which costs more than a frame on a typical file. Its autocmds are replaced by the same
    -- callbacks behind a short trailing timer per buffer; the events that mean "a new view" stay immediate.
    local delayed = { TextChanged = true, TextChangedP = true, WinScrolled = true }
    local group = vim.api.nvim_create_augroup("HighlightColorsDebounced", { clear = true })
    local timers = {}
    for _, au in ipairs(vim.api.nvim_get_autocmds { event = vim.tbl_keys(delayed) }) do
      local cb = au.callback
      if type(cb) == "function" and debug.getinfo(cb, "S").source:find("nvim-highlight-colors", 1, true) then
        vim.api.nvim_del_autocmd(au.id)
        vim.api.nvim_create_autocmd(au.event, {
          group = group,
          callback = function(ev)
            local timer = timers[ev.buf] or vim.uv.new_timer()
            timers[ev.buf] = timer
            timer:stop()
            timer:start(
              60,
              0,
              vim.schedule_wrap(function()
                if vim.api.nvim_buf_is_valid(ev.buf) then
                  cb(ev)
                end
              end)
            )
          end,
        })
      end
    end
  end,
}
