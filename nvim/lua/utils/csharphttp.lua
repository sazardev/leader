-- ── .http test file from a minimal API (pure) ───────────────────────────────
-- What `<leader>ch` needs: the routes `Program.cs` maps (`app.MapGet("/hello/{name}", …)`), a sample value for
-- `{param}`, the base URL from `Properties/launchSettings.json`, the `.http` text (Rider/JetBrains format) and
-- the equivalent `curl` lines. No process runs here. Limitation: routes behind `MapGroup("/prefix")` keep only
-- their own suffix (the group prefix is not resolved).
local M = {}

M.METHODS = { "Get", "Post", "Put", "Delete", "Patch" }

--- Every `x.MapMETHOD("/route", …)` in the text, file order, no duplicates (pure).
--- `MapGroup("/prefix")` prefixes are not resolved: a grouped route keeps its own suffix.
---@param text string?
---@return { method: string, route: string }[]
function M.routes(text)
  text = text or ""
  local want = { MapGet = "Get", MapPost = "Post", MapPut = "Put", MapDelete = "Delete", MapPatch = "Patch" }
  local out, seen = {}, {}
  local at = 1
  while true do
    local s, e, map, route = text:find('%.(Map%w+)%s*%(%s*"([^"]+)"', at)
    if not s then
      break
    end
    local method = want[map]
    if method and not seen[method .. " " .. route] then
      seen[method .. " " .. route] = true
      out[#out + 1] = { method = method, route = route }
    end
    at = e + 1
    _ = s
  end
  return out
end

--- A route with `{param}` (or `:param`) replaced by a sample value (pure)
---@param route string
---@return string
function M.sample(route)
  return (route:gsub("{[^}]+}", "world"):gsub(":([%w_]+)", "world"))
end

--- The base URL: first `applicationUrl` of the launch profiles, else the fallback (pure)
---@param launch_text string? the launchSettings.json text ("" = none)
---@param fallback string? default "http://localhost:5000"
---@return string
function M.base_url(launch_text, fallback)
  launch_text = launch_text or ""
  fallback = fallback or "http://localhost:5000"
  local url = launch_text:match '"applicationUrl"%s*:%s*"([^"]+)"'
  if url then
    return url:match "^[^;]+" or fallback
  end
  return fallback
end

--- The `.http` file (Rider/JetBrains format): one request per route, `###` between them (pure)
---@param base string e.g. "http://localhost:5231"
---@param routes { method: string, route: string }[]
---@param name string? the project name, for the header comment
---@return string
function M.render(base, routes, name)
  local lines = {
    ("### %s (%s)"):format(name or "api", base),
    "### run the app first (<leader>cr), then fire each request",
    "",
  }
  for i, r in ipairs(routes) do
    if i > 1 then
      lines[#lines + 1] = "###"
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = ("%s %s%s"):format(r.method:upper(), base, M.sample(r.route))
    if r.method ~= "Get" and r.method ~= "Delete" then
      lines[#lines + 1] = "Content-Type: application/json"
      lines[#lines + 1] = ""
      lines[#lines + 1] = "{}"
    end
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

--- The equivalent `curl` of one route (pure): status code + URL on one line, body discarded
---@param base string
---@param route { method: string, route: string }
---@return string
function M.curl(base, route)
  local url = base .. M.sample(route.route)
  return ("curl -s -o /dev/null -w %s %s"):format(
    vim.fn.shellescape(("%s %s -> %%{http_code}\\n"):format(route.method:upper(), M.sample(route.route))),
    vim.fn.shellescape(url)
  )
end

return M
