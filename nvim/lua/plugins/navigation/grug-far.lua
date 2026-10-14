-- Project-wide search and replace, VS Code style. Flat: a soft panel on the right, a `Grug FAR · g? help` header,
-- each input a `deep` bar with its label inside (ui/flat/grug.lua), the results right under them.
return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  keys = {
    { "<leader>fr", "<cmd>GrugFar<cr>", desc = "Find replace in project" },
  },
  opts = {
    icons = { enabled = false }, -- plain labels (Search:, Replace:), like the rest of the flat UI
    keymaps = {
      close = { n = "q" },
    },
    -- the demo's panel: labels inside the input rows, no padding lines, no help line (the header says `g? help`),
    -- no engine name or status icon on the separator
    showCompactInputs = true,
    showInputsTopPadding = false,
    showInputsBottomPadding = false,
    helpLine = { enabled = false },
    showEngineInfo = false,
    showStatusIcon = false,
    resultsSeparatorLineChar = " ",
    resultLocation = { showNumberLabel = false },
    engines = {
      ripgrep = { placeholders = { enabled = false } }, -- empty inputs stay empty bars, like the demo's
      astgrep = { placeholders = { enabled = false } },
    },
  },
  config = function(_, opts)
    require("grug-far").setup(opts)
    -- search/replace fields are free text: blink suggests nothing there (like the agent's input)
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("GrugFarNoCompletion", { clear = true }),
      pattern = "grug-far",
      callback = function(ev)
        vim.b[ev.buf].completion = false
      end,
    })
    if require("ui.flat").enabled() then
      require("ui.flat.grug").setup()
    end
  end,
}
