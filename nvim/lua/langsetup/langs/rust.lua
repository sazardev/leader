-- Rust setup (<leader>rS): rustfmt, rust-toolchain, clippy lints, cargo-deny, Docker, CI, .editorconfig. Filled from
-- Cargo.toml (package name, edition).
local M = { name = "Rust" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, "Cargo.toml") or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local text = require("utils.project").read(root .. "/Cargo.toml") or ""
  local name = text:match '%[package%][^%[]-\nname%s*=%s*"([^"]+)"' or vim.fs.basename(root)
  return {
    name = name,
    binary = name,
    edition = text:match 'edition%s*=%s*"(%d+)"' or "2021",
  }
end

M.topics = {
  {
    id = "rustfmt",
    key = "f",
    label = "rustfmt config",
    default = "standard",
    core = true,
    alts = { ".rustfmt.toml" },
  },
  { id = "toolchain", key = "t", label = "rust-toolchain", default = "stable", core = true },
  { id = "clippy", key = "l", label = "clippy config", default = "standard", alts = { ".clippy.toml" } },
  { id = "deny", key = "y", label = "cargo-deny (licenses, advisories)", default = "standard" },
  { id = "docker", key = "d", label = "Dockerfile", default = "debian" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "rust" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "rust", core = true },
}

function M.hint(topic)
  if topic.id == "deny" then
    return "cargo install cargo-deny, then `cargo deny check`"
  end
end

return M
