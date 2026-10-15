-- ── After a Dart conversion is accepted: its import and `part` lines ─────────
-- `<leader>at` replaces only the selection, but freezed / json_serializable / drift code needs lines at the top of the
-- file (the annotation import, `part 'x.freezed.dart';`, `part 'x.g.dart';`). They are added here when the proposal is
-- accepted, by rule (agent/convert.lua `header`): 0 tokens, never twice, never in a file that already has them.
local convert = require "agent.convert"

local M = {}

function M.setup()
  require("agent.events").on("proposal.accepted", function(e)
    local job = e.job
    if not (job and job.action and job.action.name == "convert" and job.target and job.target.lang == "dart") then
      return
    end
    local buf = e.buf
    local base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
    local edits = convert.header(vim.api.nvim_buf_get_lines(buf, 0, -1, false), base, e.lines or {})
    for _, edit in ipairs(edits) do
      vim.api.nvim_buf_set_lines(buf, edit.row, edit.row, false, edit.lines)
    end
  end)
end

return M
