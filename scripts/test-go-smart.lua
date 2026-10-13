-- Pruebas de las ayudas de Go sin LLM: `if err != nil` con retornos reales (goiferr), mapeadores (gomap),
-- cableado de constructores (gowire), helpers de enum (goenum), interfaz desde un struct (goport) y
-- handlers HTTP (gohttp). Hermético: módulos Go en directorios temporales, sin gopls ni red.
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

local root = vim.fn.tempname()
local function write(rel, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
  vim.fn.writefile(lines, root .. "/" .. rel)
end
local function open(rel)
  vim.cmd("silent edit! " .. root .. "/" .. rel)
  vim.bo.filetype = "go"
end
--- Pone el buffer con `lines` y el cursor al final de la ÚLTIMA línea; devuelve el ctx de blink
local function type_at(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  local row = #lines
  local col = #lines[row]
  vim.api.nvim_win_set_cursor(0, { row, col })
  return { line = lines[row], cursor = { row, col } }
end
local function labels(items)
  return vim.tbl_map(function(it)
    return it.label .. " | " .. it.labelDetails.description
  end, items)
end
local function plain(it)
  return (it.textEdit.newText:gsub("%${%d:([^}]*)}", "%1"):gsub("%$%d", ""):gsub("\\([%$}\\])", "%1"))
end

write("go.mod", { "module notesapi", "", "go 1.21" })
open "svc.go"

-- ── goiferr ──────────────────────────────────────────────────────────────────
local iferr = require "utils.goiferr"
eq(
  "words: FindByID → find by id",
  { iferr.words "FindByID", iferr.words "Save", iferr.words "GetHTTPServer" },
  { "find by id", "save", "get http server" }
)

local ctx = type_at {
  "package p",
  "",
  "func (s *noteService) Get(ctx context.Context, id string) (*Note, error) {",
  "\tn, err := s.repo.FindByID(ctx, id)",
  "\t",
}
local items = iferr.items(ctx)
eq("iferr: tras `x, err := …` ofrece envolver y devolver tal cual", labels(items), {
  "if err != nil | wrap · find by id",
  "if err != nil | return err",
})
eq(
  "iferr: el retorno sale de la función (nil por el puntero) y el mensaje de lo llamado",
  plain(items[1]),
  'if err != nil {\n\treturn nil, fmt.Errorf("find by id: %w", err)\n}\n'
)
eq(
  "iferr: la variante simple devuelve el error sin envolver",
  plain(items[2]),
  "if err != nil {\n\treturn nil, err\n}\n"
)
eq(
  "iferr: la primera tecla de salto es el mensaje",
  items[1].textEdit.newText:find("${1:find by id}", 1, true) ~= nil,
  true
)
eq("iferr: es posición de menú automático (línea recién abierta)", iferr.fresh(ctx), true)

write("config.go", { "package p", "", "type Config struct{ Path string }" })
local ctx_multi = type_at {
  "package p",
  "",
  "func Load(path string) (Config, map[string]int, int, error) {",
  "\tdata, err := os.ReadFile(path)",
  "\t",
}
eq(
  "iferr: ceros de varios retornos (struct, map, int)",
  plain(iferr.items(ctx_multi)[2]),
  "if err != nil {\n\treturn Config{}, nil, 0, err\n}\n"
)
eq(
  "iferr: Config no es struct conocido aquí → *new si no se conoce el tipo",
  plain(iferr.items(ctx_multi)[2]):find("return ", 1, true) ~= nil,
  true
)

local ctx_only = type_at {
  "package p",
  "",
  "func Save(r Repo, n *Note) error {",
  "\terr := r.Save(n)",
  "\t",
}
eq(
  "iferr: función que solo devuelve error",
  plain(iferr.items(ctx_only)[1]),
  'if err != nil {\n\treturn fmt.Errorf("save: %w", err)\n}\n'
)

local ctx_main = type_at {
  "package main",
  "",
  "func main() {",
  "\tdb, err := sql.Open(driver, dsn)",
  "\t",
}
eq("iferr: en main usa log.Fatalf", labels(iferr.items(ctx_main)), { "if err != nil | log.Fatalf" })
eq(
  "iferr: main + log.Fatalf lleva el mensaje del open",
  plain(iferr.items(ctx_main)[1]),
  'if err != nil {\n\tlog.Fatalf("open: %v", err)\n}\n'
)

local ctx_noerr = type_at {
  "package p",
  "",
  "func Count(r Repo) int {",
  "\tn, err := r.Count()",
  "\t",
}
eq(
  "iferr: una función que no devuelve error no recibe el bloque",
  { iferr.items(ctx_noerr), iferr.fresh(ctx_noerr) },
  { {}, false }
)

local ctx_prefix = type_at {
  "package p",
  "",
  "func Save(r Repo, n *Note) error {",
  "\terr := r.Save(n)",
  "\tif",
}
eq("iferr: tecleando `if` también sale", #iferr.items(ctx_prefix), 2)
local ctx_other = type_at {
  "package p",
  "",
  "func Save(r Repo, n *Note) error {",
  "\terr := r.Save(n)",
  "\tfor",
}
eq("iferr: tecleando otra cosa no estorba", iferr.items(ctx_other), {})
local ctx_done = type_at {
  "package p",
  "",
  "func Save(r Repo, n *Note) error {",
  "\terr := r.Save(n)",
  "\t",
  "\tif err != nil {",
  "\t\treturn err",
  "\t}",
}
vim.api.nvim_win_set_cursor(0, { 5, 1 })
eq("iferr: si ya hay un `if err` debajo no se ofrece otro", iferr.items { line = "\t", cursor = { 5, 1 } }, {})
local ctx_none = type_at {
  "package p",
  "",
  "func Save(r Repo) error {",
  "\tx := 1",
  "\t",
}
eq("iferr: sin error asignado antes no sale", iferr.items(ctx_none), {})
type_at {
  "package p",
  "",
  "func Run(r Repo) error {",
  "\tgo func() (int, error) {",
  "\t\tv, err := r.Do()",
  "\t\t",
  "\t}()",
  "\treturn nil",
  "}",
}
vim.api.nvim_win_set_cursor(0, { 6, 2 })
eq(
  "iferr: dentro de un func literal usa SUS retornos",
  plain(iferr.items({ line = "\t\t", cursor = { 6, 2 } })[2]),
  "if err != nil {\n\treturn 0, err\n}\n"
)

-- ── proyecto por capas para el resto ─────────────────────────────────────────
write("go.mod", { "module notesapi", "", "go 1.22" })
write("internal/domain/note.go", {
  "package domain",
  "",
  'import "context"',
  "",
  "type Status string",
  "",
  "type Note struct {",
  "\tID     string",
  "\tTitle  string",
  "\tStatus Status",
  "\tTags   []string",
  "}",
  "",
  "type Tag struct {",
  "\tid   string",
  "\tname string",
  "}",
  "",
  "func (t Tag) ID() string   { return t.id }",
  "func (t Tag) Name() string { return t.name }",
  "",
  "type ListFilter struct {",
  "\tQuery  string",
  "\tDone   *bool",
  "\tLimit  int",
  "\tOffset int",
  "}",
  "",
  "type NoteRepository interface {",
  "\tSave(ctx context.Context, note *Note) error",
  "\tFindByID(ctx context.Context, id string) (*Note, error)",
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
  "\tSetDone(ctx context.Context, id string, done bool) (*domain.Note, error)",
  "\tDelete(ctx context.Context, id string) error",
  "}",
  "",
  "func NewNoteService(repo domain.NoteRepository) NoteService { return &noteService{repo: repo} }",
})
write("internal/application/note_service.go", {
  "package application",
  "",
  'import "notesapi/internal/domain"',
  "",
  "type noteService struct{ repo domain.NoteRepository }",
  "",
  "func (s *noteService) Get() {}",
  "func (s *noteService) Delete() {}",
  "func (s *noteService) Create() {}",
})
write("internal/infrastructure/note_repo.go", {
  "package infrastructure",
  "",
  "import (",
  '\t"context"',
  '\t"database/sql"',
  "",
  '\t"notesapi/internal/domain"',
  ")",
  "",
  "type postgresNoteRepository struct{ db *sql.DB }",
  "",
  "func NewNoteRepository(db *sql.DB) domain.NoteRepository { return &postgresNoteRepository{db: db} }",
  "",
  "func (r *postgresNoteRepository) Save(ctx context.Context, note *domain.Note) error { return nil }",
  "func (r *postgresNoteRepository) FindByID(ctx context.Context, id string) (*domain.Note, error) { return nil, nil }",
})

local TOP = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }
local function find(items, label)
  for _, it in ipairs(items) do
    if it.label == label then
      return it
    end
  end
end
local function sorted(list)
  table.sort(list)
  return list
end

-- ── goenum ───────────────────────────────────────────────────────────────────
local goenum = require "utils.goenum"
write("internal/domain/status.go", {
  "package domain",
  "",
  "type Status string",
  "",
  "const (",
  '\tStatusPending Status = "pending"',
  '\tStatusDone    Status = "done"',
  ")",
  "",
  "type Priority int",
  "",
  "const (",
  "\tPriorityLow Priority = iota",
  "\tPriorityHigh",
  ")",
  "",
  "func (s Status) IsValid() bool { return true }",
})
open "internal/domain/status.go"
eq("enum string: lo que falta (IsValid ya existe)", goenum.missing "Status", { "ParseStatus", "UnmarshalText" })
eq("enum numérico: String, Parse, Marshal/UnmarshalText además de IsValid", goenum.missing "Priority", {
  "IsValid",
  "ParsePriority",
  "String",
  "MarshalText",
  "UnmarshalText",
})
local enum_items = goenum.declaration_items(TOP, "")
eq("enum: ítems con 'todos' primero para cada tipo", labels(enum_items), {
  "func …enum helpers Priority (5) | enum",
  "func (p Priority) IsValid | Priority · enum",
  "func ParsePriority | Priority · enum",
  "func (p Priority) String | Priority · enum",
  "func (p Priority) MarshalText | Priority · enum",
  "func (p *Priority) UnmarshalText | Priority · enum",
  "func …enum helpers Status (2) | enum",
  "func ParseStatus | Status · enum",
  "func (s *Status) UnmarshalText | Status · enum",
})
eq(
  "enum string: Parse valida con un switch sobre las constantes",
  plain(find(enum_items, "func ParseStatus")),
  'func ParseStatus(v string) (Status, error) {\n\tswitch s := Status(v); s {\n\tcase StatusPending, StatusDone:\n\t\treturn s, nil\n\t}\n\treturn "", fmt.Errorf("invalid status %q", v)\n}'
)
eq(
  "enum numérico: String usa el nombre de la constante sin el prefijo del tipo",
  plain(find(enum_items, "func (p Priority) String")),
  'func (p Priority) String() string {\n\tswitch p {\n\tcase PriorityLow:\n\t\treturn "low"\n\tcase PriorityHigh:\n\t\treturn "high"\n\t}\n\treturn fmt.Sprintf("Priority(%d)", int(p))\n}'
)
eq(
  "enum numérico: Parse por nombre devuelve 0 si es inválido",
  plain(find(enum_items, "func ParsePriority")):find('return 0, fmt.Errorf("invalid priority %q", v)', 1, true) ~= nil,
  true
)

-- ── goport ───────────────────────────────────────────────────────────────────
local goport = require "utils.goport"
open "internal/application/service.go"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "package application", "", "type NoteService interface {", "\t", "}" })
local ictx = { line = "\t", cursor = { 4, 1 } }
vim.api.nvim_win_set_cursor(0, { 4, 1 })
local port_items = goport.interface_items(ictx)
eq("interface desde un struct: los métodos del struct relacionado que la interfaz aún no tiene", labels(port_items), {
  "…all of noteService (3) | from methods",
  "Get | noteService · method",
  "Delete | noteService · method",
  "Create | noteService · method",
})
eq("interface: el ítem de un método lleva su firma (sin cuerpo)", find(port_items, "Get").textEdit.newText, "Get()")
vim.api.nvim_buf_set_lines(0, 3, 4, false, { "\tGe" })
eq(
  "interface: lo tecleado filtra",
  labels(goport.interface_items { line = "\tGe", cursor = { 4, 3 } }),
  { "Get | noteService · method" }
)

