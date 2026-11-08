-- C# / .NET env preset
local M = { id = "csharp", label = "C# / .NET", markers = { "*.csproj", "*.sln", "global.json" } }

---@param root string
---@return table<string,string>
function M.vars(root)
  local csproj = vim.fs.find(function(n)
    return n:match "%.csproj$" ~= nil
  end, { path = root, type = "file", limit = 1 })[1]
  local text = csproj and require("utils.project").read(csproj) or ""
  local name = text:match "<AssemblyName>([^<]+)</AssemblyName>"
    or (csproj and vim.fs.basename(csproj):gsub("%.csproj$", ""))
    or vim.fs.basename(root)
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (C# / .NET)
# Copy to .env and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
# .NET also reads appsettings.json (ConnectionStrings, Jwt, Cors). This file is
# the portable source for secrets and per-environment overrides.
ASPNETCORE_ENVIRONMENT=Development   # Development | Qa | Staging | Production
APP_NAME=%s
APP_DEBUG=true
ASPNETCORE_URLS=http://localhost:5000
PORT=5000
LOG_LEVEL=Information

# --- Database (IConfiguration: ConnectionStrings__<name> or DB_*) ---------
ConnectionStrings__DefaultConnection=Server=localhost;Database=%s_dev;User Id=app;Password=changeme;TrustServerCertificate=True
DB_HOST=localhost
DB_PORT=5432
DB_NAME=%s_dev
DB_USER=app
DB_PASSWORD=changeme
DATABASE_URL=postgres://app:changeme@localhost:5432/%s_dev

# --- Cache ------------------------------------------------------------------
Redis__ConnectionString=localhost:6379

# --- Auth -------------------------------------------------------------------
Jwt__Key=change-me-32-chars-minimum
Jwt__Issuer=%s
Jwt__Audience=%s
Jwt__ExpireHours=24
JWT_SECRET=change-me-32-chars-minimum

# --- External ---------------------------------------------------------------
Cors__AllowedOrigins__0=http://localhost:5173
S3_BUCKET=%s-dev
S3_ENDPOINT=http://localhost:9000

# --- Mailer -----------------------------------------------------------------
Smtp__Host=localhost
Smtp__Port=1025

# --- Observability ----------------------------------------------------------
Sentry__Dsn=
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

]]):format(name, name, name, name, name, name, name, name)
end

M.loader = {
  target = "Config/Env.cs",
  style = "C# .NET 10: a static `Env` class with `Load(IConfiguration)` that reads a .env file via DotNetEnv (or a manual parse) then IConfiguration over env vars. Typed properties with dev defaults, Required() that throws InvalidOperationException listing missing keys. Support both `ConnectionStrings__`/`Jwt__Key` (double-underscore) and `DATABASE_URL`/`JWT_SECRET` forms. No static mutable state beyond Init().",
}

return M
