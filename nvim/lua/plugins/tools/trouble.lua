-- Diagnostics panel
return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics project list" },
  },
  opts = {
    modes = {
      -- focus: on opening, the cursor enters the panel (by default it stays in the code and you
      -- cannot select or press Enter). Flat: the demo's list, one row per diagnostic
      -- (`✖ message  file [line:col]`), no folders or files to fold, under a `Diagnostics N` header
      diagnostics = require("ui.flat").enabled()
          and {
            focus = true,
            groups = {},
            sort = { "severity", "filename", "pos", "message" },
            format = "{flat_icon} {message:md} {flat_where}",
            win = {
              size = 0.4,
              wo = {
                winbar = "%#TroubleTitle# Diagnostics %#TroubleCount#%{v:lua.require'ui.flat'.diagnostic_total()}",
                winhighlight = "Normal:TroubleNormal,NormalNC:TroubleNormalNC,EndOfBuffer:TroubleNormal,"
                  .. "CursorLine:TroubleCursorLine,WinBar:TroubleTitle,WinBarNC:TroubleTitle",
              },
            },
          }
        or { focus = true },
    },
    formatters = {
      -- ✖ red / ▲ yellow / ● blue, like the demo's list
      flat_icon = function(ctx)
        local sev = ctx.item.severity or vim.diagnostic.severity.ERROR
        local icon = ({ "✖", "▲", "●", "○" })[sev] or "●"
        local hl = ({ "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" })[sev]
        return { text = icon, hl = hl }
      end,
      -- `note_service.go [6:2]`, faint
      flat_where = function(ctx)
        local name = vim.fn.fnamemodify(ctx.item.filename or "", ":t")
        return { text = ("%s [%d:%d]"):format(name, ctx.item.pos[1], ctx.item.pos[2] + 1), hl = "TroubleSource" }
      end,
    },
    keys = {
      -- Enter jumps to the diagnostic and opens its popup, like <leader>xd
      ["<cr>"] = {
        action = function(view, ctx)
          if not ctx.item then
            return view:fold(ctx.node) -- on a file: folds/unfolds
          end
          view:jump(ctx.item)
          vim.schedule(require("utils.diagblocks").popup)
        end,
        desc = "Jump and show diagnostic popup",
      },
    },
  },
  config = function(_, opts)
    require("trouble").setup(opts)
  end,
}
