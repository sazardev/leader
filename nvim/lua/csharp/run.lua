-- ── Run / Debug configurations (<leader>cG) ──────────────────────────────────
-- The saveable dropdown: launch profiles per project, Docker/Compose when present, and the saved
-- custom/compound configs (stdpath("state")/csharp-run.json). Keys: Enter run, d debug (dotnet configs
-- only — same netcoredbg flow as <leader>cDd), s save the current selection as a custom command,
-- x delete the saved one, / filter, Tab fold a kind. Compound configs are chains with &&; Docker configs
-- are `docker build && docker run`.
local market = require "utils.market"
local modal = require "utils.modal"
local proj = require "utils.csharpproj"
local solution = require "utils.csharpsolution"
local runcfg = require "utils.csharprun"

local M = {}

--- Every config of the current root (reads the disk)
---@param root string?
---@return table[]
function M.current_configs(root)
  root = root or proj.root()
  local model = solution.model(root, proj.solution(root))
  local saved = runcfg.read()[root] or {}
  local docker = runcfg.docker(
    root,
    vim.uv.fs_stat(root .. "/Dockerfile") ~= nil,
    vim.uv.fs_stat(root .. "/docker-compose.yml") ~= nil or vim.uv.fs_stat(root .. "/docker-compose.yaml") ~= nil
  )
  return runcfg.build(root, model.projects, saved, docker)
end

