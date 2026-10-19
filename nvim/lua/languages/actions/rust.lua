-- ── Rust actions (cargo) ─────────────────────────────────────────────────────
-- At the crate root (Cargo.toml). Tests run in the editor (langtest: the #[test] under the cursor, the file's module,
-- the crate), debugging with codelldb (langdebug), rust-analyzer's own commands (expand a macro, open Cargo.toml,
-- explain an error), setup files under `S`.
local actions = require "utils.actions"
local log = require "utils.log"
local run = actions.run
local terminal = require "utils.terminal"

local function cargo(sub)
  return run("cargo", "cargo " .. sub, { "Cargo.toml" })
end

--- cargo with the crate names you type (cargo add serde --features derive)
local function cargo_packages(sub, ask)
  return function()
    require("utils.modal").input({ ask }, { title = "cargo " .. sub, confirm = "Run" }, function(text)
      if text ~= "" then
        cargo(sub .. " " .. text)()
      end
    end)
  end
end

--- A rust-analyzer request on the cursor, its answer in a float (`rust-analyzer/expandMacro`)
local function expand_macro()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "rust_analyzer" })[1]
  if not client then
    return log.warn "Rust: rust-analyzer is not running in this buffer"
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request("rust-analyzer/expandMacro", params, function(err, result)
    if err or not result then
      return log.info "Rust: no macro under the cursor"
    end
    local lines = vim.list_extend({ "// " .. result.name, "" }, vim.split(result.expansion, "\n", { plain = true }))
    vim.lsp.util.open_floating_preview(lines, "rust", { border = require("ui.flat").border(), focusable = true })
  end, 0)
end

--- Opens the Cargo.toml of the crate this file belongs to (rust-analyzer knows it in workspaces)
local function open_cargo_toml()
  local client = vim.lsp.get_clients({ bufnr = 0, name = "rust_analyzer" })[1]
  if not client then
    local found = vim.fs.find("Cargo.toml", { path = vim.fn.expand "%:p:h", upward = true })[1]
    if not found then
      return log.warn "Rust: no Cargo.toml"
    end
    return vim.cmd.edit(vim.fn.fnameescape(found))
  end
  client:request(
    "experimental/openCargoToml",
    { textDocument = vim.lsp.util.make_text_document_params(0) },
    function(_, loc)
      if loc then
        vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true })
      end
    end,
    0
  )
end

--- `rustc --explain` of the error code on the cursor's line (E0382…)
local function explain()
  local code = vim.api.nvim_get_current_line():match "E%d%d%d%d"
  for _, d in ipairs(vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })) do
    code = code or (type(d.code) == "string" and d.code:match "^E%d%d%d%d$" and d.code)
  end
  if not code then
    return log.info "Rust: no error code (E0…) on this line"
  end
  terminal.run("rustc --explain " .. code, vim.fn.expand "%:p:h")
end

local maps = {
  { "r", "cargo run", cargo "run" },
  { "b", "cargo build", cargo "build" },
  { "c", "cargo check", cargo "check" },
  { "v", "cargo clippy", cargo "clippy --all-targets" },
  { "x", "cargo clippy --fix", cargo "clippy --fix --allow-dirty --allow-staged" },
  { "f", "format", actions.format },
  { "a", "cargo add crates", cargo_packages("add", "Crates to add (e.g. serde --features derive)") },
  { "R", "cargo remove crates", cargo_packages("remove", "Crates to remove") },
  { "u", "cargo update", cargo "update" },
  { "o", "cargo doc --open", cargo "doc --open" },
  { "e", "expand macro under cursor", expand_macro },
  { "p", "open Cargo.toml", open_cargo_toml },
  { "E", "explain error code", explain },
}

vim.list_extend(maps, require("langtest").maps())
vim.list_extend(maps, require("langdebug").maps "rust")
vim.list_extend(maps, require("langsetup").maps "rust")
return maps
