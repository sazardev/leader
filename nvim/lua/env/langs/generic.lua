-- Generic fallback env preset (any stack)
local M = { id = "generic", label = "Generic", markers = {} }

---@param root string
---@return table<string,string>
function M.vars(root)
  return { name = vim.fs.basename(root) }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s
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
API_KEY=

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:5173
S3_BUCKET=%s-dev

# --- Observability ----------------------------------------------------------
SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

]]):format(name, name, name, name, name)
end

M.loader = {
  target = "config/env",
  style = "Typed Config struct/class whose Load() reads the .env file and System environment, validates required keys, and returns dev defaults. Export a single MustLoad()/load() that fails with a message listing missing keys. Keep business code free of direct env reads.",
}

return M
