-- ── CSS actions ──────────────────────────────────────────────────────────────
local actions = require "utils.actions"

return {
  { "f", "format", actions.format },
  { "c", "toggle color preview", actions.ex "HighlightColors Toggle" },
  { "o", "outline", actions.ex "AerialToggle" },
}
