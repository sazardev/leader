-- Swift env preset (SwiftPM server / Vapor-style)
local M = { id = "swift", label = "Swift", markers = { "Package.swift" } }

---@param root string
---@return table<string,string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/Package.swift") or ""
  local name = text:match 'Package%(%s*name:%s*"([^"]+)"' or vim.fs.basename(root)
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (Swift)
# Copy to .env and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
APP_NAME=%s
APP_ENV=development   # development | qa | staging | production
APP_DEBUG=true
HOST=0.0.0.0
PORT=8080
LOG_LEVEL=info

# --- Database -------------------------------------------------------------
DATABASE_URL=postgres://app:changeme@localhost:5432/%s_dev
DB_HOST=localhost
DB_PORT=5432
DB_NAME=%s_dev
DB_USER=app
DB_PASSWORD=changeme

# --- Cache ------------------------------------------------------------------
REDIS_URL=redis://localhost:6379/0

# --- Auth -------------------------------------------------------------------
JWT_SECRET=change-me-32-chars-minimum
JWT_EXPIRE_SECONDS=86400

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:5173
S3_BUCKET=%s-dev

# --- Mailer -----------------------------------------------------------------
SMTP_HOST=localhost
SMTP_PORT=1025

# --- Observability ----------------------------------------------------------
SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

]]):format(name, name, name, name, name)
end

M.loader = {
  target = "Sources/App/Config/Env.swift",
  style = "Swift 6: an `Env` struct with `static func load() throws -> Env` that reads a .env file via DotEnv (or a manual parse of .env) then ProcessInfo.processInfo.environment. Typed properties with dev defaults; required keys throw AppError.missingEnv listing the missing names. Export `AppConfig` from Vapor's Config or a plain struct. No force-unwrapping of env outside load().",
}

return M
