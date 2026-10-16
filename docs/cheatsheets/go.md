# Go

## Tools

| What | With |
|---|---|
| LSP | gopls (gofumpt, staticcheck, placeholders, analyses: unusedparams, shadow, unusedwrite, useany; inlay hints) |
| Format (on save and `<leader>fm`) | `goimports` then `gofumpt` |
| Lint | `golangci-lint` (in light mode: `go vet`); does not run when leaving insert |
| Extra | go.nvim (`GoAddTag`, `GoFillStruct`, `GoIfErr`, `GoAddTest`...), treesitter, gomodifytags |

## `<leader>g` menu (only in `*.go`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

- Struct actions (tags, fill literal, `if err`, add test) act on the cursor. The **tag** ones (`ga`/`gA`/`gD`) **save the file** when done (that is how go.nvim works).
- In light mode go.nvim does not load: those actions warn instead of failing.
- `run` and `build` run on the file's directory (`.` if there is a `go.mod`, or the single file if not). The rest run from the module root.

## Project setup (`<leader>gS`, `lua/gosetup/`)

The config files a Go project usually wants, one key each (0 tokens, nothing resident): **golangci-lint** (`.golangci.yml`:
`minimal`, `standard`, `strict`, v2 format), **Air** (`.air.toml`: `basic`, `api` with graceful restarts), **Dockerfile**
(`alpine` or `distroless`, multi-stage, non-root), **.dockerignore**, **GitHub Actions CI**, **git hooks** (lefthook) and
**.editorconfig**. `Sp` is a checklist of all of them (what is missing and core is checked), `Sm` creates a Makefile (same as
`<leader>Rc`) and `Sg` the `.gitignore` (`<leader>Gi`).

