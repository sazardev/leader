-- ── Imports of a file, per language (pure, no treesitter) ────────────────────
-- Returns `{ line, spec }` for each import. It is regex over the text: faster than parsing hundreds of
-- files and enough to know which layer or library each one points to.
local M = {}

---@param lines string[]
---@param pattern string
---@param out table[]
local function each(lines, pattern, out)
  for i, l in ipairs(lines) do
    local spec = l:match(pattern)
    if spec then
      out[#out + 1] = { line = i, spec = spec }
    end
  end
end

---@param lines string[]
---@return table[]
local function go(lines)
  local out, in_block = {}, false
  for i, l in ipairs(lines) do
    if in_block then
      if l:match "^%s*%)" then
        in_block = false
      else
        local spec = l:match '"([^"]+)"'
        if spec then
          out[#out + 1] = { line = i, spec = spec }
        end
      end
    elseif l:match "^%s*import%s*%(" then
      in_block = true
    else
      local spec = l:match '^%s*import%s+[%w_%.]*%s*"([^"]+)"'
      if spec then
        out[#out + 1] = { line = i, spec = spec }
      end
    end
  end
  return out
end

local BY_EXT = {
  go = go,
  ts = function(l)
    local out = {}
    each(l, "from%s+[\"']([^\"']+)[\"']", out)
    each(l, "require%(%s*[\"']([^\"']+)[\"']", out)
    each(l, "^%s*import%s+[\"']([^\"']+)[\"']", out)
    return out
  end,
  py = function(l)
    local out = {}
    each(l, "^%s*from%s+([%w_%.]+)%s+import", out)
    each(l, "^%s*import%s+([%w_%.]+)", out)
    return out
  end,
  java = function(l)
    local out = {}
    each(l, "^%s*import%s+static%s+([%w_%.]+)", out)
    local plain = {}
    each(l, "^%s*import%s+([%w_%.]+)", plain)
    for _, imp in ipairs(plain) do
      if imp.spec ~= "static" then
        out[#out + 1] = imp
      end
    end
    return out
  end,
  rs = function(l)
    local out = {}
    each(l, "^%s*pub%s+use%s+([%w_:]+)", out)
    each(l, "^%s*use%s+([%w_:]+)", out)
    return out
  end,
  cs = function(l)
    local out = {}
    each(l, "^%s*using%s+([%w_%.]+)%s*;", out)
    return out
  end,
  php = function(l)
    local out = {}
    each(l, "^%s*use%s+([%w_\\]+)", out)
    return out
  end,
  dart = function(l)
    local out = {}
    each(l, "^%s*import%s+[\"']([^\"']+)[\"']", out)
    return out
  end,
}
BY_EXT.tsx, BY_EXT.js, BY_EXT.jsx, BY_EXT.mjs, BY_EXT.cjs = BY_EXT.ts, BY_EXT.ts, BY_EXT.ts, BY_EXT.ts, BY_EXT.ts
BY_EXT.kt, BY_EXT.scala = BY_EXT.java, BY_EXT.java

--- Is it an extension we know how to read?
---@param ext string
---@return boolean
function M.supports(ext)
  return BY_EXT[ext] ~= nil
end

---@param lines string[]
---@param ext string without the dot ("go", "ts"...)
---@return { line: integer, spec: string }[]
function M.extract(lines, ext)
  local fn = BY_EXT[ext]
  return fn and fn(lines) or {}
end

-- Libraries and frameworks that must NOT appear in domain/application: they couple the logic to the transport,
-- the database or the framework. They are compared as a substring of the import.
M.FRAMEWORKS = {
  go = {
    "database/sql",
    "net/http",
    "gorm.io",
    "gin-gonic",
    "labstack/echo",
    "go-chi",
    "jackc/pgx",
    "go-redis",
    "mongo-driver",
    "aws/aws-sdk",
    "google.golang.org/grpc",
    "gofiber",
    "jmoiron/sqlx",
  },
  ts = {
    "express",
    "@nestjs/",
    "typeorm",
    "@prisma/client",
    "mongoose",
    "axios",
    "fastify",
    "sequelize",
    "knex",
    "pg",
    "mysql2",
    "redis",
    "ioredis",
    "next/",
    "react",
  },
  py = {
    "sqlalchemy",
    "django",
    "flask",
    "fastapi",
    "requests",
    "psycopg",
    "pymongo",
    "redis",
    "boto3",
    "httpx",
    "sqlmodel",
    "peewee",
  },
  java = {
    "javax.persistence",
    "jakarta.persistence",
    "org.springframework",
    "org.hibernate",
    "javax.servlet",
    "jakarta.servlet",
    "com.fasterxml.jackson",
    "org.apache.http",
  },
  rs = { "sqlx", "diesel", "axum", "actix", "reqwest", "tokio_postgres", "rocket", "redis", "mongodb" },
  cs = { "Microsoft.EntityFrameworkCore", "System.Data", "Microsoft.AspNetCore", "Dapper", "System.Net.Http" },
  php = { "Illuminate\\", "Doctrine\\", "Symfony\\" },
  dart = { "package:flutter", "package:http", "package:dio", "package:sqflite" },
}
M.FRAMEWORKS.tsx, M.FRAMEWORKS.js, M.FRAMEWORKS.jsx, M.FRAMEWORKS.mjs, M.FRAMEWORKS.cjs =
  M.FRAMEWORKS.ts, M.FRAMEWORKS.ts, M.FRAMEWORKS.ts, M.FRAMEWORKS.ts, M.FRAMEWORKS.ts
M.FRAMEWORKS.kt, M.FRAMEWORKS.scala = M.FRAMEWORKS.java, M.FRAMEWORKS.java

--- Does `fw` appear in `spec` as a whole name (between separators) and not as part of another? `express` is the
--- framework in "express" or "x/express/y", but not in "./expressions".
---@param spec string
---@param fw string
---@return boolean
local function matches(spec, fw)
  if fw:find "[/\\:]$" then
    return spec:find(fw, 1, true) ~= nil
  end
  local start = 1
  while true do
    local s, e = spec:find(fw, start, true)
    if not s then
      return false
    end
    local before, after = spec:sub(s - 1, s - 1), spec:sub(e + 1, e + 1)
    if (before == "" or before:find "[/%.:@\\]") and (after == "" or after:find "[/%.:@\\%-]") then
      return true
    end
    start = e + 1
  end
end

--- The framework library an import points to, if it is one
---@param spec string
---@param ext string
---@return string?
function M.framework(spec, ext)
  for _, fw in ipairs(M.FRAMEWORKS[ext] or {}) do
    if matches(spec, fw) then
      return fw
    end
  end
  return nil
end

return M
