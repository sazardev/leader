-- ── Acciones de Rust (cargo) ─────────────────────────────────────────────────
local run = require("utils.actions").run

local function cargo(sub)
  return run("cargo", "cargo " .. sub, { "Cargo.toml" })
end

return {
  { "r", "cargo run", cargo "run" },
  { "b", "cargo build", cargo "build" },
  { "m", "cargo test", cargo "test" },
  { "c", "cargo check", cargo "check" },
  { "v", "cargo clippy", cargo "clippy" },
  { "x", "cargo clippy --fix --allow-dirty", cargo "clippy --fix --allow-dirty" },
  { "f", "cargo fmt", cargo "fmt" },
}