open "internal/application/note_service.go"
local assert_items = goport.declaration_items(TOP, "va")
eq(
  "var _: la comprobación del struct cuya interfaz se reconoce por su constructor",
  labels(assert_items),
  { "var _ NoteService = (*noteService)(nil) | compile-time check" }
)
eq("var _: nada si no se teclea `v…` de var", goport.declaration_items(TOP, "xyz"), {})

-- ── gomap ────────────────────────────────────────────────────────────────────
local gomap = require "utils.gomap"
eq(
  "gomap: bases de un DTO (con y sin prefijo de acción)",
  { (gomap.bases "NoteResponse"), (gomap.bases "CreateNoteRequest") },
  { { "Note" }, { "Note", "CreateNote" } }
)
eq("gomap: sin sufijo conocido no hay par", { gomap.bases "Note" }, { {} })
write("internal/transport/dto.go", {
  "package transport",
  "",
  'import "notesapi/internal/domain"',
  "",
  "type NoteResponse struct {",
  '\tID     string `json:"id"`',
  "\tTitle  string",
  "\tStatus string",
  "\tTags   []string",
  "\tExtra  int",
  "}",
  "",
  "type TagResponse struct{ ID, Name string }",
  "",
  "type CreateNoteRequest struct{ Title string }",
})
open "internal/transport/dto.go"
local map_items = gomap.declaration_items(TOP, "")
eq("gomap: del dominio al DTO, la lista y de vuelta, para cada par", labels(map_items), {
  "func toCreateNoteRequest | domain.Note → CreateNoteRequest",
  "func toCreateNoteRequests | domain.Note → CreateNoteRequest (list)",
  "func (r CreateNoteRequest) toNote | CreateNoteRequest → domain.Note",
  "func toNoteResponse | domain.Note → NoteResponse",
  "func toNoteResponses | domain.Note → NoteResponse (list)",
  "func (r NoteResponse) toNote | NoteResponse → domain.Note",
  "func toTagResponse | domain.Tag → TagResponse",
  "func toTagResponses | domain.Tag → TagResponse (list)",
  "func (r TagResponse) toTag | TagResponse → domain.Tag",
})
eq(
  "gomap: campos por nombre, conversión de tipos definidos y TODO donde no encaja",
  plain(find(map_items, "func toNoteResponse")),
  "func toNoteResponse(n *domain.Note) NoteResponse {\n\treturn NoteResponse{\n\t\tID: n.ID,\n\t\tTitle: n.Title,\n\t\tStatus: string(n.Status),\n\t\tTags: n.Tags,\n\t\t// TODO: Extra (int) has no source field in Note\n\t}\n}"
)
eq(
  "gomap: con campos privados y getter, usa el getter",
  plain(find(map_items, "func toTagResponse")):find("ID: t.ID(),", 1, true) ~= nil,
  true
)
eq(
  "gomap: de vuelta convierte a los tipos del dominio (calificados)",
  plain(find(map_items, "func (r NoteResponse) toNote")):find("Status: domain.Status(r.Status),", 1, true) ~= nil,
  true
)
eq(
  "gomap: la lista usa el mapeador de uno",
  plain(find(map_items, "func toNoteResponses")):find("out = append(out, toNoteResponse(n))", 1, true) ~= nil,
  true
)
eq(
  "gomap: un struct con campos privados avisa al construir",
  plain(find(map_items, "func (r TagResponse) toTag")):find("TODO: domain.Tag has unexported fields", 1, true) ~= nil,
  true
)

