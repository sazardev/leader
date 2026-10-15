-- ── Convert: what the selection is and what it becomes ───────────────────────
-- Pure (no Neovim API): recognises the source (a JSON sample, a SQL CREATE TABLE, a curl command) and says what it turns
-- into in the language of the file it sits in. The action (agent/actions/convert.lua) puts both in the prompt, so the
-- model gets a fixed, explicit recipe instead of guessing what "convert" means.
local M = {}

M.SOURCES = {
  json = "a JSON sample",
  sql = "a SQL CREATE TABLE statement",
  curl = "a curl command",
}

-- what each source becomes per language; `default` covers any other programming language
local GOALS = {
  json = {
    go = "Go structs: one named type per JSON object (nested objects and arrays of objects get their own type, declared after the type that uses them), `json` tags with the exact keys, `,omitempty` where the sample has null; field types inferred from the values (int64 for integers, float64 for decimals, bool, string, time.Time for RFC 3339 strings, a pointer for null, []T for arrays); exported names with Go initialisms (ID, URL, HTTP)",
    typescript = "TypeScript `export interface`s: one per JSON object (nested objects get their own interface), the exact keys, `T | null` where the sample has null, `T[]` for arrays",
    javascript = "JSDoc `@typedef {Object}` blocks with one `@property` per key: one typedef per JSON object (nested objects get their own), `T|null` where the sample has null, `T[]` for arrays; plain JavaScript, no TypeScript syntax",
    python = "Python `@dataclass`es with type hints: one per JSON object (nested ones first), `Optional[T] = None` where the sample has null, `list[T]` for arrays",
    rust = 'Rust structs with `#[derive(Debug, Clone, Serialize, Deserialize)]`: one per JSON object, snake_case fields with `#[serde(rename = "…")]` where the key differs, `Option<T>` where the sample has null, `Vec<T>` for arrays',
    dart = "Dart classes: one per JSON object, final fields, a const constructor with named required parameters, `factory fromJson(Map<String, dynamic>)` and `Map<String, dynamic> toJson()`, nullable types where the sample has null",
    java = "Java records: one per JSON object (nested ones as their own record), `@JsonProperty` where the key is not a valid camelCase name, `List<T>` for arrays",
    kotlin = "Kotlin `@Serializable data class`es: one per JSON object, `@SerialName` where the key differs, nullable types with `= null` where the sample has null, `List<T>` for arrays",
    default = "the idiomatic %s type declarations for this data: one type per JSON object, field types inferred from the values",
  },
  sql = {
    go = "a Go struct per table: exported field names, `db` and `json` tags with the column name, NOT NULL columns as plain types and nullable ones as pointers; types mapped from SQL (integer/serial → int64, numeric/decimal → float64, text/varchar → string, boolean → bool, timestamp/date → time.Time, uuid → string, json/jsonb → json.RawMessage)",
    typescript = "a TypeScript `export interface` per table: camelCase fields, nullable columns as `T | null`, dates as `Date`",
    javascript = "a JSDoc `@typedef {Object}` per table with one `@property` per column, camelCase names, nullable columns as `T|null`; plain JavaScript, no TypeScript syntax",
    python = "a Python `@dataclass` per table with type hints: nullable columns as `Optional[T] = None`, timestamps as `datetime`",
    rust = "a Rust struct per table with `#[derive(Debug, Clone)]`: nullable columns as `Option<T>`, timestamps as `chrono::DateTime<Utc>`",
    default = "the idiomatic %s type for each table: nullable columns as optional types",
  },
  curl = {
    go = "a Go function that sends this request with net/http: `func(ctx context.Context, client *http.Client) (*http.Response, error)` built with http.NewRequestWithContext, the same method, URL, headers and body; secrets from the command (tokens, passwords) become parameters, never literals",
    typescript = "an async TypeScript function that sends this request with `fetch` (same method, URL, headers and body) and returns the Response; secrets from the command become parameters, never literals",
    javascript = "an async JavaScript function that sends this request with `fetch` (same method, URL, headers and body) and returns the Response; secrets from the command become parameters, never literals",
    python = "a Python function that sends this request with `requests` (same method, URL, headers and body, a timeout) and returns the Response; secrets from the command become parameters, never literals",
    default = "a %s function that sends this request with the standard HTTP client (same method, URL, headers and body); secrets from the command become parameters, never literals",
  },
}

-- Dart projects with code generation get their own recipes (detected from pubspec.yaml by `M.dart_stack`): the result is
-- what the project's generators expect, and the import/`part` lines it needs are added on accept (`M.header`), not asked
local DART_STACK = {
  json = {
    freezed = "Dart freezed classes for the project's code generation: one per JSON object (nested objects get their own class, declared after the one that uses them), each `@freezed abstract class Name with _$Name { const factory Name({required T field, …}) = _Name; factory Name.fromJson(Map<String, Object?> json) => _$NameFromJson(json); }`; camelCase fields with `@JsonKey(name: 'key')` where the JSON key differs; a nullable `T?` (not required) where the sample has null; `List<T>` for arrays; `DateTime` for ISO-8601 strings. No import or `part` lines: they are added for you",
    json_serializable = "Dart `@JsonSerializable()` classes for the project's code generation: one per JSON object (nested objects get their own class, declared after the one that uses them), final fields, a const constructor with named required parameters, `factory Name.fromJson(Map<String, dynamic> json) => _$NameFromJson(json);` and `Map<String, dynamic> toJson() => _$NameToJson(this);`; camelCase fields with `@JsonKey(name: 'key')` where the JSON key differs; a nullable `T?` where the sample has null; `List<T>` for arrays; `DateTime` for ISO-8601 strings. No import or `part` lines: they are added for you",
  },
  sql = {
    drift = "drift table classes: one `class Names extends Table` per table with a column getter per column (`IntColumn get id => integer().autoIncrement()();`, `TextColumn`, `BoolColumn`, `DateTimeColumn`, `RealColumn`, camelCase names with `.named('column')` where the SQL name differs, `.nullable()` for nullable columns, `.withDefault(…)` for defaults), `@override Set<Column> get primaryKey => {…};` for a primary key that is not an autoincrement id. No import lines: they are added for you",
  },
}

