-- ── Noodle collection from a minimal API (pure) ─────────────────────────────
-- What `<leader>cNo` needs: one `.yml` request per `MapGet/MapPost/…` route (Noodle's collection format —
-- one request per file, `$base_url` + native `:param` tokens), `settings.yml` (env `local`) and
-- `.environments/local.env` (the base URL). Never overwrites: files that exist are left alone. No process runs here.
local M = {}

--- The `{param}` names of a route, file order, no duplicates (pure)
---@param route string e.g. "/hello/{name}/posts/{id:int}"
---@return string[]
function M.params(route)
  local out, seen = {}, {}
  for p in route:gmatch "{([^{}:/]+)" do
    if not seen[p] then
      seen[p] = true
      out[#out + 1] = p
    end
  end
  return out
end

--- The URL Noodle wants: `{param}` → `:param` (pure)
---@param route string
---@return string
function M.noodle_url(route)
  return (route:gsub("{([^{}:/]+)[^}]*}", ":%1"))
end

--- The file slug of a route: "/" → "root", "/hello/{name}" → "hello-name" (pure)
---@param route string
---@return string
function M.slug(route)
  local s = route:gsub("[{}]", ""):gsub("[^%w]+", "-"):gsub("^-", ""):gsub("-$", ""):lower()
  return s == "" and "root" or s
end

--- The file name of a request: "get-hello-name.yml" (pure)
---@param method string "Get"
---@param route string
---@return string
function M.filename(method, route)
  return ("%s-%s.yml"):format(method:lower(), M.slug(route))
end

--- One request file (pure): native `:param` tokens + `path_params` samples, status 200 asserted on reads
---@param method string "Get"
---@param route string "/hello/{name}"
---@param sampled string "/hello/world" for the display name
---@return string
function M.request_yml(method, route, sampled)
  local lines = {
    ("name: %s %s"):format(method:upper(), sampled),
    ("method: %s"):format(method:upper()),
    ("url: $base_url%s"):format(M.noodle_url(route)),
  }
  local params = M.params(route)
  if #params > 0 then
    lines[#lines + 1] = "path_params:"
    for _, p in ipairs(params) do
      lines[#lines + 1] = ("  - name: %s"):format(p)
      lines[#lines + 1] = "    value: world"
    end
  end
  if method == "Get" or method == "Delete" or method == "Head" then
    lines[#lines + 1] = "assert:"
    lines[#lines + 1] = "  - expression: status"
    lines[#lines + 1] = "    operator: equals"
    lines[#lines + 1] = "    value: 200"
    lines[#lines + 1] = "tags:"
    lines[#lines + 1] = "  - smoke"
  else
    lines[#lines + 1] = "body_type: json"
    lines[#lines + 1] = "body: |-"
    lines[#lines + 1] = "  {}"
  end
  return table.concat(lines, "\n") .. "\n"
end

--- Collection settings: display name + default env `local` (pure)
---@param name string
---@return string
function M.settings_yml(name)
  return ("name: %s\nenvironment: local\n"):format(name)
end

--- The `local` environment: badge color + base URL (pure)
---@param base string
---@return string
function M.env_file(base)
  return ("_color=info\nbase_url=%s\n"):format(base)
end

return M
