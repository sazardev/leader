-- ── NuGet Manager (<leader>cNm) ──────────────────────────────────────────────
-- The Rider-like view: Direct / Transitive / Vulnerable / Outdated on the left, the selected package on the
-- right (versions, project, vulnerability, and the assets.json graph as "depends on"). Keys: Enter update
-- to latest (outdated only, otherwise open search), a add a package, x remove the selected direct package,
-- / filter, Tab fold a group, q close. The graph is real only with `obj/project.assets.json`
-- (`dotnet restore`); without it transitive packages are shown flat grouped by framework.
local market = require "utils.market"
local modal = require "utils.modal"
local proj = require "utils.csharpproj"
local nuget = require "utils.csharpnuget"

local M = {}

--- The data of the manager for `root` (runs the three `dotnet list` queries lazily on open)
---@param root string
---@param on_ready fun(state: table)
function M.load(root, on_ready)
  local target = proj.test_target(root) or proj.solution(root) or proj.project(root)
  if not target then
    return on_ready(nil)
  end
  local function list(args, cb)
    vim.system(
      { "dotnet", "list", target, "package", unpack(args) },
      { cwd = root, text = true, timeout = 60000 },
      function(res)
        vim.schedule(function()
          if res.code ~= 0 then
            require("utils.log").warn(
              ("C#: dotnet list failed: %s"):format(vim.trim(res.stderr or ""):match "[^\n]+" or "?")
            )
            return cb(nil)
          end
          cb(res.stdout or "")
        end)
      end
    )
  end
  list({ "--format", "json" }, function(all_text)
    if not all_text then
      return on_ready(nil)
    end
    local all = proj.parse_list_all(all_text)
    list({ "--outdated", "--format", "json" }, function(out_text)
      local outdated = out_text and proj.parse_outdated(out_text) or {}
      list({ "--vulnerable", "--include-transitive", "--format", "json" }, function(vul_text)
        local vulnerable = vul_text and proj.parse_vulnerable(vul_text) or {}
        -- graph from the first project with assets.json
        local graph = {}
        for _, p in ipairs(all) do
          if p.direct then
            local g = nuget.project_graph(p.project)
            for k, v in pairs(g) do
              graph[k] = v
            end
          end
        end
        on_ready { root = root, target = target, all = all, outdated = outdated, vulnerable = vulnerable, graph = graph }
      end)
    end)
  end)
end

--- Opens the manager (market)
---@return table?
function M.open()
  local root = proj.root()
  require("utils.log").info "NuGet: reading packages…"
  M.load(root, function(st)
    if not st then
      return
    end
    local m = market.new {
      title = "NuGet manager",
      rows = function()
        return nuget.rows(st.all, st.outdated, st.vulnerable, st.graph)
      end,
      selectable = function(row)
        return row.pkg ~= nil
      end,
      list_line = function(row)
        if row.title then
          return { { "  " .. row.title, modal.hl.key } }
        elseif row.spacer then
          return { { "" } }
        elseif row.group then
          return { { ("  %s"):format(row.group:upper()), modal.hl.muted } }
        end
        local p = row.pkg
        local badges = ""
        if row.vuln then
          badges = badges .. " ⚠"
        end
        if row.latest then
          badges = (" ▲ %s→%s"):format(p.resolved or p.requested or "?", row.latest)
        end
        return {
          { "  " .. p.id, row.vuln and modal.hl.warn or modal.hl.file },
          { ("  · %s%s"):format(p.resolved or p.requested or "?", badges), modal.hl.muted },
        }
      end,
      pane = function(_, row)
        local lines = nuget.detail(row, st.all)
        return vim.tbl_map(function(line)
          return { { line, modal.hl.muted } }
        end, lines)
      end,
      summary = function()
        local direct = vim.tbl_filter(function(p)
          return p.direct
        end, st.all)
        return {
          {
            {
              ("  %d direct · %d transitive · %d outdated · %d vulnerable"):format(
                #direct,
                #st.all - #direct,
                #st.outdated,
                #st.vulnerable
              ),
              modal.hl.key,
            },
          },
          { { "  Enter update/search · a add · x remove (direct) · / filter · Tab group", modal.hl.muted } },
        }
      end,
      hints = function()
        return {
          { "Enter", "update" },
          { "a", "add" },
          { "x", "remove" },
          { "q", "close" },
        }
      end,
      help = {
        { "Enter", "update an outdated package to latest, otherwise search" },
        { "a", "add a package (prompt for id)" },
        { "x", "remove the selected direct package from its project" },
        { "Tab", "fold a group" },
      },
      keys = {
        list = {
          {
            "a",
            function(_, _)
              modal.input(
                { "Package (e.g. Microsoft.EntityFrameworkCore.Sqlite)" },
                { title = "dotnet add package", confirm = "Add" },
                function(id)
                  if id ~= "" then
                    local project = st.all[1] and st.all[1].project
                    if project then
                      market.close(m)
                      require("utils.terminal").run(
                        ("dotnet add %s package %s"):format(vim.fn.shellescape(project), vim.fn.shellescape(id)),
                        root
                      )
                    end
                  end
                end
              )
            end,
          },
          {
            "x",
            function(_, row)
              if row and row.pkg and row.pkg.direct and row.pkg.project then
                market.close(m)
                require("utils.terminal").run(
                  ("dotnet remove %s package %s"):format(
                    vim.fn.shellescape(row.pkg.project),
                    vim.fn.shellescape(row.pkg.id)
                  ),
                  root
                )
              else
                require("utils.log").warn "C#: only direct packages can be removed here"
              end
            end,
          },
        },
      },
      read = function(_, row)
        if row and row.pkg and row.latest then
          market.close(m)
          require("utils.terminal").run(
            ("dotnet add %s package %s --version %s"):format(
              vim.fn.shellescape(row.pkg.project),
              vim.fn.shellescape(row.pkg.id),
              vim.fn.shellescape(row.latest)
            ),
            root
          )
        else
          require("utils.log").info "NuGet: no newer version for this package (a to add, x to remove)"
        end
      end,
    }
    return m
  end)
  return nil
end

return M
