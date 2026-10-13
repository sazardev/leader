-- Pruebas de utils/goimpl.lua: métodos que faltan para cumplir una interfaz de Go, como completado (0 tokens).
-- Hermético: módulos Go en directorios temporales, sin gopls ni red.
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
-- lo que se insertaría, sin los marcadores del snippet
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

-- ── el caso del usuario: noteService / NoteService ───────────────────────────
open "internal/application/note_service.go"
eq("detecta la interfaz (constructor y nombre) y lo que falta, en orden", gi.missing "noteService", {
  { iface = "NoteService", missing = { "Create", "Get", "List", "Update", "SetDone", "Delete" } },
})

local function at_method(prefix)
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", prefix })
  local row = vim.api.nvim_buf_line_count(0)
  return { line = prefix, cursor = { row, #prefix } }, row
end
local ctx = at_method "func (s *noteService) "
local items = gi.method_items(ctx)
eq("al escribir el receptor: 'todos' primero y luego cada método que falta", labels(items), {
  "…all missing (6)",
  "Create",
  "Get",
  "List",
  "Update",
  "SetDone",
  "Delete",
})
eq(
  "firma exacta de la interfaz, con el receptor que tecleaste y el cuerpo vacío compilable",
  plain(item(items, "Create")),
  "Create(ctx context.Context, title, content string) (*domain.Note, error) {\n\t\n\treturn nil, nil\n}"
)
eq(
  "cuerpo: Get llama a repo.FindByID (misma forma de parámetros y retorno)",
  plain(item(items, "Get")),
  "Get(ctx context.Context, id string) (*domain.Note, error) {\n\treturn s.repo.FindByID(ctx, id)\n}"
)
eq(
  "cuerpo: List → repo.FindAll (aunque el tipo se escriba con otro paquete)",
  plain(item(items, "List")):match "return [^\n]+",
  "return s.repo.FindAll(ctx, filter)"
)
eq(
  "cuerpo: Delete → repo.Delete (mismo nombre y forma)",
  plain(item(items, "Delete")):match "return [^\n]+",
  "return s.repo.Delete(ctx, id)"
)
eq(
  "Update y SetDone no tienen equivalente en el repo: cuerpo vacío con return de ceros",
  plain(item(items, "SetDone")):match "return [^\n]+",
  "return nil, nil"
)
eq("el ítem 'todos' lleva cada método con su cabecera completa", {
  select(2, plain(items[1]):gsub("\nfunc %(s %*noteService%) ", "")),
  plain(items[1]):find "^Create%(" ~= nil,
}, { 5, true })
eq(
  "se inserta desde lo tecleado (reemplaza solo el nombre)",
  { item(items, "Get").textEdit.range.start.character, item(items, "Get").textEdit.range["end"].character },
  { 22, 22 }
)

-- el snippet de "todos" es válido: nvim solo admite UN `$0` (cada cuerpo vacío lleva su propio $N)
local all = items[1].textEdit.newText
eq("'todos': un solo $0 como mucho y tabstops numerados para los cuerpos vacíos", {
  select(2, all:gsub("%$0", "")) <= 1,
  all:find "%$1" ~= nil,
  select(2, item(items, "Create").textEdit.newText:gsub("%$0", "")),
}, { true, true, 1 })
local parsed_ok = pcall(vim.lsp._snippet_grammar.parse, all)
eq("'todos' lo acepta el parser de snippets de nvim", parsed_ok, true)

-- filtrado por lo tecleado
local ctx2 = at_method "func (s *noteService) Se"
eq("lo tecleado filtra (Se → SetDone)", labels(gi.method_items(ctx2)), { "SetDone" })
eq(
  "sin receptor completo no hay nada que ofrecer",
  gi.method_items { line = "func (s *noteService", cursor = { 1, 20 } },
  {}
)

-- al empezar la declaración (columna 0)
local top = gi.declaration_items({ start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, "")
eq("al empezar una declaración: para el struct del archivo, con receptor y cabecera", {
  top[1].label,
  top[2].label,
  plain(top[3]):match "^func %(n %*noteService%) Get%(",
}, { "func (n *noteService) …all missing (6)", "func (n *noteService) Create", "func (n *noteService) Get(" })

-- lo ya implementado no se vuelve a ofrecer, y sirve para reconocer la interfaz
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
eq("lo ya implementado se excluye (sin constructor: por nombre y por lo que ya tiene)", gi.missing "noteService", {
  { iface = "NoteService", missing = { "Create", "List", "Update", "SetDone" } },
})
eq(
  "el receptor ya usado en el struct se respeta aunque no lo teclees",
  select(
    2,
    plain(gi.declaration_items({ start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }, "")[2]):gsub(
      "func %(s %*noteService%)",
      ""
    )
  ),
  1
)

-- ── interfaz de OTRO paquete: tipos calificados y nombres inventados ─────────
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
eq("interfaz de otro paquete del módulo: se lee de disco", gi.missing "postgresNoteRepository", {
  { iface = "domain.NoteRepository", missing = { "Save", "FindByID", "FindAll", "Delete" } },
})
local repo_items = gi.method_items(at_method "func (r *postgresNoteRepository) ")
eq("los tipos del otro paquete se califican (Note → domain.Note, ListFilter → domain.ListFilter)", {
  plain(item(repo_items, "FindByID")):match "^FindByID%b() %b()",
  plain(item(repo_items, "FindAll")):match "^FindAll%b() %b()",
}, {
  "FindByID(ctx context.Context, id string) (*domain.Note, error)",
  "FindAll(ctx context.Context, filter domain.ListFilter) ([]*domain.Note, error)",
})

-- ── var _ I = (*T)(nil), parámetros sin nombre, y lo que NO debe ofrecer ─────
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
  "var _ I = (*T)(nil) declara la interfaz aunque el nombre no se parezca",
  gi.missing "fileStore",
  { { iface = "Closer", missing = { "Close", "Write" } } }
)
eq("un struct sin relación no recibe sugerencias", gi.missing "unrelated", {})
local store_items = gi.method_items(at_method "func (f fileStore) ")
eq("parámetros sin nombre: se inventan (string → arg1, []byte → arg2) y receptor por valor", {
  plain(item(store_items, "Write")):match "^Write%b() %b()",
  item(store_items, "Close") ~= nil,
}, { "Write(arg1 string, arg2 []byte) (int, error)", true })
eq("retorno cero de (int, error)", plain(item(store_items, "Write")):match "return [^\n]+", "return 0, nil")

vim.cmd "silent bwipeout!"
vim.fn.delete(root, "rf")
print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
