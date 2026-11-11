-- Local FIM completion: Qwen2.5-Coder 1.5B (Q8) through llama.cpp, ghost text drawn by llama.vim.
-- The server and the on/off switch live in lua/fim; this file only configures the client. Loaded on demand
-- (lua/fim calls lazy.load once the server answers), never at startup when disabled.
return {
  "ggml-org/llama.vim",
  event = "User FimReady",
  cond = function()
    return require("core.settings").fim.enabled == true
  end,
  init = function()
    local settings = require "core.settings"
    vim.g.llama_config = {
      endpoint_fim = ("http://127.0.0.1:%d/infill"):format(settings.fim.port or 8012),
      auto_fim = true,
      enable_at_startup = true,
      show_info = 0,
      n_prefix = 128,
      n_suffix = 32,
      n_predict = settings.fim.max_predict or 64,
      fim_debounce_ms = settings.fim.debounce_ms or 150,
      t_max_predict_ms = 1000,
      ring_n_chunks = 8,
      ring_chunk_size = 32,
      max_line_suffix = 8,
      -- Accept with Ctrl+Tab (full) / Ctrl+Shift+Tab (first line); lua/fim also binds these globally so they exist
      -- before the first hint and in every buffer. Tab stays blink.cmp's normal completion.
      keymap_fim_trigger = "",
      keymap_fim_accept_full = "<C-Tab>",
      keymap_fim_accept_line = "<C-S-Tab>",
      keymap_fim_accept_word = "",
      keymap_fim_next = "",
      keymap_fim_prev = "",
      keymap_debug_toggle = "",
      keymap_inst_trigger = "",
      keymap_inst_rerun = "",
      keymap_inst_continue = "",
      keymap_inst_accept = "",
      keymap_inst_cancel = "",
    }
    -- the flat editor's faint text, not llama.vim's orange
    vim.api.nvim_set_hl(0, "llama_hl_fim_hint", { link = require("ui.flat").enabled() and "LspInlayHint" or "Comment" })
  end,
}
