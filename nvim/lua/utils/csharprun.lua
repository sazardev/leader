-- ── Run / Debug configurations (pure + persistence) ──────────────────────────
-- What Rider calls Run Configurations: a saveable list (launch profiles per project, Docker, Docker Compose,
-- compound, custom commands) with a dropdown to run or debug. The view and the execution are
-- csharp/run.lua; this file only builds the list, the shell command of a config and its persistence
-- (stdpath("state")/csharp-run.json, one entry per project root, like dartrun.json/tasks.json).
local proj = require "utils.csharpproj"

local M = {}

M.FILE = "csharp-run.json"

--- The state file (once per session, so tests can point XDG_STATE_HOME at a temp dir)
---@return string
function M.file()
  return vim.fn.stdpath "state" .. "/" .. M.FILE
end

--- Saved custom/compound configs of every root (pure file read)
---@return table<string, table[]>
function M.read()
  local f = io.open(M.file(), "r")
  if not f then
    return {}
  end
  local text = f:read "*a"
  f:close()
  local ok, data = pcall(vim.json.decode, text or "")
  return ok and type(data) == "table" and data or {}
end

--- Saves the configs of one root (never deletes another root's)
---@param root string
---@param list table[]
function M.write(root, list)
  local all = M.read()
  all[root] = list
  vim.fn.mkdir(vim.fn.stdpath "state", "p")
  local f = io.open(M.file(), "w")
  if f then
    f:write(vim.json.encode(all))
    f:close()
  end
end

--- Docker config of a folder (pure over the given file names)
---@param root string
---@param has_dockerfile boolean
---@param has_compose boolean
---@return table?
function M.docker(root, has_dockerfile, has_compose)
  if not has_dockerfile and not has_compose then
    return nil
  end
  if has_dockerfile then
    return {
      name = "Docker · " .. vim.fs.basename(root),
      kind = "docker",
      dockerfile = root .. "/Dockerfile",
      root = root,
    }
  end
  return {
    name = "Docker Compose · " .. vim.fs.basename(root),
    kind = "compose",
    compose = root .. "/docker-compose.yml",
    root = root,
  }
end

--- Every config of a root: launch profiles per project, Docker/Compose, then the saved ones (pure over
--- the given project infos and saved list; the caller reads the disk)
---@param root string
---@param projects table[] from csharpsolution.model
---@param saved table[] custom/compound configs of this root
---@param docker table? from M.docker
---@return table[]
function M.build(root, projects, saved, docker)
  local out = {}
  for _, p in ipairs(projects or {}) do
    local dir = vim.fs.dirname(p.path)
    local profiles = proj.profiles(dir)
    if #profiles == 0 then
      out[#out + 1] = { name = p.name, kind = "dotnet", project = p.path, root = root }
    else
      for _, pr in ipairs(profiles) do
        out[#out + 1] = {
          name = ("%s · %s"):format(p.name, pr.name),
          kind = "dotnet",
          project = p.path,
          profile = pr.name,
          url = pr.url,
          env = pr.env or {},
          root = root,
        }
      end
    end
  end
  if docker then
    out[#out + 1] = docker
  end
  for _, cfg in ipairs(saved or {}) do
    out[#out + 1] = cfg
  end
  return out
end

--- The shell command of a config (pure)
---@param cfg table
---@return string?
function M.command(cfg)
  if not cfg then
    return nil
  end
  if cfg.kind == "dotnet" and cfg.project then
    local flag = cfg.profile and (" --launch-profile " .. vim.fn.shellescape(cfg.profile)) or ""
    local args = cfg.args and (" -- " .. cfg.args) or ""
    return ("dotnet run --project %s%s%s"):format(vim.fn.shellescape(cfg.project), flag, args)
  elseif cfg.kind == "docker" and cfg.dockerfile then
    local dir = vim.fs.dirname(cfg.dockerfile)
    local tag = vim.fs.basename(dir):lower():gsub("[^%w_.-]", "-")
    return ("docker build -t %s -f %s %s && docker run --rm -p 8080:8080 %s"):format(
      vim.fn.shellescape(tag),
      vim.fn.shellescape(cfg.dockerfile),
      vim.fn.shellescape(dir),
      vim.fn.shellescape(tag)
    )
  elseif cfg.kind == "compose" and cfg.compose then
    local svc = cfg.service and (" " .. vim.fn.shellescape(cfg.service)) or ""
    return ("docker compose -f %s up --build%s"):format(vim.fn.shellescape(cfg.compose), svc)
  elseif cfg.kind == "custom" and cfg.command then
    return cfg.command
  elseif cfg.kind == "compound" and cfg.targets then
    local cmds = {}
    for _, t in ipairs(cfg.targets) do
      cmds[#cmds + 1] = t.command or t
    end
    return #cmds > 0 and table.concat(cmds, " && ") or nil
  end
  return nil
end

--- The env a config wants (pure): launchSettings env + saved env
---@param cfg table
---@return table<string, string>
function M.env(cfg)
  local out = {}
  for k, v in pairs(cfg and cfg.env or {}) do
    out[k] = v
  end
  if cfg and cfg.url then
    out.ASPNETCORE_URLS = cfg.url
  end
  return out
end

return M
