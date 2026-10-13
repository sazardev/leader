-- ── Comments context (global): <leader>C ─────────────────────────────────────
-- Folds long comments (utils/comments.lua; minimum lines in
-- `settings.comments.min_lines`) and generates/audits documentation comments (utils/docgen.lua).
local function comments()
  return require "utils.comments"
end

local function docgen()
  return require "utils.docgen"
end

return {
  name = "Comments",
  prefix = "C",
  global = true,
  maps = {
    {
      "c",
      "collapse long comments",
      function()
        comments().collapse()
      end,
    },
    {
      "e",
      "expand comments",
      function()
        comments().expand()
      end,
    },
    {
      "t",
      "toggle comment under cursor",
      function()
        comments().toggle()
      end,
    },
    {
      "d",
      "doc comment template for this function/type",
      function()
        docgen().skeleton()
      end,
    },
    {
      "m",
      "public functions missing a doc comment (quickfix)",
      function()
        docgen().missing()
      end,
    },
  },
}
