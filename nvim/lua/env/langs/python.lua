-- Python env preset
local M = { id = "python", label = "Python", markers = { "pyproject.toml", "requirements.txt", "setup.py" } }

---@param root string
---@return table<string,string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/pyproject.toml") or ""
  local name = text:match '%[project%][^%[]-\nname%s*=%s*"([^"]+)"' or vim.fs.basename(root)
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (Python)
# Copy to .env.local and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
APP_NAME=%s
APP_ENV=development   # development | qa | staging | production
APP_DEBUG=true
DEBUG=true
HOST=0.0.0.0
PORT=8000
LOG_LEVEL=INFO

# --- Database -------------------------------------------------------------
DATABASE_URL=postgres://app:changeme@localhost:5432/%s_dev
DB_HOST=localhost
DB_PORT=5432
DB_NAME=%s_dev
DB_USER=app
DB_PASSWORD=changeme
SQLALCHEMY_DATABASE_URL=${DATABASE_URL}  # optional alias

# --- Cache / Queue ----------------------------------------------------------
REDIS_URL=redis://localhost:6379/0
REDIS_PASSWORD=
CELERY_BROKER_URL=${REDIS_URL}
CELERY_RESULT_BACKEND=${REDIS_URL}

# --- Auth -----------------------------------------------------------------
SECRET_KEY=change-me-50-chars-minimum
JWT_SECRET=change-me-32-chars-minimum
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=1440
API_KEY=

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:5173,http://localhost:3000
S3_BUCKET=%s-dev
S3_ENDPOINT_URL=http://localhost:9000
S3_ACCESS_KEY_ID=minio
S3_SECRET_ACCESS_KEY=minio-secret

# --- Mailer -----------------------------------------------------------------
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_USER=
SMTP_PASSWORD=
EMAIL_FROM=no-reply@%s.local

# --- Observability ----------------------------------------------------------
SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

]]):format(name, name, name, name, name, name)
end

M.loader = {
  target = "src/config/env.py",
  style = "Python 3.12+: use pydantic-settings (BaseSettings) if available else a typed dataclass. Load .env via python-dotenv (load_dotenv) or pydantic's env_file. Fields with dev defaults, required fields fail with a clear message listing missing keys. Export `settings = get_settings()` (lru_cache) and `Config` class. Do not read os.environ directly inside business logic.",
}

return M
