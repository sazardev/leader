-- ── Solution Explorer (<leader>cLo) ──────────────────────────────────────────
-- The Rider-like view of the .sln: left, the solution by folder with TFM/output/test badges; right, the
-- selected project (TFMs, output kind, dependencies, direct packages). Keys: Enter open the .csproj,
-- b build it, r run it, a add it to the solution (when it is not in it), / filter, Tab fold a folder,
-- q close. Nothing is dragged or dropped (Neovim has no Solution Explorer tree editing); edits happen
-- through `dotnet sln` / `dotnet add reference` in the terminal.
local market = require "utils.market"
local modal = require "utils.modal"
local proj = require "utils.csharpproj"
local model_mod = require "utils.csharpsolution"

local M = {}

--- Builds the model of the solution around the current file (disk reads only)
---@param root string?
---@param solution string?
---@return table
function M.current_model(root, solution)
  root = root or proj.root()
  solution = solution or proj.solution(root)
  return model_mod.model(root, solution)
end

--- Opens the explorer (market state lives on the returned table, so tests can drive rows/detail)
---@param opts { root?: string, solution?: string }?
---@return table?
function M.open(opts)
  opts = opts or {}
  local st = { model = M.current_model(opts.root, opts.solution) }
  if #st.model.projects == 0 then
    require("utils.log").warn "C#: no solution or project around this file"
    return nil
  end
  local function open_project(p)
    market.close(m)
    vim.cmd.edit(vim.fn.fnameescape(p.path))
  end
  local function run_in_terminal(cmd, p)
    market.close(m)
    require("utils.terminal").run(cmd, st.model.root)
  end
  local function build(p)
    run_in_terminal(("dotnet build %s"):format(vim.fn.shellescape(p.path)), p)
  end
  local function run_project(p)
    local profiles = proj.profiles(vim.fs.dirname(p.path))
    local flag = profiles[1] and (" --launch-profile " .. vim.fn.shellescape(profiles[1].name)) or ""
    run_in_terminal(("dotnet run --project %s%s"):format(vim.fn.shellescape(p.path), flag), p)
  end
  local function add_to_solution(p)
    if not st.model.solution then
      require("utils.log").warn "C#: no .sln/.slnx to add to"
      return
    end
    run_in_terminal(
      ("dotnet sln %s add %s"):format(vim.fn.shellescape(st.model.solution), vim.fn.shellescape(p.path)),
      p
    )
  end
  local m = market.new {
    title = "Solution explorer",
    rows = function()
      return model_mod.rows(st.model)
    end,
    selectable = function(row)
      return row.project ~= nil
    end,
    list_line = function(row)
      if row.title then
        return { { "  " .. row.title, modal.hl.key } }
      elseif row.spacer then
        return { { "" } }
      elseif row.group then
        return { { ("  %s"):format(row.group:upper()), modal.hl.muted } }
      end
      local p = row.project
      local badges = table.concat(p.tfms, ",") .. " " .. p.output:lower()
      if p.is_test then
        badges = badges .. " test"
      end
      return {
        { "  " .. p.name, modal.hl.file },
        { ("  · %s"):format(badges), modal.hl.muted },
      }
    end,
    pane = function(_, row)
      local lines = model_mod.detail(st.model, row and row.project)
      return vim.tbl_map(function(line)
        return { { line, modal.hl.muted } }
      end, lines)
    end,
    summary = function()
      return {
        {
          {
            ("  %s · %d projects · %d groups"):format(
              st.model.solution and vim.fs.basename(st.model.solution) or "projects",
              #st.model.projects,
              #(st.model.groups or {})
            ),
            modal.hl.key,
          },
        },
        { { "  Enter open · b build · r run · a add to solution · / filter · Tab folder", modal.hl.muted } },
      }
    end,
    hints = function()
      return {
        { "Enter", "open" },
        { "b", "build" },
        { "r", "run" },
        { "a", "add" },
        { "/", "filter" },
        { "q", "close" },
      }
    end,
    help = {
      { "Enter", "open the .csproj under the cursor" },
      { "b", "dotnet build the project" },
      { "r", "dotnet run the project (first launch profile)" },
      { "a", "dotnet sln add the project" },
    },
    keys = {
      list = {
        {
          "b",
          function(_, row)
            if row and row.project then
              build(row.project)
            end
          end,
        },
        {
          "r",
          function(_, row)
            if row and row.project then
              run_project(row.project)
            end
          end,
        },
        {
          "a",
          function(_, row)
            if row and row.project then
              add_to_solution(row.project)
            end
          end,
        },
      },
    },
    read = function(_, row)
      if row and row.project then
        open_project(row.project)
      end
    end,
  }
  return m
end

return M
