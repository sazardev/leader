-- Rust env preset
local M = { id = "rust", label = "Rust", markers = { "Cargo.toml" } }

---@param root string
---@return table<string,string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/Cargo.toml") or ""
  local name = text:match '%[package%][^%[]-\nname%s*=%s*"([^"]+)"' or vim.fs.basename(root)
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (Rust)
# Copy to .env and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
APP_NAME=%s
APP_ENV=development   # development | qa | staging | production
APP_DEBUG=true
HOST=0.0.0.0
PORT=8080
RUST_LOG=info
LOG_LEVEL=info

# --- Database -------------------------------------------------------------
DATABASE_URL=postgres://app:changeme@localhost:5432/%s_dev
DB_HOST=localhost
DB_PORT=5432
DB_NAME=%s_dev
DB_USER=app
DB_PASSWORD=changeme

# --- Cache / Queue ----------------------------------------------------------
REDIS_URL=redis://localhost:6379/0

# --- Auth -----------------------------------------------------------------
JWT_SECRET=change-me-32-chars-minimum
JWT_EXPIRE_SECONDS=86400
API_KEY=

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:5173
S3_BUCKET=%s-dev
S3_ENDPOINT=http://localhost:9000

# --- Mailer -----------------------------------------------------------------
SMTP_HOST=localhost
SMTP_PORT=1025

# --- Observability ----------------------------------------------------------
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
SENTRY_DSN=

]]):format(name, name, name, name, name)
end

M.loader = {
  target = "src/config.rs",
  style = "Rust 2021+: a `Config` struct with `from_env()` that reads dotenvy (dotenvy::dotenv) then std::env::var. Required keys return a clear Err listing missing keys (use anyhow/thiserror). Dev defaults for PORT/HOST/LOG_LEVEL. Export `AppConfig` with typed fields (String/bool/u16) and a `load()` that panics with a readable message in main. No lazy_static global beyond OnceLock after load.",
}

return M
