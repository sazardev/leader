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
| `e` explain | function or selection | window next to the code, streaming; closes by itself when the cursor moves |
| `a` ask | your question (text field) | window, same as explain |
| `f` fix inline | the diagnostic (LSP, linter or agent finding) on the cursor line + optional hint | diff with the minimal change on **only those lines**; the surrounding code and the objects it points to (the variable's type, the signature of what is called) go along as read-only context; with no diagnostic on the line, it does nothing |
| `F` fix block | all the diagnostics of the function (or selection) + optional hint | diff with the minimal change that leaves the block coherent (several diagnostics with the same cause are fixed together) |
| `d` docs | function + optional focus | diff that only adds/updates the documentation comment |
| `R` refactor | your instruction (text field) | diff that applies exactly that instruction |
| `g` handoff | your instruction | sends `file:range` + instruction to an agent already running in Herdr |

**The instruction field is inline** (like the inline chat in Zed or VS Code): it opens right ABOVE the target code and
**pushes the code down** instead of covering it, with an accent bar, a header (`✦ implement · claude/sonnet`) and
a placeholder. It grows as you type (up to 6 rows), `⏎` sends, `⎋` cancels (also if you switch windows), `⌃J` / `Alt+Enter`
insert a line break and `↑`/`↓` (or `⌃P`/`⌃N`) walk through the previous instructions of that action, which are remembered
across sessions. In narrow windows the key hint shortens itself. There is no autocompletion or auto-closing of quotes inside.

**Instruction**: `i`, `d` and `f` open the field and **Enter with an empty field runs without an instruction**; if you type something, it is appended
to the prompt and takes precedence over the default behaviour. Useful for an empty `func main() {}` ("read a CSV and sum column
3"), for an unclear function ("this validates orders before charging; the coupon case is missing") or to steer a fix.
`a` ask and `R` refactor require the text; `r` review and `e` explain run instantly.

**Short menu**: `i` implement, `d` docs, `r` review, `e` explain, `a` ask, `f` fix inline, `F` fix block, `R` refactor, `g` hand off (only inside
Herdr), `h` history, `m` model (main, light and effort in a single selector), `c` clear (discards the finding on the line, or those in the selection in visual mode), `C` clear file (those in this file), `x` stop (cancels what is running and discards the
pending proposals; it does **not** touch findings) and `l` last answer (reopens the last answer or rejected proposal). Accepting and rejecting a proposal have no
menu entry: they are `⏎` and `⎋` on the proposal.

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
Cap: `context.types` (4) definitions of `context.type_lines` (30) lines.

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

## Models per tier (cheap where it is enough)

Each action runs on the **main** model or the **light** one. `docs` and `explain` are light (Claude: `haiku`); the rest
use the main one (`sonnet` by default). Measured with Claude, a single-function action: **~$0.005 on sonnet vs ~$0.0003 on
haiku**, about 17 times less, and the spinner shows the model that is running. Light actions do not inherit the
effort either: they are the cheap ones and must not become expensive because of a setting meant for others.

- `<leader>am` opens a selector with the **main** model (and the backend), the **light** model and the effort, with their current value. Everything is remembered.
- Change which actions are light: `agent = { tiers = { review = "light", docs = "main" } }` in `local.lua`.
- `agent.claude.light_model` / `agent.opencode.light_model` set the default light model. In OpenCode it is `nil` (uses the
  main one) because its ids depend on your provider: pick it in `<leader>am`.

## Backend and model

`<leader>am` → Main model opens ONE fuzzy list with the models of all installed backends (Claude: `haiku`/`sonnet`/`opus`;
OpenCode: whatever `opencode models` returns). Choosing one also switches the backend and **is remembered** across sessions
(`stdpath("state")/agent.json`). Effort (Claude only; `--effort`) is in the same selector. With `backend = "auto"` the
first available one in `agent.order` is used.

- **Claude Code** (`claude -p`): no tools, no session on disk, text streaming.
- **OpenCode** (`opencode run`): each action travels as an ephemeral agent with no tools (`OPENCODE_CONFIG_CONTENT`).
  Slow to start (~4 s): with `agent.opencode.attach = "http://localhost:4096"` (an `opencode serve` already running) this is avoided.
  `agent.opencode.agent` uses an agent of your own. If opencode does not find the requested agent it warns and falls back to the default one, which
  DOES have tools: here that is treated as an error.
- Each opencode session stays in its list with the title `nvim <action>`.

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

`<leader>a` keeps the generic ones (implement, review, explain, ask, fix inline, fix block, docs, refactor, hand off, model, history, clear, stop, last).
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
  adds up the total spent. The preview shows the full detail; `⏎` opens it large.
- `⌃S` opens the **spending report**: by period (today, 7 days, total), by action, by model, by day, **cost per applied
  change**, what was spent on proposals you did not apply, errors, cache hits, **where the prompt goes** (system,
  context per provider, target) and the 5 most expensive runs. It is the basis for deciding what to cut.
- `⌃Y` **copies EVERYTHING about the run** (the same text you see in the detail): outcome and event line (accepted at
  09:38:27...), target, time, tokens, cost, your instruction, the response, the system prompt and the exact message
  sent. `⌃P` copies only the prompt (system + message) to reproduce or tweak it. In the detail panel and in
  the report panel, `Y` copies the whole panel. Everything goes to the clipboard (`+`) and the unnamed register.
- Privacy: the history includes your code (it goes inside the prompt). `agent.history.store_text = false` stores only metrics;
  `enabled = false` turns it off. It compacts itself to the `max_entries` (1000) most recent.

## Project conventions: `.agent.md`

An `.agent.md` at the root (or further up) is added to ALL prompts: style, preferred libraries, what to avoid. Max.
1500 useful characters. Example: `Idiomatic Go; errors with %w; no logs in pure functions; tests with testify.`

## Settings (`settings.agent`, overridable in `local.lua`)

`backend`, `order`, `light_backend`, `history`, `language` (of explanations, answers and findings; `English` by default), `rules`, `timeout_ms`, `tiers`, `context.*`, `apply.format`
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
