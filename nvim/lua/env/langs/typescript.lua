-- TypeScript / JavaScript env preset
local M = { id = "typescript", label = "TypeScript / JavaScript", markers = { "package.json" } }

local function read(path)
  return require("utils.project").read(path)
end

---@param root string
---@return table<string,string>
function M.vars(root)
  local ok, pkg = pcall(vim.json.decode, read(root .. "/package.json") or "")
  pkg = ok and type(pkg) == "table" and pkg or {}
  local name = (type(pkg.name) == "string" and pkg.name) or vim.fs.basename(root)
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (TypeScript)
# Copy to .env and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
APP_NAME=%s
APP_ENV=development   # development | qa | staging | production
APP_DEBUG=true
PORT=3000
HOST=0.0.0.0
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
REDIS_PASSWORD=

# --- Auth -----------------------------------------------------------------
JWT_SECRET=change-me-32-chars-minimum
JWT_EXPIRE=24h
SESSION_SECRET=change-me
NEXTAUTH_SECRET=change-me-nextauth
NEXTAUTH_URL=http://localhost:3000

# --- Public (Vite / Next) ---------------------------------------------------
VITE_API_BASE_URL=http://localhost:4000
NEXT_PUBLIC_API_BASE_URL=http://localhost:4000

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:5173
S3_BUCKET=%s-dev
S3_REGION=us-east-1
S3_ACCESS_KEY=
S3_SECRET_KEY=

# --- Mailer -----------------------------------------------------------------
SMTP_HOST=localhost
SMTP_PORT=1025

# --- Observability ----------------------------------------------------------
SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

]]):format(name, name, name, name, name)
end

M.loader = {
  target = "src/config/env.ts",
  style = "TypeScript (ESM): export a typed `env` object with `process.env` access; use dotenv/config or load via `dotenv`. Validate required keys with zod (or plain checks) and fail with a clear message listing missing keys. Export `config` with typed fields and sensible dev defaults (PORT 3000, LOG_LEVEL info). Do not use non-null assertions hidden inside business logic.",
}

return M
