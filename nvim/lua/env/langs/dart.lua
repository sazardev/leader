-- Dart / Flutter env preset (flutter_dotenv)
local M = { id = "dart", label = "Dart / Flutter", markers = { "pubspec.yaml" } }

---@param root string
---@return table<string,string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/pubspec.yaml") or ""
  local name = text:match "^name:%s*(%S+)" or vim.fs.basename(root)
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (Dart / Flutter)
# Copy to .env and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
APP_NAME=%s
APP_ENV=development   # development | qa | staging | production
APP_DEBUG=true
LOG_LEVEL=debug

# --- API --------------------------------------------------------------------
API_BASE_URL=http://localhost:8080
API_TIMEOUT_MS=15000
WS_URL=ws://localhost:8080/ws

# --- Auth -------------------------------------------------------------------
JWT_SECRET=change-me-for-local-only
OAUTH_CLIENT_ID=
OAUTH_CLIENT_SECRET=

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:3000
S3_BUCKET=%s-dev
ANALYTICS_ENABLED=false
SENTRY_DSN=

# --- Firebase / push (optional) ---------------------------------------------
FIREBASE_API_KEY=
FIREBASE_PROJECT_ID=

]]):format(name, name, name)
end

M.loader = {
  target = "lib/config/env.dart",
  style = "Dart 3: an `Env` class with `static Future<void> load()` using flutter_dotenv (dotenv.load) then String.fromEnvironment / dotenv.env with typed getters and dev defaults. Required keys are checked and a clear StateError lists missing keys. Export `AppEnv` singleton (getIt or plain static). Use const for defaults, never hardcode secrets.",
}

return M
