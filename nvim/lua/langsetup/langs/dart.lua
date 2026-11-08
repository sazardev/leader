-- Dart / Flutter setup (<leader>dS): analysis_options, .editorconfig, .fvmrc, CI, Dockerfile. Filled from
-- pubspec.yaml (name, sdk constraint) or the folder's name.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "Dart / Flutter" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, "pubspec.yaml") or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local text = read(root .. "/pubspec.yaml") or ""
  local name = text:match "^name:%s*(%S+)" or vim.fs.basename(root)
  local sdk = text:match "sdk:%s*[\"']([^\"']+)[\"']" or ">=3.5.0 <4.0.0"
  local flutter = tostring(text:find "\n%s*flutter:" ~= nil)
  return {
    name = name,
    sdk = sdk,
    flutter = flutter,
  }
end

M.topics = {
  { id = "analysis", key = "a", label = "analysis_options.yaml", default = "standard", core = true },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "dart", core = true },
  { id = "fvm", key = "v", label = ".fvmrc (Flutter version)", default = "pinned", core = true },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
  { id = "docker", key = "d", label = "Dockerfile (Dart server)", default = "server" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "dart" },
}

function M.hint(topic)
  if topic.id == "fvm" then
    return "run `fvm use` once (or `flutter pub get`); .fvmrc pins the SDK"
  elseif topic.id == "analysis" then
    return "lints via `flutter analyze` or `dart analyze`"
  end
end

return M
