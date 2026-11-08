-- ── Env context (global): <leader>E ───────────────────────────────────────
-- One menu for every filetype and every stack (Go, TS, Python, Rust, C#, Swift, Dart, JVM or generic):
-- same keys, same flow. The stack is detected from the markers under the git root; when nothing matches (or several
-- do) it is a picker. See lua/env/.
return {
  name = "Env",
  prefix = "E",
  global = true,
  maps = require("env").maps(),
}
