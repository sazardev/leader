-- ── Modismos de DDD por lenguaje ─────────────────────────────────────────────
-- UNA línea por lenguaje, y solo la del lenguaje en curso va al modelo: así el consejo es específico
-- (constructores, errores, inyección) sin pagar tokens por los demás.
local M = {}

local GO =
  "Go: constructor New<T> that validates invariants and returns (*T, error); unexported fields behind methods; small interfaces defined where they are consumed; wrap errors with %w; inject dependencies as interface-typed constructor params; context.Context first param outside the domain."
local TS =
  "TypeScript: private constructor + static create() validating invariants; readonly value objects; interfaces as ports; constructor injection; no ORM/framework decorators in the domain; typed DomainError instead of throwing strings."
local PY =
  "Python: @dataclass(frozen=True) for value objects; ABC/Protocol for ports; constructor injection; type hints; no ORM or web framework imports in the domain; domain exceptions."
local JAVA =
  "Java/Kotlin: final fields and factory methods; interfaces as ports; constructor injection; no JPA/Spring annotations in domain classes (map from a separate persistence model); domain exceptions."
local RS =
  "Rust: newtype value objects with fallible constructors; traits as ports; Result<T, DomainError>; no serde/sqlx/axum types in the domain; dependencies passed as generics or Arc<dyn Port>."
local CS =
  "C#: sealed classes, private setters and factory methods; interfaces as ports; constructor injection; no EF Core attributes in the domain; domain exceptions."

M.BY_EXT = {
  go = GO,
  ts = TS,
  tsx = TS,
  js = TS,
  jsx = TS,
  mjs = TS,
  py = PY,
  java = JAVA,
  kt = JAVA,
  scala = JAVA,
  rs = RS,
  cs = CS,
}

---@param ext string
---@return string?
function M.for_ext(ext)
  return M.BY_EXT[ext]
end

return M
