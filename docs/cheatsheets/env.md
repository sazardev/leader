# Env files (`<leader>E`)

One global menu for **every** filetype and **every** stack. The stack is detected from the markers under the git root
(`go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `Package.swift`, `pubspec.yaml`,
`pom.xml`/`build.gradle`…); when nothing matches or several do, a picker chooses the preset. 0 tokens,
nothing resident.

| Key | What it does |
|---|---|
| `En` | Create `.env.example` + `.env` for the detected stack (never overwrites) |
| `Ee` / `Ex` / `El` / `Ed` / `Eq` / `Es` / `Ep` | Open `.env`, `.env.example`, `.env.local`, `.env.dev`, `.env.qa`, `.env.staging`, `.env.prod` |
| `Ec` | Check: every `.env*` against `.env.example` (missing / extra / empty) |
| `Ea` | AI: generate the typed loader (`internal/config/env.go`, `src/config/env.ts`, `src/config/env.py`, `src/config.rs`, `Config/Env.cs`, …) |
| `Eo` | Open any `.env*` (picker with preview) |
| `EN` | New environment: `.<name>` from `.env.example` with `APP_ENV` set (free name, also `dev/qa/staging/prod/test/local`) |
| `Ei` | Ensure `.gitignore` has the secrets rules |

## How a preset looks

Each language in `nvim/lua/env/langs/<id>.lua` declares:

- `markers` — what says “this project is this stack”.
- `vars(root)` — name/module from the manifest (`{{name}}`, `{{module}}`… filled into the template).
- `template(vars)` — the `.env.example` body: one section per group (App, Database, Cache, Auth, External, Mailer, Observability) with `APP_ENV=development`, `PORT`, `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`… committed as the template; `.env` is the local copy.
- `loader` — where the AI writes the loader (`internal/config/env.go` for Go, `src/config/env.ts` for TypeScript, `src/config/env.py` for Python, `src/config.rs` for Rust, `Config/Env.cs` for C#, `Sources/App/Config/Env.swift` for Swift, `lib/config/env.dart` for Dart, `src/main/java/config/EnvConfig.java` for JVM) and the language-specific style hint.

`.env.example` is the contract: it is committed (same name, dummy values, comments). `.env` and every
`.env.<name>` are ignored by git. Creating any `.env` also adds the *Secrets* rules to `.gitignore` if they are
missing (`<leader>Gi`’s preset: `.env`, `.env.*` but not `.env.example`) — never removes a rule.

## Stacks and tolerances — audit by language

`nvim/lua/env/langs/` covers **all packs** (`nvim/lua/languages/packs.lua`). Each preset knows its stack’s
*markers*, its *conventions* (variable names, file names, loader idiom) and its *tolerances* (what the parser
and the generated loader accept without complaining). When several stacks match (a monorepo with `go.mod` and
`package.json`), you pick once in the picker; the next run detects the same set again.

| Stack (pack) | Markers | `.env.example` highlights | File-name tolerances | Loader (`Ea`) |
|---|---|---|---|---|
| **Go** (`go`) | `go.mod`, `go.work` | `APP_NAME` from `binary`, `PORT=8080`, `DB_DRIVER`, `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, S3 local | `.env` (godotenv default); `Load()` also reads `APP_ENV`-selected file | `internal/config/env.go`: `Config` struct, `Load()`/`MustLoad()`, godotenv or manual parse, dev defaults |
| **TypeScript / JavaScript** (`typescript`) | `package.json` | `PORT=3000`, `DATABASE_URL` (Prisma), `NEXTAUTH_SECRET/URL`, public `VITE_API_BASE_URL`, `NEXT_PUBLIC_API_BASE_URL` | `.env`, `.env.local`, `.env.development`, `.env.production`, `.env.dev/qa/staging/prod` (Next.js, Vite, dotenv) | `src/config/env.ts`: ESM `env` object with `dotenv/config`, zod validation, no scattered `process.env` |
| **Python** (`python`) | `pyproject.toml`, `requirements.txt`, `setup.py` | `APP_NAME` from `pyproject [project].name`, `DEBUG`, `DATABASE_URL` + `SQLALCHEMY_DATABASE_URL=${DATABASE_URL}`, `CELERY_*`, `SECRET_KEY` | `.env`, `.env.local` (pydantic-settings default), `.env.dev/qa/staging/prod` | `src/config/env.py`: pydantic `BaseSettings` or dataclass, `load_dotenv()`, `get_settings()` |
| **Rust** (`rust`) | `Cargo.toml` | `RUST_LOG`, `DATABASE_URL`, `JWT_EXPIRE_SECONDS`, `PORT=8080` | `.env` (dotenvy default); `dotenvy::dotenv()` reads the file named by `APP_ENV` when the loader says so | `src/config.rs`: `Config::from_env()`, dotenvy, anyhow/thiserror, `OnceLock` global |
| **C# / .NET** (`csharp`) | `*.csproj`, `*.sln`, `global.json` | `ASPNETCORE_ENVIRONMENT`, `ConnectionStrings__DefaultConnection`, `Jwt__Key/Issuer/Audience`, `Redis__ConnectionString`, `DATABASE_URL` mirror | `.env` + `appsettings.json` (IConfiguration): either `__` double-underscore or plain `DB_*` | `Config/Env.cs`: `static Env.Load(IConfiguration)`, DotNetEnv, `Required()` throws listing missing keys |
| **Swift** (`swift`) | `Package.swift` | `APP_NAME` from `Package(name:)`, `DATABASE_URL`, `JWT_EXPIRE_SECONDS` | `.env` (DotEnv) | `Sources/App/Config/Env.swift`: `Env.load() throws`, ProcessInfo + .env parse, `AppError.missingEnv` |
| **Dart / Flutter** (`dart`) | `pubspec.yaml` | `API_BASE_URL`, `WS_URL`, `API_TIMEOUT_MS`, `FIREBASE_*` | `.env` (flutter_dotenv `asset`); `--dart-define` also works | `lib/config/env.dart`: `dotenv.load()`, typed getters, `StateError` on missing required |
| **Java / Kotlin** (`jvm`) | `pom.xml`, `build.gradle*` | `SPRING_PROFILES_ACTIVE`, `DATABASE_URL` + `SPRING_DATASOURCE_URL=${DATABASE_URL}`, `SPRING_DATA_REDIS_URL` | `.env` + `application.yml`; loader also accepts the shell environment | `src/main/java/config/EnvConfig.java`: `@ConfigurationProperties` or `Env.fromEnv()`, `IllegalStateException` on missing |
| **Web / infra** (`web`, `infra`, `sql` packs, `lua`…) | — (no dedicated marker) | Generic: `APP_NAME`, `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET` — same sections, no stack-specific names | `.env` per the tool that reads it (docker-compose `env_file`, Prisma `DATABASE_URL`) | `config/env` generic typed `Load()` — you rename it to your idiom with `EN`/rename |

### What “tolerances” means here

- **Files**: `parse.lua` (`nvim/lua/env/parse.lua`, pure, 0 tokens) tolerates `export KEY=`, `KEY="quoted"`,
  `KEY='quoted'`, `KEY=value # inline comment`, blank lines, CRLF, missing trailing newline. `list_files`
  collects every `.env*` under the root (so `.env.local`, `.env.development` and any `EN`-created file are
  checked without enumerating them).
- **Names**: the checker is *exact* on the example (that is the point — a typo shows as `extra` + `missing`),
  but the *presets* themselves tolerate both styles where the ecosystem does: C# accepts
  `ConnectionStrings__X` **and** `DATABASE_URL`; JVM accepts `SPRING_DATASOURCE_URL` as an alias of
  `DATABASE_URL` (with `${}` interpolation preserved verbatim); TypeScript keeps server `JWT_SECRET` separate
  from public `VITE_*`/`NEXT_PUBLIC_*`.
- **Environments**: `EN` accepts any free name, lower-cased and sanitized; `APP_ENV` is set when the key exists,
  otherwise prepended. The loader is told the file to read (`dotenv(path: ".env.qa")`, `APP_ENV=qa`), so
  `dev`/`qa`/`staging`/`prod` are just files, not code paths.

## Environments

`EN` asks for a name (`dev`, `qa`, `staging`, `prod`, `test`, `local`… or any) and creates `.env.<name>` from
`.env.example`, setting `APP_ENV=<name>` when the key exists. The same file is reused by the stack’s own loader
(`dotenv`, `godotenv`, `pydantic-settings`, `dotenvy`, …) — no code change per environment. `settings.env.environments`
is the suggested list; `settings.env.ensure_gitignore = false` disables the automatic `.gitignore` update.

## Check

`Ec` reads `.env.example` as the required set and every `.env*` under the root:

- **missing** — a key the example has but the file does not.
- **extra** — a key the file has but the example does not (typo or undocumented secret).
- **empty** — a key with no value (in `.env` often a forgotten secret).

It shows the verdict in a modal and as a one-line notification; 0 tokens, pure (`nvim/lua/env/parse.lua`).

## AI loader

`Ea` is a one-shot `agent.complete` (main tier): the prompt sends only the `.env.example` keys (never the real
secrets), the language’s style hint and the target path. The answer — only the file content, no prose or fences —
is written to the target (never overwrites). The UI is identical in every language: one key, one file, same flow.

## Possibilities (what else it plugs into)

- **`.gitignore`**: `Ei` / auto on create adds the *Secrets* topic (`.env`, `.env.*`, `!.env.example`). `sqlrun`
  (`<leader>Q`) already reads `DATABASE_URL` from `.env`; `commit`’s sensitive patterns already protect
  `.env` from `GM`.
- **Docker**: `docker compose --env-file .env.qa up` — no code change; the example already has `HOST`/`PORT`.
- **Makefile**: `include .env` + `export` picks the chosen file up for `tasks`.
- **CI**: `.env.example` is the only file you commit; the CI reads the real file from secrets.

## Pitfalls

- **Never commit `.env`**: `.env.example` is the template; `.env` must stay ignored (the Secrets preset).
- **`.env.<name>` is not magic**: the loader must be told which file to read (`dotenv`’s `path: ".env.qa"` or `APP_ENV`).
- **Missing `go.mod`-like marker**: you get the picker — choose the stack once; the next time it is detected again.
- **Monorepo**: one `.env.example` per detected stack; run `EN` from inside the subfolder (or move the root) when
  they diverge.