--- Rows for the market: grouped by kind (pure over the configs)
---@param configs table[]
---@return table[]
function M.rows(configs)
  local rows = { { title = ("RUN CONFIGURATIONS · %d"):format(#(configs or {})) }, { spacer = true } }
  local groups = {}
  local order = {}
  for _, cfg in ipairs(configs or {}) do
    local g = ({
      dotnet = "Dotnet profiles",
      docker = "Docker",
      compose = "Docker Compose",
      custom = "Saved",
      compound = "Compound",
    })[cfg.kind] or (cfg.kind or "Other")
    if not groups[g] then
      groups[g] = { name = g, list = {} }
      order[#order + 1] = g
    end
    groups[g].list[#groups[g].list + 1] = cfg
  end
  for _, g in ipairs(order) do
    rows[#rows + 1] = { group = g }
    for _, cfg in ipairs(groups[g].list) do
      rows[#rows + 1] = { config = cfg, group = g }
    end
    rows[#rows + 1] = { spacer = true }
  end
  if #(configs or {}) == 0 then
    rows[#rows + 1] = { title = "NO CONFIGURATIONS" }
  end
  return rows
end

--- Runs a config (terminal for dotnet/docker/custom/compound)
---@param cfg table
function M.run_config(cfg)
  if not cfg then
    return
  end
  local cmd = runcfg.command(cfg)
  if not cmd then
    return require("utils.log").warn "C#: this configuration has no command"
  end
  require("utils.terminal").run(cmd, cfg.root or proj.root())
end

--- Debugs a config (dotnet only, through langdebug's netcoredbg flow)
---@param cfg table
function M.debug_config(cfg)
  if not cfg or cfg.kind ~= "dotnet" then
    return require("utils.log").warn "C#: only dotnet configurations can be debugged here (use <leader>cDd)"
  end
  -- langdebug builds the project and launches the assembly with the profile URL/env
  require("langdebug").start("csharp", "program")
end

--- Saves a custom command under `name` for `root` (s appends, never overwrites an existing name silently)
---@param root string
---@param name string
---@param command string
function M.save(root, name, command)
  local all = runcfg.read()
  local list = all[root] or {}
  for _, cfg in ipairs(list) do
    if cfg.name == name then
      require("utils.log").warn(("C#: config %q already exists (delete it first)"):format(name))
      return
    end
  end
  list[#list + 1] = { name = name, kind = "custom", command = command, root = root }
  runcfg.write(root, list)
  require("utils.log").info(("C#: saved %q"):format(name))
end

--- Deletes a saved config by name
---@param root string
---@param name string
function M.delete(root, name)
  local list = runcfg.read()[root] or {}
  local out = vim.tbl_filter(function(cfg)
    return cfg.name ~= name
  end, list)
  runcfg.write(root, out)
end

--- Opens the dropdown (market)
---@return table?
function M.open()
  local root = proj.root()
  local st = { root = root, configs = M.current_configs(root) }
  if #st.configs == 0 then
    require("utils.log").warn "C#: no run configurations here (create a launchSettings.json or a Dockerfile)"
    return nil
  end
  local m = market.new {
    title = "Run configurations",
    rows = function()
      return M.rows(st.configs)
    end,
    selectable = function(row)
      return row.config ~= nil
    end,
    list_line = function(row)
      if row.title then
        return { { "  " .. row.title, modal.hl.key } }
      elseif row.spacer then
        return { { "" } }
      elseif row.group then
        return { { ("  %s"):format(row.group:upper()), modal.hl.muted } }
      end
      local cfg = row.config
      local hint = cfg.kind == "dotnet" and (cfg.profile or "no profile")
        or cfg.kind == "docker" and "docker build+run"
        or cfg.kind == "compose" and "compose up"
        or cfg.kind == "compound" and ("compound · " .. #(cfg.targets or {}) .. " commands")
        or cfg.command
        or ""
      return {
        { "  " .. cfg.name, modal.hl.file },
        { ("  · %s"):format(hint), modal.hl.muted },
      }
    end,
    pane = function(_, row)
      local cfg = row and row.config
      if not cfg then
        return { { "  No configuration under the cursor.", modal.hl.muted } }
      end
      local lines = {
        ("  %s"):format(cfg.name:upper()),
        ("  kind %s"):format(cfg.kind or "-"),
        "",
        ("  %s"):format(runcfg.command(cfg) or "(no command)"),
      }
      if cfg.url then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("  URL %s"):format(cfg.url)
      end
      local env = runcfg.env(cfg)
      if next(env) ~= nil then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "  ENV"
        for k, v in pairs(env) do
          lines[#lines + 1] = ("  %s=%s"):format(k, v)
        end
      end
      if cfg.project then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("  project %s"):format(proj.relative(root, cfg.project))
      end
      return vim.tbl_map(function(line)
        return { { line, modal.hl.muted } }
      end, lines)
    end,
    summary = function()
      return {
        { { ("  %d configurations"):format(#st.configs), modal.hl.key } },
        { { "  Enter run · d debug · s save custom · x delete saved · / filter · Tab kind", modal.hl.muted } },
      }
    end,
    hints = function()
      return {
        { "Enter", "run" },
        { "d", "debug" },
        { "s", "save" },
        { "x", "delete" },
        { "q", "close" },
      }
    end,
    help = {
      { "Enter", "run the configuration in the integrated terminal" },
      { "d", "debug it (dotnet only, netcoredbg)" },
      { "s", "save the selected command as a custom configuration (prompt for name+command)" },
      { "x", "delete the selected saved configuration" },
    },
    keys = {
      list = {
        {
          "d",
          function(_, row)
            if row and row.config then
              market.close(m)
              M.debug_config(row.config)
            end
          end,
        },
        {
          "s",
          function(_, row)
            local cfg = row and row.config
            local default_cmd = cfg and runcfg.command(cfg) or "dotnet run"
            modal.input(
              { "Custom command, e.g. dotnet run --project src/Api" },
              { title = "Save custom run", confirm = "Save" },
              function(cmd)
                if cmd == "" then
                  return
                end
                modal.input(
                  { (cfg and cfg.name:gsub("%s.*", "") or "MyConfig") .. " (name)" },
                  { title = "Name", confirm = "Save" },
                  function(name)
                    if name ~= "" then
                      M.save(root, name, cmd)
                      st.configs = M.current_configs(root)
                      market.refresh(m)
                    end
                  end
                )
              end
            )
          end,
        },
        {
          "x",
          function(_, row)
            local cfg = row and row.config
            if cfg and (cfg.kind == "custom" or cfg.kind == "compound") then
              M.delete(root, cfg.name)
              st.configs = M.current_configs(root)
              market.refresh(m)
            else
              require("utils.log").warn "C#: only saved configurations can be deleted here"
            end
          end,
        },
      },
    },
    read = function(_, row)
      if row and row.config then
        market.close(m)
        M.run_config(row.config)
      end
    end,
  }
  m = m or nil
  return m
end

return M
