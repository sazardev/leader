-- Tests for the Go helpers without an LLM: `if err != nil` with real returns (goiferr), mappers (gomap),
-- constructor wiring (gowire), enum helpers (goenum), interface from a struct (goport) and
-- HTTP handlers (gohttp). Hermetic: Go modules in temporary directories, no gopls or network.
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
--- Sets the buffer to `lines` with the cursor at the end of the LAST line; returns the blink ctx
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
eq("iferr: after `x, err := …` offers to wrap and to return as is", labels(items), {
  "if err != nil | wrap · find by id",
  "if err != nil | return err",
})
eq(
  "iferr: the return comes from the function (nil for the pointer) and the message from the callee",
  plain(items[1]),
  'if err != nil {\n\treturn nil, fmt.Errorf("find by id: %w", err)\n}\n'
)
eq("iferr: the simple variant returns the error unwrapped", plain(items[2]), "if err != nil {\n\treturn nil, err\n}\n")
eq("iferr: the first jump stop is the message", items[1].textEdit.newText:find("${1:find by id}", 1, true) ~= nil, true)
eq("iferr: is an automatic-menu position (freshly opened line)", iferr.fresh(ctx), true)

write("config.go", { "package p", "", "type Config struct{ Path string }" })
local ctx_multi = type_at {
  "package p",
  "",
  "func Load(path string) (Config, map[string]int, int, error) {",
  "\tdata, err := os.ReadFile(path)",
  "\t",
}
eq(
  "iferr: zero values of several returns (struct, map, int)",
  plain(iferr.items(ctx_multi)[2]),
  "if err != nil {\n\treturn Config{}, nil, 0, err\n}\n"
)
eq(
  "iferr: Config is not a known struct here → *new if the type is unknown",
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
  "iferr: function that only returns error",
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
eq("iferr: in main it uses log.Fatalf", labels(iferr.items(ctx_main)), { "if err != nil | log.Fatalf" })
eq(
  "iferr: main + log.Fatalf carries the open message",
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
  "iferr: a function that does not return error gets no block",
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
eq("iferr: typing `if` also shows it", #iferr.items(ctx_prefix), 2)
local ctx_other = type_at {
  "package p",
  "",
  "func Save(r Repo, n *Note) error {",
  "\terr := r.Save(n)",
  "\tfor",
}
eq("iferr: typing something else does not get in the way", iferr.items(ctx_other), {})
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
eq(
  "iferr: if there is already an `if err` below, another is not offered",
  iferr.items { line = "\t", cursor = { 5, 1 } },
  {}
)
local ctx_none = type_at {
  "package p",
  "",
  "func Save(r Repo) error {",
  "\tx := 1",
  "\t",
}
eq("iferr: without an error assigned before, it does not show", iferr.items(ctx_none), {})
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
  "iferr: inside a func literal it uses ITS returns",
  plain(iferr.items({ line = "\t\t", cursor = { 6, 2 } })[2]),
  "if err != nil {\n\treturn 0, err\n}\n"
)

-- ── layered project for the rest ─────────────────────────────────────────
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
eq("string enum: what is missing (IsValid already exists)", goenum.missing "Status", { "ParseStatus", "UnmarshalText" })
eq("numeric enum: String, Parse, Marshal/UnmarshalText besides IsValid", goenum.missing "Priority", {
  "IsValid",
  "ParsePriority",
  "String",
  "MarshalText",
  "UnmarshalText",
})
local enum_items = goenum.declaration_items(TOP, "")
eq("enum: items with 'all' first for each type", labels(enum_items), {
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
  "string enum: Parse validates with a switch over the constants",
  plain(find(enum_items, "func ParseStatus")),
  'func ParseStatus(v string) (Status, error) {\n\tswitch s := Status(v); s {\n\tcase StatusPending, StatusDone:\n\t\treturn s, nil\n\t}\n\treturn "", fmt.Errorf("invalid status %q", v)\n}'
)
eq(
  "numeric enum: String uses the constant name without the type prefix",
  plain(find(enum_items, "func (p Priority) String")),
  'func (p Priority) String() string {\n\tswitch p {\n\tcase PriorityLow:\n\t\treturn "low"\n\tcase PriorityHigh:\n\t\treturn "high"\n\t}\n\treturn fmt.Sprintf("Priority(%d)", int(p))\n}'
)
eq(
  "numeric enum: Parse by name returns 0 if invalid",
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
eq("interface from a struct: the related struct's methods that the interface does not have yet", labels(port_items), {
  "…all of noteService (3) | from methods",
  "Get | noteService · method",
  "Delete | noteService · method",
  "Create | noteService · method",
})
eq("interface: a method item carries its signature (no body)", find(port_items, "Get").textEdit.newText, "Get()")
vim.api.nvim_buf_set_lines(0, 3, 4, false, { "\tGe" })
eq(
  "interface: what was typed filters",
  labels(goport.interface_items { line = "\tGe", cursor = { 4, 3 } }),
  { "Get | noteService · method" }
)

open "internal/application/note_service.go"
local assert_items = goport.declaration_items(TOP, "va")
eq(
  "var _: the check for the struct whose interface is recognised by its constructor",
  labels(assert_items),
  { "var _ NoteService = (*noteService)(nil) | compile-time check" }
)
eq("var _: nothing unless `v…` of var is typed", goport.declaration_items(TOP, "xyz"), {})

-- ── gomap ────────────────────────────────────────────────────────────────────
local gomap = require "utils.gomap"
eq(
  "gomap: bases of a DTO (with and without action prefix)",
  { (gomap.bases "NoteResponse"), (gomap.bases "CreateNoteRequest") },
  { { "Note" }, { "Note", "CreateNote" } }
)
eq("gomap: without a known suffix there is no pair", { gomap.bases "Note" }, { {} })
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
eq("gomap: from domain to DTO, the list and back, for each pair", labels(map_items), {
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
  "gomap: fields by name, conversion of defined types and TODO where it does not fit",
  plain(find(map_items, "func toNoteResponse")),
  "func toNoteResponse(n *domain.Note) NoteResponse {\n\treturn NoteResponse{\n\t\tID: n.ID,\n\t\tTitle: n.Title,\n\t\tStatus: string(n.Status),\n\t\tTags: n.Tags,\n\t\t// TODO: Extra (int) has no source field in Note\n\t}\n}"
)
eq(
  "gomap: with private fields and a getter, it uses the getter",
  plain(find(map_items, "func toTagResponse")):find("ID: t.ID(),", 1, true) ~= nil,
  true
)
eq(
  "gomap: on the way back it converts to the domain types (qualified)",
  plain(find(map_items, "func (r NoteResponse) toNote")):find("Status: domain.Status(r.Status),", 1, true) ~= nil,
  true
)
eq(
  "gomap: the list uses the single-item mapper",
  plain(find(map_items, "func toNoteResponses")):find("out = append(out, toNoteResponse(n))", 1, true) ~= nil,
  true
)
eq(
  "gomap: a struct with private fields warns when building",
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
  "gowire: typing the service name offers its constructor with the repo already filled in",
  labels(wire_items),
  { "noteService := application.NewNoteService(…) | application" }
)
eq(
  "gowire: the argument is the variable whose type satisfies the parameter's interface",
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
  "gowire: the `db` parameter is taken from the variable with that name",
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
  "gowire: with nothing in scope, a placeholder with the parameter name",
  gowire.items(wctx3)[1].textEdit.newText,
  "noteService := application.NewNoteService(${1:repo})"
)
eq("gowire: offers nothing with fewer than 3 letters", gowire.items { line = "\tNe", cursor = { 4, 3 } }, {})
local wctx4 = type_at { "package main", "", "var x = 1", "NewNote" }
eq("gowire: outside a function it offers nothing", gowire.items(wctx4), {})

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
eq("gohttp (net/http, go 1.22): all, routes and one handler per service method", labels(h_items), {
  "…all handlers (5) | NoteService",
  "Routes | NoteService · 5 routes",
  "Create | NoteService · POST",
  "Get | NoteService · GET",
  "List | NoteService · GET",
  "SetDone | NoteService · PATCH",
  "Delete | NoteService · DELETE",
})
eq(
  "gohttp: Get reads the id from the route, calls and responds with the JSON",
  plain(find(h_items, "Get")),
  'Get(w http.ResponseWriter, r *http.Request) {\n\tid := r.PathValue("id")\n\tres, err := h.svc.Get(r.Context(), id)\n\tif err != nil {\n\t\twriteError(w, err)\n\t\treturn\n\t}\n\twriteJSON(w, http.StatusOK, res)\n}'
)
eq(
  "gohttp: Create decodes a JSON body with snake_case tags and responds 201",
  plain(find(h_items, "Create")),
  'Create(w http.ResponseWriter, r *http.Request) {\n\tvar body struct {\n\t\tTitle string `json:"title"`\n\t\tContent string `json:"content"`\n\t}\n\tif err := json.NewDecoder(r.Body).Decode(&body); err != nil {\n\t\thttp.Error(w, err.Error(), http.StatusBadRequest)\n\t\treturn\n\t}\n\tres, err := h.svc.Create(r.Context(), body.Title, body.Content)\n\tif err != nil {\n\t\twriteError(w, err)\n\t\treturn\n\t}\n\twriteJSON(w, http.StatusCreated, res)\n}'
)
local list_text = plain(find(h_items, "List"))
eq("gohttp: List builds the filter from the query field by field", {
  list_text:find('filter := domain.ListFilter{\n\t\tQuery: q.Get("query"),\n\t}', 1, true) ~= nil,
  list_text:find("strconv.Atoi(v)", 1, true) ~= nil,
  list_text:find("strconv.ParseBool(v)", 1, true) ~= nil,
  list_text:find("filter.Done = &b", 1, true) ~= nil,
}, { true, true, true, true })
eq(
  "gohttp: Delete (error only) responds 204",
  plain(find(h_items, "Delete")):find("w.WriteHeader(http.StatusNoContent)", 1, true) ~= nil,
  true
)
eq(
  "gohttp: SetDone mixes route id and body",
  plain(find(h_items, "SetDone")):find("h.svc.SetDone(r.Context(), id, body.Done)", 1, true) ~= nil,
  true
)
eq(
  "gohttp: Routes registers the verb and route of each method",
  plain(find(h_items, "Routes")),
  'Routes(mux *http.ServeMux) {\n\tmux.HandleFunc("POST /notes", h.Create)\n\tmux.HandleFunc("GET /notes/{id}", h.Get)\n\tmux.HandleFunc("GET /notes", h.List)\n\tmux.HandleFunc("PATCH /notes/{id}/done", h.SetDone)\n\tmux.HandleFunc("DELETE /notes/{id}", h.Delete)\n}'
)
local top_http = gohttp.declaration_items(TOP, "")
eq("gohttp at the start of the declaration: with header and the response helper at the end", {
  top_http[1].label,
  top_http[#top_http].label,
}, { "func (h *NoteHandler) …all handlers (5)", "func …handler helpers (writeJSON, writeError)" })

write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/gin-gonic/gin v1.9.0" })
handler_file()
local gctx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
local gin_items = gohttp.method_items(gctx)
eq("gohttp (gin): signature with *gin.Context and responses with c.JSON", {
  plain(find(gin_items, "Get")):match "^Get%b() {",
  plain(find(gin_items, "Get")):find('c.Param("id")', 1, true) ~= nil,
  plain(find(gin_items, "Get")):find("c.JSON(http.StatusOK, res)", 1, true) ~= nil,
  plain(find(gin_items, "Routes")):find('r.GET("/notes/:id", h.Get)', 1, true) ~= nil,
  find(gin_items, "…all handlers (5)") ~= nil,
}, { "Get(c *gin.Context) {", true, true, true, true })
write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/labstack/echo/v4 v4.0.0" })
handler_file()
local ectx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
eq("gohttp (echo): returns error and c.JSON", {
  plain(find(gohttp.method_items(ectx), "Get")):match "^Get%b() error {",
  plain(find(gohttp.method_items(ectx), "Get")):find("return c.JSON(http.StatusOK, res)", 1, true) ~= nil,
}, { "Get(c echo.Context) error {", true })
write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/gofiber/fiber/v2 v2.0.0" })
eq("gohttp: with fiber nothing is made up", gohttp.method_items(ectx), {})
write("go.mod", { "module notesapi", "", "go 1.21" })
eq("gohttp: net/http before Go 1.22 (no PathValue) neither", gohttp.method_items(ectx), {})
write("go.mod", { "module notesapi", "", "go 1.22", "", "require github.com/go-chi/chi/v5 v5.0.0" })
handler_file()
local cctx = type_at(vim.list_extend(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "func (h *NoteHandler) " }))
eq("gohttp (chi): URLParam and routes with r.Get", {
  plain(find(gohttp.method_items(cctx), "Get")):find('chi.URLParam(r, "id")', 1, true) ~= nil,
  plain(find(gohttp.method_items(cctx), "Routes")):find('r.Get("/notes/{id}", h.Get)', 1, true) ~= nil,
}, { true, true })

-- the filter is resolved even if the handler file does not import the domain package
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
eq("gohttp: the service filter is read from the domain even if the handler does not import it", {
  web_list:find('filter := domain.ListFilter{\n\t\tQuery: q.Get("query"),', 1, true) ~= nil,
  web_list:find("strconv.Atoi(v)", 1, true) ~= nil,
}, { true, true })
eq(
  "gohttp: 'all' after the receiver does not repeat the first one's header",
  plain(web_items[1]):find "^Create%(" ~= nil,
  true
)

vim.cmd "silent! bwipeout!"
vim.fn.delete(root, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
