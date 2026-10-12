-- ── Acciones de Markdown ─────────────────────────────────────────────────────
local actions = require "utils.actions"
local log = require "utils.log"
local md = require "utils.markdown"

--- Muestra/oculta los diagnósticos (errores del linter) SOLO en este buffer: sirve
--- para leer el markdown "como libro". El linter sigue corriendo, solo se ocultan.
local function toggle_diagnostics()
  local on = not vim.diagnostic.is_enabled { bufnr = 0 }
  vim.diagnostic.enable(on, { bufnr = 0 })
  log.info("Diagnostics for this buffer: " .. (on and "visible" or "hidden"))
end

return {
  { "r", "toggle render", actions.ex "RenderMarkdown toggle" },
  { "d", "toggle linter diagnostics (this buffer only)", toggle_diagnostics },
  { "z", "reading mode (centered, distraction-free)", md.reading_mode },
  { "s", "spell check (es, en)", md.toggle_spell },
  { "w", "word count and reading time", md.word_count },
  { "x", "toggle checkbox", md.toggle_checkbox },
  { "o", "outline", actions.ex "AerialToggle" },
  { "f", "format", actions.format },
}