-- ── gowire ───────────────────────────────────────────────────────────────────
local gowire = require "utils.gowire"
write("cmd/main.go", { "package main", "" })
open "cmd/main.go"
local wctx = type_at {
  "package main",
  "",
  "func main() {",
  '\tdb, err := sql.Open("pgx", dsn)',
  "\tctx := context.Background()",
  "\tnoteRepo := infrastructure.NewNoteRepository(db)",
  "\tnoteSer",
}
local wire_items = gowire.items(wctx)
eq(
  "gowire: tecleando el nombre del servicio sale su constructor con el repo ya puesto",
  labels(wire_items),
  { "noteService := application.NewNoteService(…) | application" }
)
eq(
  "gowire: el argumento es la variable cuyo tipo cumple la interfaz del parámetro",
  plain(wire_items[1]),
  "noteService := application.NewNoteService(noteRepo)"
)
local wctx2 = type_at {
  "package main",
  "",
  "func main() {",
  '\tdb, err := sql.Open("pgx", dsn)',
  "\tNewNoteRepo",
}
eq(
  "gowire: el parámetro `db` se toma de la variable con ese nombre",
  plain(gowire.items(wctx2)[1]),
  "noteRepository := infrastructure.NewNoteRepository(db)"
)
local wctx3 = type_at {
  "package main",
  "",
  "func main() {",
  "\tNewNoteSer",
}
eq(
  "gowire: sin nada en ámbito, un hueco con el nombre del parámetro",
  gowire.items(wctx3)[1].textEdit.newText,
  "noteService := application.NewNoteService(${1:repo})"
)
eq("gowire: no ofrece nada con menos de 3 letras", gowire.items { line = "\tNe", cursor = { 4, 3 } }, {})
local wctx4 = type_at { "package main", "", "var x = 1", "NewNote" }
eq("gowire: fuera de una función no ofrece nada", gowire.items(wctx4), {})

