-- Tests of docs that return ONLY the comment (agent/docplace.lua): placing it above the function or inside it (Python),
-- replacing the old one, keeping the code byte-identical, falling back when the model retypes the function, and the
-- whole flow with a fake model. Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local place = require("agent.docplace").merge
local function merge(lang, doc, code)
  return place(doc, { lang = lang, lines = code })
end

-- ── above the function ──────────────────────────────────────────────────────
eq(
  "go: a new comment goes above",
  merge("go", { "// Add sums two numbers." }, { "func Add(a, b int) int {", "\treturn a + b", "}" }),
  {
    "// Add sums two numbers.",
    "func Add(a, b int) int {",
    "\treturn a + b",
    "}",
  }
)
eq(
  "go: it replaces the old one",
  merge("go", { "// Add sums.", "// It never overflows." }, {
    "// old comment",
    "func Add(a, b int) int {",
    "\treturn a + b",
    "}",
  }),
  { "// Add sums.", "// It never overflows.", "func Add(a, b int) int {", "\treturn a + b", "}" }
)
eq(
  "ts: a block comment replaces a block comment",
  merge("typescript", { "/**", " * Adds.", " */" }, {
    "/** old */",
    "export function add(a: number) {",
    "  return a",
    "}",
  }),
  { "/**", " * Adds.", " */", "export function add(a: number) {", "  return a", "}" }
)
eq(
  "rust: attributes stay between the doc and the function",
  merge("rust", { "/// Adds." }, {
    "/// old",
    "#[inline]",
    "pub fn add() {}",
  }),
  { "/// Adds.", "#[inline]", "pub fn add() {}" }
)
eq(
  "indentation follows the code (a method)",
  merge("java", { "/** Adds. */" }, { "    public int add() {", "        return 1;", "    }" }),
  {
    "    /** Adds. */",
    "    public int add() {",
    "        return 1;",
    "    }",
  }
)
eq(
  "a multi-line comment keeps its relative indentation",
  merge("java", { "/**", " * Adds.", " */" }, { "    int add() {}" }),
  {
    "    /**",
    "     * Adds.",
    "     */",
    "    int add() {}",
  }
)
eq(
  "lua: --- comments",
  merge("lua", { "--- Adds." }, { "-- old", "function M.add() end" }),
  { "--- Adds.", "function M.add() end" }
)

-- ── inside the function (Python) ────────────────────────────────────────────
eq(
  "python: a docstring goes in the body",
  merge("python", { '    """Adds."""' }, { "def add(a, b):", "    return a + b" }),
  {
    "def add(a, b):",
    '    """Adds."""',
    "    return a + b",
  }
)
eq(
  "python: it replaces a one-line docstring",
  merge("python", { '    """New."""' }, {
    "def add(a, b):",
    '    """Old."""',
    "    return a + b",
  }),
  { "def add(a, b):", '    """New."""', "    return a + b" }
)
eq(
  "python: and a multi-line one",
  merge("python", { '    """New.', "", "    Args: a", '    """' }, {
    "def add(a, b):",
    '    """Old',
    "",
    "    more old",
    '    """',
    "    return a + b",
  }),
  { "def add(a, b):", '    """New.', "", "    Args: a", '    """', "    return a + b" }
)
eq(
  "python: a signature over several lines, with a decorator",
  merge("python", { '    """Adds."""' }, {
    "@cache",
    "def add(",
    "    a,",
    "    b,",
    "):",
    "    return a + b",
  }),
  { "@cache", "def add(", "    a,", "    b,", "):", '    """Adds."""', "    return a + b" }
)
eq(
  "python: the docstring takes the body's indentation",
  merge("python", { '"""Adds."""' }, { "  def add(self):", "      return 1" }),
  {
    "  def add(self):",
    '      """Adds."""',
    "      return 1",
  }
)

-- ── what must not break ─────────────────────────────────────────────────────
local fn = { "func Add(a, b int) int {", "\treturn a + b", "}" }
eq("fallback: an empty answer changes nothing", merge("go", { "", "  " }, fn), fn)
local whole = { "// Add sums.", "func Add(a, b int) int {", "\treturn a + b + 0", "}" }
eq("fallback: a model that retypes the function wins as is", merge("go", whole, fn), whole)
eq(
  "fallback: python too",
  merge("python", { "def add(a, b):", '    """Adds."""', "    return a + b" }, { "def add(a, b):", "    return a + b" }),
  {
    "def add(a, b):",
    '    """Adds."""',
    "    return a + b",
  }
)
eq("a target of only comments is left alone", merge("go", { "// x" }, { "// just a comment" }), { "// just a comment" })
eq("blank lines around the answer are dropped", merge("go", { "", "// Add.", "" }, fn)[1], "// Add.")
local before = vim.deepcopy(fn)
merge("go", { "// Add." }, fn)
eq("the target's lines are never modified", fn, before)

-- ── the whole flow ──────────────────────────────────────────────────────────
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["add.go"] = {
    "package p", -- 1
    "", -- 2
    "func Add(a, b int) int {", -- 3
    "\treturn a + b", -- 4
    "}", -- 5
  },
}
local FAKE = K.fake()
local pipeline = require "agent.pipeline"
local replace = require "agent.output.replace"
local buf = K.open "add.go"

FAKE.text = "```go\n// Add returns the sum of a and b.\n```"
K.at(3)
pipeline.run "docs"
K.idle()
local pending = replace.pending()
eq("flow: a proposal is waiting", #pending, 1)
eq("flow: it is the comment plus the untouched code", pending[1] and pending[1].lines, {
  "// Add returns the sum of a and b.",
  "func Add(a, b int) int {",
  "\treturn a + b",
  "}",
})
eq("flow: the raw answer (what a refinement starts from) is only the comment", pending[1] and pending[1].raw, {
  "// Add returns the sum of a and b.",
})
ok("flow: the request asks for ONLY the comment", FAKE.req.system:find("ONLY the doc comment", 1, true) ~= nil)
replace.accept()
eq("flow: accepting writes it", vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
  "package p",
  "",
  "// Add returns the sum of a and b.",
  "func Add(a, b int) int {",
  "\treturn a + b",
  "}",
})

K.finish()
