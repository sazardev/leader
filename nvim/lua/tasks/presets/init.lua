-- ── Makefile presets ─────────────────────────────────────────────────────────
-- `<leader>Rc` creates a Makefile where there is none. Presets are plain Makefiles, one folder per language:
-- `presets/<language>/<preset>.mk`. Drop a file in and it is discovered; its first line is a `# description` comment (it stays in
-- the created Makefile). Every target carries a `## text` so the task picker lists it, and every preset has a `help` target.
local M = {}

--- Folder → what the picker calls it
M.LABELS = {
  c = "C / C++",
  dart = "Dart / Flutter",
  docker = "Docker",
  go = "Go",
  java = "Java",
  kotlin = "Kotlin",
  python = "Python",
  rust = "Rust",
  shell = "Shell",
  typescript = "TypeScript / Node",
}

--- Files in a project root that say which language it is, first match wins
M.MARKERS = {
  { "go.mod", "go" },
  { "Cargo.toml", "rust" },
  { "pubspec.yaml", "dart" },
  { "pom.xml", "java" },
  { "build.gradle.kts", "kotlin" },
  { "build.gradle", "java" },
  { "package.json", "typescript" },
  { "pyproject.toml", "python" },
  { "requirements.txt", "python" },
  { "manage.py", "python" },
  { "CMakeLists.txt", "c" },
  { "docker-compose.yml", "docker" },
  { "compose.yaml", "docker" },
  { "Dockerfile", "docker" },
}

--- Filetype → folder, when the root has no marker
M.FILETYPES = {
  go = "go",
  rust = "rust",
  dart = "dart",
  java = "java",
  kotlin = "kotlin",
  python = "python",
  typescript = "typescript",
  typescriptreact = "typescript",
  javascript = "typescript",
  javascriptreact = "typescript",
  c = "c",
  cpp = "c",
  dockerfile = "docker",
  sh = "shell",
  bash = "shell",
}

---@return string
function M.dir()
  return vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
end

---@class MakePreset
---@field name string   file name without extension
---@field desc string?  the first comment line
---@field path string

---@class MakeLanguage
---@field name string   folder
---@field label string
---@field presets MakePreset[]

---@param path string
---@return string?
local function describe(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local first = f:read "*l"
  f:close()
  return first and first:match "^#%s*(.+)$" or nil
end

--- Every language folder with its presets, by label
---@param dir string? the presets directory (tests point it at their own)
---@return MakeLanguage[]
function M.languages(dir)
  dir = dir or M.dir()
  local out = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "directory" then
      local presets = {}
      for file, fkind in vim.fs.dir(dir .. "/" .. name) do
        if fkind == "file" and file:match "%.mk$" then
          local path = ("%s/%s/%s"):format(dir, name, file)
          presets[#presets + 1] = { name = file:gsub("%.mk$", ""), desc = describe(path), path = path }
        end
      end
      table.sort(presets, function(a, b)
        return a.name < b.name
      end)
      if #presets > 0 then
        out[#out + 1] = { name = name, label = M.LABELS[name] or (name:sub(1, 1):upper() .. name:sub(2)), presets = presets }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.label < b.label
  end)
  return out
end

--- The language a project looks like: its marker files, else the buffer's filetype
---@param root string
---@param ft string?
---@param exists fun(path: string): boolean?
---@return string?
function M.guess(root, ft, exists)
  exists = exists or function(path)
    return vim.uv.fs_stat(path) ~= nil
  end
  for _, m in ipairs(M.MARKERS) do
    if exists(root .. "/" .. m[1]) then
      return m[2]
    end
  end
  return ft and M.FILETYPES[ft] or nil
end

--- The guessed language first, the rest as they were
---@param list MakeLanguage[]
---@param guessed string?
---@return MakeLanguage[]
function M.order(list, guessed)
  local out = {}
  for _, lang in ipairs(list) do
    if lang.name == guessed then
      table.insert(out, 1, lang)
    else
      out[#out + 1] = lang
    end
  end
  return out
end

--- Writes the preset as `<root>/Makefile`. It never overwrites anything
---@param root string
---@param preset MakePreset
---@return string? path, string? reason
function M.write(root, preset)
  local target = root .. "/Makefile"
  if vim.uv.fs_stat(target) then
    return nil, "a Makefile is already there"
  end
  local src = io.open(preset.path, "r")
  if not src then
    return nil, "the preset cannot be read"
  end
  local text = src:read "*a"
  src:close()
  local out, err = io.open(target, "w")
  if not out then
    return nil, err
  end
  out:write(text)
  out:close()
  return target
end

return M
