-- ── Language packs: what the installer asks and the settings panel toggles ───
-- The base is always on (cheap, every project has them). A pack is a set of registry languages (lua/languages/) with
-- the commands that say this machine already uses it: the installer's checklist starts with those checked, and with no
-- terminal (or --yes) that is what it installs. Only the languages that are on download their LSPs, formatters and
-- linters. Pure data: scripts/install-local.lua reads this file without loading the config, and install.sh reads it
-- with sed before nvim is even installed: keep ONE pack per line (stylua is told to leave them alone).
return {
  base = { "lua", "markdown", "json", "yaml", "toml" },
  -- stylua: ignore start
  packs = {
    { id = "go", label = "Go", langs = { "go" }, detect = { "go" } },
    { id = "dart", label = "Dart / Flutter", langs = { "dart" }, detect = { "flutter", "dart" } },
    { id = "typescript", label = "TypeScript / JavaScript", langs = { "typescript" }, detect = { "tsc", "bun", "deno", "pnpm", "yarn" } },
    { id = "web", label = "Web: HTML, CSS, Tailwind, Astro", langs = { "html", "css", "tailwind", "astro" }, detect = { "bun", "pnpm" } },
    { id = "python", label = "Python", langs = { "python" }, detect = { "uv", "poetry", "pipx", "pyenv" } },
    { id = "rust", label = "Rust", langs = { "rust" }, detect = { "cargo", "rustup" } },
    { id = "sql", label = "SQL: PostgreSQL, SQLite", langs = { "sql" }, detect = { "psql" } },
    { id = "swift", label = "Swift (Swift Package Manager)", langs = { "swift" }, detect = { "swift" } },
    { id = "jvm", label = "Java / Kotlin", langs = { "java", "kotlin" }, detect = { "gradle", "mvn", "kotlin" } },
    { id = "infra", label = "Docker, Make, Prisma", langs = { "docker", "make", "prisma" }, detect = { "docker" } },
    { id = "yarnspinner", label = "Yarn Spinner (game dialogue)", langs = { "yarnspinner" }, detect = {} },
  },
  -- stylua: ignore end
}
