-- Go env preset
local M = { id = "go", label = "Go", markers = { "go.mod", "go.work" } }

---@ Vars read from go.mod (module, binary, Go version) — same source as gosetup
---@param root string
---@return table<string,string>
function M.vars(root)
  local v = require("gosetup.vars").collect(root)
  return { name = v.binary, module = v.module, go = v.go, main = v.main }
end

---@ .env.example for Go
---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (Go)
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
DB_DRIVER=postgres    # postgres | sqlite
DB_HOST=localhost
DB_PORT=5432
DB_NAME=%s_dev
DB_USER=app
DB_PASSWORD=changeme

# --- Cache / Queue ----------------------------------------------------------
REDIS_URL=redis://localhost:6379/0
REDIS_PASSWORD=

# --- Auth -----------------------------------------------------------------
JWT_SECRET=change-me-32-chars-minimum
JWT_EXPIRE=24h
SESSION_SECRET=change-me-too
API_KEY=

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:3000,http://localhost:5173
S3_ENDPOINT=http://localhost:9000
S3_BUCKET=%s-dev
S3_ACCESS_KEY=minio
S3_SECRET_KEY=minio-secret

# --- Mailer / Notifications -------------------------------------------------
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=no-reply@%s.local

# --- Observability ----------------------------------------------------------
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
SENTRY_DSN=

]]):format(name, name, name, name, name, name)
end

M.loader = {
  target = "internal/config/env.go",
  -- hint for the AI prompt: idiomatic Go, no godotenv hard dep, typed struct + Load() from .env
  style = "package config; a typed Config struct; Load() reads the .env file (godotenv or manual parse), validates required vars, returns defaults for dev (PORT 8080, LOG_LEVEL info). Export MustLoad() that panics with a clear message listing missing keys. No global mutable state beyond a package-level var after Load.",
}

return M
