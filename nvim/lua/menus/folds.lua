-- ── Fold context (global): <leader>z ─────────────────────────────────────────
-- Folds code by what it is (function, type, object, block) or everything at once (utils/folds.lua). The
-- comments have their own menu (<leader>C). All keys are single: `f` here, `F` the whole file.
local function folds()
  return require "utils.folds"
end

return {
  name = "Fold",
  prefix = "z",
  global = true,
  maps = {
    {
      "f",
      "function here",
      function()
        folds().here "function"
      end,
    },
    {
      "t",
      "type here (struct, class, interface)",
      function()
        folds().here "type"
      end,
    },
    {
      "o",
      "object here (table, map, array)",
      function()
        folds().here "object"
      end,
    },
    {
      "b",
      "block here (again: the one around it)",
      function()
        folds().block()
      end,
    },
    {
      "m",
      "methods of this type",
      function()
        folds().methods()
      end,
    },
    {
      "F",
      "all functions",
      function()
        folds().all "function"
      end,
    },
    {
      "T",
      "all types",
      function()
        folds().all "type"
      end,
    },
    {
      "O",
      "all objects",
      function()
        folds().all "object"
      end,
    },
    {
      "a",
      "all, outline only",
      function()
        folds().close_all_folds()
      end,
    },
    {
      "e",
      "expand all",
      function()
        folds().open_all_folds()
      end,
    },
    {
      "s",
      "all but this (focus)",
      function()
        folds().focus()
      end,
    },
    {
      "u",
      "unfold here and inside",
      function()
        folds().open_here()
      end,
    },
    {
      "z",
      "toggle here",
      function()
        folds().toggle()
      end,
    },
    {
      "1",
      "level 1 (top-level folds open)",
      function()
        folds().level(1)
      end,
    },
    {
      "2",
      "level 2",
      function()
        folds().level(2)
      end,
    },
    {
      "3",
      "level 3",
      function()
        folds().level(3)
      end,
    },
  },
}
