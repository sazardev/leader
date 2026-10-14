-- Tests for the agent run history (<leader>ah): filters by agent, provider, model, action, outcome and project, and the
-- markdown detail of a run (the code sent, in its language). Pure: hand-made runs, no store, no telescope.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

local filter = require "agent.runs.filter"
local detail = require "agent.runs.detail"

local RUNS = {
  { ts = 1, backend = "claude", model = "sonnet", action = "fix", outcome = "accepted", cwd = "/w/notesapi", usage = { cost = 0.01 } },
  { ts = 2, backend = "claude", model = "haiku", action = "explain", outcome = "shown", cwd = "/w/notesapi", usage = { cost = 0.002 } },
  { ts = 3, backend = "opencode", model = "anthropic/claude-sonnet-4", action = "fix", outcome = "rejected", cwd = "/w/other" },
  { ts = 4, backend = "opencode", model = "openai/gpt-5", action = "review", outcome = "findings", cwd = "/w/notesapi" },
  { ts = 5, backend = "ollama", model = "qwen2.5-coder:7b", action = "fix", cwd = "/w/notesapi" },
}
local function ts(runs)
  return vim.tbl_map(function(r)
    return r.ts
  end, runs)
end

-- ── filters ─────────────────────────────────────────────────────────────────
eq("no filter: everything", ts(filter.apply(RUNS, nil)), { 1, 2, 3, 4, 5 })
eq("by agent", ts(filter.apply(RUNS, { backend = "claude" })), { 1, 2 })
eq("by provider: claude's CLI is Anthropic, and so is an anthropic/ model", ts(filter.apply(RUNS, { provider = "anthropic" })), { 1, 2, 3 })
eq("by provider: openai/ model", ts(filter.apply(RUNS, { provider = "openai" })), { 4 })
eq("by provider: a local model", ts(filter.apply(RUNS, { provider = "local (ollama)" })), { 5 })
eq("filters combine", ts(filter.apply(RUNS, { action = "fix", backend = "opencode" })), { 3 })
eq("outcome missing = pending", ts(filter.apply(RUNS, { outcome = "pending" })), { 5 })
eq("by project (folder name)", ts(filter.apply(RUNS, { project = "other" })), { 3 })
local actions = filter.values(RUNS, "action")
eq("values: most used first, with count", { actions[1].value, actions[1].count }, { "fix", 3 })
eq("values: cost adds up", math.floor(filter.values(RUNS, "backend")[1].cost * 1000 + 0.5), 12)
eq("label: in the dimensions' order", filter.label { model = "sonnet", backend = "claude" }, "agent claude · model sonnet")
eq("label: none", filter.label {}, "")

-- ── detail: the code sent, in its language ──────────────────────────────────
local prompt = table.concat({
  "<around>",
  "func Get() {",
  "[<target> lines 2-2 go here]",
  "}",
  "</around>",
  '<target lines="2-2" kind="diagnostic">',
  "\tn, err := find()",
  "</target>",
}, "\n")
local target, around = detail.code_sent(prompt)
eq("code sent: target", target, "\tn, err := find()")
eq("code sent: around", around, "func Get() {\n[<target> lines 2-2 go here]\n}")
local text = detail.text {
  ts = 1,
  action = "fix",
  backend = "claude",
  model = "sonnet",
  file = "x.go",
  first = 2,
  last = 2,
  lang = "go",
  prompt = prompt,
  system = "sys",
  response = "```go\n\t_, err := find()",
}
eq("detail: the target in a go fence", text:find("```go\n\tn, err := find()\n```", 1, true) ~= nil, true)
eq("detail: an empty instruction reads none when texts are stored", text:find("## Your instruction\n\n_none_", 1, true) ~= nil, true)
eq("detail: a cut answer's fence is closed", text:find("_, err := find()\n```\n", 1, true) ~= nil, true)

print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
