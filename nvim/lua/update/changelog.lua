-- ── CHANGELOG.md (pure) ──────────────────────────────────────────────────────
-- The file is one section per release, newest first: `## [1.8.0] - 2026-10-20`, then `### Highlights`,
-- `### Features`… with bullets. Here it is split into sections and drawn as lines for the panel.
local semver = require "update.semver"

local M = {}

---@class ChangelogSection
---@field version string
---@field date string?
---@field lines string[] the section's lines, after its heading

---@param text string
---@return ChangelogSection[] newest first, as the file has them
function M.sections(text)
  local out, current = {}, nil
  for line in (text or ""):gmatch "([^\n]*)\n?" do
    local version, date = line:match "^## %[?v?([%d%.%-%w]+)%]?%s*%-?%s*([%d%-]*)"
    if version and semver.parse(version) then
      current = { version = version, date = date ~= "" and date or nil, lines = {} }
      out[#out + 1] = current
    elseif current then
      current.lines[#current.lines + 1] = line
    end
  end
  for _, section in ipairs(out) do
    while #section.lines > 0 and section.lines[#section.lines]:match "^%s*$" do
      section.lines[#section.lines] = nil
    end
    while #section.lines > 0 and section.lines[1]:match "^%s*$" do
      table.remove(section.lines, 1)
    end
  end
  return out
end

--- Sections newer than `from` (exclusive) up to `to` (inclusive, default: every one newer).
---@param sections ChangelogSection[]
---@param from string
---@param to string?
---@return ChangelogSection[]
function M.between(sections, from, to)
  return vim.tbl_filter(function(s)
    return semver.newer(s.version, from) and (not to or semver.compare(s.version, to) ~= 1)
  end, sections)
end

--- One section as styled lines (segments `{ text, hl }`) for a pane `width` wide.
---@param section ChangelogSection
---@param width integer
---@return table[][]
function M.render(section, width)
  local wrap = require("utils.market").wrap
  local out = {
    {
      { "  " .. section.version, "GuiPickerTitle" },
      { section.date and ("   " .. section.date) or "", "GuiPickerDim" },
    },
    { { "" } },
  }
  for _, line in ipairs(section.lines) do
    local heading = line:match "^###%s+(.*)$"
    if heading then
      out[#out + 1] = { { "" } }
      out[#out + 1] = { { "  " .. heading:upper(), "GuiPickerLabel" } }
    elseif line:match "^%s*$" then
      out[#out + 1] = { { "" } }
    else
      local bullet, rest = line:match "^(%s*[-*])%s+(.*)$"
      local indent = bullet and "  • " or "    "
      local text = (rest or line):gsub("%*%*(.-)%*%*", "%1"):gsub("`([^`]*)`", "%1"):gsub("%s*%([%x]+%)%s*$", "")
      local first = true
      for _, part in ipairs(wrap(text, width - 6)) do
        out[#out + 1] = { { (first and indent or "    ") .. part, "GuiPickerText" } }
        first = false
      end
    end
  end
  return out
end

return M
