# Agent skills (`<leader>aK`)

**SKILL.md files the agents load on demand** (OpenCode `skill` tool in `.agents/skills`; tool-less backends receive ONE body as a context section). Leader manages them for you: no manual copying, no question about what to install. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (**Skills** menu).

## Marketplace

`<leader>aK` + `o` (or `<leader>Sp` → Skills → Marketplace) opens the full-screen marketplace (same widget as the SPEC.md modules):

* **Left:** skills by group: **Installed**, **Suggested for your model**, **Catalog** (skills.sh + offline list). `■` on, `□` off, `+` suggested, `○` catalog.
* **Right:** what it is and its instructions, plus where it lives (`~/.config/opencode/skills/...` or `.agents/skills/...`).
* **Bottom:** counts (`N ON · M OFF · model small/medium/strong`) and what `A` will do.

| Key | What |
|---|---|
| `Space` / `x` | Install a suggested/catalog skill (writes `.agents/skills`) or toggle an installed one on/off |
| `e` | Edit its `SKILL.md` in a split over the marketplace (coming back, the market is still there) |
| `n` | New skill: id → trigger line → instructions |
| `d` | Delete to Leader's trash (30 days, `<leader>Fu` brings the last one back) |
| `A` | Apply every suggestion for your model (0-config, no question) |
| `/` | Search the catalog (`npx skills find` when Node is there, offline curated list otherwise) |
| `⏎` / `l` | Read it (Esc/h goes back), `?` keys, `Esc`/`q` close |

You never leave the view to add, edit or delete: after each action the list refreshes where you were.

## 0-configuración (infiera, no pregunte)

`skills/infer.lua` (pure, tested) decides from what you already have:

1. **Your model** (`agent.selection` + `agent.profiles`): a **small** model gets the token-savers first (`caveman`, `caveman-commit`); a **medium** gets `caveman`; a **strong** gets only stack skills.
2. **Your stack + environment** (project markers): `go.mod` → `go-pro`, `test-master`; `*.sln`/`*.csproj` → `dotnet-pro` (C#/.NET); `pubspec.yaml` → `flutter-expert`; `package.json` → `typescript-pro`, `react-expert`; `pyproject.toml` → `python-pro`; `Dockerfile` → `docker-pro`, `devops-engineer`; `*.tf` → `terraform-pro`; `wrangler.toml` → `cloudflare-expert`; `serverless.yml`/`cdk.json` → `aws-pro`; `firebase.json` → `gcp-pro`; `netlify.toml` → `netlify-expert`; `vercel.json` → `vercel-expert`; `azure.yaml` → `azure-pro`; `Chart.yaml` → `kubernetes-specialist`. C# and cloud/deploy are first-class: the environment with no inferred skill is exactly where the agent invents flags and commands.
3. **What is already there**: installed+on is `keep`, installed+off is `enable`, missing is `install`, disabled by you (`skills.disabled`) is `skip`.

`A` (or `<leader>aKs`) applies it with `npx skills add <repo> --skill <id> -a opencode -y` (global adds `-g`); without `npx` it clones the repo with git and copies the dir in. Nothing is installed without you pressing `A`/install: never a package manager in silence (same rule as the welcome screen).

## Sources (marketplaces)

* **skills.sh CLI** (`npx skills find/add/list/check/update/remove`): live search and install for 75+ agents, project by default, `-g` global.
* **HTTP catalogs** (OpenCode 2 `skills` array): `https://opencodeskills.dev/catalog/` and `https://skills.sh/` are added in `settings.skills.sources` when you give one.
* **Offline curated** (`skills/store.CURATED`): languages (`typescript-pro`, `python-pro`, `go-pro`, `flutter-expert`, `dotnet-pro`, `php-pro`, `ruby-pro`, `elixir-pro`, `rust-pro`-adjacent via stack), environments/deploys (`docker-pro`, `kubernetes-specialist`, `terraform-pro`, `aws-pro`, `gcp-pro`, `cloudflare-expert`, `netlify-expert`, `vercel-expert`, `azure-pro`, `devops-engineer`) and the always-on (`caveman`, `code-reviewer`, `test-master`, `postgres-pro`, `api-designer`, `security-reviewer`) — always searchable with no network.

## How each backend uses them

* **OpenCode** (`agent/backends/opencode.lua`): `skill` tool is on when `skills.enabled` (it lists only id+description per step, so small models are not drowned; the body loads on demand).
* **Claude / Ollama / OpenAI** (tool-less): `agent/context/providers/skills.lua` injects **ONE** relevant body (`skills.max_chars`, default 1200) matched by language + file + action words. The provider is silent with no match or when off.

On/off per skill lives in its frontmatter (`metadata: { opencode/autoinvoke: false }` = dormant), where the model will not see it. `skills-lock.json` (project root) records where each one came from.

## Settings

`skills = { enabled, auto, scope (project|global), max_chars, disabled, sources }` in `core/settings.lua` (or `<leader>Sp` → Skills). `auto = false` turns suggestions off (the marketplace still works).

## Tolerance (repos oldie / legacy / ya trabajados)

Leader detects and adjusts, never overwrites (`skills/adopt.lua`, pure + `collect`):

* **Ya hay skills**: se conservan y no se duplican (`store.list` deduplica: proyecto gana sobre global; `create` se niega si existe). Las inválidas sin `description` se listan con `⚠` y **no se anuncian** al modelo; editarlas con `e` las arregla.
* **Ya hay agents**: `AGENTS.md`/`CLAUDE.md`/`.agent.md`/`.agents`/`.claude`/`.opencode` se detectan: `CLAUDE.md` sin `AGENTS.md` sugiere `<leader>aSc` (enlaza, no crea de cero); `AGENTS.md` existente nunca se sobrescribe (kit confirma + papelera).
* **Ya hay docs**: `STACK.md`/`DESIGN.md`/`SPEC.md`/`PROGRESS.md` se detectan: Stack/Design/Spec ya documentados se ajustan con `<leader>aS`, no se recrean.
* **Legacy sin manifests modernos**: solo token-savers (`caveman`) + `keep`, sin forzar skills de stack (`adopt.adjust`). Un repo con `Makefile`/muchos archivos y ningún `go.mod`/`package.json`/… se marca legacy, no se le propone infra nueva.
* **Verlo**: la franja del marketplace muestra `Detected: ...` (hints del repo) y `<leader>aKd` abre el doctor con todo lo detectado y un consejo por cosa.

## Tests

`scripts/test-skills.sh` (pure parsing/inference, discovery+CRUD on temp dirs, tolerance, market windows/keys/back navigation, menu and provider shape). No network.
