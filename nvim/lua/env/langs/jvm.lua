-- Java / Kotlin (JVM) env preset (Spring-style)
local M = {
  id = "jvm",
  label = "Java / Kotlin",
  markers = { "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle" },
}

---@param root string
---@return table<string,string>
function M.vars(root)
  local name = vim.fs.basename(root)
  -- try gradle / pom name
  local gradle = require("utils.project").read(root .. "/build.gradle.kts")
    or require("utils.project").read(root .. "/build.gradle")
    or ""
  local pom = require("utils.project").read(root .. "/pom.xml") or ""
  name = gradle:match 'rootProject.name%s*=%s*"([^"]+)"' or pom:match "<artifactId>([^<]+)</artifactId>" or name
  return { name = name }
end

---@param v table<string,string>
---@return string
function M.template(v)
  local name = v.name or "app"
  return ([[
# .env.example — committed template for %s (Java / Kotlin)
# Copy to .env and fill real values. Never commit .env itself.
# Leader: <leader>E creates this file; check with <leader>Ec
APP_NAME=%s
APP_ENV=development   # development | qa | staging | production
SPRING_PROFILES_ACTIVE=dev
APP_DEBUG=true
SERVER_PORT=8080
SERVER_ADDRESS=0.0.0.0
LOG_LEVEL=INFO

# --- Database -------------------------------------------------------------
DATABASE_URL=jdbc:postgresql://localhost:5432/%s_dev
DB_HOST=localhost
DB_PORT=5432
DB_NAME=%s_dev
DB_USER=app
DB_PASSWORD=changeme
SPRING_DATASOURCE_URL=${DATABASE_URL}
SPRING_DATASOURCE_USERNAME=${DB_USER}
SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}

# --- Cache ------------------------------------------------------------------
REDIS_URL=redis://localhost:6379/0
SPRING_DATA_REDIS_URL=${REDIS_URL}

# --- Auth -------------------------------------------------------------------
JWT_SECRET=change-me-32-chars-minimum
JWT_EXPIRATION=86400
API_KEY=

# --- External ---------------------------------------------------------------
CORS_ORIGINS=http://localhost:5173
S3_BUCKET=%s-dev
S3_ENDPOINT=http://localhost:9000

# --- Mailer -----------------------------------------------------------------
SPRING_MAIL_HOST=localhost
SPRING_MAIL_PORT=1025

# --- Observability ----------------------------------------------------------
SENTRY_DSN=
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

]]):format(name, name, name, name, name)
end

M.loader = {
  target = "src/main/java/config/EnvConfig.java",
  style = "Java 21 / Kotlin: a `@ConfigurationProperties` class (Spring) with typed fields and dev defaults, or a plain `Env` record with `static Env fromEnv()` reading System.getenv() plus a .env parse. Validate required keys and throw IllegalStateException listing missing keys. Export `EnvConfig` bean. No scattered System.getenv() in business logic.",
}

return M
