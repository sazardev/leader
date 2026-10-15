# Inline agent (`<leader>a`)

**One-shot** actions on what you are looking at: a function, a class or a selection. No chat, no sidebar, no
conversation. Every action has a closed prompt, a bounded context and an output with a fixed format, so it is
predictable and cheap. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (**Agent** menu).

## Flow

1. Put the cursor inside a function (or select lines in visual mode) and press `<leader>a` + the action.
2. The code being sent is highlighted and a spinner turns on the right: `⠋ implement · claude/haiku · 1.2s`.
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
  Models matching `agent.opencode.no_thinking` (default `deepseek`, `haiku`, `minimax-m3`) run with thinking off: deepseek-v4.1-flash spent 300-1400
  reasoning tokens (4-15 s) on small functions; it costs some quality, `{}` turns it back on. It is per model because glm/cat-jam reject the parameter.
  The shortlist (deepseek-v4.1-flash, minimax-m3, claude-haiku-5-5, glm-5.3-flash, gpt-6-luna) was picked by benchmarking all opencode-go
  models on four graded tasks (two `implement` checked with `go test`, a `review` with a seeded bug, a `review` of clean code that must
  answer `OK`): 4/4, 1.4-3 s warm, ~$0.0002 per action. Haiku keeps requests 30 days; Gemini and Muse Spark train on prompts (left out).
  DeepSeek costs double at Peak (01-04 and 06-10 UTC, Mon-Fri). Only one run per task, so differences under ~0.5 s are noise.
  `agent.opencode.attach` points at a server of your own instead, but `opencode run --attach` printed no text in v1.19.
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
| `<leader>aS` | **Service** (`agent/service/`) | implement `i`, review `r` | **deps** `d` (ports it uses, nonexistent calls, implementations, wiring) | `ports` |
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

## Service (`<leader>aS`): application services / use cases

A service can only call the methods that its **ports** declare. The `ports` provider finds the interfaces the service receives
(fields, constructor parameters, method parameters, in any language) and reads them with their real signatures, each with its path and the
instruction to call only those methods; with `examples` it adds another service of the project as a style example.

- **`<leader>aSi` service implement**: orchestrates the domain and calls ONLY the ports in `<ports>` with their exact names and signatures; business
  rules are called on the entity (not reimplemented); it propagates the context and translates the ports' errors.
- **`<leader>aSr` service review**: calls to port methods that do not exist or with wrong arguments, business rules in the service, leaking
  infrastructure details, swallowed or untranslated errors, non-atomic steps or steps ordered in a risky way (effects before saving), N+1.
- **`<leader>aSd` service deps** (0 tokens): for each port, which methods it declares, **which ones this file calls and which ones the port does NOT declare** (it
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
