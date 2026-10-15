-- ── Dart / Flutter completion: declarations for the project's stack ──────────
-- A blink.cmp source (`dart` only). At the start of a top-level declaration it offers what the package's pubspec.yaml
-- says it uses, named after the file (`snippet_filter_bar.dart` → `SnippetFilterBar`, `cart_provider.dart` → `cart`):
--   consumer / consumerstateful    ConsumerWidget, ConsumerStatefulWidget + its State   (flutter_riverpod, hooks_riverpod)
--   riverpod / riverpodnotifier    `@riverpod` function provider, `@riverpod` Notifier class   (riverpod_annotation)
--   freezed / freezedunion         `@freezed` data class (with fromJson when json_serializable is there), sealed union
--   stateless / stateful           StatelessWidget, StatefulWidget + its State   (any Flutter package)
-- Accepting one also adds the import and `part` lines it needs and the file lacks (utils/dartheader.lua, applied by
-- `Source:execute` once the snippet is in), so a
-- generator's `part 'x.g.dart';` is never forgotten. Nothing resident: pubspec.yaml is read once per change.
local header = require "utils.dartheader"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

--- `snippet_filter_bar` → `SnippetFilterBar`
---@param base string
---@return string
function M.pascal(base)
  return (base:gsub("^%l", string.upper):gsub("_(%w)", string.upper))
end

--- `cart_provider` → `cart`: the provider's name, without the suffix riverpod_generator adds back (`cartProvider`)
---@param base string
---@return string
function M.provider_name(base)
  local name = base:gsub("_providers?$", "")
  return (name:gsub("_(%w)", string.upper))
end

--- `cart_notifier` / `cart_provider` → `Cart`: the Notifier class (its provider is `cartProvider`)
---@param base string
---@return string
function M.notifier_name(base)
  return M.pascal((base:gsub("_providers?$", ""):gsub("_notifier$", ""):gsub("_controller$", "")))
end

-- snippet bodies: `\$` is a literal dollar (the generated `_$Name` mixins), `${1:Name}` mirrors repeat the name
local RECIPES = {
  {
    label = "consumer",
    detail = "ConsumerWidget",
    when = "consumer",
    body = function(n)
      return ("class ${1:%s} extends ConsumerWidget {\n  const ${1:%s}({super.key});\n\n  @override\n  Widget build(BuildContext context, WidgetRef ref) {\n    return ${0:const Placeholder()};\n  }\n}"):format(
        n.widget,
        n.widget
      )
    end,
  },
  {
    label = "consumerstateful",
    detail = "ConsumerStatefulWidget + State",
    when = "consumer",
    body = function(n)
      return ("class ${1:%s} extends ConsumerStatefulWidget {\n  const ${1:%s}({super.key});\n\n  @override\n  ConsumerState<${1:%s}> createState() => _${1:%s}State();\n}\n\nclass _${1:%s}State extends ConsumerState<${1:%s}> {\n  @override\n  Widget build(BuildContext context) {\n    return ${0:const Placeholder()};\n  }\n}"):format(
        n.widget,
        n.widget,
        n.widget,
        n.widget,
        n.widget,
        n.widget
      )
    end,
  },
  {
    label = "riverpod",
    detail = "@riverpod function provider",
    when = "riverpod",
    body = function(n)
      -- one placeholder for the whole return type: Neovim's snippet parser rejects nested ones (`${1:Future<${2:T}>}`)
      return ("@riverpod\n${1:Future<Object>} ${2:%s}(Ref ref) ${3:async }{\n  $0\n}"):format(n.provider)
    end,
  },
  {
    label = "riverpodnotifier",
    detail = "@riverpod Notifier class",
    when = "riverpod",
    body = function(n)
      return ("@riverpod\nclass ${1:%s} extends _\\$${1:%s} {\n  @override\n  ${2:Object} build() {\n    $0\n  }\n}"):format(
        n.notifier,
        n.notifier
      )
    end,
  },
  {
    label = "freezed",
    detail = "@freezed data class",
    when = "freezed",
    body = function(n, stack)
      local json = stack.json_serializable
          and ("\n\n  factory ${1:%s}.fromJson(Map<String, Object?> json) => _\\$${1:%s}FromJson(json);"):format(
            n.widget,
            n.widget
          )
        or ""
      return ("@freezed\nabstract class ${1:%s} with _\\$${1:%s} {\n  const factory ${1:%s}({\n    ${0:required String id,}\n  }) = _${1:%s};%s\n}"):format(
        n.widget,
        n.widget,
        n.widget,
        n.widget,
        json
      )
    end,
  },
  {
    label = "freezedunion",
    detail = "@freezed sealed union",
    when = "freezed",
    body = function(n)
      return ("@freezed\nsealed class ${1:%s} with _\\$${1:%s} {\n  const factory ${1:%s}.${2:loading}() = ${3:Loading};\n  const factory ${1:%s}.${4:data}(${5:Object value}) = ${6:Data};\n  const factory ${1:%s}.${7:error}(${8:Object error}) = ${9:Error};\n}"):format(
        n.widget,
        n.widget,
        n.widget,
        n.widget,
        n.widget
      )
    end,
  },
  {
    label = "stateless",
    detail = "StatelessWidget",
    when = "flutter",
    body = function(n)
      return ("class ${1:%s} extends StatelessWidget {\n  const ${1:%s}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return ${0:const Placeholder()};\n  }\n}"):format(
        n.widget,
        n.widget
      )
    end,
  },
  {
    label = "stateful",
    detail = "StatefulWidget + State",
    when = "flutter",
    body = function(n)
      return ("class ${1:%s} extends StatefulWidget {\n  const ${1:%s}({super.key});\n\n  @override\n  State<${1:%s}> createState() => _${1:%s}State();\n}\n\nclass _${1:%s}State extends State<${1:%s}> {\n  @override\n  Widget build(BuildContext context) {\n    return ${0:const Placeholder()};\n  }\n}"):format(
        n.widget,
        n.widget,
        n.widget,
        n.widget,
        n.widget,
        n.widget
      )
    end,
  },
}