-- buffer filetype → language name used for goals and prompts (the rest are not code: nothing to convert into)
local LANGUAGES = {
  go = "go",
  typescript = "typescript",
  typescriptreact = "typescript",
  javascript = "javascript",
  javascriptreact = "javascript",
  python = "python",
  rust = "rust",
  dart = "dart",
  java = "java",
  kotlin = "kotlin",
  c = "C",
  cpp = "C++",
  cs = "C#",
  swift = "Swift",
  php = "PHP",
  ruby = "Ruby",
  lua = "Lua",
}

--- What the lines are, or nil when they are none of the known sources
---@param lines string[]
---@return string? kind "json" | "sql" | "curl"
function M.detect(lines)
  local text = table.concat(lines, "\n")
  local first = text:match "^%s*(%S)"
  if first == "{" or first == "[" then
    return "json"
  end
  if text:lower():match "^%s*create%s+table" or text:lower():match "\n%s*create%s+table" then
    return "sql"
  end
  if text:match "^%s*%$?%s*curl%s" then
    return "curl"
  end
end

--- The language a buffer of this filetype converts into, or nil if it is not a programming language
---@param ft string
---@return string?
function M.language(ft)
  return LANGUAGES[ft]
end

--- The code generators a Dart package uses (utils/dartheader.lua `stack`)
M.dart_stack = require("utils.dartheader").stack

--- What a source becomes in a language (in Dart, `stack` picks the project's generators)
---@param kind string
---@param language string from `M.language`
---@param stack? { freezed: boolean, json_serializable: boolean, drift: boolean }
---@return string
function M.goal(kind, language, stack)
  if language == "dart" and stack then
    local recipes = DART_STACK[kind] or {}
    for _, name in ipairs { "freezed", "json_serializable", "drift" } do
      if stack[name] and recipes[name] then
        return recipes[name]
      end
    end
  end
  local goals = GOALS[kind]
  return goals[language] or goals.default:format(language)
end

--- Every key of a JSON sample, nested ones included (nil if the text is not valid JSON)
---@param lines string[]
---@return string[]?
function M.json_keys(lines)
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then
    return nil
  end
  local keys, seen = {}, {}
  local function walk(v)
    if type(v) ~= "table" then
      return
    end
    for k, child in pairs(v) do
      if type(k) == "string" and not seen[k] then
        seen[k] = true
        keys[#keys + 1] = k
      end
      walk(child)
    end
  end
  walk(data)
  table.sort(keys)
  return keys
end

--- `full_name` → `fullName`, `unit-price` → `unitPrice`
---@param key string
---@return string
function M.camel(key)
  local out = key:gsub("[_%-]+(%w)", function(c)
    return c:upper()
  end)
  return out
end

--- Dart fields whose JSON key is not their name get `@JsonKey(name: 'key')` when the model forgot it: the sample says which
--- keys exist, so this is checked by rule instead of trusted (a missing one deserializes as null at run time)
---@param code string[]
---@param keys string[] from `M.json_keys`
---@return string[]
function M.dart_json_keys(code, keys)
  local out = vim.deepcopy(code)
  for _, key in ipairs(keys) do
    local name = M.camel(key)
    if name ~= key then
      for i, line in ipairs(out) do
        -- a field declaration (`required String fullName,`, `final String fullName;`, `String? fullName,`) without an annotation
        local lead, rest = line:match("^(%s*)(.-[%w>?%]]%s+" .. name .. "%s*[,;=)].*)$")
        if lead and not line:find("@JsonKey", 1, true) and not rest:match "^return" and not rest:match "^this" then
          out[i] = ("%s@JsonKey(name: '%s') %s"):format(lead, key, rest)
        end
      end
    end
  end
  return out
end

--- The import and `part` lines converted Dart code needs and the file lacks (utils/dartheader.lua, shared with the Dart
--- completion), as insertions applied from the bottom up
M.header = require("utils.dartheader").edits

--- A blank line between top-level declarations the model glued together (two in Python, as PEP 8 asks): a line at
--- column 0 that follows the end of a block (a closing `}` / `)` at column 0, or in Python an indented line)
---@param lines string[]
---@param ft string
---@return string[]
function M.spaced(lines, ft)
  local python = ft == "python"
  local out = {}
  for i, line in ipairs(lines) do
    local prev = lines[i - 1]
    local starts = line:match "^[%w_@#]" ~= nil
    local ended = prev and (prev:match "^[%)}%]];?%)?;?%s*$" or (python and prev:match "^%s+%S"))
    if starts and ended then
      out[#out + 1] = ""
      if python then
        out[#out + 1] = ""
      end
    end
    out[#out + 1] = line
  end
  return out
end

return M