-- ── gohttp ───────────────────────────────────────────────────────────────────
local gohttp = require "utils.gohttp"
write("internal/transport/note_handler.go", { "package transport", "" })
local function handler_file(extra)
  local lines = {
    "package transport",
    "",
    'import "notesapi/internal/application"',
    "",
    "type NoteHandler struct{ svc application.NoteService }",
    "",
  }
  vim.list_extend(lines, extra or {})
  write("internal/transport/note_handler.go", lines)
  open "internal/transport/note_handler.go"
end
handler_file()
local hctx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
local h_items = gohttp.method_items(hctx)
eq("gohttp (net/http, go 1.22): todos, rutas y un handler por método del servicio", labels(h_items), {
  "…all handlers (5) | NoteService",
  "Routes | NoteService · 5 routes",
  "Create | NoteService · POST",
  "Get | NoteService · GET",
  "List | NoteService · GET",
  "SetDone | NoteService · PATCH",
  "Delete | NoteService · DELETE",
})
eq(
  "gohttp: Get lee el id de la ruta, llama y responde con el JSON",
  plain(find(h_items, "Get")),
  'Get(w http.ResponseWriter, r *http.Request) {\n\tid := r.PathValue("id")\n\tres, err := h.svc.Get(r.Context(), id)\n\tif err != nil {\n\t\twriteError(w, err)\n\t\treturn\n\t}\n\twriteJSON(w, http.StatusOK, res)\n}'
)
eq(
  "gohttp: Create decodifica un cuerpo JSON con tags snake_case y responde 201",
  plain(find(h_items, "Create")),
  'Create(w http.ResponseWriter, r *http.Request) {\n\tvar body struct {\n\t\tTitle string `json:"title"`\n\t\tContent string `json:"content"`\n\t}\n\tif err := json.NewDecoder(r.Body).Decode(&body); err != nil {\n\t\thttp.Error(w, err.Error(), http.StatusBadRequest)\n\t\treturn\n\t}\n\tres, err := h.svc.Create(r.Context(), body.Title, body.Content)\n\tif err != nil {\n\t\twriteError(w, err)\n\t\treturn\n\t}\n\twriteJSON(w, http.StatusCreated, res)\n}'
)
local list_text = plain(find(h_items, "List"))
eq("gohttp: List arma el filtro desde la query campo a campo", {
  list_text:find('filter := domain.ListFilter{\n\t\tQuery: q.Get("query"),\n\t}', 1, true) ~= nil,
  list_text:find("strconv.Atoi(v)", 1, true) ~= nil,
  list_text:find("strconv.ParseBool(v)", 1, true) ~= nil,
  list_text:find("filter.Done = &b", 1, true) ~= nil,
}, { true, true, true, true })
eq(
  "gohttp: Delete (solo error) responde 204",
  plain(find(h_items, "Delete")):find("w.WriteHeader(http.StatusNoContent)", 1, true) ~= nil,
  true
)
eq(
  "gohttp: SetDone mezcla id de ruta y cuerpo",
  plain(find(h_items, "SetDone")):find("h.svc.SetDone(r.Context(), id, body.Done)", 1, true) ~= nil,
  true
)
eq(
  "gohttp: Routes registra el verbo y la ruta de cada método",
  plain(find(h_items, "Routes")),
  'Routes(mux *http.ServeMux) {\n\tmux.HandleFunc("POST /notes", h.Create)\n\tmux.HandleFunc("GET /notes/{id}", h.Get)\n\tmux.HandleFunc("GET /notes", h.List)\n\tmux.HandleFunc("PATCH /notes/{id}/done", h.SetDone)\n\tmux.HandleFunc("DELETE /notes/{id}", h.Delete)\n}'
)
local top_http = gohttp.declaration_items(TOP, "")
eq("gohttp al empezar la declaración: con cabecera y el helper de respuestas al final", {
  top_http[1].label,
  top_http[#top_http].label,
}, { "func (h *NoteHandler) …all handlers (5)", "func …handler helpers (writeJSON, writeError)" })

write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/gin-gonic/gin v1.9.0" })
handler_file()
local gctx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
local gin_items = gohttp.method_items(gctx)
eq("gohttp (gin): firma con *gin.Context y respuestas con c.JSON", {
  plain(find(gin_items, "Get")):match "^Get%b() {",
  plain(find(gin_items, "Get")):find('c.Param("id")', 1, true) ~= nil,
  plain(find(gin_items, "Get")):find("c.JSON(http.StatusOK, res)", 1, true) ~= nil,
  plain(find(gin_items, "Routes")):find('r.GET("/notes/:id", h.Get)', 1, true) ~= nil,
  find(gin_items, "…all handlers (5)") ~= nil,
}, { "Get(c *gin.Context) {", true, true, true, true })
write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/labstack/echo/v4 v4.0.0" })
handler_file()
local ectx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
eq("gohttp (echo): devuelve error y c.JSON", {
  plain(find(gohttp.method_items(ectx), "Get")):match "^Get%b() error {",
  plain(find(gohttp.method_items(ectx), "Get")):find("return c.JSON(http.StatusOK, res)", 1, true) ~= nil,
}, { "Get(c echo.Context) error {", true })
write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/gofiber/fiber/v2 v2.0.0" })
eq("gohttp: con fiber no se inventa nada", gohttp.method_items(ectx), {})
write("go.mod", { "module notesapi", "", "go 1.21" })
eq("gohttp: net/http antes de Go 1.22 (sin PathValue) tampoco", gohttp.method_items(ectx), {})
write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/go-chi/chi/v5 v5.0.0" })
handler_file()
local cctx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
eq("gohttp (chi): URLParam y rutas con r.Get", {
  plain(find(gohttp.method_items(cctx), "Get")):find('chi.URLParam(r, "id")', 1, true) ~= nil,
  plain(find(gohttp.method_items(cctx), "Routes")):find('r.Get("/notes/{id}", h.Get)', 1, true) ~= nil,
}, { true, true })

-- el filtro se resuelve aunque el archivo del handler no importe el paquete del dominio
write("go.mod", { "module notesapi", "", "go 1.22" })
write("internal/web/h.go", {
  "package web",
  "",
  'import "notesapi/internal/application"',
  "",
  "type NoteHandler struct{ svc application.NoteService }",
  "",
  "func (h *NoteHandler) ",
})
open "internal/web/h.go"
local web_items = gohttp.method_items { line = "func (h *NoteHandler) ", cursor = { 7, 22 } }
local web_list = plain(find(web_items, "List"))
eq("gohttp: el filtro del servicio se lee del dominio aunque el handler no lo importe", {
  web_list:find('filter := domain.ListFilter{\n\t\tQuery: q.Get("query"),', 1, true) ~= nil,
  web_list:find("strconv.Atoi(v)", 1, true) ~= nil,
}, { true, true })
eq(
  "gohttp: 'todos' tras el receptor no repite la cabecera del primero",
  plain(web_items[1]):find "^Create%(" ~= nil,
  true
)

vim.cmd "silent! bwipeout!"
vim.fn.delete(root, "rf")
print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
