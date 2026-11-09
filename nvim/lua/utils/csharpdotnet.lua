-- ── dotnet command builders (pure) ─────────────────────────────────────────
-- Every `dotnet …` the C# menu runs, built here so a missing/empty project never becomes `--project ''`
-- (dotnet answers "Required argument missing for option '--project'"). With no project the command is bare
-- (`dotnet build` in the cwd builds whatever project is there); the callers decide the cwd. No process runs here.
local M = {}

---@param s string?
---@return string shell-quoted, or "" when there is nothing to pass
local function q(s)
  if s == nil or s == "" then
    return ""
  end
  return vim.fn.shellescape(s)
end

--- The `--project <path>` argument, or "" when there is no project (bare command in the cwd instead)
---@param path string?
---@return string
function M.project_arg(path)
  if path == nil or path == "" then
    return ""
  end
  return " --project " .. q(path)
end

--- The `--launch-profile <name>` flag, or "" without a profile
---@param profile string?
---@return string
function M.profile_flag(profile)
  if profile == nil or profile == "" then
    return ""
  end
  return " --launch-profile " .. q(profile)
end

---@param path string? the .csproj ("" = bare `dotnet run` in the cwd)
---@param profile string? launch profile ("" = none)
---@return string
function M.run_cmd(path, profile)
  return ("dotnet run%s%s"):format(M.project_arg(path), M.profile_flag(profile))
end

---@param path string? the .csproj ("" = bare `dotnet watch` in the cwd)
---@param profile string? launch profile ("" = none)
---@return string
function M.watch_cmd(path, profile)
  return ("dotnet watch%s run%s"):format(M.project_arg(path), M.profile_flag(profile))
end

---@param sub string dotnet verb ("build", "publish", "format", "restore"…)
---@param path string? the .csproj ("" = bare `dotnet <sub>` in the cwd)
---@param opts? { project_flag?: boolean, extra?: string } `project_flag` forces `--project` (run/watch style),
--- otherwise the path goes positional (`dotnet build <path>`), as before
---@return string
function M.cmd(sub, path, opts)
  opts = opts or {}
  local arg
  if opts.project_flag then
    arg = M.project_arg(path)
  elseif path == nil or path == "" then
    arg = ""
  else
    arg = " " .. q(path)
  end
  return ("dotnet %s%s%s"):format(sub, arg, opts.extra and (" " .. opts.extra) or "")
end

return M
