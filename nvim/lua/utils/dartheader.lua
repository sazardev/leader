-- ── The import and `part` lines Dart code needs ──────────────────────────────
-- Pure. Code that uses a generator or a framework needs lines at the top of its file: freezed and json_serializable
-- their annotation import and `part 'x.freezed.dart';` / `part 'x.g.dart';`, Riverpod's `@riverpod` its annotation and
-- `part 'x.g.dart';`, a Consumer widget flutter_riverpod and Flutter. Shared by `<leader>at` (agent/convert, added on
-- accept) and the Dart completion (utils/dartsmart, as the item's additional edits): what is missing, never twice.
local M = {}

local MATERIAL = "import 'package:flutter/material.dart';"

---@class DartStack
---@field flutter boolean
---@field freezed boolean
---@field json_serializable boolean
---@field drift boolean
---@field riverpod boolean code generation for providers (riverpod_annotation)
---@field consumer boolean Consumer widgets (flutter_riverpod or hooks_riverpod)

--- The generators and frameworks a Dart package uses, from its pubspec.yaml
---@param pubspec string?
---@return DartStack
function M.stack(pubspec)
  pubspec = "\n" .. (pubspec or "")
  local function has(name)
    return pubspec:match("\n%s+" .. name .. "%s*:") ~= nil
  end
  return {
    flutter = has "flutter",
    freezed = has "freezed",
    json_serializable = has "json_serializable",
    drift = has "drift",
    riverpod = has "riverpod_annotation",
    consumer = has "flutter_riverpod" or has "hooks_riverpod",
  }
end

--- What a piece of code needs: imports in order, parts (`freezed` before `g`)
---@param text string
---@param base string the file name without `.dart`
---@return string[] imports, string[] parts
local function needs(text, base)
  local imports, parts, seen = {}, {}, {}
  local function import(line)
    if not seen[line] then
      seen[line] = true
      imports[#imports + 1] = line
    end
  end
  local freezed_part, g_part = false, false

  if text:find("@freezed", 1, true) then
    import "import 'package:freezed_annotation/freezed_annotation.dart';"
    freezed_part = true
    g_part = g_part or text:find("FromJson(", 1, true) ~= nil
  elseif text:find("@JsonSerializable", 1, true) then
    import "import 'package:json_annotation/json_annotation.dart';"
    g_part = true
  end
  if text:find("@riverpod", 1, true) or text:find("@Riverpod(", 1, true) then
    import "import 'package:riverpod_annotation/riverpod_annotation.dart';"
    g_part = true
  end
  if text:find("extends Consumer", 1, true) then
    import "import 'package:flutter_riverpod/flutter_riverpod.dart';"
  end
  if text:find("Widget build(", 1, true) then
    import(MATERIAL)
  end
  if text:find("extends Table", 1, true) then
    import "import 'package:drift/drift.dart';"
  end

  if freezed_part then
    parts[#parts + 1] = ("part '%s.freezed.dart';"):format(base)
  end
  if g_part then
    parts[#parts + 1] = ("part '%s.g.dart';"):format(base)
  end
  return imports, parts
end

--- The missing lines as insertions applied from the bottom up ({ row = 0-based line to insert before, lines })
---@param file string[] the whole file
---@param base string the file name without `.dart` (`user` for user.dart)
---@param code string[] the code that needs them
---@return { row: integer, lines: string[] }[]
function M.edits(file, base, code)
  local imports, parts = needs(table.concat(code, "\n"), base)

  local present, last_import, last_part, library, flutter = {}, nil, nil, nil, false
  for i, line in ipairs(file) do
    present[vim.trim(line)] = true
    if line:match "^import%s" then
      last_import = i
      -- any Flutter library already brings Widget and BuildContext (widgets, material, cupertino)
      flutter = flutter or line:find("package:flutter/", 1, true) ~= nil
    elseif line:match "^part%s+['\"]" then
      last_part = i
    elseif line:match "^library[%s;]" then
      library = i
    end
  end
  imports = vim.tbl_filter(function(l)
    return not present[l] and not (l == MATERIAL and flutter)
  end, imports)
  parts = vim.tbl_filter(function(l)
    return not present[l]
  end, parts)

  local edits = {}
  if #parts > 0 then
    if last_part then
      edits[#edits + 1] = { row = last_part, lines = parts }
    elseif last_import then
      edits[#edits + 1] = { row = last_import, lines = vim.list_extend({ "" }, parts) }
    else
      -- no imports or parts yet: after the new imports, at the top
      local top = vim.list_extend(vim.list_extend({}, imports), { "" })
      imports = {}
      edits[#edits + 1] = { row = library or 0, lines = vim.list_extend(vim.list_extend(top, parts), { "" }) }
    end
  end
  if #imports > 0 then
    if last_import then
      edits[#edits + 1] = { row = last_import, lines = imports }
    else
      edits[#edits + 1] = { row = library or 0, lines = vim.list_extend(vim.list_extend({}, imports), { "" }) }
    end
  end
  -- bottom up; at the same row the parts go in first, so the imports inserted after them end up above
  for i, e in ipairs(edits) do
    e.seq = i
  end
  table.sort(edits, function(a, b)
    return a.row > b.row or (a.row == b.row and a.seq < b.seq)
  end)
  for _, e in ipairs(edits) do
    e.seq = nil
  end
  return edits
end

return M
