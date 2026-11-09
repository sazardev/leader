-- ── NuGet Manager: the model (pure) ──────────────────────────────────────────
-- What the manager needs: every package of the solution (`dotnet list package --format json`), the outdated
-- and vulnerable subsets, and the real dependency graph from `obj/project.assets.json` (`dependencies` of
-- each library) when it exists. The view is csharp/nuget.lua; this file only groups and explains.
local proj = require "utils.csharpproj"

local M = {}

--- The graph a manager shows: direct packages with their children (from assets.json), everything else flat
---@param assets table<string, string[]>|nil from csharpproj.parse_assets
---@param all table[] from csharpproj.parse_list_all
---@return table<string, string[]> direct id → child ids (sorted)
function M.graph(assets, all)
  if assets and next(assets) ~= nil then
    local out = {}
    local ids = {}
    for _, p in ipairs(all or {}) do
      if p.direct then
        ids[p.id] = true
      end
    end
    for id in pairs(ids) do
      out[id] = assets[id] or {}
    end
    -- also keep direct→transitive edges that assets.json knows even when the id is not in `all`
    for from, kids in pairs(assets) do
      if from ~= "<root>" and ids[from] then
        out[from] = kids
      end
    end
    return out
  end
  -- without assets.json: transitive packages are grouped by framework only (still visual, not a full graph)
  return {}
end

--- The rows of the manager (pure): groups Direct/Transitive/Vulnerable/Outdated
---@param all table[]
---@param outdated table[]
---@param vulnerable table[]
---@param graph table<string, string[]>?
---@return table[]
function M.rows(all, outdated, vulnerable, graph)
  local out_ids, vul_ids = {}, {}
  for _, p in ipairs(outdated or {}) do
    out_ids[p.id] = p.latest
  end
  for _, p in ipairs(vulnerable or {}) do
    vul_ids[p.id] = p
  end
  local direct, transitive = {}, {}
  for _, p in ipairs(all or {}) do
    local row = { pkg = p, latest = out_ids[p.id], vuln = vul_ids[p.id], children = (graph or {})[p.id] or {} }
    if p.direct then
      direct[#direct + 1] = row
    else
      transitive[#transitive + 1] = row
    end
  end
  table.sort(direct, function(a, b)
    return a.pkg.id < b.pkg.id
  end)
  table.sort(transitive, function(a, b)
    return a.pkg.id < b.pkg.id
  end)
  local rows = { { title = ("NUGET · %d direct · %d transitive"):format(#direct, #transitive) }, { spacer = true } }
  local function section(title, list)
    if #list == 0 then
      return
    end
    rows[#rows + 1] = { group = title }
    for _, row in ipairs(list) do
      rows[#rows + 1] = row
    end
    rows[#rows + 1] = { spacer = true }
  end
  section("Direct", direct)
  section("Transitive", transitive)
  local vul = vim.tbl_filter(function(r)
    return r.vuln ~= nil
  end, direct)
  local transitive_vul = vim.tbl_filter(function(r)
    return r.vuln ~= nil
  end, transitive)
  vim.list_extend(vul, transitive_vul)
  if #vul > 0 then
    section("Vulnerable", vul)
  end
  local out = vim.tbl_filter(function(r)
    return r.latest ~= nil
  end, direct)
  if #out > 0 then
    section("Outdated", out)
  end
  if #all == 0 then
    rows[#rows + 1] = { title = "NO PACKAGES" }
  end
  return rows
end

--- The detail pane of one package (pure)
---@param row table?
---@param all table[]
---@return string[]
function M.detail(row, all)
  if not row or not row.pkg then
    return { "No package under the cursor." }
  end
  local p = row.pkg
  local out = {
    ("  %s"):format(p.id:upper()),
    ("  %s%s"):format(p.direct and "direct" or "transitive", p.framework and (" · " .. p.framework) or ""),
    "",
    ("  Requested %s"):format(p.requested or "-"),
    ("  Resolved %s"):format(p.resolved or "-"),
    ("  Latest %s"):format(row.latest or "-"),
    ("  Project %s"):format(p.project and vim.fs.basename(p.project) or "-"),
  }
  if row.vuln then
    out[#out + 1] = ""
    out[#out + 1] = ("  ⚠ VULNERABLE %s · %s"):format(row.vuln.severity or "?", row.vuln.advisory or "")
  end
  out[#out + 1] = ""
  out[#out + 1] = ("  DEPENDS ON (%d)"):format(#(row.children or {}))
  if row.children and #row.children > 0 then
    for _, c in ipairs(row.children) do
      out[#out + 1] = ("  → %s"):format(c)
    end
  else
    out[#out + 1] = "  - no graph (run `dotnet restore` so obj/project.assets.json exists)"
  end
  -- who uses this package, when it is transitive
  if not p.direct then
    out[#out + 1] = ""
    out[#out + 1] = "  USED BY (transitive)"
    local used = false
    for _, o in ipairs(all or {}) do
      if o.direct and o.framework == p.framework then
        used = true
        out[#out + 1] = ("  · direct %s"):format(o.id)
        break
      end
    end
    if not used then
      out[#out + 1] = "  - only via assets.json graph"
    end
  end
  return out
end

--- The assets.json of a project (or nil)
---@param project_path string
---@return string?
function M.assets_path(project_path)
  local dir = vim.fs.dirname(project_path)
  local candidate = dir .. "/obj/project.assets.json"
  return vim.uv.fs_stat(candidate) and candidate or nil
end

--- The graph of a project from its assets.json (pure file read)
---@param project_path string
---@return table<string, string[]>
function M.project_graph(project_path)
  local path = M.assets_path(project_path)
  if not path then
    return {}
  end
  return proj.parse_assets(proj.read(path))
end

return M