- **Filled in from the project, never asked**: the module path (golangci's local import prefix), the Go version of `go.mod`
  (image tags), where `main` really is (`./cmd/api` or `.`) and the binary's name. The module is the nearest `go.mod` up from
  the current file.
- **Never overwrites.** A file that is already there (also `.golangci.yaml`/`.toml`/`.json` for golangci-lint) is opened.
  A misnamed config such as `.golangcli.yml` (golangci-lint only reads `.golangci.yml`) is offered a **rename** with the
  buffers and servers following; the content is kept.
- With several variants the picker previews the file exactly as it will be written.
- golangci-lint **v2** configs (`version: "2"`): a v1 binary refuses them, and the action warns when it finds one.
- **Add a preset**: drop `presets/<topic>/<variant>.<ext>` in `lua/gosetup/`. Line 1 is `# description` (stays in the file),
  line 2 is `# target: path/relative/to/the/module` (not written). Placeholders: `{{module}}` `{{go}}` `{{main}}` `{{binary}}`.
  A new topic (a folder) also needs its entry in `TOPICS` (`gosetup/init.lua`): key, label, default variant.
- Tests: `scripts/test-gosetup.sh` renders every preset and, where the tools exist, has them check it (golangci-lint v2
  `config verify`, air's own keys from `air init`, `lefthook validate`, TOML/YAML parsing).

## Struct tags while you type (`utils/gotags.lua`)

The tag value is **derived from the field name**: `SentAt` → `sent_at`, `UserID` → `user_id`, `HTTPServer` → `http_server`, `Kind` → `kind`.

| You type (in a struct field) | Suggests |
|---|---|
| `` ` `` after the type | `json:"kind"`, `json:"kind,omitempty"`, `json:"sentAt"` (camelCase if it differs), **the `gorm:"…"` variants for that field and its type** (see below), yaml, db, mapstructure, form, toml, xml, `json:"-"`, `validate:"required"` |
| `json:` | `"kind"`, `"kind,omitempty"`, camelCase, `"-"` |
| `json:"` | `kind`, `kind,omitempty`, camelCase, `-` |
| `json:"kind,` | `omitempty`, `omitzero`, `string` (options change depending on the key) |
| `gorm:"` | full values by field and type: `primaryKey;type:text`, `type:text;not null`… |
| `gorm:"type:text;` | loose options you have not used yet: `not null`, `index`, `size:255`, `column:title`, `default:…`… |

```go
type Envelope struct {
    Kind   Kind      `json:"kind"`
    ID     string    `json:"id,omitempty"`
    SentAt time.Time `json:"sent_at"`
}
```

- Inside a tag **the first item comes preselected**: `Enter` accepts it.
- The cursor ends up **inside the quotes**: type `,` for options, or `Tab` to leave.
- Only keys you have not used yet in that tag are offered.
- It does not trigger in raw strings (`` query := `SELECT… ``), `return`, assignments, etc. (treesitter checks that you are in a struct).

### gorm

gorm separates its options with **`;`** (not `,`) and some take a value (`size:255`, `column:sent_at`). When you open the `gorm:"` tag, **full values** are offered, chosen by the **field name and type**; after a `;`, **loose options** are offered (already used ones are not repeated, and the cursor lands on the value of `size:`, `type:`, `column:`… with Tab to jump).

| Field | Variants offered (in this order) |
|---|---|
| `ID string` | `primaryKey;type:text`, `primaryKey`, `primaryKey;type:uuid` |
| integer `ID` | `primaryKey;autoIncrement`, `primaryKey` |
| `string` | `type:text;not null`, `type:text`, `not null`, `type:text;not null;index`, `uniqueIndex`, `index`, `size:255` |
| `CreatedAt` / `UpdatedAt` (`time.Time`) | `autoCreateTime` / `autoUpdateTime`, `not null;auto…`, `not null`, `index` |
| other `time.Time`, `gorm.DeletedAt` | `not null`, `index` / `index` |
| `bool` | `not null;default:false`, `default:false`, `index` |
| integers and floats | `not null`, `not null;default:0`, `default:0`, `index` |
| `[]byte` | `type:blob`, `type:bytea` |
| custom type or relation (`Author User`) | `foreignKey:AuthorID`, `embedded`, `many2many:author` |
| (all) | `column:<name_in_snake>`, `-` |

With a pointer (`*string`) `not null` is not offered. `gorm` tags show up **in any** `.go` file.

```go
type NoteModel struct {
    ID        string    `gorm:"primaryKey;type:text"`
    Title     string    `gorm:"type:text;not null;index"`
    Content   string    `gorm:"type:text"`
    CreatedAt time.Time `gorm:"not null"`
}
```

### Model files (`*_model.go` / `model.go`, `utils/gomodel.lua`)

Only there do `functable`, `funcdomain`, `functodomain` and `funcfromdomain` show up, **at the top of the list** (type `funct…`, `funcd…`, `functo…`, `funcf…`; also `toDomain` / `fromDomain` / `TableName`). They are generated from the struct fields and only for those that do not have the function yet.

- **Domain by name**: `NoteModel` → `note.Note` (package `note`, type `Note`). Fields are passed in order to the constructor and read with getters (`n.Title()`).
- **Real constructor**: if the file imports `…/note` and the package is in the module, it looks there for `Reconstitute`, `Rehydrate`, `Restore`, `Hydrate`, `FromPersistence` or `Load`. If none is found, `Reconstitute` stays as an editable placeholder (Tab).
- **Several models in the file**: `functodomain NoteModel`, and `fromDomain` becomes `fromNoteDomain` to avoid a clash.
- The domain package import is added by `goimports` on save. Formatting (alignment of `ID:   n.ID(),`) is fixed by `gofumpt`.

## Contextual completion (`utils/gosmart.lua`)

Reads the treesitter tree to know **where you are** and offers only what applies. The documentation window shows the code that will be inserted.

### When starting a declaration (column 0)
Type `func`, `type`, `New…` or the name of a struct.
There, loose buffer words and the generic LSP `func`/`type` do **not** show up.

**`func`** — function variants:

| Option | Generates |
|---|---|
| `func` | simple function |
| `func error` | returns `error` (with `return nil`) |
| `func value` | returns a `T` |
| `func pointer` | returns a `*T` |
| `func bool` | returns `bool` |
| `func result error` | returns `(T, error)` |
| `func pointer error` | returns `(*T, error)` |
| `func ctx error` | takes `ctx context.Context`, returns `error` |
| `func ctx result error` | takes `ctx`, returns `(T, error)` |
| `func main` / `func init` | the special functions |

**Methods per struct** (for *each* struct in the file, e.g. `Envelope`):

| Option | Generates |
|---|---|
| `func (e *Envelope)` | method with pointer receiver |
| `func (e *Envelope) error` | method that returns `error` |
| `func (e Envelope)` | method with value receiver |
| `func (e Envelope) String` | `fmt.Stringer` |
| `functable` | gorm: `func (NoteModel) TableName() string` with the derived name (`NoteModel` → `notes`, `Category` → `categories`). **Shows up first**: just type `funct…` (or `func ` / `TableName`). With several structs: `functable NoteModel`, `functable Category`… **Only in `*_model.go` or `model.go` files**, and not for structs that already have it. |
| `funcdomain` | `toDomain` + `fromDomain` at once (see below). Shows up with `func ` or by typing `funcd…` |
| `functodomain` | `func (m NoteModel) toDomain() *note.Note { return note.Reconstitute(m.ID, m.Title, …) }` |
| `funcfromdomain` | `func fromDomain(n *note.Note) NoteModel { return NoteModel{ID: n.ID(), …} }` |

**Constructor** — `NewEnvelope` shows up for every struct **without** a `NewX` and already includes the fields:

```go
func NewEnvelope(kind Kind, id string, sentAt time.Time) *Envelope {
	return &Envelope{
		Kind:   kind,
		ID:     id,
		SentAt: sentAt,
	}
}
```

Parameters are in lowerCamel (`UserID` → `userID`, `ID` → `id`). Embedded fields are not included.

**`funcnew`** — constructor that returns `(*X, error)`. It is **optional**: it does not show up in the list until you type `funcn…` (at package level). Tab/Enter insert it:

```go
func New(id, title, content string) (*Note, error) {
	|   // ← cursor here: validations (max lengths, empties…)
	now := time.Now().UTC()
	return &Note{
		id:        id,
		title:     title,
		content:   content,
		createdAt: now,
		updatedAt: now,
	}, nil
}
```

`time.Time` fields whose name starts with `created`, `updated` or `modified` **are not parameters**: they come from a single `now := time.Now().UTC()`. Any other `time.Time` (`dueDate`) or `*time.Time` is still a parameter. Without fields of that type, `now` is not generated.

Contiguous parameters of the same type are grouped. With a single struct in the file it is called `New`; with several, `NewX` (and several entries show up: `funcnew Note`, `funcnew Other`…).

**`Reconstitute`** — the persistence-layer constructor: it takes **every** field and sets it, with no validation and no `now`,
because the data was valid when it was saved. Optional like `funcnew`: it shows up when you type `recon…` (or `funcrecon…`),
5 letters at least, at package level, once per struct **declared in the current file** (also inside `type ( … )` blocks) that has no
such function yet. Structs of other files of the package and generic structs are not offered:

```go
// Reconstitute rehydrates a Note from persistence without validating it.
func Reconstitute(id, title, content string, createdAt, updatedAt time.Time) *Note {
	return &Note{
		id:        id,
		title:     title,
		content:   content,
		createdAt: createdAt,
		updatedAt: updatedAt,
	}
}
```

Same rules as `funcnew` for the rest: grouped parameters, `lowerCamel` names, embedded fields skipped, `Reconstitute` with one struct
in the file and `ReconstituteX` with several. It is the name `toDomain` (`functodomain`, `*_model.go`) looks for in the domain package.

**Getters** — the accessors of an aggregate's private fields: no `Get` prefix, no setters (changes go through methods that mean
something). For every **unexported** field of a struct declared in the current file that has no accessor yet:

```go
func (n *Note) ID() string           { return n.id }
func (n *Note) Title() string        { return n.title }
func (n *Note) CreatedAt() time.Time { return n.createdAt }
func (n *Note) Tags() []string       { return slices.Clone(n.tags) }
```

Two ways in: at package level type `getters` (or `funcgetters`, `accessors`; 5 letters at least) for all the missing ones of a
struct at once, or write `func (n *Note) ` and the menu (it opens by itself) lists one item per missing getter plus
`all getters`. Details: the receiver is the one your other methods use (else the first letter of the struct, pointer);
names follow Go's initialisms (`id` → `ID`, `userId` → `UserID`, `url` → `URL`); exported and embedded fields are skipped; a
getter you already wrote is not repeated; the bodies come aligned like gofmt writes them. A **slice or map is returned as a
copy** (`slices.Clone` / `maps.Clone`, the import comes with `goimports` on save), so the caller cannot change the aggregate's
state through it. `settings.go.getters.clone = false` returns the field as it is. A pointer field is returned as it is.

**`package` at the top of a file** — gopls always offers `package main` next to `package <folder>`, and it used to rank first. Now the
candidates are judged by where the file is (`utils/gopackage.lua`):

- the **other `.go` files of the folder decide**: they say `package notes` → `notes` first and no `main`; they say `main` → `main` first
  (`_test` files count as their package; files with `//go:build ignore` and comments are not read as neighbours);
- **no neighbours**: `main` leads only under `cmd/…`, in a file called `main.go`, or in the module root; anywhere else it is **not
  offered** (typing `package m…` still brings it, below the rest);
- `X_test` stays below `X`, except in a `_test.go` file, where both are real options.

**Repository port** — the persistence interface of a domain object, which is almost always the same. **Only in the domain layer**
(a `domain/`, `entities/`, `model/`… folder, the names of `settings.agent.ddd.layers.domain`, read from the path under the module
root) type `repository` (`repo` is enough) at package level and each aggregate of the package that has no port yet is offered:

```go
// Repository is the persistence port of the Note aggregate; infrastructure implements it.
type Repository interface {
	Save(ctx context.Context, note *Note) error
	FindByID(ctx context.Context, id string) (*Note, error)
	Delete(ctx context.Context, id string) error
	List(ctx context.Context) ([]*Note, error)
}
```

- An **aggregate** is a struct with an identity: a field `id`, `ID` or `<Struct>ID`; its type is the one in the signatures
  (`string`, `uuid.UUID`, `int64`, `NoteID`). Value objects (no id) and `*Model`, `*DTO`, `*Request`, `*Response`, `*Row`, `*Entity`
  structs get nothing. A struct that already has its port is not offered again.
- In a package named after the struct (`package note`) the port is `Repository` (`note.Repository`); in any other, `NoteRepository`.
- Nothing shows up outside the domain layer, nor in `*_model.go` files: the port belongs to the domain.
- `settings.go.repository.methods` sets the methods and their order (`Save`, `FindByID`, `Delete`, `List`, `Exists`).
- The adapter is the other half: in infrastructure, `func (r *noteRepo) ` offers the methods it is missing (goimpl) and
  `var _ note.Repository = (*noteRepo)(nil)` comes from goport.

**`type`** — type variants:

| Option | Generates |
|---|---|
| `type struct` | empty struct |
| `type struct constructor` | struct + `NewX` |
| `type generic struct` | `Set[T comparable] struct` |
| `type interface` | empty interface |
| `type interface method` | interface with one method |
| `type interface ctx result error` | interface with `(ctx, …) (T, error)` |
| `type enum string` | string type + constants |
| `type enum iota` | int type + `iota` |
| `type defined` | `type Name string` |
| `type func` | `type Handler func(…) error` |
| `type error` | custom error with `Error()` |
| `type options` | functional options (`WithX`) |

**Strict prefix matching** (not fuzzy): only what *starts with* what you typed shows up.

| You type | Shows up |
|---|---|
| `f`, `fu`, `func`, `func ` | only the `func` variants, the methods and the pending `NewX` |
| `t`, `ty`, `type`, `type ` | only the `type` variants |
| `New`, `NewE`, `Env` | only the `NewEnvelope` constructor |
| `func Ne` | only `NewEnvelope` |
| `pac`, `package`, `i`, `v`, `c`… | none of this (the rest comes from the LSP and friendly-snippets) |
| `type Foo`, `func Foo` | nothing: you are *naming* something |

### Missing methods to satisfy an interface (`utils/goimpl.lua`)
If a struct **shows signs of** implementing an interface and is missing methods, the menu offers exactly those, with the interface's
signature and a useful body (0 tokens, no LLM). Two places:

- **After typing the receiver**: `func (s *noteService) ` opens the menu by itself (without typing anything) with `…all missing (6)` and each
  missing method (`Create`, `Get`, ...). Filter as you type (`Se` → `SetDone`). The receiver is used as you wrote it (`s`).
- **When starting the declaration** (`func ` at column 0): the same for each struct in the file, with the `func (s *noteService)` header already in place.

How it knows which interface it implements (the first that fits): `var _ NoteService = (*noteService)(nil)`; a constructor that
returns it (`func NewNoteService(...) NoteService { return &noteService{...} }`); the name (`noteService` ~ `NoteService`,
`postgresNoteRepository` ~ `domain.NoteRepository`, also if the interface is in another package of the module); or what it already
implemented. What is already written is not offered again.

**Body**: if the struct holds a dependency that is an interface (`repo domain.NoteRepository`) and it has a method with the
**same shape** (parameter and return types; the name does not matter), the body calls it: `Get` → `return s.repo.FindByID(ctx, id)`,
`List` → `s.repo.FindAll(ctx, filter)`, `Delete` → `s.repo.Delete(ctx, id)`. If there is no equivalent (`Create`, `Update`...) the
cursor is left in the body with a `return nil, nil` (zero values) that compiles. With `…all missing` each empty body is a tabstop (Tab jumps).

Interfaces from **another package of the module** are read from disk (the `go.mod` module) and their types are qualified (`Note` →
`domain.Note`); missing imports are added by `goimports` on save. Those from the standard library or from dependencies are not read:
for those, gopls already offers `<leader>ca` → "Declare missing methods of …" on the constructor error (fills everything with
`panic("unimplemented")`).

### More helpers without an LLM (0 tokens, they read your code and your `go.mod`)
They show up in the same `func ` / `New…` menu, above the rest. They share an index (`utils/goindex.lua`: interfaces, structs, methods,
functions and constants of each file, package and the whole module, cached by date).

- **`if err != nil` that knows what to return** (`utils/goiferr.lua`): after `n, err := s.repo.FindByID(ctx, id)` and **Enter**, the menu opens by itself
  with the block already built and **Enter accepts it** (turn off with `vim.g.goiferr_preselect = false`): the zero values come from the
  RETURNS of the function containing the cursor (`return nil, fmt.Errorf("find by id: %w", err)`), and the message from the name of what you
  called (editable; `FindByID` → "find by id"). Second variant: `return nil, err`. In `main` → `log.Fatalf`. Inside a `func`
  literal it uses ITS returns. In a function that does not return an error it offers nothing. `fmt` is added by goimports on save.
- **Mappers between layers** (`utils/gomap.lua`): for each struct in the file ending in `Response`/`Request`/`DTO`/`Model`/`Entity`/
  `Record`/`Input`/`Output`... it looks for its counterpart in the module (`NoteResponse` → `Note`; `CreateNoteRequest` → `Note`) and on `func ` offers
  `func toNoteResponse(n *domain.Note) NoteResponse`, `toNoteResponses` (list) and `func (r NoteResponse) toNote() *domain.Note`. Fields
  by name (ignoring case and `_`); if the source has the field private and a getter (`ID()`), it uses the getter; types defined
  over a basic type are converted (`string(n.Status)` / `domain.Status(r.Status)`); whatever does not fit or has no source comes out as `// TODO`
  (nothing made up). `*_model.go` files keep using `toDomain`/`fromDomain` from gomodel.
- **Wiring constructors** (`utils/gowire.lua`): in a function (typically `main`) type `New…` or the variable name
  (`noteSer`): it offers `noteService := application.NewNoteService(noteRepo)` with the arguments already filled in, for ALL packages of the
  module (even if you have not imported them yet; goimports adds it). Each argument: a variable of the same type → a variable whose concrete
  type **implements** the interface the parameter asks for → a variable named like the parameter → `context.Background()` → a
  hole. Variable types come from parameters, `var x T`, `&T{}` and the returns of constructors already called.
- **Enum helpers** (`utils/goenum.lua`): with `type Status string` + its `const (...)`, `func ` offers `IsValid`, `ParseStatus`,
  `UnmarshalText` and, on numeric enums (iota), `String` and `MarshalText`; plus "…enum helpers" with all of them. Only what is missing.
- **Interface from a struct and `var _`** (`utils/goport.lua`): inside `type NoteService interface { }` it offers the exported methods of
  `noteService` it does not declare yet (with their signature); and `var ` at column 0 offers `var _ NoteService = (*noteService)(nil)` for the
  structs whose interface is recognized (that line is what makes the compiler complain and what goimpl recognizes with certainty).
- **HTTP handlers from a service** (`utils/gohttp.lua`): in a struct `NoteHandler { svc application.NoteService }`, `func (h *NoteHandler) `
  (or `func `) offers one handler for each service method that is missing, `Routes` and "all". Framework by `go.mod`: net/http (Go ≥ 1.22,
  `PathValue`), chi, gin or echo (fiber: nothing). Verb by name (Get/List → GET, Create → POST, Update → PUT, Set*/Patch* → PATCH,
  Delete → DELETE); `id` → route parameter; a struct in a GET (`filter ListFilter`) → query string field by field
  (`strconv.Atoi`/`ParseBool`); the rest → JSON body (anonymous struct with snake_case tags); `(T, error)` → 200 with the JSON (201 on
  POST), only `error` → 204. For net/http and chi, a separate item with `writeJSON`/`writeError` if they do not exist.

### After `type Envelope `
Offers `struct`, `interface` and `func(…)`. If you already typed `struct`, nothing shows up.

### Inside `interface { }`
Method signatures: `method`, `method error`, `method value`, `method result error`, `method ctx error`, `method ctx result error`, `embed interface`.

### Struct name in value position → literal already filled
Type the name (`x := Env`) and **`Enter` inserts the full struct**, with no extra steps:

```go
o := Envelope{
	Kind: ,
	ID: "",
	SentAt: time.Time{},
}
```

`Tab` jumps from value to value (each value comes with its zero default selected). It applies when what you type is a **value**:

| Context | Example |
|---|---|
| right side of `:=` / `=` | `o := Env`, `o = &Env` |
| `return` | `return Env` |
| field value | `Outer{In: Env` |
| call argument | `process(Env`, `process(a, Env` |

In **type** position it does not trigger and normal gopls completion continues: `var e Env`, parameters `func(a Env`, `new(Env`, `[]Env`.
Only for structs of the same package; the bare gopls/buffer name is hidden to avoid duplicating the item.

### Inside a literal `Envelope{ }`
For structs of the **same package** (same file or another `.go` in the same folder with the same `package`).
The menu opens **by itself**, without typing anything, at three moments: when typing `{` (leaves `Envelope{|}`), when accepting `Envelope{}` from the type menu, and when pressing `Enter` after `{` or after a `field: value,`:

| Option | Does |
|---|---|
| `fill all fields` | inserts all missing fields, with default values; `Tab` jumps from value to value |
| `Kind`, `ID`, `SentAt`… | a single field: `Kind: █,` with the cursor on the value |

- Fields you already put do not show up again; it repeats after each `field: value,`.
- Default values by type: `string` → `""`, numbers → `0`, `bool` → `false`, pointers/slices/maps → `nil`, `time.Time{}`, `Inner{}` (struct from the file).
- Works with `Envelope{`, `&Envelope{` and elements of `[]Envelope{ {…} }`.
- With `Envelope{|}` on a single line, it opens the lines for you: leaves `Envelope{` / fields / `}`.
- A `package x_test` does not see the structs of `package x` (it does not compile without qualifying), so it does not offer them.
- It does not trigger in positional literals (`T{a, b}`) nor inside another field's value (e.g. call arguments).
- Structs from **other packages** (`http.Client{`): gopls completes it as usual. For those, use `<leader>gs` (`GoFillStruct`).
- Buffer words do not show up here, and gopls fields are hidden to avoid duplicates.

### Inside a function
Statement snippets show up (below). Declaration ones are hidden. Inside a struct none show up.

## Declaring sentinel errors (`goerrors`)

Type only the error **name**: the rest appears by itself, in gray, and grows with each letter (`utils/goerrors.lua`).

```go
ErrDescriptionTooLong|  →  ErrDescriptionTooLong = errors.New("description too long")
```

| Where | You type | Written |
|---|---|---|
| inside `var ( … )` | `ErrNotFound` | `ErrNotFound = errors.New("not found")` |
| after `var ` | `ErrInvalidID` | `ErrInvalidID = errors.New("invalid id")` |
| package level | `ErrEmptyTitle` | `var ErrEmptyTitle = errors.New("empty title")` |

| Key | Action |
|---|---|
| `Tab` | accepts the gray text (cursor at end of line) |
| `Enter` | accepts it and opens a new line (ideal to continue with the next error in the block) |
| `Esc` | discards it |

- Splits the name by capitals and lowercases it (`TitleTooLong` → `title too long`, `HTTPError` → `http error`).
- Also accepts unexported names (`errNotFound`). It needs `Err` + capital letter (`Error…` does not trigger).
- It only shows up with the cursor at the end of the line; while there is a suggestion the completion menu does not open.
- The `errors` import is added by goimports on save.
- It does not show up inside functions (sentinels are not declared there).

## Statement snippets (`nvim/snippets/go.json`)

Full names: you find them by typing **any part** (`wrap` → `errorsis`…, `ctx` → the context ones).

| Snippet | Inserts |
|---|---|
| `iferr` | `if err != nil { return err }` (`err` is left selected so you can change it; only inside functions) |
| `errorsis` | `if errors.Is(err, ErrX) { … }` |
| `errorsas` | `var t *MyError; if errors.As(err, &t) { … }` |
| `errorsentinel` | `var ErrX = errors.New("…")` (package level only; message derived from the name: see above) |
| `contexttimeout` | `ctx, cancel := context.WithTimeout(…)` + `defer cancel()` |
| `contextcancel` | `context.WithCancel` + `defer cancel()` |
| `waitgroup` | `sync.WaitGroup` over a range |
| `errgroup` | `errgroup.WithContext` + `g.Go` + `g.Wait` |
| `mutex` | `mu.Lock()` + `defer mu.Unlock()` |
| `once` | `once.Do(func() { … })` |
| `selectcontext` | `select` with `ctx.Done()` |
| `forrangeindex` | `for i, v := range items` |
| `forrangeint` | `for i := range n` (Go 1.22+) |
| `testsubtest` | `t.Run("name", func(t *testing.T) { … })` |
| `testtable` | table-driven test with subtests (package level only) |
| `testhelper` | helper with `t.Helper()` (package level only) |
| `httphandlerjson` | HTTP handler that responds with JSON (package level only) |
| `jsondecodebody` | decode the body's JSON |
| `slog` | `slog.Info/Error/Warn/Debug(…)` |
| `deferfunc` | `defer func() { … }()` |
| `embed` | `//go:embed` (package level only) |

The **friendly-snippets** ones that are not duplicated are also still available (`if`, `ife`, `ir`, `for`, `forr`, `switch`, `sel`, `go`, `df`, `fp`, `ff`, `lp`, `make`, `tf`, `tdt`, `hand`…).
The friendly declaration ones (`func`, `meth`, `tys`, `tyi`, `tyf`, `finit`, `fmain`) are hidden at package level because `gosmart` replaces them with more variants.

## Where everything lives

| File | Role |
|---|---|
| `lua/languages/go.lua` | declaration: gopls, goimports, gofumpt, golangci-lint, govet |
| `lua/languages/actions/go.lua` | `<leader>g` menu actions |
| `lua/gosetup/` | `<leader>gS`: presets (`presets/<topic>/<variant>`), `vars.lua` (module, Go version, main), `init.lua` (topics, flows) |
| `lua/plugins/languages/go.lua` | go.nvim (`tag_transform = "snakecase"`, `tag_options = false`) |
| `lua/servers/gopls.lua` | gopls settings |
| `lua/utils/gotags.lua` | blink source: struct tags |
| `lua/utils/gosmart.lua` | blink source: func/type/methods/constructor/interface + filters |
| `lua/utils/goindex.lua` | shared index (treesitter over text, per file/package/module) for the helpers below |
| `lua/utils/goiferr.lua` · `gomap.lua` · `gowire.lua` · `goenum.lua` · `goport.lua` · `gohttp.lua` | `if err` with returns, mappers, wiring, enums, interface from a struct, HTTP handlers |
| `lua/utils/goimpl.lua` | missing methods to satisfy an interface (receiver and declaration), bodies that call the dependency |
| `lua/utils/gomodel.lua` | `*_model.go`-only shortcuts: `functable`, `funcdomain`, `functodomain`, `funcfromdomain` |
| `lua/utils/goerrors.lua` | ghost text for sentinel errors (`ErrX` → `ErrX = errors.New("x")`); Tab/Enter are wired in `blink.lua` |
| `lua/plugins/editing/blink.lua` | registers the sources and filters (buffer, lsp, snippets) |
| `snippets/go.json` | statement snippets |

## Notes

- If the treesitter tree comes out broken (unclosed brace), the filter prefers to **show everything** rather than hide something useful.
- To tweak or add `func`/`type`/`method` variants: `FUNCS`, `TYPES` and `METHODS` tables in `utils/gosmart.lua`.
- To add a statement snippet: `snippets/go.json`, and if it only applies inside functions, add its name to `FUNC_ONLY` in `gosmart.lua`.
