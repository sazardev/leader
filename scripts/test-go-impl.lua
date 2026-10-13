-- Tests for utils/goimpl.lua: methods still missing to satisfy a Go interface, as completion (0 tokens).
-- Hermetic: Go modules in temporary directories, no gopls or network.
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

local gi = require "utils.goimpl"
local root = vim.fn.tempname()
local function write(rel, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
  vim.fn.writefile(lines, root .. "/" .. rel)
end
local function open(rel)
  vim.cmd("silent edit " .. root .. "/" .. rel)
  vim.bo.filetype = "go"
end
local function labels(items)
  return vim.tbl_map(function(it)
    return it.label
  end, items)
end
local function item(items, label)
  for _, it in ipairs(items) do
    if it.label == label then
      return it
    end
  end
end
-- what would be inserted, without the snippet markers
local function plain(it)
  return (it.textEdit.newText:gsub("%$%d", ""):gsub("\\([%$}\\])", "%1"))
end

write("go.mod", { "module notesapi", "", "go 1.21" })
write("internal/domain/note.go", {
  "package domain",
  "",
  'import "context"',
  "",
  "type Note struct{ ID string }",
  "",
  "type ListFilter struct{ Limit int }",
  "",
  "type NoteRepository interface {",
  "\tSave(ctx context.Context, note *Note) error",
  "\tFindByID(ctx context.Context, id string) (*Note, error)",
  "\tFindAll(ctx context.Context, filter ListFilter) ([]*Note, error)",
  "\tDelete(ctx context.Context, id string) error",
  "}",
})
write("internal/application/service.go", {
  "package application",
  "",
  "import (",
  '\t"context"',
  "",
  '\t"notesapi/internal/domain"',
  ")",
  "",
  "type NoteService interface {",
  "\tCreate(ctx context.Context, title, content string) (*domain.Note, error)",
  "\tGet(ctx context.Context, id string) (*domain.Note, error)",
  "\tList(ctx context.Context, filter domain.ListFilter) ([]*domain.Note, error)",
  "\tUpdate(ctx context.Context, id, title, content string) (*domain.Note, error)",
  "\tSetDone(ctx context.Context, id string, done bool) (*domain.Note, error)",
  "\tDelete(ctx context.Context, id string) error",
  "}",
})
write("internal/application/note_service.go", {
  "package application",
  "",
  'import "notesapi/internal/domain"',
  "",
  "type noteService struct {",
  "\trepo domain.NoteRepository",
  "}",
  "",
  "func NewNoteService(repo domain.NoteRepository) NoteService {",
  "\treturn &noteService{",
  "\t\trepo: repo,",
  "\t}",
  "}",
})

-- ── the user's case: noteService / NoteService ───────────────────────────
open "internal/application/note_service.go"
eq("detects the interface (constructor and name) and what is missing, in order", gi.missing "noteService", {
  { iface = "NoteService", missing = { "Create", "Get", "List", "Update", "SetDone", "Delete" } },
})

local function at_method(prefix)
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", prefix })
  local row = vim.api.nvim_buf_line_count(0)
  return { line = prefix, cursor = { row, #prefix } }, row
end
local ctx = at_method "func (s *noteService) "
local items = gi.method_items(ctx)
eq("typing the receiver: 'all' first, then each missing method", labels(items), {
  "…all missing (6)",
  "Create",
  "Get",
  "List",
  "Update",
  "SetDone",
  "Delete",
})
eq(
  "exact interface signature, with the receiver you typed and a compilable empty body",
  plain(item(items, "Create")),
  "Create(ctx context.Context, title, content string) (*domain.Note, error) {\n\t\n\treturn nil, nil\n}"
)
eq(
  "body: Get calls repo.FindByID (same parameter and return shape)",
  plain(item(items, "Get")),
  "Get(ctx context.Context, id string) (*domain.Note, error) {\n\treturn s.repo.FindByID(ctx, id)\n}"
)
eq(
  "body: List → repo.FindAll (even if the type is written with another package)",
  plain(item(items, "List")):match "return [^\n]+",
  "return s.repo.FindAll(ctx, filter)"
)
eq(
  "body: Delete → repo.Delete (same name and shape)",
  plain(item(items, "Delete")):match "return [^\n]+",
  "return s.repo.Delete(ctx, id)"
)
eq(
  "Update and SetDone have no equivalent in the repo: empty body returning zero values",
  plain(item(items, "SetDone")):match "return [^\n]+",
  "return nil, nil"
)
eq("the 'all' item carries each method with its full header", {
  select(2, plain(items[1]):gsub("\nfunc %(s %*noteService%) ", "")),
  plain(items[1]):find "^Create%(" ~= nil,
}, { 5, true })
eq(
  "inserts from what was typed (replaces only the name)",
  { item(items, "Get").textEdit.range.start.character, item(items, "Get").textEdit.range["end"].character },
  { 22, 22 }
)

-- the "all" snippet is valid: nvim only admits ONE `$0` (each empty body carries its own $N)
local all = items[1].textEdit.newText
eq("'all': at most one $0 and numbered tabstops for the empty bodies", {
  select(2, all:gsub("%$0", "")) <= 1,
  all:find "%$1" ~= nil,
  select(2, item(items, "Create").textEdit.newText:gsub("%$0", "")),
}, { true, true, 1 })
local parsed_ok = pcall(vim.lsp._snippet_grammar.parse, all)
eq("'all' is accepted by nvim's snippet parser", parsed_ok, true)

-- filtering by what was typed
local ctx2 = at_method "func (s *noteService) Se"
eq("what was typed filters (Se → SetDone)", labels(gi.method_items(ctx2)), { "SetDone" })
eq(
  "without a complete receiver there is nothing to offer",
  gi.method_items { line = "func (s *noteService", cursor = { 1, 20 } },
  {}
)

-- at the start of the declaration (column 0)
local top = gi.declaration_items({ start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, "")
eq("at the start of a declaration: for the file's struct, with receiver and header", {
  top[1].label,
  top[2].label,
  plain(top[3]):match "^func %(s %*noteService%) Get%(",
}, { "func (s *noteService) …all missing (6)", "func (s *noteService) Create", "func (s *noteService) Get(" })

-- what is already implemented is not offered again, and it helps recognise the interface
vim.cmd "silent bwipeout!"
write("internal/application/note_service.go", {
  "package application",
  "",
  'import "notesapi/internal/domain"',
  "",
  "type noteService struct{ repo domain.NoteRepository }",
  "",
  "func (s *noteService) Get(ctx context.Context, id string) (*domain.Note, error) { return nil, nil }",
  "func (s *noteService) Delete(ctx context.Context, id string) error { return nil }",
})
open "internal/application/note_service.go"
eq(
  "what is already implemented is excluded (no constructor: by name and by what it already has)",
  gi.missing "noteService",
  {
    { iface = "NoteService", missing = { "Create", "List", "Update", "SetDone" } },
  }
)
eq(
  "the receiver already used in the struct is respected even if you do not type it",
  select(
    2,
    plain(gi.declaration_items({ start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, "")[2]):gsub(
      "func %(s %*noteService%)",
      ""
    )
  ),
  1
)

-- ── interface from ANOTHER package: qualified types and made-up names ─────────
write("internal/infrastructure/note_repo.go", {
  "package infrastructure",
  "",
  "import (",
  '\t"database/sql"',
  "",
  '\t"notesapi/internal/domain"',
  ")",
  "",
  "type postgresNoteRepository struct{ db *sql.DB }",
  "",
  "func NewNoteRepository(db *sql.DB) domain.NoteRepository {",
  "\treturn &postgresNoteRepository{db: db}",
  "}",
})
open "internal/infrastructure/note_repo.go"
eq("interface from another package of the module: read from disk", gi.missing "postgresNoteRepository", {
  { iface = "domain.NoteRepository", missing = { "Save", "FindByID", "FindAll", "Delete" } },
})
local repo_items = gi.method_items(at_method "func (r *postgresNoteRepository) ")
eq("the other package's types are qualified (Note → domain.Note, ListFilter → domain.ListFilter)", {
  plain(item(repo_items, "FindByID")):match "^FindByID%b() %b()",
  plain(item(repo_items, "FindAll")):match "^FindAll%b() %b()",
}, {
  "FindByID(ctx context.Context, id string) (*domain.Note, error)",
  "FindAll(ctx context.Context, filter domain.ListFilter) ([]*domain.Note, error)",
})

-- ── var _ I = (*T)(nil), unnamed parameters, and what it must NOT offer ─────
write("pkg/store/store.go", {
  "package store",
  "",
  "type Closer interface {",
  "\tClose() error",
  "\tWrite(string, []byte) (int, error)",
  "}",
  "",
  "type fileStore struct{}",
  "",
  "var _ Closer = (*fileStore)(nil)",
  "",
  "type unrelated struct{}",
})
open "pkg/store/store.go"
eq(
  "var _ I = (*T)(nil) declares the interface even if the name does not look alike",
  gi.missing "fileStore",
  { { iface = "Closer", missing = { "Close", "Write" } } }
)
eq("an unrelated struct gets no suggestions", gi.missing "unrelated", {})
local store_items = gi.method_items(at_method "func (f fileStore) ")
eq("unnamed parameters: made up (string → arg1, []byte → arg2) and value receiver", {
  plain(item(store_items, "Write")):match "^Write%b() %b()",
  item(store_items, "Close") ~= nil,
}, { "Write(arg1 string, arg2 []byte) (int, error)", true })
eq("zero return of (int, error)", plain(item(store_items, "Write")):match "return [^\n]+", "return 0, nil")

vim.cmd "silent bwipeout!"
vim.fn.delete(root, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