--- The text a snippet becomes once its placeholders take their default value (what the header is computed from)
---@param snippet string
---@return string
local function expanded(snippet)
  local text = snippet:gsub("\\%$", "\1")
  text = text:gsub("%${%d+:([^{}]*)}", "%1")
  return (text:gsub("%$%d+", ""):gsub("\1", "$"))
end

---@class DartSmartOpts
---@field before string what is typed on the line before the cursor
---@field row integer 0-based
---@field col integer 0-based, the cursor
---@field file string[] the whole file
---@field base string the file name without `.dart`
---@field stack DartStack

--- Items for a cursor at the start of a top-level declaration (`fre|` at column 0); none elsewhere
---@param o DartSmartOpts
---@return table[]
function M.items(o)
  local frag = o.before:match "^(%l*)$"
  if not frag or frag == "" then
    return {}
  end
  local names = { widget = M.pascal(o.base), provider = M.provider_name(o.base), notifier = M.notifier_name(o.base) }
  local items = {}
  for _, r in ipairs(RECIPES) do
    if o.stack[r.when] then
      local body = r.body(names, o.stack)
      items[#items + 1] = {
        label = r.label,
        labelDetails = { description = r.detail },
        kind = KIND.Snippet,
        insertTextFormat = FORMAT.Snippet,
        filterText = r.label,
        sortText = ("%03d"):format(#items),
        textEdit = {
          newText = body,
          range = { start = { line = o.row, character = 0 }, ["end"] = { line = o.row, character = o.col } },
        },
        -- the import and `part` lines go in AFTER the snippet (Source:execute): as additionalTextEdits, blink applies them
        -- after expanding it, and in a new file an insert at the typed line lands below the class
        data = { header = header.edits(o.file, o.base, vim.split(expanded(body), "\n", { plain = true })) },
        documentation = { kind = "markdown", value = "```dart\n" .. expanded(body) .. "\n```" },
      }
    end
  end
  return items
end

---@type table<string, { stamp: string, stack: DartStack }>
local stacks = {}

--- The stack of the package a buffer belongs to (pubspec.yaml re-read only when it changes)
---@param buf integer
---@return DartStack?
function M.stack_of(buf)
  local root = vim.fs.root(buf, "pubspec.yaml")
  if not root then
    return nil
  end
  local path = root .. "/pubspec.yaml"
  local stat = vim.uv.fs_stat(path)
  local stamp = stat and (stat.mtime.sec .. ":" .. stat.size) or ""
  local cached = stacks[root]
  if cached and cached.stamp == stamp then
    return cached.stack
  end
  local f = io.open(path, "r")
  local text = f and f:read "*a" or ""
  if f then
    f:close()
  end
  stacks[root] = { stamp = stamp, stack = header.stack(text) }
  return stacks[root].stack
end

-- ── blink.cmp source ────────────────────────────────────────────────────────
local Source = {}
Source.__index = Source

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "dart"
end

--- Inserts the snippet (blink's own way), then the missing import and `part` lines above it: they all sit at or above
--- the line that was typed, so the snippet only moves down (its placeholders are extmarks and follow)
function Source:execute(ctx, item, callback, default_implementation)
  default_implementation()
  M.apply_header(ctx.bufnr, item.data and item.data.header or {})
  callback()
end

--- Applies `dartheader.edits` insertions to a buffer (bottom up, as they come)
---@param buf integer
---@param edits { row: integer, lines: string[] }[]
function M.apply_header(buf, edits)
  for _, e in ipairs(edits) do
    vim.api.nvim_buf_set_lines(buf, e.row, e.row, false, e.lines)
  end
end

function Source:get_completions(ctx, callback)
  local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local stack = M.stack_of(ctx.bufnr)
  local items = {}
  if stack then
    items = M.items {
      before = ctx.line:sub(1, col),
      row = row,
      col = col,
      file = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false),
      base = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.bufnr), ":t:r"),
      stack = stack,
    }
  end
  callback { is_incomplete_forward = false, is_incomplete_backward = false, items = items }
end

return M
