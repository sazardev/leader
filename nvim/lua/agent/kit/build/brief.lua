-- ── Build with agent: the plan's brief of the documents (pure) ───────────────
-- The plan and the file requests do not need the whole documents: the summary, the problem, the milestones, the generic
-- engineering principles and the workflow are for the people and for the checks. They need the requirements, the layout,
-- the conventions and the design system. A document without `##` sections is kept whole. The file requests still get the
-- full DESIGN.md (the interface is drawn there).
local M = {}

M.SECTIONS = {
  agents = { "Project", "Layout", "Conventions", "Boundaries" },
  stack = { "Stack", "Project layout", "Conventions", "Commands", "Testing", "Quality gates" },
  spec = {
    "Users and scenarios",
    "Requirements",
    "Non-functional requirements",
    "Data",
    "Interfaces",
    "Edge cases",
    "Open questions",
  },
}

--- The plan/file view of the documents: only the sections in `M.SECTIONS` (in the document's own order); the design is
--- kept whole. Pure (tested in test-kit.lua).
---@param docs table<string, string>
---@return table<string, string>
function M.brief(docs)
  local out = {}
  for id, text in pairs(docs or {}) do
    local keep = M.SECTIONS[id]
    if not keep or type(text) ~= "string" then
      out[id] = text
    else
      local kept, inside = {}, nil
      for line in (text .. "\n"):gmatch "([^\n]*)\n" do
        local heading = line:match "^##%s+(.-)%s*$"
        if heading then
          inside = vim.tbl_contains(keep, heading)
        end
        if inside ~= false then
          kept[#kept + 1] = line
        end
      end
      out[id] = #kept > 0 and table.concat(kept, "\n") or text
    end
  end
  return out
end

return M
