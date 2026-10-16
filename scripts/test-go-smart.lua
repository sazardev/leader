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

-- ── goreconstitute ───────────────────────────────────────────────────────────
local recon = require "utils.goreconstitute"
write("domain/note.go", {
  "package note",
  "",
  'import "time"',
  "",
  "type Note struct {",
  "\tid        string",
  "\ttitle     string",
  "\tcontent   string",
  "\tcreatedAt time.Time",
  "\tupdatedAt time.Time",
  "}",
  "",
})
open "domain/note.go"
local rec = recon.declaration_items(TOP, "recon")
eq("goreconstitute: one item for the one struct", labels(rec), { "Reconstitute | rehydrate Note" })
eq(
  "goreconstitute: every field is a parameter, grouped by type, no validation and no now",
  plain(rec[1]),
  "// Reconstitute rehydrates a Note from persistence without validating it.\nfunc Reconstitute(id, title, content string, createdAt, updatedAt time.Time) *Note {\n\treturn &Note{\n\t\tid:        id,\n\t\ttitle:     title,\n\t\tcontent:   content,\n\t\tcreatedAt: createdAt,\n\t\tupdatedAt: updatedAt,\n\t}\n}"
)
eq("goreconstitute: the funcreconstitute spelling works too", #recon.declaration_items(TOP, "funcrecon"), 1)
eq("goreconstitute: nothing before 5 letters", recon.declaration_items(TOP, "reco"), {})
eq("goreconstitute: nothing for another word", recon.declaration_items(TOP, "recoverx"), {})
eq("goreconstitute: nothing without a fragment", recon.declaration_items(TOP, ""), {})

-- through the completion source, as it is typed at package level
local source = require("utils.gosmart").new()
local got
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
lines[#lines + 1] = "recon"
local sctx = type_at(lines)
source:get_completions(sctx, function(res)
  got = res
end)
vim.wait(500, function()
  return got ~= nil
end)
eq("goreconstitute: the source offers it first while typing `recon`", got and got.items[1] and got.items[1].label, "Reconstitute")
eq("goreconstitute: and does not ask again once it can show up", got and got.is_incomplete_forward, false)
lines[#lines] = "rec"
got = nil
source:get_completions(type_at(lines), function(res)
  got = res
end)
vim.wait(500, function()
  return got ~= nil
end)
eq("goreconstitute: blink is asked again while the word grows", got and got.is_incomplete_forward, true)

-- already there: not offered again
write("domain/done.go", {
  "package note",
  "",
  "type Note struct{ id string }",
  "",
  "func Reconstitute(id string) *Note { return &Note{id: id} }",
})
open "domain/done.go"
eq("goreconstitute: not offered when the function exists", recon.declaration_items(TOP, "recon"), {})

-- several structs: one per struct, named after it; embedded and keyword fields
write("domain/many.go", {
  "package note",
  "",
  "type Note struct {",
  "\tbase",
  "\tID   string",
  "\tType string",
  "}",
  "",
  "type Tag struct{}",
})
open "domain/many.go"
local many = recon.declaration_items(TOP, "Reconstitute")
eq("goreconstitute: several structs, several names", labels(many), { "ReconstituteNote | rehydrate Note", "ReconstituteTag | rehydrate Tag" })
eq(
  "goreconstitute: embedded fields are skipped and Go keywords are not used as names",
  plain(many[1]),
  "// ReconstituteNote rehydrates a Note from persistence without validating it.\nfunc ReconstituteNote(id, type_ string) *Note {\n\treturn &Note{\n\t\tID:   id,\n\t\tType: type_,\n\t}\n}"
)
eq("goreconstitute: an empty struct", plain(many[2]):match "\n(.*)$", "func ReconstituteTag() *Tag {\n\treturn &Tag{}\n}")

-- every struct of the file: grouped `type ( … )` blocks too; generic ones and the package's other files are not
write("domain/other.go", { "package note", "", "type FromOtherFile struct{ A string }" })
write("domain/block.go", {
  "package note",
  "",
  "type (",
  "\tOrder struct {",
  "\t\tID string",
  "\t}",
  "",
  "\tItem struct{ SKU string; Qty int }",
  "\tAlias = string",
  ")",
  "",
  "type Box[T any] struct{ value T }",
  "",
  "type Plain struct{ N int }",
})
open "domain/block.go"
eq(
  "goreconstitute: every struct of the file, in a type block too; not generics, not other files",
  labels(recon.declaration_items(TOP, "recon")),
  {
    "ReconstituteItem | rehydrate Item",
    "ReconstituteOrder | rehydrate Order",
    "ReconstitutePlain | rehydrate Plain",
  }
)

-- ── gogetters ────────────────────────────────────────────────────────────────
local getters = require "utils.gogetters"
eq(
  "gogetters: names follow Go's initialisms",
  vim.tbl_map(getters.method_name, { "id", "title", "createdAt", "userId", "userID", "httpClient", "ipAddress", "ids", "url" }),
  { "ID", "Title", "CreatedAt", "UserID", "UserID", "HTTPClient", "IPAddress", "Ids", "URL" }
)

write("getters/note.go", {
  "package getters",
  "",
  'import "time"',
  "",
  "type Note struct {",
  "\tid        string",
  "\ttitle     string",
  "\tcontent   string",
  "\ttags      []string",
  "\tmeta      map[string]string",
  "\tcreatedAt time.Time",
  "\tUpdatedAt time.Time",
  "\tbase",
  "}",
  "",
})
open "getters/note.go"
local gitems = getters.declaration_items(TOP, "getters")
eq("gogetters: one item for the struct, counting the missing ones", labels(gitems), { "getters | 6 for Note" })
eq(
  "gogetters: one line each, aligned, no Get prefix; slices and maps come back as copies; exported and embedded are skipped",
  plain(gitems[1]),
  table.concat({
    "func (n *Note) ID() string              { return n.id }",
    "func (n *Note) Title() string           { return n.title }",
    "func (n *Note) Content() string         { return n.content }",
    "func (n *Note) Tags() []string          { return slices.Clone(n.tags) }",
    "func (n *Note) Meta() map[string]string { return maps.Clone(n.meta) }",
    "func (n *Note) CreatedAt() time.Time    { return n.createdAt }",
  }, "\n")
)
eq("gogetters: the other spellings and the length", {
  #getters.declaration_items(TOP, "funcgetters"),
  #getters.declaration_items(TOP, "accessors"),
  #getters.declaration_items(TOP, "gett"),
  #getters.declaration_items(TOP, ""),
}, { 1, 1, 0, 0 })
eq("gogetters: pending while the word grows", { getters.pending "get", getters.pending "getters", getters.pending "xyz", getters.pending "fun" }, { true, false, false, true })

-- the knob: no copies
require("core.settings").go.getters.clone = false
eq("gogetters: clone = false returns the field as it is", plain(getters.declaration_items(TOP, "getters")[1]):match "Tags%(%)[^\n]*", "Tags() []string          { return n.tags }")
require("core.settings").go.getters.clone = true

-- the receiver of the other methods, and what already exists
write("getters/svc.go", {
  "package getters",
  "",
  "type Account struct {",
  "\tid    string",
  "\temail string",
  "\tname  string",
  "}",
  "",
  "func (a Account) Email() string { return a.email }",
  "func (a Account) Rename(n string) Account { a.name = n; return a }",
})
open "getters/svc.go"
local acc = getters.declaration_items(TOP, "getters")
eq(
  "gogetters: the receiver is the one the struct already uses (a value here), and an existing getter is not repeated",
  plain(acc[1]),
  "func (a Account) ID() string   { return a.id }\nfunc (a Account) Name() string { return a.name }"
)

-- several structs; one with everything covered gives nothing
write("getters/two.go", {
  "package getters",
  "",
  "type A struct{ x int }",
  "",
  "type B struct{ y int }",
  "",
  "func (b *B) Y() int { return b.y }",
})
open "getters/two.go"
eq("gogetters: several structs, one item each, none for a struct that has them all", labels(getters.declaration_items(TOP, "getters")), { "getters A | 1 for A" })

-- after `func (n *Note) `: one item per getter and all of them
open "getters/note.go"
local mlines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
mlines[#mlines + 1] = "func (x *Note) "
local mctx = type_at(mlines)
local mitems = getters.method_items(mctx)
eq(
  "gogetters: after the receiver, each getter and `all getters`",
  vim.tbl_map(function(it)
    return it.label
  end, mitems),
  { "ID", "Title", "Content", "Tags", "Meta", "CreatedAt", "all getters" }
)
eq("gogetters: the receiver is the one typed", plain(mitems[2]), "Title() string { return x.title }")
eq(
  "gogetters: `all getters` continues the line, the rest are whole functions",
  plain(mitems[7]):match "^[^\n]*",
  "ID() string              { return x.id }"
)
mlines[#mlines] = "func (x *Note) Ti"
local filtered = getters.method_items(type_at(mlines))
eq(
  "gogetters: typing the name narrows them",
  vim.tbl_map(function(it)
    return it.label
  end, filtered),
  { "Title", "all getters" }
)

-- through the completion source
local gsrc = require("utils.gosmart").new()
local gres
mlines[#mlines] = "func (x *Note) "
gsrc:get_completions(type_at(mlines), function(res)
  gres = res
end)
vim.wait(500, function()
  return gres ~= nil
end)
eq(
  "gogetters: the source offers them after the receiver",
  gres and vim.iter(gres.items):any(function(it)
    return it.label == "ID" and it.labelDetails.description:find "getter" ~= nil
  end),
  true
)
local glines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
glines[#glines] = "gette"
gres = nil
gsrc:get_completions(type_at(glines), function(res)
  gres = res
end)
vim.wait(500, function()
  return gres ~= nil
end)
eq("gogetters: and at package level once `gette` is typed", gres and gres.items[1] and gres.items[1].label, "getters")
glines[#glines] = "get"
gres = nil
gsrc:get_completions(type_at(glines), function(res)
  gres = res
end)
vim.wait(500, function()
  return gres ~= nil
end)
eq("gogetters: blink is asked again while the word grows", gres and gres.is_incomplete_forward, true)

-- ── gorepository ─────────────────────────────────────────────────────────────
local repo = require "utils.gorepository"
eq("gorepository: the identity is `id`, `ID` or `<Struct>ID`", {
  repo.id_type("Note", { { name = "id", type = "string" } }),
  repo.id_type("Order", { { name = "ID", type = "uuid.UUID" } }),
  repo.id_type("Note", { { name = "NoteID", type = "int64" } }),
  repo.id_type("Money", { { name = "amount", type = "int64" } }),
}, { "string", "uuid.UUID", "int64", nil })
eq(
  "gorepository: `Repository` in a package named after the struct, `NoteRepository` elsewhere",
  { repo.port_name("Note", "note"), repo.port_name("Note", "domain"), repo.port_name("Note", nil) },
  { "Repository", "NoteRepository", "NoteRepository" }
)
eq("gorepository: pending while the word grows", { repo.pending "re", repo.pending "repo", repo.pending "x" }, { true, false, false })

write("domain/note/note.go", {
  "package note",
  "",
  "type Note struct {",
  "\tid    string",
  "\ttitle string",
  "}",
  "",
  "type Tag struct{ name string }",
})
write("domain/note/repository.go", { "package note", "" })
open "domain/note/repository.go"
local ritems = repo.declaration_items(TOP, "repo")
eq("gorepository: in the domain layer, the aggregate gets its port, a value object does not", labels(ritems), { "repository | port of Note → Repository" })
eq(
  "gorepository: the port, written from the aggregate (the package is named after it)",
  plain(ritems[1]),
  "// Repository is the persistence port of the Note aggregate; infrastructure implements it.\ntype Repository interface {\n\tSave(ctx context.Context, note *Note) error\n\tFindByID(ctx context.Context, id string) (*Note, error)\n\tDelete(ctx context.Context, id string) error\n\tList(ctx context.Context) ([]*Note, error)\n}"
)
eq("gorepository: the whole word works, too short or another word does not", {
  #repo.declaration_items(TOP, "repository"),
  #repo.declaration_items(TOP, "rep"),
  #repo.declaration_items(TOP, "repox"),
  #repo.declaration_items(TOP, ""),
}, { 1, 0, 0, 0 })

-- the knob
local repo_settings = require("core.settings").go.repository
repo_settings.methods = { "FindByID", "Exists" }
eq(
  "gorepository: the methods are the ones configured, in that order",
  plain(repo.declaration_items(TOP, "repo")[1]):match "interface {\n(.*)\n}",
  "\tFindByID(ctx context.Context, id string) (*Note, error)\n\tExists(ctx context.Context, id string) (bool, error)"
)
repo_settings.methods = { "Save", "FindByID", "Delete", "List" }

-- several aggregates with their own identity type and package name
write("domain/shop/shop.go", {
  "package shop",
  "",
  "type Order struct {",
  "\tID    uuid.UUID",
  "\tTotal Money",
  "}",
  "",
  "type Customer struct{ CustomerID int64 }",
  "",
  "type Money struct{ amount int64 }",
  "",
  "type CustomerRepository interface{ Save(ctx context.Context, c *Customer) error }",
})
open "domain/shop/shop.go"
local shop = repo.declaration_items(TOP, "repo")
eq("gorepository: one per aggregate; a port that exists is not offered again", labels(shop), { "repository | port of Order → OrderRepository" })
eq("gorepository: the identity type is the field's", plain(shop[1]):match "FindByID%(([^)]*)%)", "ctx context.Context, id uuid.UUID")

write("domain/pair/pair.go", { "package pair", "", "type Alpha struct{ id string }", "", "type Beta struct{ id int64 }" })
open "domain/pair/pair.go"
eq(
  "gorepository: several aggregates, one item each, named after them",
  labels(repo.declaration_items(TOP, "repo")),
  { "repository Alpha | port of Alpha → AlphaRepository", "repository Beta | port of Beta → BetaRepository" }
)

-- outside the domain layer, and persistence models
write("infrastructure/notes/store.go", { "package notes", "", "type Note struct{ id string }" })
open "infrastructure/notes/store.go"
eq("gorepository: nothing outside the domain layer", repo.declaration_items(TOP, "repo"), {})
write("domain/note/note_model.go", { "package note", "", "type NoteModel struct{ ID string }" })
open "domain/note/note_model.go"
eq("gorepository: nothing in a persistence model file (and a `*Model` struct is never an aggregate)", repo.declaration_items(TOP, "repo"), {})

-- through the completion source
open "domain/note/repository.go"
local rsrc = require("utils.gosmart").new()
local rres
local rlines = { "package note", "", "repo" }
rsrc:get_completions(type_at(rlines), function(res)
  rres = res
end)
vim.wait(500, function()
  return rres ~= nil
end)
eq("gorepository: the source offers it first while typing `repo`", rres and rres.items[1] and rres.items[1].label, "repository")
rlines[3] = "re"
rres = nil
rsrc:get_completions(type_at(rlines), function(res)
  rres = res
end)
vim.wait(500, function()
  return rres ~= nil
end)
eq("gorepository: blink is asked again while the word grows", rres and rres.is_incomplete_forward, true)

-- ── gopackage ────────────────────────────────────────────────────────────────
local gopackage = require "utils.gopackage"
local function info(over)
  return vim.tbl_extend("force", { siblings = {}, file = "x.go", cmd = false, root = false }, over)
end
eq("gopackage: the neighbours decide: their package first, no main", gopackage.decide(info { siblings = { "notes", "notes" } }), { prefer = "notes", main = false })
eq("gopackage: neighbours that are main: main first", gopackage.decide(info { siblings = { "main" } }), { prefer = "main", main = true })
eq("gopackage: the most common neighbour wins", gopackage.decide(info { siblings = { "a", "b", "b" } }).prefer, "b")
eq("gopackage: a tie goes by name", gopackage.decide(info { siblings = { "b", "a" } }).prefer, "a")
eq("gopackage: nobody around, under cmd/: main", gopackage.decide(info { cmd = true }), { prefer = "main", main = true })
eq("gopackage: nobody around, main.go: main", gopackage.decide(info { file = "main.go" }), { prefer = "main", main = true })
eq("gopackage: nobody around, the module root: main", gopackage.decide(info { root = true }), { prefer = "main", main = true })
eq("gopackage: nobody around, anywhere else: no main", gopackage.decide(info {}), { prefer = nil, main = false })

local function pkgs(list)
  return vim.tbl_map(function(name)
    return { label = "package " .. name, kind = 9 }
  end, list)
end
local function ranked(list, typed, decision, test_file)
  local out = gopackage.rank(pkgs(list), typed, decision, test_file)
  table.sort(out, function(a, b)
    return (a.score_offset or 0) > (b.score_offset or 0)
  end)
  return vim.tbl_map(function(it)
    return it.label:gsub("^package ", "")
  end, out)
end
eq("gopackage: main is not even listed where it makes no sense", ranked({ "main", "billing", "billing_test" }, "", { main = false }, false), { "billing", "billing_test" })
eq("gopackage: unless it is being typed, then it goes last", ranked({ "main", "billing" }, "m", { main = false }, false), { "billing", "main" })
eq("gopackage: the neighbours' package goes first, main last", ranked({ "main", "api", "api_test" }, "", { prefer = "api", main = true }, false), { "api", "api_test", "main" })
eq("gopackage: main first when it is the one", ranked({ "api", "main", "api_test" }, "", { prefer = "main", main = true }, false), { "main", "api", "api_test" })
eq("gopackage: in a _test.go file X_test comes right after X", ranked({ "x_test", "x", "main" }, "", { prefer = "x", main = false }, true), { "x", "x_test" })
local keep = gopackage.rank({ { label = "package" }, { label = "other" } }, "", { main = false }, false)
eq("gopackage: anything that is not a package clause is left alone", #keep, 2)

-- from the folder
write("pk/notes/a.go", { "package notes", "", "type A struct{}" })
write("pk/notes/a_test.go", { "package notes_test" })
write("pk/notes/gen.go", { "//go:build ignore", "", "package main" })
write("pk/notes/doc.go", { "// Package notes does things.", "/*", "package fake", "*/", "package notes" })
local got_info = gopackage.info(root .. "/pk/notes/new.go")
table.sort(got_info.siblings)
eq("gopackage: the folder's neighbours (tests count as their package, `go:build ignore` and comments do not)", got_info.siblings, { "notes", "notes", "notes" })
eq("gopackage: and the rest of what it knows", { got_info.file, got_info.cmd, got_info.root }, { "new.go", false, false })
write("cmd/tool/x.go", { "package main" })
eq("gopackage: cmd/ is recognised", gopackage.info(root .. "/cmd/tool/other.go").cmd, true)
eq("gopackage: the module root is recognised", gopackage.info(root .. "/main2.go").root, true)
eq("gopackage: the current file is not its own neighbour", gopackage.info(root .. "/cmd/tool/x.go").siblings, {})

-- through the LSP filter, as blink calls it
open "pk/notes/new.go"
local plines = { "package " }
local pctx = type_at(plines)
local lsp_items = { { label = "package main", kind = 9 }, { label = "package notes", kind = 9 }, { label = "package notes_test", kind = 9 } }
local out = require("utils.gosmart").quiet_lsp(pctx, lsp_items)
eq(
  "gopackage: quiet_lsp drops main in a folder of package notes and puts notes first",
  vim.tbl_map(function(it)
    return it.label
  end, out),
  { "package notes", "package notes_test" }
)
eq("gopackage: and boosts it", out[1].score_offset > (out[2].score_offset or 0), true)
open "cmd/tool/new.go"
local cmd_out = require("utils.gosmart").quiet_lsp(type_at { "package " }, { { label = "package main", kind = 9 }, { label = "package tool", kind = 9 } })
eq("gopackage: under cmd/ main stays and leads", cmd_out[1].label == "package main" and cmd_out[1].score_offset > (cmd_out[2].score_offset or 0), true)

vim.cmd "silent! bwipeout!"
vim.fn.delete(root, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
