# Inline agent (`<leader>a`)

**One-shot** actions on what you are looking at: a function, a class or a selection. No chat, no sidebar, no
conversation. Every action has a closed prompt, a bounded context and an output with a fixed format, so it is
predictable and cheap. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (**Agent** menu).

## Flow

1. Put the cursor inside a function (or select lines in visual mode) and press `<leader>a` + the action.
2. The code being sent is highlighted and a spinner turns on the right: `⠋ implement · claude/haiku · 1.2s`.
   Requests with no code to paint (the project documents of `<leader>aS`, including the screens of `<leader>aSw`, the commit
   draft, the staged review, plans) show a badge in the **statusline** from any buffer: `⠹ drawing screens`, then `✓ drawing screens` (or a red `✗`) for a few seconds after it ends. `<leader>ax` cancels them too.
3. The result shows up **in the code**, depending on the action:

| Action | Input | Result |
|---|---|---|
| `i` implement | function (its name, signature, doc or `TODO` are the spec) + optional instruction | inline diff: deleted lines in red, added lines in green below. `⏎` accepts, `⎋` rejects |
| `r` review | function or selection | real findings as **diagnostics** on their line (`◆`); `<leader>xd` shows the detail |
| `e` explain | function or selection | window next to the code, streaming; closes by itself when the cursor moves, or with `Esc` from the code (while it is still streaming, `Esc` also stops the call) |
| `a` ask | your question (text field) | window, same as explain |
| `f` fix inline | the diagnostic (LSP, linter or agent finding) on the cursor line + optional hint | diff with the minimal change on **only those lines**; the surrounding code and the objects it points to (the variable's type, the signature of what is called) go along as read-only context; with no diagnostic on the line, it does nothing |
| `F` fix block | all the diagnostics of the function (or selection) + optional hint | diff with the minimal change that leaves the block coherent (several diagnostics with the same cause are fixed together) |
| `d` docs | function + optional focus | diff that only adds/updates the documentation comment; the model returns **only the comment** (`agent/docplace.lua` puts it above the function, or inside it for Python), so the code cannot change and the output is a few lines |
| `t` convert | selection (or the paragraph under the cursor) holding a JSON sample, a SQL `CREATE TABLE` or a curl command, in a code file + optional root type name | diff that replaces it with ready code in the file's language: JSON → Go structs with `json` tags and nested types (TS interfaces, JSDoc typedefs in JavaScript, Python dataclasses, Rust serde structs, Dart classes with `fromJson`/`toJson`…), a table → a struct with `db` tags and pointers for nullable columns, curl → a function that sends the request with the standard client (secrets become parameters). What each source becomes is fixed per language (`agent/convert.lua`), so the prompt is explicit; light model, only `rules` as context. A one-word instruction names the root type (`Invoice`); in a non-code file it refuses (paste the JSON where the types should go). In Dart it follows `pubspec.yaml`: JSON → freezed classes (or `@JsonSerializable()`), a table → a drift `Table`; the import and `part` lines are added on accept (`convert_header.lua` on `proposal.accepted`, rules in `utils/dartheader.lua`) and a snake_case key left without `@JsonKey(name: …)` gets it by rule ([Dart / Flutter](dart-flutter.md#the-agent-with-dart)) |
| `n` next edit | the 30 lines around the cursor + what you just changed in this file | diff with the ONE edit that follows from your recent changes (the rename you are following through, the field added to one constructor and not the others); with nothing changed in the file it asks nothing ([Next edit](#next-edit-on-demand)) |
| `R` refactor | your instruction (text field) | diff that applies exactly that instruction |
| `g` handoff | your instruction | sends `file:range` + instruction to an agent already running in Herdr |
| `aA` + `a` fix all | none (the file's findings and diagnostics) | one proposal per function that holds any, asked **once** with the total estimate; they wait in a queue ([Several proposals at once](#several-proposals-at-once)) |
| `aA` + `o` / `O` fix from output | none / a command | the errors a build printed (last terminal, quickfix, or a command you run), one proposal per function they point into |
| `aA` + `p` plan across files | your instruction (text field) on a type or function | an editable plan of steps, then one proposal per step ([Multi-file plans](#multi-file-plans)) |

**The instruction field is inline** (like the inline chat in Zed or VS Code): it opens right ABOVE the target code and
**pushes the code down** instead of covering it, with an accent bar, a header (`✦ implement · claude/sonnet`) and
a placeholder. It grows as you type (up to 6 rows), `⏎` sends, `⎋` cancels (also if you switch windows), `⌃J` / `Alt+Enter`
insert a line break and `↑`/`↓` (or `⌃P`/`⌃N`) walk through the previous instructions of that action, which are remembered
across sessions. In narrow windows the key hint shortens itself. There is no autocompletion or auto-closing of quotes inside.

**Instruction**: `i`, `d`, `t` and `f` open the field and **Enter with an empty field runs without an instruction**; if you type something, it is appended
to the prompt and takes precedence over the default behaviour. Useful for an empty `func main() {}` ("read a CSV and sum column
3"), for an unclear function ("this validates orders before charging; the coupon case is missing") or to steer a fix.
`a` ask and `R` refactor require the text; `r` review and `e` explain run instantly.

**Short menu**: `i` implement, `d` docs, `t` convert, `n` next edit, `r` review, `e` explain, `a` ask, `f` fix inline, `F` fix block, `R` refactor, `g` hand off (only inside
Herdr), `h` history, `m` model (main, light and effort in a single selector), `c` clear (discards the finding on the line, or those in the selection in visual mode), `C` clear file (those in this file), `x` stop (cancels what is running and discards the
pending proposals; it does **not** touch findings) and `l` last answer (reopens the last answer or rejected proposal). Everything that works on many pieces at once lives
in its own **Advanced menu, `<leader>aA`**, so the everyday one stays short: `a` fix all, `o` / `O` fix from output / from a command, `p` plan across
files, and for the proposals they leave waiting `]` / `[` next / previous, `y` accept all, `l` list. Accepting and
rejecting a proposal have no menu entry: they are `⏎` and `⎋` on the proposal (and `Tab` refines it).

**Accepting is a single change**: `u` undoes it entirely. If you edit the code while the agent is working, the proposal
is **discarded** instead of overwriting your change. Several actions can run at once (not on the same block).

## Which target it takes

Priority: **visual selection** (always whole lines) > **function** under the cursor (with the contiguous comments
above it, which are the spec) > **class** > **paragraph** of lines around the cursor (useful for a half-written
signature: type `func ParseConfig(path string) (*Config, error)` and press `<leader>ai`).
"Function/class" is the definition of `af`/`ac` (treesitter textobjects), for any language with a parser.
More than `context.max_target_lines` (400) is rejected: trimming it would break the replacement.

## Context (and why it is cheap)

Each action asks for providers; together they are capped at `context.max_chars` (8000 characters), the target is counted separately:

| Provider | What it contributes | Cost |
|---|---|---|
| `rules` | `settings.agent.rules` + `.agent.md` at the project root (your conventions) | text |
| `types` | **the definition of the types the target uses** (fields of a struct, members of a class/interface/enum/trait), so the model does not guess `Note.Done` | local + LSP |
| `contracts` | if the target is an **adapter** (`PostgresOrderRepository`): the **port** it must satisfy (with path), which methods already exist and **which are missing**, the **entity** the port names and, when implementing, **another implementation in the project** as a style example (constructor, errors, mapping) | rg + treesitter |
| `schema` | for a persistence adapter: the entity's **real table** (SQL migrations with their later `ALTER`s/indexes, or `schema.prisma`) and the database in use: dialect, driver, parameter style (`$1`, `?`, `@p1`) | rg + manifests |
| `diagnostics` | LSP/linter diagnostics inside the target, **each one with its code line** (the target is not numbered) | local |
| `callees` | REAL signature of what the target calls, requested from the LSP (hover); whatever does not arrive within 700 ms is omitted | LSP |
| `outline` | imports + first line of each function (without repeating the types already included in `types`) | local |

`types` is language-independent (it uses the same treesitter queries as `af`/`ac`): Go (struct, interface, alias),
TypeScript (interface, class, type, enum), Python, Rust (a method of `impl Note` brings `struct Note`, not the `impl`), Java...
A type in the **same file** is read instantly; one in **another file or package** is located with the LSP
(`textDocument/definition`) and extracted from the destination file (project only, not dependencies). Field types
are followed one level (`Tags []Tag`), and if the target is a class method, the class is included without the method itself.
Cap: `context.types` (4) definitions of `context.type_lines` (30) lines. Each definition is compacted first (`compact` in
`providers/types.lua`): full-line comments and blank lines go (`context.type_comments = true` keeps comments), and runs of
bare enum values are joined, at most 24 shown and the rest counted (`… (188 more)`). Measured on a Flutter widget whose
`build` uses two enums with a doc comment per value: the `<types>` section went from 3,243 to 871 characters. Definitions
are never taken from generated files (`x.freezed.dart` repeats the class ~5x longer; `utils/generated.lua`).

Each action asks for what it needs, **in priority order** (if the budget gets tight, the last ones are trimmed):

| Action | Context |
|---|---|
| implement | rules, contracts, schema, types, callees, outline, diagnostics |
| port | rules, contracts, schema, types, diagnostics |
| review | rules, diagnostics, contracts, schema, types, callees |
| fix (inline) | rules, **diagnostics**, findings, contracts, **around** (surrounding code), types, callees |
| fix block | rules, **diagnostics**, findings, contracts, types, callees |
| refactor | rules, types, callees, outline |
| ask | rules, types, callees, outline, diagnostics |
| explain | rules, types, callees |
| docs | rules, types (documents the real fields and parameters, without paying for outline or callees) |
| convert | rules (the selection is the whole input) |

**Transparency (`note:`)**: after the code block the model may add `note: ...` (max. ~15 words) when it assumed or
added something that was not in the context, and `needs-import: ...`. Both show up in the proposal hint (`note: Note has no
Done field; assumed one`) and are kept in the history. Measured in a test with `SetDone` without `types`: it guessed `Done` and `Updated` and said so;
with `types`: the same code, with no warning, **-70 % output tokens and -25 % cost**.

**Measured with Claude**: a normal `claude -p` call drags ~46 000 input tokens (your plugins, skills, hooks
and memory). With `--setting-sources ""`, `--tools ""` and its own `--system-prompt` it drops to **~600 tokens** (+ the context), about
2 s and fractions of a cent per action (haiku). The CLIs run in a neutral directory (`stdpath("cache")/agent`), so they
do not load the `AGENTS.md`/`CLAUDE.md` of your repo either. That is why **`--bare` is not used**: it would break subscription login.

**Cost audit (measured)**: every `claude -p` call was billed as a 1-hour cache *write* (up to 2× the
input price) and never hit the cache, because the message changes on every call. With `DISABLE_PROMPT_CACHING=1`
(setting `agent.claude.prompt_cache = false`, the default) a Sonnet action went from **$0.0065 to $0.0037** and a Haiku one
from $0.0005 to $0.0003, with no change in latency. The system prompts were also shortened ~35 % (implement 1462 → 943 characters) and now state what is true (`types`, `callees`, `diagnostics`) and that whatever was assumed must be flagged with `note:`. In total, the same
action costs **~50 % less** than before the audit. About ~560 fixed input tokens from the CLI itself remain, which no safe
flag trims (`CLAUDE_CODE_SIMPLE` and `--bare` break subscription login). `agent.claude.max_cost_usd`
(0.25) cuts off a runaway call.

### Order of the prompt (stable first, volatile last)

The sections reach the prompt arranged by each provider's `stability`: **1** the same on every call of the project (`rules`, `testing`),
**2** changes only when the code does (`types`, `outline`, `contracts`, `schema`, `ports`, `ddd`, `testfile`, `callees`), **3** changes
with the cursor or the editor (`diagnostics`, `findings`, `around`, `callers`, `gitlog`, `changes`, `subject`). The declared order still
decides what survives when the budget is tight; only what is SENT is rearranged. What this buys depends on the backend:

- **Ollama / llama.cpp / vLLM** keep the KV cache of the last prompt and reuse what is identical from the start: a second action on the
  same code re-reads only the tail. For that, Ollama's `num_ctx` is now *sticky* per model (a small action after a big one keeps the big
  window, otherwise Ollama reloads the model and drops that cache).
- **`claude -p`** gets almost nothing from it: the CLI sends the whole message as ONE block and the fixed part is under the cache's minimum
  size. That is why `prompt_cache` stays off (measured: -40% per call); if you turn it on, `<leader>ah` shows `cache_read`/`cache_write` per
  run so you can check it pays. The [answer cache](#answer-cache-repeated-questions-are-free) is what makes repeated questions free there.
- A new provider declares `stability = 1|2|3` next to its `cap` (default 2).

## Models per tier (cheap where it is enough)

Each action runs on the **main** model or the **light** one. `docs`, `explain` and `convert` are light (Claude: `haiku`); the rest
use the main one (`sonnet` by default). Measured with Claude, a single-function action: **~$0.005 on sonnet vs ~$0.0003 on
haiku**, about 17 times less, and the spinner shows the model that is running. Light actions do not inherit the
effort either: they are the cheap ones and must not become expensive because of a setting meant for others.

- `<leader>am` opens a selector with the **main** model (and the backend), the **light** model and the effort, with their current value. Everything is remembered.
- Change which actions are light: `agent = { tiers = { review = "light", docs = "main" } }` in `local.lua`.
- `agent.claude.light_model` / `agent.opencode.light_model` set the default light model. In OpenCode both default to
  `opencode-go/deepseek-v4.1-flash` (ids depend on your provider: pick another in `<leader>am`).

## Backend and model

`<leader>am` → Main model opens ONE fuzzy list with the models of all installed backends (Claude: `haiku`/`sonnet`/`opus`;
OpenCode: the cheap, fast shortlist in `agent.opencode.models`, or whatever `opencode models` returns if that is `nil`). Choosing one also switches the backend and **is remembered** across sessions
(`stdpath("state")/agent.json`). Effort (Claude only; `--effort`) is in the same selector. With `backend = "auto"` the
first available one in `agent.order` is used.

- **Claude Code** (`claude -p`): no tools, no session on disk, text streaming.
- **OpenCode** (`opencode run`): each action travels as an ephemeral agent with no tools (`OPENCODE_CONFIG_CONTENT`).
  Your global MCP servers are turned off for these runs (`agent.opencode.mcp = true` keeps them): their tool schemas were
  ~20k input tokens and ~2 s per action. With `agent.opencode.serve` (default) a **private `opencode serve`** (free loopback
  port, random password, no MCP, stopped on exit, off in light mode) boots in the background and actions talk to its HTTP
  API with curl on a session created ahead: ~2 s per action instead of ~8 s. The first action (while it boots) is cold.
  **The CLI line is detected** (`opencode --version`): 2.x changes the inline schema (`agents`/`system`/`permissions`), takes
  the variant in `-m provider/model#level`, needs `run --standalone` (without it the background service, which never sees
  `OPENCODE_CONFIG_CONTENT`, answers and the requested agent is "not found") and has no `--pure` equivalent. Its warm path is
  off until `opencode serve`'s **v2 HTTP API** is driven, so every action pays the private-server boot (~3 s measured on 2.0.31)
  and the run's JSON stream carries no usage events in our tests (the report shows tokens as —).
  In 1.x, models matching `agent.opencode.no_thinking` (default `deepseek`, `haiku`, `minimax-m3`) run with thinking off: deepseek-v4.1-flash spent 300-1400
  reasoning tokens (4-15 s) on small functions; it costs some quality, `{}` turns it back on. It is per model because glm/cat-jam reject the parameter.
  (2.x has no such option: reasoning is chosen with the model's variants, `effort` in `<leader>am`.)
  The shortlist (deepseek-v4.1-flash, minimax-m3, claude-haiku-5-5, glm-5.3-flash, gpt-6-luna) was picked by benchmarking all opencode-go
  models on four graded tasks (two `implement` checked with `go test`, a `review` with a seeded bug, a `review` of clean code that must
  answer `OK`): 4/4, 1.4-3 s warm, ~$0.0002 per action. Haiku keeps requests 30 days; Gemini and Muse Spark train on prompts (left out).
  DeepSeek costs double at Peak (01-04 and 06-10 UTC, Mon-Fri). Only one run per task, so differences under ~0.5 s are noise.
  `agent.opencode.attach` points at a server of your own instead (`--server` on 2.x), but `opencode run --attach` printed no text in v1.19.
  `agent.opencode.agent` uses an agent of your own. If opencode does not find the requested agent it warns and falls back to the default one, which
  DOES have tools: here that is treated as an error.
- Each opencode session stays in its list: titled `nvim <action>` in the cold path, `nvim agent` on the private server.

## Local backends and models (automatic setup)

Besides Claude Code and OpenCode, the agent talks to **local models** (Ollama on CPU or CUDA, LM Studio, llama.cpp,
vLLM...) and to any other agent CLI (Hermes Agent, Gemini CLI, Codex, Aider). A setup detects and connects them.

**Quick start**

1. `<leader>am` → **Setup** (or `scripts/agent-setup.sh` from the terminal). It detects in parallel, without touching anything: the installed
   CLIs, Ollama and OpenAI-compatible servers (also the **Windows one if you are on WSL**: it tries `127.0.0.1`, the
   nameserver and the gateway), their models, whether what is loaded runs on **GPU or CPU**, the VRAM/RAM, and it remembers the server
   it found.
2. **Use detected models** applies the recommendation with what you already have. If there are no models, it offers to **Download** a couple
   according to your memory (VRAM, or half the RAM without a GPU): `qwen2.5-coder` 32b/14b/7b/3b/1.5b. They are **suggestions**, you decide.
3. If Ollama is installed but stopped: **Start Ollama server** (`ollama serve` in the background). Starting and downloading
   are always requested explicitly: nothing is installed or downloaded by itself.

**Terminal** (`scripts/agent-setup.sh`; with no flags it only reports and exits with 0 if a backend is ready):

| Flag | Does |
|---|---|
| `--start` | starts `ollama serve` if it does not respond |
| `--pull MODEL` | downloads a model (repeatable) |
| `--auto` | applies the recommendation with the models already installed |
| `--use backend/model[@light]` | sets backend and model (main, or light with `@light`) |
| `--json` | the full snapshot, for other tools |

Example: `scripts/agent-setup.sh --start --pull qwen2.5-coder:3b --auto`.

**The best of each tier**: the main one stays on Claude and local models cover the **light** tier (`docs`, `explain`):
`light_backend` (in `<leader>am` → Light model, or `agent.light_backend`) keeps those actions on a free local model without
moving `implement`/`fix`/`review`. With no cloud CLI at all, the local one becomes the main one too.

**Backends** (all use `curl`, no dependencies):

- `ollama`: `agent.ollama = { host, model, light_model, models, num_ctx, max_ctx, keep_alive, temperature, think }`. The host comes
  from `host` > `OLLAMA_HOST` > what the setup detected > `127.0.0.1:11434`. `num_ctx` is **automatic** (power of two depending on
  the prompt, capped by `max_ctx`): Ollama SILENTLY truncates whatever does not fit in its window and would lose precisely the rules at
  the beginning. `keep_alive` leaves the model loaded (the first action is slow, the following ones are not); `temperature` is low (0.1)
  because the required format is respected better. Cost is always 0. The `<think>…</think>` blocks of qwen3/deepseek-r1 are discarded.
- `openai`: `agent.openai = { base_url, api_key_env, model, light_model, models, temperature }` (LM Studio `:1234`, llama.cpp
  `:8080`, vLLM `:8000`, LiteLLM, OpenRouter...). The key is read from the `api_key_env` variable and travels through the process
  environment, not in the arguments (it does not show up in `ps`).
- `custom` (Hermes Agent, Gemini CLI...): a declarative entry in `agent.custom`, without writing code:

```lua
-- local.lua
return { agent = { custom = {
  hermes = {
    label = "Hermes Agent",
    cmd = { "hermes", "chat", "-q", "{prompt}" },   -- {prompt} {system} {model}
    system_in_prompt = true,
    model_flag = { "-m", "{model}" },
    models = { "hermes3" },
  },
} } }
```

The flags in the Hermes Agent example are **not verified** (the CLI was not installed when this was written): check them with
`hermes --help`. Hermes *models* do work today through Ollama (`ollama pull hermes3`).

**Pitfalls**

- A small local model fails more often with the structured format (code block, `L<n>|sev|msg`): use it for `docs`/`explain`
  and, if you want more, move up to a 14b+ code model. `Esc` rejects malformed output as usual.
- Without a GPU the model runs on CPU: fine for the light tier; the report says whether what is loaded is on GPU, GPU+CPU or CPU.
- WSL2: to reach the Windows Ollama, set `OLLAMA_HOST=0.0.0.0` there. In Docker with NVIDIA:
  `docker run -d --gpus all -p 11434:11434 -v ollama:/root/.ollama ollama/ollama`.
- The setup (and the terminal report) stores the servers it finds in `agent.json` (`endpoints`).

## Handoff to Herdr

`<leader>ah` (only inside Herdr): you type the instruction, pick an agent from `herdr agent list` (those in this
folder first) and `file:range` + diagnostics are sent with `herdr agent prompt`. With unsaved changes it attaches the current
code. Use it when the task no longer fits in a single shot.

## Hexagonal architecture levels (one menu per level)

`<leader>a` keeps the generic ones (implement, review, explain, ask, fix inline, fix block, docs, convert, refactor, hand off, model, history, clear, stop, last).
Each architecture **level** has its own folder (`lua/agent/<level>/`), its own action registry and its own menu, with its context and,
in each one, a **local 0-token analysis**. The actions of each level run through the same pipeline (inline diff, findings,
history and cost), and in the history they appear under their own name (`repo_port`, `service_review`, `ddd_fix`...).

| Menu | Level | LLM actions | Local analysis (0 tokens) | Own context |
|---|---|---|---|---|
| `<leader>aD` | **Domain / DDD** (`agent/ddd/`) | implement `i`, review `r`, fix `f`, missing `m`, ask `a` | diagnose `d` (layers, violations, aggregates), clear `c` | `ddd` (layers, naming, related pieces) |
| `<leader>aP` | **Repository** (`agent/repository/`) | port `p`, implement `i`, review `r` | **check** `c` (port vs methods, entity vs table) | `contracts`, `schema` |
| `<leader>aU` | **Service** (use cases) (`agent/service/`) | implement `i`, review `r` | **deps** `d` (ports it uses, nonexistent calls, implementations, wiring) | `ports` |
| `<leader>aT` | **Tests** (`agent/tests/`) | write `w`, mock `m`, fix `f` | **gaps** `g` (public functions in the folder that no test names) | `testing`, `subject`, `testfile` |
| `<leader>aL` | **Lenses** (`agent/lenses/`) | security `s`, performance `p`, concurrency `c`, errors `e`, api `a` | — (each lens first discards what is not its concern) | `changes` |

The providers of each level (`contracts`, `schema`, `ports`, `ddd`) are **silent if the code does not belong to that level**, so
`implement`/`review`/`fix` of the generic menu also receive them when applicable, at no cost when not. The shared code
(searching with ripgrep, reading a type definition) lives in `agent/discovery.lua`, so levels do not depend on each other.

## Repository (`<leader>aP`): persistence adapters

Implementing a repository (SQL, Postgres, MySQL, in-memory...) is long but mechanical, and the model needs what is **not in the
file you are looking at**. The agent finds it by itself, without you mentioning files, and each piece arrives **with its path**:

- **Port**: the interface it must satisfy. It is deduced from the name (`PostgresOrderRepository`, `pgOrderRepository`,
  `OrderRepositoryImpl`, `CachedOrderRepository` → `OrderRepository`) and from what is declared explicitly (`implements X`, `class T(X)`,
  `impl X for T`, `var _ X = (*T)(nil)`); it is located with ripgrep in **any folder structure** and read with treesitter.
- **What is missing**: it compares the port's methods with those the type already has (in Go, the functions with that receiver in the package)
  and also warns about the constructor. Only the missing ones are requested.
- **Entity and types the port names** (`Order`, with its fields and constants) even if the empty struct does not mention them:
  without this the model invents the fields.
- **Sibling example**: another implementation in the project (the one in the same folder is preferred) with the constructor and the
  equivalent method: this way it copies your structure, your error handling (`fmt.Errorf("…: %w")`, `errors.Is(err, sql.ErrNoRows)`) and your mapping.
- **Schema**: the entity's real table with its later changes and the **dialect** (from the schema syntax and from
  `go.mod`/`package.json`/`pyproject`/`Cargo.toml`/`pom.xml`), the access library and the parameter style. It is **agnostic**: with
  the same prompt, a Postgres migration produces `$1` and `ON CONFLICT`, and a MySQL one, `?` and `ON DUPLICATE KEY UPDATE`.

`<leader>aPp` (**repo port**) uses the type under the cursor (or that of its receiver, if you are inside one of its methods) and writes the type,
the constructor and ALL the missing methods, in the port's order. `<leader>aPi` (repo implement) writes a single method with that context; `implement` (`i`/`aDi`) receives it too if the code is an
adapter, and `<leader>aPr` (repo review) reviews what is specific to persistence (columns that do not match, dialect parameters, concatenated SQL, unclosed `rows`,
unwrapped errors, N+1) and `<leader>aPc` (**repo check**, 0 tokens) compares the port's methods with those of the type and the entity's fields with the columns of its table. **Silent if it does not apply**:
a service, a handler or any other function does not pay even for the search (measured: 0 characters of extra context).

Tested with Claude on an empty `PostgresOrderRepository` with a 4-method port: it returned the constructor and the 4 methods with the real
columns from the migration, `$1…`, the error style of the sibling implementation and no invented fields (what it assumed, such as
`order.ErrNotFound`, it states in `note:`), for ~$0.0013 with Haiku. **Limits**: the port is found by name or explicit
declaration (not by type inference); the sibling example is the first reasonable one it finds; the schema is only read from `*.sql` and
`*.prisma` (not from ORM models or the live database).

## Service (`<leader>aU`): application services / use cases

A service can only call the methods that its **ports** declare. The `ports` provider finds the interfaces the service receives
(fields, constructor parameters, method parameters, in any language) and reads them with their real signatures, each with its path and the
instruction to call only those methods; with `examples` it adds another service of the project as a style example.

- **`<leader>aUi` service implement**: orchestrates the domain and calls ONLY the ports in `<ports>` with their exact names and signatures; business
  rules are called on the entity (not reimplemented); it propagates the context and translates the ports' errors.
- **`<leader>aUr` service review**: calls to port methods that do not exist or with wrong arguments, business rules in the service, leaking
  infrastructure details, swallowed or untranslated errors, non-atomic steps or steps ordered in a risky way (effects before saving), N+1.
- **`<leader>aUd` service deps** (0 tokens): for each port, which methods it declares, **which ones this file calls and which ones the port does NOT declare** (it
  would not compile), which implementations it has and whether any is wired (used outside its file); it lists what needs attention.

Tested with Claude: on a service that called `orders.FindByID` (the port declares `ByID`), `deps` detected it without an LLM and `service review`
flagged it against the real port; `service implement` used only `ByID`, `Save` and `Mailer.Send` and called the entity's `o.Confirm()` instead of repeating the
rule (what it assumed, such as a method the entity does not have, it stated in `note:`).

## Findings that stay (and how to fix them)

The findings of `review` and `ddd review`, and the violations of `ddd diagnose`, are diagnostics **pending attention**: they are saved
(`stdpath("state")/agent-findings.json`) and **come back when you open the file in another session**, even if you do not deal with them today.

- Each one is saved with the **text of the flagged line**. If the code has moved since then (you edited above, another
  branch...), it is **relocated** by that text (up to ±40 lines); if the line no longer exists, it is dropped with a warning
  (`Agent: 1 saved finding no longer matches the code and was dropped`). Saving the file updates the positions.
- Only the agent's are saved: LSP ones are not touched. If there is no findings file, opening a file costs nothing.
- **Clearing them** (from memory and from disk; review and ddd alike): `<leader>ac` clear discards the one on the cursor line (in
  visual mode, those in the selection) → one at a time; `<leader>aC` clear file, all those in this file; `:AgentClear [file|all]`
  (with a range: `:'<,'>AgentClear`), `all` = all files. `<leader>aDc` ddd clear, the DDD diagnostic of the whole project. **`<leader>ax` stop does not delete them**: it only cancels what is running and discards pending proposals.
- **Fixing them**: `<leader>af` (fix inline, the one on the line), `<leader>aF` (fix block, the whole function) and `<leader>aDf` (**ddd fix**) read the findings that fall in the function or selection,
  together with the LSP diagnostics, and propose the minimal change (in `ddd fix`, respecting the layers in `<ddd>`; if the fix
  needs a port, type or file that does not exist, it says so in `note:` and does not invent its content). When you **accept** the proposal, the
  findings in that range are considered resolved and also disappear from what is saved. `review` and `ddd review` do **not** read earlier
  findings: a new review must not start from what the previous one said.
- Flow: `<leader>aDr` (review) → tomorrow, another session: the diagnostics are still there → `<leader>aDf` on the function → `⏎`.

## DDD (`<leader>aD`)

A feature **separate** from the normal agent, with its menu, its action registry (`lua/agent/ddd/`) and its context. Same
pipeline and same experience (inline diff, findings as diagnostics, window, history and cost, where they are distinguished
as `ddd_implement`, `ddd_review`...), but the actions follow the **layers and naming of YOUR project**.

| Key | Action | Costs |
|---|---|---|
| `<leader>aDd` | **diagnose**: static analysis of the whole project | 0 tokens |
| `<leader>aDi` | implement: writes the code in the layer where it belongs, with your names and the language's idiom | LLM |
| `<leader>aDr` | review: DDD and SOLID violations as diagnostics (without repeating those the local analysis already detected) | LLM |
| `<leader>aDf` | **fix**: fixes what `ddd review` and the diagnostic left pending (minimal change, respecting the layers) | LLM |
| `<leader>aDm` | missing: what is missing around what you see (ports, implementations, use cases, DTOs, **wiring**, errors, tests), with file names following your convention | LLM |
| `<leader>aDa` | ask: architecture question with the real layers and pieces | LLM |
| `<leader>aDc` | clear: discards the violations of the whole-project diagnostic (also from what is saved) | 0 tokens |

**What the local analysis does (free, no LLM)**: it walks the project once (asynchronously, in batches; it only reads files
**inside layer directories** and that are not tests; cached by mtime) and deduces:

- **Layers** by directory name (`domain`, `application`, `infrastructure`, `interface` and synonyms: `usecases`, `adapters`,
  `persistence`, `api`, `handlers`...; adjustable in `settings.agent.ddd.layers`). The dependency rule points inwards:
  domain ← application ← infrastructure / interface. Composition roots (`main`, `cmd/`, `container`, `di`...) may wire everything.
- **Violations** (`◈` diagnostics in the code + quickfix list + panel): outward dependencies (with the exact import),
  **frameworks in domain/application** (`database/sql`, `net/http`, `gorm`, `@nestjs`, `sqlalchemy`, `org.springframework`... per
  language: Go, TS/JS, Python, Java/Kotlin/Scala, Rust, C#, PHP, Dart) and badly named files (`PaymentService` in `pricing.go`).
  Only the **project's own** imports are assigned to layers (`go.mod` module, relative ones in TS/Python, `crate::` in Rust): `database/sql` is a framework, not "the database layer".
- **Naming**: file style (`snake_case`, `kebab-case`, `order.entity.ts`, `PascalCase`) and most used roles
  (`repository`, `service`, `handler`...), deduced from what already exists; suggestions for missing files respect it.
- **Aggregates, gaps and connections**: for each domain entity (a type with an `ID` field) it looks for its repository **port**, its
  **implementation**, whether it is **wired** (its name is used in some other file, via `rg`) and its **use cases**; it lists what is missing.

**What the model receives** (`<ddd>` section, max. 1800 characters, only what is relevant to that target): its layer and what it
may depend on, project layers, naming convention with examples, neighbouring files, the pieces surrounding the entities
it touches (`Order: port OrderRepository (...) · impl PostgresOrderRepository (...) wired ✓ · use cases PlaceOrder`), the violations
in that file and **a line with the idiom of the current language** (constructors, errors, injection). Plus the DDD rules (~600 characters).

Measured on a Go project with one complete entity (port + implementation + use case) and another without a port: `implement` of
`Order.Confirm()` used `Pending`/`Confirmed` (the constants of the `Status` type travel with it) and respected the layer; `review` found the
`*sql.DB` and the concrete repository stuffed into the entity, plus primitives without invariant; `missing` listed the vertical slice of
`Customer` with paths in the project's style. Each action, under $0.001 with Haiku. On a repo with 7500 code files, the
first analysis takes ~0.9 s (252 layer files) and the next one 35 ms.

**Limits**: layers are recognised by directory name (if yours are named differently, adjust `layers`); "entity" is a domain
type with an `ID` field; "wired" means "its name appears in another file", not a dependency-graph analysis; imports
are read with regex and types with treesitter, so it is not a compiler. Languages without a treesitter parser only contribute imports.

## History and spending (`<leader>ah`)

Every action is stored in `stdpath("state")/agent-history.jsonl` (append-only): when, action, model, target, **your
instruction, the system prompt, the exact message sent, the response**, tokens (with cache read/write), cost,
time and **what you did with the result** (accepted, rejected, discarded, N findings...). This way you can see transparently what was
asked and what was paid.

- `<leader>ah` opens a selector with one row per run (date, outcome, action, model, cost, target); the title
  adds up the total spent. The preview shows the full detail rendered as markdown, including **the code sent** (the
  target and the code around it, highlighted in its language); `⏎` opens it large and `⌫` (BS) comes back to the
  list with the same filters, search text and run selected.
- `⌃F` **filters** the history by agent (claude, opencode, ollama…), provider (who serves the model: anthropic,
  openai, local…), model, action, outcome or project: pick the dimension, then the value (each with its runs and
  cost). Filters stack and show in the title with the runs and spend that match; `⌃X` clears them.
- `⌃S` opens the **spending report** (`⌫` comes back to the list): by period (today, 7 days, total), by action, by model, by day, **cost per applied
  change**, what was spent on proposals you did not apply, errors, cache hits, **where the prompt goes** (system,
  context per provider, target) and the 5 most expensive runs. It is the basis for deciding what to cut.
- `⌃Y` **copies EVERYTHING about the run** as markdown (the same text you see in the detail): outcome and event line (accepted at
  09:38:27...), target, time, tokens, cost, your instruction, the response, the system prompt and the exact message
  sent. `⌃P` copies only the prompt (system + message) to reproduce or tweak it. In the detail panel and in
  the report panel, `Y` copies the whole panel. Everything goes to the clipboard (`+`) and the unnamed register.
- Privacy: the history includes your code (it goes inside the prompt). `agent.history.store_text = false` stores only metrics;
  `enabled = false` turns it off. It compacts itself to the `max_entries` (1000) most recent.

## Refine: change a proposal without starting over

A proposal is on screen and almost right? **`Tab`** (`settings.agent.keys.refine`) opens the instruction field again ("how should it
change?") and replaces the proposal with a new one that **starts from the previous code**: the model sees the original target,
the proposal and only what you ask to change. The old proposal never touched your buffer; the history links the new run to it.
Cost: about one ordinary run per round (your instruction is ~30 tokens, the previous proposal 100-300), instead of rejecting and
describing everything again.

The same key on an **answer** (explain / ask window) asks the next question about the same code with the
earlier questions and answers as the conversation (the oldest turns are dropped past ~4k characters). The answer window never takes
focus, so while it is on screen the key is also bound on the code buffer you are in (it goes away with the window; a proposal waiting in
that buffer gets the key back). Pressing it needs no `<leader>al` first.

## After accepting: verification

Accepting a proposal is no longer the end. `agent/verify` listens to the replace presenter's events and, for free:

1. remembers the buffer's **LSP and linter diagnostics before** the code is written (the agent's own findings do not count: accepting resolves those);
2. waits until the language server settles (`verify.settle_ms`, never more than `verify.max_wait_ms`) and compares: a diagnostic is
   identified by what it says (source, code, message), not by its line, so the same old warning one line lower is not new;
3. nothing new → one quiet line `✓ verified · no new problems`; something new → a question
   `fix regression 1/2`: it names the problems, the attempt, the model and the estimate. **Yes** launches a `fix regression` proposal
   over the function that holds them (same experience as any proposal, and verified again if you accept it); `verify.max_retries`
   (2) bounds the chain, `verify.auto_retry = true` skips the question (still bounded and still behind the spend guard);
4. a **build check** (`verify.command = "auto"`: `go build ./...`, `cargo check`, `py_compile`, `dart analyze` of the saved file
   in machine format (only its errors count, never warnings); or your own per language) runs when
   you **save** the accepted code, because a compiler reads the disk. Only the errors on or next to that code are blamed on it; the rest
   of the project's errors are counted, not guessed at.

Tokens: 0 unless you answer yes; then about 1.8 runs per attempt (the original prompt plus the errors). `docs` is excluded
(`verify = false`: only comments change).

## Several proposals at once

`fix all`, `fix from output` and multi-file plans share one engine (`agent/batch`):

- **One confirmation** with the total (`3 proposals · claude/sonnet · ~2.3k tokens · ~$0.0012`, the files and how many problems each
  holds). The budget guard is not asked again per piece, but a hard cap still stops the rest.
- The pieces run **one by one**; the statusline says `⠋ agent fix all 2/3`. If you cancel (`<leader>ax`) or the budget blocks one, the rest does not go on.
- Each piece is anchored (an extmark), so accepting something above it while it runs does not misplace it.
- The proposals wait in a **queue**: `<leader>aA]` / `<leader>aA[` jump between them across files, `<leader>aAl` lists them in the quickfix,
  `<leader>aAy` accepts them all after one question (each is its own `u`). Each proposal's hint ends with `2/4 · <leader>aA] next`.

**Fix all (`<leader>aAa`)** groups the file's diagnostics by the function (else the type) that contains them: three findings in one function
are **one** request. Sources and severity: `settings.agent.fixall` (agent findings, DDD violations, LSP/linters; `warn` and up by default).
Tokens: about one `fix block` run per affected function (5 findings in 3 functions ≈ 3 runs).

**Fix from output (`<leader>aAo`)**: the errors come from the last terminal buffer, else the quickfix list; `<leader>aAO` asks for a command
(the project's build by default), runs it and uses what it prints. They are parsed by Neovim's own `errorformat`
(go, tsc, cargo, python, javac, `flutter analyze`, `dart analyze` (human and `--format=machine`) and the generic
`file:line:col: message`), **0 tokens**; each piece sends only the errors of its function
(`<build_errors>`), not the whole output. At most `settings.agent.errors.max_errors` (20) errors are read.

## Multi-file plans

`<leader>aAp` on a type or function, then what should change ("add a Done flag to notes, through every layer"):

1. **Free**: where it reaches. Language-server references (completed with `git grep` when the server never leaves the starting
   file), collapsed to the **declarations** that hold the symbol (function or type, with its first line as the signature), capped by
   `settings.agent.plan` (`max_files`, `max_sites`).
2. **One request**: the instruction and only those signatures (never bodies; ~40 tokens per site) go to the model, which answers ordered
   steps `n|path|symbol|what`. Steps that name a file or symbol that is not in the list are dropped (the model inventing them).
3. **You**: the plan panel (`☑ 1. path · Symbol — what`). `Space` unchecks a step, `a` all/none, `Enter` runs the checked ones, `q`
   cancels. Its first line keeps the estimate up to date as you toggle.
4. **One request per step, in order**: each is a proposal for its declaration, with the overall plan (this step marked) and **what the steps
   before it proposed** as context, so step 3 uses the field that step 1 adds. They land in the queue above and are verified as you accept.

A snapshot (`git stash create`, nothing in your work tree changes) is taken first: `git diff <ref>` shows everything the plan changed and
`git checkout <ref> -- <file>` restores a file. Renames are better done with LSP rename (deterministic, 0 tokens); the plan is for semantic
changes. Tokens: plan ≈ 1-2.5k in, 300 out; each step ≈ 1 run; a 5-step plan is about 6 runs in total.

## Spend guard

Before every request (actions, batches, the staged review, plans) the **budget guard** (`agent/guards/budget.lua`, pure core in
`agent/budget.lua`) checks the size of what is about to be sent (characters ÷ 3.5 ≈ tokens) against `settings.agent.budget` and what
the history says you already spent. The price of a token is learned from **your own history with that model** (no price table).
Above `confirm_tokens` / `confirm_usd`, or near a cap, it **asks** (modal with the reasons); a used-up `day_usd` / `session_usd` **blocks**.
Every one-shot call (commit draft, staged review, plan) is recorded in the history too, so the spend is complete. The usage report
(`<leader>ah` → `⌃S`) gains a **Budget** line and **Suggestions**: actions you accept rarely (and what they cost), the share of the spend
that went to proposals nobody applied, and how often the verifier had to retry.

## Review before committing

`<leader>Gv` (or `⌃R` in the commit panel) reviews **what is staged**:

1. **Free checks** on the added lines: secrets (AWS/GitHub/Slack/OpenAI-style keys, private keys, `password = "…"` literals), merge-conflict
   markers, debugger/print leftovers per language (not in tests) and sensitive files (`settings.git.commit.sensitive`).
2. If there is real code to read (not only lockfiles, generated files, deletions or binaries) **one request** goes out with the staged
   diff **numbered by its lines in the new file** (`+L13` added, ` L12` context), within `git.commit.review_max_chars`. A finding must
   point at one of those lines or it is dropped as invented.
3. Findings land as **diagnostics** on their lines (open files at once; the others when you open them: they persist like any finding) with source
   `staged review`, and as a quickfix list. The panel's agent line says `review: 2 findings (quickfix)`.

Tokens: a typical commit (40-200 changed lines) is ~1.5-6k in and 100-600 out; a docs-only or lockfile-only commit costs nothing.

## Context for refactors and explanations

Two providers that are opt-in per action (they cost tokens): **`callers`** (refactor, the `api` lens): who calls the target, from the LSP
references, one short line each (`path:line  code`), at most `context.callers` (6) and two per file, so a refactor sees how the function
is really used before it changes a signature (~60 tokens each). **`gitlog`** (explain, review, refactor): the last `context.gitlog` (3)
commits that touched those lines (`git log -L`), one line each (~40 tokens): the "why is it like this" and "this was fixed before".

## Project conventions: `.agent.md`

An `.agent.md` at the root (or further up) is added to ALL prompts: style, preferred libraries, what to avoid. Max.
1500 useful characters. Example: `Idiomatic Go; errors with %w; no logs in pure functions; tests with testify.`

## Next edit (on demand)

Not autocomplete and not ghost text: **one key press** (`<leader>an`) asks the **light** model (a small local one through `light_backend` is
enough) for the edit you are about to make. What it sees: the lines around the cursor (`settings.agent.next_edit.window`, 30 each side) and
`<edits>`, your latest changes in this file as `-`/`+` hunks, oldest first.

- The changes are tracked by `agent/edits.lua`: a baseline snapshot per file buffer, compared with the buffer when an insert ends or a normal-mode
  change settles (one `vim.diff`; no model, no LSP, files over `next_edit.max_lines` are not followed). It keeps the last `keep` hunks and sends
  at most `max_chars` of them (the newest win).
- With nothing changed in the file it **asks nothing** (0 tokens, and says why). If nothing in the window clearly follows from your changes the
  model returns the window unchanged and you get "no changes".
- It is a normal `replace` proposal: inline diff, `⏎`/`⎋`, verification after accepting, history. Not cached (a proposal on live code).
- Why on demand: a streaming ghost-text subscription spends tokens on every pause; this spends them only when you ask.

## Answer cache (repeated questions are free)

A request is identified by everything the model would receive: system prompt, file, context sections, target, task, your
instruction, plus backend, model and effort (`agent/cache/`, pure logic in `cache/core.lua`). If the same request was answered
before, the stored answer comes back **with 0 tokens**, before the budget guard (nothing to ask about), and goes through the same
presenter (the status line says `cached · 0 tok · saved $…`). A hit is **not a run**: it never appears in the history (`<leader>ah`) or the spend report, since no model was called. Any change to the function, to a type
or diagnostic it reads, or to your instruction changes the hash, so a stale answer cannot come back.

- Kept by default: `text` and `findings` outputs (explain, ask, review, lenses). A `replace` proposal is never cached: asking again
  on live code should give a fresh one. An action can opt in or out with `cache = true|false`.
- Stored in `stdpath("state")/agent-cache.json`; the least recently used go past `max_entries`, and answers expire after `ttl_days`.
- `<leader>aAk` shows what the cache holds and has saved you (answers kept, times it answered, tokens and money saved: counters the cache keeps itself) and has a **Clear** button. `settings.agent.cache.enabled = false` turns it off.
- Tests must never share the real cache (a hit hides the call they count): `K.fake()` points it at a temp file.

## Project documents (`<leader>aS`): AGENTS.md, STACK.md, DESIGN.md, SPEC.md

The documents every coding agent (Claude Code, Codex, Cursor, opencode, this one) reads before it changes code, written at
the repository's root in the **same sections in every project**, so an agent always knows where to look. Lowercase keys use
presets or the project's own facts; uppercase ones take what you describe in your words and the model writes the document.

| Key | Document | How |
|---|---|---|
| `bb` | the project | **build with agent**, everything at once: reads the four documents (says which one is missing and its key) and builds the project in its own tab: one plan request, then one small request per file (only the documents it needs, the plan, the API of what is already written and the files it uses), then the manifest's own checks (Go: tidy, gofmt, build, vet, test) and up to 2 fix rounds for the files the errors name. One question before it starts (files, estimated tokens and cost, what it replaces, what the previous build left that this plan drops) |
| `bt` | the foundation | **build one layer** from STACK.md: manifest, layout, tooling, a minimal entry point that runs (below) |
| `bs` | the domain | **build one layer** from SPEC.md: entities, rules, use cases and their tests, no interface (below) |
| `bd` | the design | **build one layer** from DESIGN.md: theme, styles, components, screens, wired to the domain the project has (below) |
| `m` | SPEC.md | **modules**: what every app repeats (accounts, roles, lists, workspaces, notifications, audit log, uploads, import/export, offline, payments, subscriptions) merged into your SPEC.md, with edge cases, and questions where the answer is yours (below) |
| `bf` | one feature | **build one requirement** end to end: pick an FR of SPEC.md (`○` no test yet, `●` tested) or describe a new one, which becomes the next FR-n in SPEC.md (below) |
| `r` | a recipe | **prefab task** for your stack (a screen with its state, an endpoint, an entity with its repository, a form…): asks its values, then builds it on the project (below) |
| `v` | coverage | **0 tokens**: which FR-n have a test, what STACK.md names that the manifest lacks, DESIGN.md tokens no code uses, folders no document mentions (below) |
| `P` | records | PROGRESS.md and the decisions (ADRs) the builds wrote, with a preview |
| `B` | the project | check again: the checks and fix rounds on the files the last build wrote, as they are now (after you edit them, or after a restart; its list is kept per project in the state dir) |
| `/` | the library | every preset in one search (stacks, designs, their add-ons, principles) with its preview: `⏎` uses it (a stack or design opens its customize step; an add-on is merged into the STACK.md/DESIGN.md there; a principle is added), `^e` embeds its text under your cursor, `^y` copies it, `^o` opens the preset file (to read it or make your own from it) |
| `o` | all four | which are there (`●`) and which are missing; Enter opens one or starts it |
| `a` | AGENTS.md | the model reads the project (file tree, languages, manifests, Makefile targets, `package.json` scripts, README, the other documents) and writes how to work in it: real commands, layout, conventions, workflow, boundaries, definition of done. With one there it **updates** it, keeping what is still true |
| `A` | AGENTS.md | the same sections without a model (0 tokens): commands detected from the Makefile and manifests, top folders, general rules, `TODO:` lines for what only you know |
| `c` | CLAUDE.md | Claude Code reads CLAUDE.md, not AGENTS.md: creates one that imports it (`@AGENTS.md`), or adds that line to yours |
| `t` | STACK.md | preset: kind of project → stack (with a preview) → **customize** → principles. Kinds: backend (Go stdlib / chi / Fiber / Huma / gRPC / workers, Bun + Hono / Elysia, Hono, NestJS, FastAPI, Axum, tonic, Spring, Ktor), web (Next.js, React + Vite, Vite vanilla, Solid, Preact, Alpine.js, Lit, SvelteKit, Astro, Nuxt), full stack (Go + templ + htmx, Bun full stack, Leptos, Next.js + Supabase, T3, Django + htmx, Laravel), mobile (Flutter with Riverpod, Bloc, Supabase, Firebase, offline-first, desktop or no package; Expo, SwiftUI, Compose), self-hosted (Go + SQLite + Litestream, PocketBase, Docker Compose stack, Bun + SQLite), monorepo, CLI / desktop / TUI (Bubble Tea, Wish over SSH, Ratatui, cobra, clap, Tauri) |
| `T` | STACK.md | described ("Go API for invoices, Postgres, self-hosted"), then customize (the add-ons that fit the words you used) and principles; the model writes it knowing the add-ons, and they are merged after |
| `k` | STACK.md | customize the one there: add deploy, CI, observability… (those already in it come checked) |
| `p` | STACK.md | change the principles it carries: the section is rebuilt from the presets you check |
| `d` | DESIGN.md | kind → design (with a preview) → **customize**. Design systems (Material 3, M3 Expressive, Cupertino, Ant Design, Fluent 2, Carbon, Primer, shadcn/ui, Notion, Linear), styles (neo-brutalism, Swiss, retro pixel, glass, mono minimal) and terminal / TUI (ASCII art, Braille, brutal, classic, retro CRT, modern Charm-style) |
| `D` | DESIGN.md | described ("like Linear but warmer", "an ASCII art TUI with amber phosphor"), then customize; a design you name is sent as the base, a terminal description gets the terminal add-ons |
| `w` | DESIGN.md | **screens**: one request draws a wireframe of every main screen SPEC.md names (and the states that change the layout: empty, error, too small) in DESIGN.md's own style, character by character at the minimum size, with what each region uses and how it adapts; written as its `## Screens` section (replaced when there is one, the old file to the trash). Needs SPEC.md and DESIGN.md. Models copy a picture far more faithfully than prose, so the build lays screens out as drawn |
| `s` | SPEC.md | write what you are building in any shape; it comes back as a spec: requirements `FR-n` with Given/When/Then acceptance criteria, non-functional `NFR-n`, data, interfaces, edge cases, milestones, and **every gap as an open question** (never invented). With a SPEC.md there, the page starts from it: edit freely and it comes back tidy, ids kept |

**Customize** is one list in groups, merged into STACK.md without a model (rows replace the row with the same first
word, rules and commands are added once, so applying twice changes nothing). It opens with **the best picks for that stack
already checked** (an add-on's `<!-- default: … -->`: in a one-of group the most specific match wins, the stack itself over its
language over its category), so Enter alone gives a complete setup; change or uncheck what you want. Round marks (`●`/`○`)
are one-of groups, squares (`■`/`□`) take any number. Only the add-ons that fit the stack are listed (its main language is
read from the Stack table, so a Go API is never offered TypeScript tools).

The customize step is a **full-screen marketplace** too (the same keys): the choices by group on the left (`●`/`○` one-of
groups, `■`/`□` any number), the add-on under the cursor on the right (what it is and what it writes: its Stack rows,
conventions, commands, rules), and under both what the choice sets (`sets the rows Database, Auth…`). `p` shows exactly the
text the document would gain, `Space` picks (in a one-of group the others go off), `⏎` goes on, `Esc` goes back, `/`
filters, `Tab` folds a group, `?` lists the keys. `<leader>aSk` opens it on an existing STACK.md and `<leader>aSK` on an
existing DESIGN.md.

**Esc goes back one step** (Principles → Customize → stack → kind of project; in `T`, Customize → the page with what you
wrote), keeping what you chose; Enter moves on. Only the first step's Esc closes.

| Group | Choices |
|---|---|
| Package manager (one of) | Bun or npm instead of pnpm: every command, the lockfile and the Stack row are rewritten |
| TypeScript | TypeScript 7 (the native `tsc`, ~10x faster type checks) |
| Lint and format (one of) | Biome, Oxlint, strict ESLint + typescript-eslint |
| Styling (one of) | Tailwind CSS 4, CSS Modules + tokens, UnoCSS |
| Database (one of) | Postgres, SQLite, MySQL, MongoDB, Turso |
| Data access (one of) | Drizzle, Prisma, sqlc, sqlx, SQLAlchemy |
| Auth (one of) | Better Auth, Auth.js, Clerk, Supabase Auth, OIDC (Keycloak/Auth0/Entra), own session cookies |
| Payments (one of) | Stripe, Lemon Squeezy, RevenueCat |
| Email (one of) | Resend, Postmark, SES, SMTP |
| File storage (one of) | S3-compatible (S3, R2, MinIO), Cloudinary, local disk |
| Search (one of) | Meilisearch, Typesense, Postgres full-text |
| Background jobs (one of) | BullMQ, River, Celery, Inngest, cron only |
| Realtime (one of) | WebSockets, Server-Sent Events, Ably |
| Internationalization (one of) | i18next, Flutter gen-l10n, gettext, go-i18n |
| Analytics and flags | PostHog, Plausible, OpenFeature |
| Unit tests (one of) | Vitest, Jest, pytest, Go + testify, cargo-nextest |
| End-to-end tests (one of) | Playwright, Cypress, Maestro |
| Deploy (one of) | Docker self-hosted + Caddy, Coolify, Fly.io, single binary + systemd, Kubernetes, Cloudflare, Vercel, stores with fastlane, GoReleaser, cargo-dist |
| CI (one of) | GitHub Actions, GitLab CI, Forgejo / Gitea Actions |
| Observability | OpenTelemetry, Prometheus + Grafana, Sentry |
| Quality | lefthook, Renovate, Dev Container, mise, Nix dev shell |

**DESIGN.md customize** works the same way (best picks checked, Esc back), with its own groups:

| Group | Choices |
|---|---|
| Platforms | web responsive, mobile app, desktop app; TUI only, narrow terminals (Termux, Blink) |
| Theme (one of) | dark + light, dark, light, high contrast; inherit the terminal (ANSI roles, `NO_COLOR`) |
| Palette (one of) | brand (tints from one color), Gruvbox, Catppuccin, Nord, Tokyo Night, monochrome, phosphor green / amber |
| Motion (one of) | none, subtle, expressive; terminal animations (spinners, typewriter, frame budget) |
| Effects | ASCII gradients, CRT, grain, glass blur, dithering, neon glow; **hero art** (ASCII art, Braille, synthwave, retro: the art is the app's identity, so the main screen carries it, framed and centered, its value also in plain text) |
| Glyphs (one of) | Unicode box + Braille, Nerd Font, ASCII-safe |
| Density (one of) | compact, comfortable, spacious |
| Accessibility | reduced motion, color-blind safe, screen reader, WCAG AAA |
| Toolkit (one of) | how the design is written in code, as a `## Toolkit` table (token → code): Charm (Lip Gloss: one styles file, `Place` to center, `Join` to compose, Harmonica), Ratatui, Textual, Ink; Tailwind CSS v4, CSS variables, Flutter theme. Checked from the project's STACK.md: Go → Charm, Rust → Ratatui, Python → Textual, a Tailwind stack → Tailwind |

A terminal design is a real DESIGN.md for a TUI: colors as ANSI 16 / 256 / truecolor roles with fallbacks, typography as
monospace cells and glyph sets, spacing in cells, borders as box drawing, motion as frames.

**The build** (`b…`) is an orchestrator you can watch, steer, leave and come back to. It builds the whole project (`bb`)
or **one layer** from the document that describes it, with the same letter that document has in this menu:

| Key | Layer | Reads (required first) | Builds | Skips |
|---|---|---|---|---|
| `bt` | foundation | STACK.md, AGENTS.md | manifest, folder layout, formatter/linter/test config, Makefile or scripts, a minimal entry point that builds and runs, one smoke test, README (15 files at most) | domain logic, screens; the wiring check and the use phase |
| `bs` | domain | STACK.md, SPEC.md, AGENTS.md | entities, value objects, rules, errors, use cases and ports where STACK.md's layout puts them, each with tests that prove its FR-n; in-memory adapters only when the tests need them | the interface and the entry point; the wiring check (nothing calls the domain yet, by design) and the use phase |
| `bd` | design | STACK.md, DESIGN.md, SPEC.md (when there), AGENTS.md | theme or tokens, styles, components and screens (as `## Screens` draws them), wired into the entry point; it **calls** the domain the project has, sample data when there is none | nothing: the wiring check, the use phase (with SPEC.md) and the look all run |

A layer is built **on top of what the project already has**: the plan request gets the existing files as `<project>` (their
paths, the manifests whole, the API the code declares), every file request sees that API and the existing files it uses,
and an existing file the plan has to change (the domain adds a dependency to `go.mod`, the design makes `main.go` open the
screens) is sent as it is and comes back whole. The review shows those as replaced. Usual order: `bt` → `bs` → `bd`, each
reviewed before anything is written; any of them alone works too (a domain on an empty folder plans its own manifest).
Each layer keeps **its own saved run** and its own list of the files it created: a replan of the domain only drops the
domain's old files, `X` sends only the files that layer created to the trash (the ones it only changed stay), and the
foundation's run is never touched by the domain's. The tab's top line and the statusline name the layer
(`domain · from SPEC.md`, `⠹ build domain 3/9`).

**One feature at a time** (`bf`): after the first build, most work is a new feature. The picker lists the requirements
of SPEC.md with whether a test proves them yet (the preview opens SPEC.md at that requirement), and **＋ new** first:
- **An existing one** opens the feature build with that requirement's text: its line to the next requirement, plus every
  other line of SPEC.md that names it (its edge cases, its open questions).
- **A new one**: you describe it on the draft page in your words; one request (main tier, SPEC.md as context) turns it
  into a requirement (title, "The system must…", 2-6 Given/When/Then criteria, edge cases, the questions only you can
  answer). A confirmation shows it; **Add and build** writes it into SPEC.md **in the document's own style** (heading
  `### FR-n:` or bullet `- **FR-n**`, the next free id), its edge cases under `## Edge cases` and its questions under
  `## Open questions` (numbered on from the last `Qn`); the old SPEC.md goes to the trash.

The feature build plans the smallest set of files that makes the requirement work for the user: the domain it needs,
the interface that reaches it (when there is one), the tests of its acceptance criteria, **following the patterns the
code already uses** (same folders, naming, state management, error handling), on top of the project as it is
(`<project>`, like the layers). Existing files it changes come back whole and keep what the rest uses. The wiring check
and the use phase run, with scenarios **from that requirement alone**. Features are additive: one feature's replan or
clean never touches another's files. One feature run is kept at a time; picking another requirement starts afresh.

**SPEC.md modules** (`m`, 0 tokens): your SPEC.md stays yours (you write the core of your business); the modules add the
well-known parts you would otherwise forget. It opens as a small **marketplace on the whole screen**: the modules by group
on the left (`□` not picked, `■` picked, `+` comes with what you picked, `✓` already in SPEC.md), the one under the cursor
on the right (what it is, its requirements with their criteria, edge cases, and the questions that are yours), and under
both what SPEC.md would get from your choice (the modules, the FR range, the counts, what came in because another needs it).
Nothing is written until you add, and the confirmation sums it up first (the old SPEC.md goes to the trash; cancelling it
brings you back to the marketplace as you left it).

- **List**: `j`/`k` move, `Space` picks, `⏎` reads and customizes, `p` shows what SPEC.md gets, `/` filters by name,
  description, key or requirement title, `{`/`}` jump between groups, `Tab` folds a group (on a folded title it unfolds
  it), `h` hides what SPEC.md already has, `t` / `d` open the STACK.md add-ons / DESIGN.md patterns it goes with
  (below), `A` adds, `?` lists every key, `q` closes. `★` marks a module your SPEC.md already talks about without
  having it (a word of its name or one of its requirement titles appears in the text: 0 tokens), and its pane says
  which word.
- **Read and customize** (`⏎`): `j`/`k` scroll, `Space` keeps or leaves out the requirement under the cursor (its edge cases and
  questions go with it; leaving every one out drops the module), `Esc`/`h` back to the list.
- **What SPEC.md gets** (`p`): exactly the text that would be added, as it would read, with what you left out missing; `Esc` goes back.

| Group | Modules |
|---|---|
| Every app | accounts and sign-in (sign up, sign in, reset, verification, lockout) · roles and permissions (ownership, changing roles) · lists (pagination, empty states, search and filters, delete with undo and a trash) · profile and preferences · first run and onboarding (empty states) · loading, errors and feedback (waiting, failures, undo) · privacy and personal data (consent, export, deletion) · languages, time zones and currencies · reviews and ratings · favorites and wishlists · multi-step flows · bulk actions |
| Teams | workspaces and invitations (data kept apart, members, leaving) · notifications (in-app, email/push, preferences, unsubscribe) · comments and mentions · sharing and links (people, links, expiry) · activity feed · chat and direct messages · tasks and boards · calendar and booking · contacts and CRM · support tickets · newsletter |
| Data | audit log · file uploads · import and export · offline and sync (queued changes, conflicts) · version history (compare, restore) · dashboards and reports · tags and categories · background and scheduled jobs (retries, never twice) · public API and webhooks (keys, signed events, limits) · forms and surveys · content publishing · media gallery · maps and location |
| Money and commerce | payments (checkout, receipts, refunds, idempotency, webhooks) · subscriptions (plans, trials, renewals, grace period, upgrades, cancelling) · cart and checkout (orders, stock) · invoices and receipts (numbering, credit notes) · coupons and promotions · product catalog · inventory · seats and billing |
| Security | two-step sign-in and sessions (second factor, devices, recovery) · limits and abuse protection (rate limits, guessing, reports, blocking) |
| Platform | back office (finding records, acting with care) · feature flags and settings (gradual release) · single sign-on |
| Quality | accessibility · performance · reliability and backups · observability |

How a module goes in:
- Each requirement gets the **next FR-n in SPEC.md's own style** (heading or bullet) with its Given/When/Then criteria;
  its edge cases go under `## Edge cases` and its questions under `## Open questions` (numbered on from your last `Qn`),
  tagged with its id.
- **Questions, not invented rules**: lockout limits, roles, taxes, grace periods… come as questions; the build's plan
  decides them explicitly until you answer.
- A requirement **you already wrote** (same title, any case or punctuation) is kept as you wrote it, and the module's
  edge cases and questions for it are tagged with your id.
- `needs:` pulls what a module builds on (subscriptions → payments → accounts, needs first) and the confirmation says so.
- `<!-- module: accounts -->` marks where a module went in: applying it again adds nothing. Nothing is ever removed.
- Then each new requirement is a `○` in `bf` (build it) and in the coverage (`v`).

Modules are plain files in `agent/kit/presets/spec/<group>/` (`## Requirements` with `### Title`, "The system must…" and
criteria; `- [Title] …` edge cases and questions; `<!-- needs: … -->`). They are also in the library (`/`), where the
search looks at their requirement titles too (`refund` finds payments).

**Starter kits** open the list of the marketplace: a product type as a set of modules (SaaS for teams, marketplace, online
store, internal tool, blog, booking, community, support desk, API product, consumer mobile app, project tool, forms and
surveys). `Space` on a kit picks all its modules (`◧` = some picked), `⏎` goes to the first one, and its pane says who it
is for, what it adds and the decisions to take first. They are files too: `agent/kit/presets/spec-kits/<id>.md` with
`<!-- modules: key key … -->`.

**Narrow terminals** (under 100 columns): the list and the pane take turns on the whole screen: `⏎`/`l` opens the pane,
`Esc`/`h` gives the list back.

**What a module goes with**: every module (and kit) names the STACK.md add-on axes and the DESIGN.md screen patterns it
pairs with (`<!-- tech: auth email -->`, `<!-- design: forms auth-screens -->`), shown in the pane under "Goes with":
accounts → Auth, Database, Email · Forms, Auth screens. The names are the library's own (`<leader>aSt` / `<leader>aSd`
customize steps), and a test checks every name exists. In the marketplace `t` opens the STACK.md add-ons **over it**
(the groups that go with what you picked marked `★`, the cursor on the first; with nothing picked it uses the module or
kit under the cursor) and `d` the DESIGN.md add-ons with those screen patterns already checked; closing them puts you
back in the marketplace with your picks. They need a STACK.md / DESIGN.md in the project. DESIGN.md has a new group, **Screen patterns** (forms, data tables,
empty states, onboarding, settings, navigation shell, toasts, dialogs, command palette, search and filters, dashboards,
auth screens, pricing and checkout, comments, file upload, notification center).

**Recipes** (`r`): prefab tasks, plain Markdown files in `agent/kit/presets/recipes/<group>/` (add your own: the header
of the presets plus one `<!-- input: key | question -->` line per value, and a body with `## Make`, `## Rules`, `## Tests`
using `{{key}}`, `{{key_snake}}`, `{{key_camel}}`, `{{key_pascal}}`, `{{key_kebab}}`). Only the recipes whose `for:`
fits STACK.md are listed (`go+server` = both, `go+!server` = a Go project that is not a server). Picking one asks its
values, fills it and opens the recipe build: the recipe says **what** to make, STACK.md and the existing code say
**where and how** (its paths are only a hint when the project already does it differently). Recipes skip the wiring check
and the use phase. They are also in the library (`/`).

| Group | Recipes |
|---|---|
| flutter | screen with its state (Riverpod Notifier or Bloc/Cubit), route and widget test · data feature (model, repository interface + implementation, provider) · form with validation · list and detail |
| go | HTTP endpoint (handler, service, route, httptest) · entity with its repository (port, in-memory + SQL adapter, contract tests) · CLI subcommand · Bubble Tea screen (teatest golden) |
| web | UI component (states, tokens, accessibility) · page with its route and data · data table · validated form · settings page |
| general (typical features) | CRUD resource · auth flow · search endpoint · background job · webhook receiver · file upload · transactional email · feature flag |
| typescript, python, rust | API route / HTTP endpoint with validation, service and tests |
| general | module with its tests (any stack) |

**Coverage** (`v`, 0 tokens): a report in a split, read from the documents and the code:

| Section | How it is checked |
|---|---|
| Requirements | every FR-n of SPEC.md's Requirements; proved when a test file names it (`FR-3`, not `FR-30`) or a build plan's `verifies` does and that file exists. `⏎` on an untested one opens its feature build |
| STACK.md names the manifest lacks | package.json: the tools the build knows; pubspec.yaml, go.mod, Cargo.toml, pyproject.toml: the package names the Stack table writes in backticks |
| DESIGN.md tokens no code uses | the first column of the Color tables and every `--css-variable`, searched in every spelling (`text-muted`, `text_muted`, `textMuted`, `TextMuted`) |
| Folders no document mentions | top-level folders and those one level under `lib/`, `src/`, `internal/`, `cmd/`, `app/`, `pkg/`…: the layout drifted from STACK.md |

`⏎` opens the place a line is about, `r` reads again, `q` closes. Ask tests to name the requirement they prove
(`// FR-3: …`): the builds' tests do.

**Records** (0 tokens, `settings.agent.kit.build.adr` / `.progress`):
- **Decisions** (`docs/adr/NNNN-title.md`): when a review is accepted, the plan's decisions that no earlier ADR records
  are written as one ADR (Status, Context, Decision, Consequences: the files created and changed) and indexed in
  `docs/adr/README.md`. A build that decides nothing new writes nothing. **Every later plan follows them**: the
  decisions still in force go to the plan request as `<decisions>` (oldest first; the newest kept past ~4000 characters),
  and the plan lists only new choices. When a build truly must reverse one, the plan says so as a decision of its own
  (`Supersedes ADR 0002: Bloc for state because …`): its ADR's Status says `supersedes ADR 0002`, the index marks 0002
  `superseded by 0005`, and 0002 is no longer sent to plans. An ADR is never edited. The feed's plan line says how many
  it followed (`follows 3 ADRs`).
- **PROGRESS.md** at the root, rewritten whenever a run settles: `Now` (the last build, how it ended, how to resume it),
  `Done` (a log, one line per finished build, kept across rewrites), `Open` (files not written, failing checks, issues the
  use phase found, SPEC.md's open questions), `Next` (the requirements no test proves yet). Any agent reads it to go on
  where the last one stopped.

Both are linked from AGENTS.md's "Read first" the first time, and neither is ever read as code by a layer build.

| Phase | What happens | Your keys |
|---|---|---|
| ready | pre-flight: the four documents and their size, the model of each phase (plan · files · fixes · use, each on the main or light tier of `<leader>am`), fix rounds, what the plan request will cost | `⏎` plan · `1` `2` `3` `4` tier of each phase · `+` `-` fix rounds |
| plan | one request writes the build's **contract**: how it works, the architecture and dependency direction, the key decisions (and the SPEC questions it had to assume), then every file in order with what it does, **what it exports and promises** (`NewKeypad() — the highlight starts on =`), what a test verifies (FR-n), the documents it needs and the files it uses, and **the wiring**: one row per requirement from what the user does to what runs to what they see and in which file (`FR-2: presses + → ui.Update → ChooseOperator → view.go shows "12 +"`), so a feature never stops at the domain. The contract goes to every file request (cached), so files written apart agree. Shown as plan.md in the code pane **while it is made**: first what the model read and its thinking steps (the CLI streams the thinking without its text on subscription accounts), then each section and file as it arrives. Long lines wrap: nothing scrolls sideways | `x` stop |
| review | the plan with an estimate per file and in total (with and without the cache), what it replaces, leftovers of the last build. **This is the confirmation**: nothing is written before `⏎` (an Enter that arrives as the review appears, typed ahead or pressed twice, is ignored) | `⏎` build · `x` skip a file · `2` `3` tiers · `n` new plan · `p` the plan request |
| write | one request per file; the code pane types each file out, the feed says what went in and what it cost | `x` stop · `q` hide (it goes on) · `p` the request of the file under the cursor |
| check | the manifest's own tools plus free consistency checks (below), then **the interface uses what the plan exports**: a function the plan promised to other files that only its own file or a test calls (`Calculator.Expression()` implemented and tested, never drawn) fails the check and goes to a diagnosis like any error (0 tokens to find; values nobody uses, a style or a color token, are only context for the use phase) | |
| use | when every check passes, **the app is used like its user would**. One request (the `use` model) writes scenarios from SPEC.md (flows, Given/When/Then, edge cases, the state the user needs mid-flow) and DESIGN.md (its smallest size): steps and what each must show, the expectations from the documents, never from the code. A driver performs them: **terminal UIs** in a private tmux at the scenario's size, keys one at a time like a person types; **command lines** run once per step (output, errors, exit code); **web apps** (dev server, static page, the project's own server) and **Electron** in Playwright, read as a screen reader would plus the layout problems measured in the page (sideways scroll, controls out of the window, overlaps, targets under 24 px, cut text) and the JavaScript errors; **Android** over adb on the device or emulator you started (uiautomator hierarchy + screenshot). Every step is checked for free (texts that must and must not show, exit codes, crashes, actions with no visible effect); one verdict request reads the scenarios as the user lived them and names what to fix (blocker, major, minor). Fixes go like a diagnosis' files, the golden snapshots are written again, and **the same scenarios** are replayed: `use_rounds` fixes at most (2), the last play only reports. The frames and screenshots stay in the state dir (the feed says where). An app that cannot be driven here (no tmux, no Playwright, no device) skips to the look at 0 tokens; off with `settings.agent.kit.build.use = false` | |
| look | then **the screens as they render** (Go teatest golden files: exactly what the terminal shows, colors stripped) go to the model with DESIGN.md (its Screens wireframes first when it has them; never invented) in one request (cached system prompt, ~$0.006). What differs (not centered, cut off, a missing frame) is fixed in the code like a diagnosis' files, the golden files go to the trash, the checks write them again and they are **looked at again**: `look_rounds` looks at most (2: one fix, verified). `r` stays at 0 tokens; off with `settings.agent.kit.build.look = false` | |
| fix | rounds go on **while they make progress** (the failure changes), up to 8; they stop after `max_fixes` rounds in a row that change nothing (the `±` keys), and a round that changed nothing escalates the next one to the main tier with more effort. Each round: first a **diagnosis**: one request sees the tool's output, the API (with each declaration's doc comment) and the files involved, and names the root cause and every file to change, including files the errors do not name (a test fails, the bug is in the code it tests). Then each of those files is fixed with the diagnosis and its own instruction, the code before the tests. A fix answers with **edit blocks** (`<<<<<<< SEARCH` the exact current lines `=======` the new ones `>>>>>>> REPLACE`, applied here; `UNCHANGED` when the file is right): a few hundred output tokens instead of the whole file. A block that does not match the file, an answer much shorter than the file (a fragment taken for it), leftover block markers, prose or tool-call markup, or "unchanged" for a file the diagnosis said how to change are caught **before anything is written** and asked again once (after blocks that do not apply: for the whole file); still wrong, the file stays as it was. A fix that weakens a test (fewer assertions or waits, a new skip) is **refused** and the test stays as it was; a check whose tool does not run sends the manifest. A file the plan missed (an asset `go:embed` reads) can be created by the diagnosis (`"new": true`, a safe path, 2 at most). Every repair (the checks, each use or look fix) has its own rounds; after a use fix the diagnosis gets what the user met (`<user>`): a test that expects the opposite locks the bug in and its expectation changes, not the code back | |
| done | ✓ or ✗, totals, every file with its lines and cost | `⏎` opens a file · `r` checks again · `n` new plan |

- **The tab**: on the left the phases as chips (done ones green, the current one with a spinner, the next ones faint), the progress
  bar, then the files (the one being written on a full-width band, like the agent's inline target) and the checks; models
  and documents only before it writes. The code (`c` shows/hides it) and the feed (`f`) on the right; with both hidden only
  the list advancing is left (`settings.agent.kit.build.view` sets which panes it opens with). The statusline of the tab
  is its own (a lualine extension): the phase as the mode chip in the color of how it stands (red failed, yellow stopped,
  green done), the keys of the moment (as many as fit, most useful first), then progress · money (and cache · time when
  the screen is wide).
- **Reading and moving**: `z` puts the code pane alone on the screen with the cursor in it (the plan, a file, a request) and
  `z` again brings the panes back; `l` hides or shows the files, `c` the code, `f` the feed; `Tab` / `Shift-Tab` move the
  cursor between the panes; `P` shows the plan (plan.md, rendered) at any moment.
- **Start over**: `n` plans again right away (the files of the old plan stay; the new review says which it replaces and
  which leftovers go to the trash). `X` cleans the build after a confirmation that lists them: every file it wrote goes to
  the trash (`<leader>Fu` brings them back), empty folders it made are removed, the saved run is forgotten; the four
  documents are never touched.
- **Nothing is lost**: the run is saved after every step. Closing Neovim with a plan in review and running `<leader>aSbb`
  (or the layer's key) again brings the review back with the plan on screen; a run stopped mid-write continues from the first file not written.
- **Leave it running**: `q` closes the tab, the build goes on; the statusline shows `⠹ build 7/25 · $0.031` from any buffer,
  a notice says how it ended, its key (`<leader>aSbb`, or the layer's) brings the view back exactly where it is.
- **Resilient**: the run is saved after every step (state dir, per project). Closing Neovim mid-build and opening it again
  offers to continue from the first file not written; the spend so far is kept.
- **Transparent**: money, tokens in/out, the share read from the cache and the time, live; per file its lines and cost;
  `p` shows the exact request (system prompt and message) a file was written from; every request is also in `<leader>ah`.
- **Clean answers**: a model that wraps the file (a ``` fence with a sentence around it, the prompt's `<file>` tags echoed,
  tool-call markup leaking from the CLI, "I'll make the file…" before the code) is cleaned before anything is written; when
  it is still not a file (Go without `package`, JSON that does not parse, markup left) the request is asked again once with
  the reason. A broken fix never replaces a file that was a file. Each of these used to cost a full fix round.
- **Cheap**: every file and fix request shares ONE system prompt (all four documents + the plan), so the backend caches it
  once and every later request reads it at a tenth of the price (measured with claude/haiku: ~20k of ~25k tokens per request
  from the cache); the message carries only the file's focus, the API of what exists and the files it uses.

Checks (never commands written by the model): Go `go mod tidy` · `gofmt` (fixes itself) · `build` · `vet` · `test`; Node/Bun
`package.json has STACK.md's tools` (Vite, Vitest, TypeScript, Biome… named in the Stack table) · install (the package
manager STACK.md names when there is no lockfile yet) · `every id the code looks up exists` (HTML vs `getElementById`,
`querySelector('#…')`, `*_ID` constants) · `every control the page declares is handled` (a `data-action`/`data-key`/`data-op`
name such as `equals` that no script handles: the button does nothing while every unit test passes) · `every stylesheet and module is used` · `tsc --noEmit` · the `lint` (Biome/Prettier
fix format themselves), `build` and `test` scripts; Python `uv sync` · compileall · ruff · pytest when declared; Rust, Dart
and Flutter their build/analyze. A Go module version the model invented (`invalid version: unknown revision`) is dropped
with `go mod edit -droprequire` and `go mod tidy` writes the real one (0 tokens; `go.mod` is asked without a `require` block,
and the plan never lists files tools generate: goldens, lockfiles, build output). Formatters (gofmt, Biome, Prettier) run
again after every fix round. Missing golden files (snapshot tests run for the first time) are created by running those packages' tests with
`-update` (no tokens; review `testdata/*.golden`), then the checks run again. A build is **done** only when every check
passes; otherwise it ends **failed** with the fix rounds it tried.

Measured fix (claude/haiku): ascii-calc's keypad opened on "7" so Enter typed a 7 and three UI tests failed; the
diagnosis named `keypad.go` (not in the errors), one fix there, tests untouched, every check green: 2 requests, $0.008.

Measured on two projects (claude/haiku): a 25-file Go TUI and a 23-file Vite + TS 7 + Bun web app each cost about
**$0.08–0.10** in total, documents, plan, files, checks and fix rounds included, in 7–8 minutes. Known limits: the use phase
reads screens as text (terminal cells, the accessibility tree and measured layout, the Android hierarchy): colors and
pixel-level looks still need your eye (the screenshots are kept for that); native desktop toolkits (GTK, Qt, Flutter
desktop) and iOS have no driver; library APIs the model knows badly can be invented (a fix round usually repairs them).

**Principles** are presets too, appended to STACK.md as `## Engineering principles` (one `###` each): SOLID, Clean Code,
one file one responsibility, hexagonal, testing, error handling and security are checked by default; Clean Architecture, DDD,
Twelve-Factor, observability, API design, performance, functional core, accessibility, git workflow and documentation are one
Space away. The model writing a STACK.md only gets their names (to keep the layout consistent); their text is the preset's.

- **Never in silence**: a document that is there is replaced only after a yes, and the old one goes to the trash (`<leader>Fu`
  brings it back). A file with unsaved changes in a buffer is never written under.
- **The page** (`s`, `D`, `T`) is a Markdown float: `:w` or Ctrl-s sends it, `q` closes it; what you wrote is kept for the
  session, so closing it or a failed request loses nothing.
- **Linked**: creating STACK.md, DESIGN.md or SPEC.md adds its line to AGENTS.md's "Read first".
- **Language**: the documents are written in `settings.agent.kit.language` (English by default) whatever language you write
  the description in: the model translates it and keeps names and domain terms. Measured with Haiku: Spanish drafts came
  back fully in English (they came back mixed before the rule was moved to the end of the request).
- **Facts vs choices**: AGENTS.md and SPEC.md never invent (a gap is a `TODO:` or an open question); STACK.md and DESIGN.md
  are choices, so the model makes them, marked `(proposed)` with the reason, and keeps `TODO:` for what only you know.
- **Commands** come from what the project declares: the Makefile's targets first, then the lockfile's manager (npm/pnpm/yarn/bun,
  uv/poetry/pdm/pip, Go, Flutter/Dart, Cargo, Maven/Gradle wrappers, Swift, Deno, Composer, Bundler) and only the tools a
  manifest names (no pytest or ruff guessed).
- **Cost**: the model ones run once on the main tier (`kit_agents`, `kit_stack`, `kit_design`, `kit_spec`, reassignable in
  `settings.agent.tiers`), through the spend guard and into the history (`<leader>ah`); presets and `A`/`c`/`p` cost 0 tokens.
- **Your own presets**: drop a Markdown file in `lua/agent/kit/presets/design/`, `stack/<category>/` (a new folder is a new
  category), `addons/<group>/` (`<!-- for: ts web -->` says which stacks it fits: tags from the stack's words, `presets.tags`) or `principles/`, starting with `<!-- name: … -->` and `<!-- desc: … -->` (`<!-- core: true -->` checks a principle
  by default). `scripts/test-kit.sh` checks every preset has its document's sections.

## Merge conflicts (`<leader>Gx…`, inside a repository)

git-conflict.nvim already chooses ours / theirs / both and jumps between conflicts (`<leader>Go T B N n p l`). The agent adds
what it cannot do:

| Key | What it does |
|---|---|
| `xt` | **trivial** conflicts for free (0 tokens): both sides made the same change, or (with `merge.conflictStyle = diff3`) only one side changed anything; trailing whitespace does not count |
| `xr` | the conflict under the cursor (or the next one) to the agent |
| `xR` | every conflict of the file (the trivial ones first, for free): ONE confirmation with the estimate, one proposal per conflict, reviewed in the proposal queue (`]`, `[`, `Y`) |
| `xf` | the files git lists as unmerged, with how many conflicts each holds |
| `xs` | `git add` of the current file once no marker is left (asks first) |

Each conflict is sent with the story of the merge, read from git and never changed: which operation is in progress (merge,
rebase, cherry-pick, revert) and which branches, what each side did (commit subjects touching that file), and what each side
changed in the file against the common ancestor (stages 1, 2 and 3 of the index). The result has no markers; where both sides
changed the same thing differently it combines them and says how in the note, and it never drops a side's change silently.
Nothing is written until you accept the inline diff. Knobs: `settings.agent.conflict` (conflicts per batch, characters of each
diff, commit subjects).

## Doctor (`<leader>aX`): the app does not build, does not start, or dies

A troubleshooting agent for failures that are not one more squiggle in a function: a build that breaks, a server that will not
start, a crash at runtime, a project that is off before you compile. Hand it the failure the easy way:

| Key | Evidence |
|---|---|
| `xx` | the best at hand: the last terminal if it holds errors, else the quickfix list, else the clipboard, else it asks you to describe it |
| `xp` | the clipboard (copy the error, press this) |
| `xc` | a command it runs for you, captured: the project's own build/test/run commands, `docker compose logs`, or one you type (a command that passes says so and stops) |
| `xd` | in your own words (a page to write on); the last terminal rides along when it looks like errors |
| `xl` | the end of a log file of the project (or any path) |
| `xs` | (visual) the selected lines |
| `xh` | **before compiling**: what the language servers already flag in the project plus every free check below |
| `xr` | reopens the last case of this project |

How it works, in this order, and what each step costs:

1. **Evidence, free.** Colors off, repeated lines folded into a count, **secrets blacked out** (passwords, tokens, API keys,
   bearer headers, `user:pass@host`, AWS/GitHub/Slack keys, private keys), the long middle cut so the lines around the first
   errors and the end of the output survive, the **stack frames that point into the project** turned into code excerpts
   (Go, Node, Python, Rust, Java… `file:line`; a Python traceback puts the culprit first; `node_modules`, `vendor`, venvs and
   the standard library are skipped), the toolchain versions the project uses (Node, Go, Python, Rust, Java, Dart, Docker…) and
   what git says changed lately (status, last commits, the size of the uncommitted diff: "it worked before" starts there).
2. **Known causes, free.** A table of the usual suspects matched on the output (a missing module, a port in use, the Docker daemon
   down, `ECONNREFUSED` to a well-known database port, a wrong Node/Go version, a missing `go.sum` entry, no C compiler…) plus
   checks of the project itself: dependencies not installed, a lockfile older than `package.json`, `.env` missing keys its
   example has, the Node/Go version the project pins against the one installed, Docker not running, a merge or rebase in
   progress. They are shown **before any model** with the command that fixes them.
3. **The model, once.** `⏎` on “Ask the model” shows what is sent (sizes, the model, about how many tokens) and asks. One
   request reads the evidence, finds the root cause (the first error, not the cascade) and writes ordered steps. If it cannot
   conclude it may ask to **read a file, search for a string, list a folder or run one read-only command**, at most twice more;
   that is all it can do: no shell (a command is split into words and checked against an allowlist of diagnostics: versions,
   package lists, `git status/log/diff`, `docker ps/logs`, `lsof -i :PORT`…), no pipes or redirects, and secret files (`.env`,
   keys, `.ssh`, `.aws`, `.npmrc`…) are never readable; every refusal goes back to the model as the result. `p` shows the exact
   text that would be sent.
4. **Steps.** A step is a **command** (`⏎` runs it captured, in the project folder: its output and exit code come back into the
   case; `t` runs it in the integrated terminal for interactive things and servers), an **edit** (`⏎`: one proposal with the usual
   inline diff, accept/reject, the queue; the screen gives way to the code and the step is done when you accept) or a **manual**
   thing (`Space` marks it). Nothing runs without a yes that shows the exact command; a command that destroys or rewrites
   something (`rm -rf`, `git push --force`, `git reset --hard`, `DROP DATABASE`, `curl | sh`…) is marked `!` and asked twice.
5. **Check again.** `r` runs the failing command again (or reads the terminal) and says whether it still fails; if it does, a new
   case starts carrying what was tried, so the model never suggests it twice. `a` asks a follow-up (what you saw after a step).

The screen is the same full-screen layout as the other markets (list, reading pane, strip; `?` lists the keys; narrow terminals
show one pane at a time). A case is kept in memory: close it, run something in the terminal, `<leader>aXr` brings it back. When
the model answers after you closed the screen you are told. Knobs: `settings.agent.doctor` (terminal lines, characters of
output sent, stack frames, rounds, command timeout, characters per tool result). Runs are in the history (`<leader>ah`).

## Settings (`settings.agent`, overridable in `local.lua`)

`backend`, `order`, `light_backend`, `history`, `cache`, `language` (of explanations, answers and findings; `English` by default), `rules`, `timeout_ms`, `tiers`, `context.*`, `apply.format`
(formats the range with conform on accept), `keys` (accept/reject), `claude.models`/`model`/`light_model`/`prompt_cache`/`max_cost_usd`, `opencode.*`, `ollama.*`, `openai.*`, `custom`.

## Extending

| I want... | Do |
|---|---|
| another backend (another CLI) | `lua/agent/backends/<n>.lua` with the contract of `backends/init.lua` + `NAMES`; without code: an entry in `agent.custom` |
| another action | `lua/agent/actions/<n>.lua` with the contract of `actions/init.lua` + `NAMES`; the menu and the cheatsheet come out by themselves |
| another kind of output | `lua/agent/output/<n>.lua` (`done` and optional `stream`/`release`) + `NAMES` |
| another context provider | `lua/agent/context/providers/<n>.lua` (`cap`, `collect(target, done)`) and use it in the `context` of an action |

The format the model must return (code block, `L<n>|sev|msg`) lives in `lua/agent/protocol.lua` next to its
parser: the prompt rules and how they are read always change together.

## Pitfalls

- Generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, protobuf; list in `utils/generated.lua`) are
  rewritten on the next build: actions that edit (`replace` output) refuse to run there, explain/ask still work. They are
  also left out of `types`, code search and the architecture levels' searches.
- If the model disobeys and sends several code blocks (draft + corrected version, 2 out of 6 times in a test
  with Rust), the **last one that starts like the target** is used and the hint warns: `model sent 2 blocks, check the diff`.
- The accept/reject hint shortens in narrow windows (it drops tokens/cost first) and the spinner switches to a compact version.
- The colors of the diff, the spinner, the hint and the window are **derived from the active theme's palette** with guaranteed
  minimum contrast (4.5:1 for text) and are recomputed when the theme changes (`<leader>S`); tested with the 97 base46 themes and the
  terminal-inherited theme. Findings use the diagnostic colors of your theme.
- A visual selection is taken as **whole lines**.
- `Esc` rejects the proposal while one is visible in the buffer (only then; `settings.agent.keys` changes it).
- A model may return an empty block: it means deleting that range (e.g. `fix` removing unused imports).
- `needs-import:` after the block is shown in the hint; imports are not added by themselves.
- `scripts/test-agent.sh` runs the tests for parsers, target, local backends and setup (no network or tokens: the Ollama/OpenAI servers are fake, `scripts/fake-llm.py`).

## Fix: two levels

- **`<leader>af` fix inline**: put the cursor on the line with the diagnostic (the underline/block from LSP, linter or review). The target
  is **only the diagnostic's lines** (if it spans more than `agent.context.diagnostic_lines`, only what starts there). It carries as
  context: the full diagnostic, the `agent.context.around` lines before and after within its function (`<around>`, read-only),
  the signature of what it calls (`<callees>`) and the definitions of the **objects it points to**: for each identifier in the
  diagnostic (and the object of an `x.Field` access) the LSP is asked for its `typeDefinition`, so the model sees `type Note struct` even if
  the code does not name the type (`n := load(); n.Titl`). If the real fix lives elsewhere (an import, a missing declaration) it says so in
  `needs-import:` / `note:` instead of editing outside the lines. In visual mode, the selection is the target.
- **`<leader>aF` fix block**: the target is the whole function (or the selection) and it fixes all its diagnostics at once, with the
  same type definitions. Use it when several diagnostics share a cause or the fix touches several lines.

## Tests (`<leader>aT`) and lenses (`<leader>aL`)

Two menus of their own so `<leader>a` does not fill up. Both run through the same pipeline (instruction field, inline diff, `⏎`/`⎋`,
history and cost) and are designed to **spend the minimum**: whatever can be decided without a model is decided beforehand.

**Tests** (`agent/tests/`): they do not replace the function, they **append to the end of the test file**.

| Key | What it does | How it saves |
|---|---|---|
| `w` write | tests for the function under the cursor (or the selection), **only what is missing**: main case, boundaries and each error branch, max. 6 cases, in the file's style | the target sent is **one line** (the end of the test file), the model returns only what is new; from the test file only the header, names, the tests that already cover that function and, if there are none, ONE example travel; a function of <4 lines is rejected before calling |
| `m` mock | a hand-written fake for the interface/class under the cursor (records calls, returns what the test sets) | **light** model |
| `f` fix | fixes a failing test | **runs the test first** (`go test -run`, `vitest`/`jest -t`, `pytest -k`, `cargo test`) and only if it fails sends its real output; if it passes, 0 tokens. If the code is at fault, it leaves the test as is and says so in `note:` |
| `g` gaps | quickfix with the public functions in the folder that no test names | local, **0 tokens** (approximate map: a short name can give a false "covered") |

- The test file comes from the language's convention (`agent/tests/convention.lua`): Go `x_test.go`; TS/JS `x.test.ts`
  (or `.spec.` if the folder already uses it; vitest/jest/mocha according to `package.json`); Python `test_x.py` (in `tests/` if it exists);
  Lua `x_spec.lua`; Rust, a `mod x_tests` in the same file; Dart `lib/` → `test/`; Java/Kotlin `src/main` → `src/test`.
- When done, the test file **opens to the side with the proposal** (`⏎` accepts, `⎋` rejects); accepting only changes the
  buffer, you save. A new file is not created (nor its folder) until you save it.
- `fix` only knows how to run Go, TS/JS (vitest/jest), Python and Rust; in another language it warns without spending anything.
- Change the model: `agent.tiers.test_write = "light"` (or `test_mock`, `test_fix`).

**Lenses** (`agent/lenses/`): reviews with **a single focus**, which come out as diagnostics with their origin (`[security]`) on the
exact line. `af`/`aF` fix them, and repeating a lens only replaces the findings of that lens (not those of another one or of `review`).

| Key | Looks for | Model |
|---|---|---|
| `s` security | untrusted input reaching a sink (SQL/command/template injection, traversal, SSRF, XSS), authentication/authorization, secrets, cryptography, deserialization | main |
| `p` performance | N+1, repeated work, quadratic algorithms, copies and allocations in hot paths, unbounded memory | light |
| `c` concurrency | races and unsynchronized shared state, deadlocks, leaking goroutines/tasks, unawaited promises, double closes | main |
| `e` errors | ignored or context-less errors, swallowed in catch, resources not released on the error path, half-done state | light |
| `a` api | **uncommitted changes** that break whoever uses it (signatures, return, errors, nil, tags) | light |

- Each lens has a **gate**: if the code contains nothing of its topic (a function without threads for `c`, without I/O for `s`, without
  changes for `a`) it warns `skipped (0 tokens)` and does not call the model.
- Minimal context per lens (rules and signatures of what it calls; `c` adds types; `a` adds the diff): the output is ≤ 8 lines.
- Adding a lens = one file in `agent/lenses/actions/` (`key`, `title`, `focus`, `gate`) and its name in `NAMES`.
- Change the model of one: `agent.tiers.lens_security = "light"`.
