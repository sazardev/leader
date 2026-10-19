/* The storyboard. Edit this file and re-render: `node video/render.mjs` (or `--serve` to preview, `--scene <id>` for one).

   TEXT holds every line the viewer reads (headlines, sub lines, the key hints next to them, the cards): change copy
   there. Each scene below is a script for the editor, written with a small synchronous API; every call happens at
   the current time and moves it forward:

     v.wait(ms)                       pause                  v.caption(TEXT.x)          headline (null clears it)
     v.layout("split"|"full"|"wide")  where the editor sits   v.zoom(scale, x, y)        camera on a point (0..1); zoom(1) back
     v.card(kind, opts) / v.cardOut() full-screen panels: hero, speed, statement, keys, install
     v.open(path, row) / v.set(lines, file, mode) / v.cursor(row, col) / v.mode(m) / v.showCursor(bool)
     v.type(text) / v.nl(indent) / v.pop(items, sel) / v.sel(i) / v.accept(lines)            completion
     v.key("⏎") / v.keys("␣ a f")     one key chip / a leader sequence with the real which-key menus
     v.diag(row, sev, src, msg) / v.clearDiag()                                                diagnostics
     v.input(row, label, ph) / v.typeInput(text) / v.dropInput()                               the agent's instruction field
     v.spin(row, label, ms) / v.diff(row, added, removed, stats, o) / v.acceptDiff() / v.done(row, text)   proposals
     v.stream(title, text, o)          an answer streaming into a float (explain / ask)
     v.ov(overlay) / v.ovDo(fn) / v.ovType(key, text)     modal, report, term, dash, dd
     v.commit(panel) / v.cpDo(fn) / v.toast(html, ms) / v.agent(statusline text) / v.tree(openDirs) / v.pal(themeId)

   Rows are indexes into the buffer as it is at that moment (an instruction field or a hint row counts as a row).
   Menus, the project files (v.open), the dashboard art and the terminal palettes come from docs/index.html. */
var TEXT = {
  hero: { lines: ["Neovim,", "for working."], lede: "<b>Fast. Minimal. Opinionated.</b> And an agent that only speaks when you ask." },
  speed: { eyebrow: "Startup", from: 400, to: 20, unit: "ms", says: "To a usable editor. Nothing loads until it has a reason to." },
  session: { eyebrow: "Monday, 9:02", lines: ["Right where", "you left it."] },
  complete: { eyebrow: "Go completion · 0 tokens", lines: ["Type less.", "It knows your code."], sub: "Errors wrapped with context, <b>missing interface methods</b>, constructors, mappers. Local, instant, free." },
  implement: { eyebrow: "Inline agent · implement", lines: ["Write the", "signature.", "Get the body."], sub: "The comment is the spec. It reads the <b>types, callers and errors</b> it needs, nothing else.", keys: "Space a i" },
  fix: { eyebrow: "Inline agent · fix block", lines: ["Red line?", "One key."], sub: "The smallest change that makes the block coherent. <b>Enter</b> accepts, <b>Esc</b> rejects, <b>Tab</b> refines.", keys: "Space a F" },
  docs: { eyebrow: "Inline agent · docs + explain", lines: ["Comments", "that say why."], sub: "It returns <b>only the comment</b>, so your code can't change. Ask for an explanation without leaving the line.", keys: "Space a d" },
  lens: { eyebrow: "Lenses · security, errors, concurrency…", lines: ["Look for one", "thing. Find it."], sub: "Findings land on their line as diagnostics. Code outside the lens costs <b>0 tokens</b>.", keys: "Space a L s" },
  convert: { eyebrow: "Inline agent · convert", lines: ["Paste JSON.", "Get types."], sub: "JSON, a <b>CREATE TABLE</b> or a curl command become ready code in the file's language.", keys: "Space a t" },
  tests: { eyebrow: "Agent tests", lines: ["Tests, next", "to the code."], sub: "Table-driven, in the right file, in your style. Gaps and mocks too.", keys: "Space a T w" },
  fixall: { eyebrow: "Agent advanced · fix all", lines: ["The whole file.", "One yes."], sub: "One proposal per function, <b>one confirmation</b> with the total cost. They wait in a queue: ] next, y accept all.", keys: "Space a A a" },
  kit: { eyebrow: "From documents to code", lines: ["Write it down.", "Build it a piece at a time."],
    rows: [["Four documents.", "AGENTS, STACK, DESIGN and SPEC. From presets or your words."], ["One layer.", "Foundation, domain or screens, each from its document."], ["One feature.", "Describe it. It lands in SPEC.md, then it is built end to end."], ["It remembers why.", "Decisions become ADRs. PROGRESS.md says what is left."]] },
  build: { eyebrow: "Build with agent · Space a S b b", lines: ["Plan, write, check, fix.", "You review once."] },
  commit: { eyebrow: "Commits", lines: ["Commits that", "write themselves."], sub: "Conventional Commits checked live. The model sees the staged diff and <b>says what it reads before spending</b>.", keys: "Space G c" },
  review: { eyebrow: "Review staged", lines: ["Caught before", "it shipped."], sub: "Free local checks first, then one numbered request. Findings go to the quickfix.", keys: "Ctrl r" },
  release: { eyebrow: "Release kit", lines: ["Changelog and", "version. Done."], sub: "The next semver and the changelog from your commits. <b>0 tokens</b>. Nothing pushes by itself.", keys: "Space G R c" },
  usage: { eyebrow: "Agent history", lines: ["Every token,", "accounted for."], sub: "Time, tokens and cost on every run. A daily budget. Identical answers come back from the cache for free.", keys: "Space a h" },
  themes: { eyebrow: "Appearance", lines: ["Your terminal's colors.", "Everywhere."] },
  keys: { eyebrow: "Keyboard", lines: ["Press Space."], lead: "One letter per context. It only shows what applies to where you are.", tiles: [["a", "Agent"], ["G", "Git"], ["g", "Go"], ["C", "Comments"], ["x", "Diagnostics"], ["f", "Find"], ["P", "Session"], ["S", "Settings"]] },
  install: { eyebrow: "Install", lines: ["One command."], cmd: "curl -fsSL https://raw.githubusercontent.com/sazardev/leader/master/install.sh | bash",
    typeMs: 36, fine: "Linux · macOS · WSL. Windows: <code>irm …/install.ps1 | iex</code>. Pick languages with <code>--lang go</code>.", name: "Leader", url: "github.com/sazardev/leader" }
};

var STORY = (function () {
  var h = VIDEO.helpers, MU = h.MU, FILE = h.FILE, YES = h.YES, cols = h.cols;
  var S1 = "1.2s · 1.9k→212 tok · $0.0049", S2 = "0.8s · 1.1k→64 tok · $0.0003";
  var SPIN = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";

  return {
    pace: 1,                                   /* > 1 slows everything down, < 1 speeds it up */
    theme: null,                               /* null = gruvbox; "light"; or a terminal palette id such as "t:tokyo-night" */
    stats: "1.4s · 2.1k→58 tok · $0.0071",     /* what agent/stats.lua prints after a run */
    chapters: ["Start", "Complete", "Agent", "Build", "Ship", "Yours"],
    /* sound (audio.mjs): a recorded mechanical keyboard for every key, synthesized effects for the UI, and an original
       score whose sections start on scene cuts ("scene" or "scene+seconds"); drop: true lands a riser + impact there.
       Parts: intro, lift, groove, groove2, break, drive, outro. levels in dB; mute: cue kinds to leave silent.
       music: { file: "audio/track.mp3", offset: 12 } (or --music) plays a file instead of the score. */
    audio: {
      keys: "audio/keys",
      levels: { keys: 0, fx: 6, music: -12, duck: 4 },       /* dB; duck = how much the music steps back while typing */
      music: { bpm: 104, sections: [
        { at: "hero", part: "intro" },
        { at: "hero+3.6", part: "lift" },
        { at: "session", part: "groove", drop: true },
        { at: "implement", part: "groove2" },
        { at: "kit", part: "break" },
        { at: "kit+4.6", part: "drive", drop: true },
        { at: "commit", part: "groove2" },
        { at: "themes", part: "drive" },
        { at: "outro+4.2", part: "outro" }
      ] }
    },
    text: TEXT,
    scenes: [

      /* ── open: the landing's hero, then the startup number ─────────────────────────────────── */
      { id: "hero", title: "Hero", chapter: "Start", run: function (v, T) {
          v.sfx("impact");
          v.card("hero", { instant: true, lines: T.hero.lines, lede: T.hero.lede, cmd: T.install.cmd, art: 1 });
          v.wait(3600);
          v.card("speed", T.speed); v.wait(2900);
        } },

      /* ── the start screen: restore the session ─────────────────────────────────────────────── */
      { id: "session", title: "Session", chapter: "Start", run: function (v, T) {
          v.layout("full", 0); v.set([""], "", "NORMAL"); v.showCursor(false);
          v.ov({ kind: "dash", art: v.L.ARTS[1].join("\n"), repo: "notesapi (main)", user: "Omar", sel: 0,
            buttons: [["Restore Session", "rs"], ["Find File", "ff"], ["Recent Files", "fo"], ["Find Word", "fw"], ["Themes", "th"], ["Mappings", "ch"], ["Change Art", "ca"]] });
          v.caption(T.session);
          v.cardOut(); v.wait(1700);
          v.key("r", 150); v.key("s", 380);
          v.tree(["internal", "internal/application"]); v.open("internal/application/note_service.go", 5, 14);
          v.toast("<b>Session restored</b> · 3 buffers · cursor where you left it", 2100);
        } },

      /* ── completion: smart if err, then the methods an interface still lacks ───────────────── */
      { id: "complete", title: "Completion", chapter: "Complete", run: function (v, T) {
          v.tree(null); v.layout("split"); v.caption(T.complete);
          v.set(["package application", "", "func (s *noteService) Get(ctx context.Context, id string) (*domain.Note, error) {", "\t", "}"], "note_service.go", "INSERT"); v.cursor(3);
          v.wait(900);
          v.type("n, err := s.repo.FindByID(ctx, id)"); v.wait(200); v.nl("\t"); v.wait(160);
          v.zoom(1.32, 0, 0);
          v.pop([["if err != nil", "wrap · find by id"], ["if err != nil", "return err"]], 0); v.wait(850); v.key("⏎", 240);
          v.accept(["\tif err != nil {", "\t\treturn nil, fmt.Errorf(\"find by id: %w\", err)", "\t}"]); v.wait(1100);
          v.zoom(1);
          v.set(["package application", "", "type noteService struct{ repo domain.NoteRepository }", "", "func NewNoteService(repo domain.NoteRepository) NoteService {", "\treturn &noteService{repo: repo}", "}", "", ""], "note_service.go", "INSERT");
          v.wait(300); v.type("func (s *noteService) "); v.wait(160);
          v.zoom(1.28, 0, 0.3);
          v.pop([["…all missing (6)", "NoteService"], ["Create", "NoteService · missing"], ["Get", "NoteService · missing"], ["List", "NoteService · missing"]], -1, 0,
            [["func (s *noteService) …", "Generates the 6 methods NoteService still lacks, each with its signature and a stub body."], null,
             ["Get(ctx context.Context, id string) (*domain.Note, error)", "Declared in NoteService, not implemented by noteService yet."], null]);
          v.wait(500); v.key("⇥", 260); v.sel(0); v.wait(700); v.sel(2); v.wait(800); v.sel(0); v.wait(300); v.key("⏎", 240);
          v.accept(["func (s *noteService) Get(ctx context.Context, id string) (*domain.Note, error) {", "\treturn s.repo.FindByID(ctx, id)", "}", "", "func (s *noteService) Delete(ctx context.Context, id string) error {", "\treturn s.repo.Delete(ctx, id)", "}"]);
          v.wait(1300); v.zoom(1);
        } },

      /* ── implement from a signature and its comment ────────────────────────────────────────── */
      { id: "implement", title: "Implement", chapter: "Agent", run: function (v, T) {
          v.caption(T.implement);
          v.set(["package application", "", "// Archive marks a note as archived. A note that is", "// already done cannot be archived: return ErrDone.", "func (s *noteService) Archive(ctx context.Context, id string) error {", "}"], "note_service.go", "NORMAL");
          v.cursor(4); v.showCursor(false); v.wait(1100);
          v.keys("␣ a i"); v.input(4, "implement · claude/sonnet", "what should it do? (Enter to skip)"); v.wait(800); v.key("⏎", 220); v.dropInput();
          v.spin(4, "implement · claude/sonnet", 1300);
          v.diff(5, ["\tn, err := s.repo.FindByID(ctx, id)", "\tif err != nil {", "\t\treturn fmt.Errorf(\"archive note: %w\", err)", "\t}", "\tif n.Status == domain.StatusDone {", "\t\treturn ErrDone", "\t}", "\tn.Status = domain.StatusArchived", "\treturn s.repo.Save(ctx, n)", "}"], 1, S1, { at: 4 });
          v.zoom(1.22, 0, 0.1); v.wait(2300); v.key("⏎", 240); v.acceptDiff(); v.wait(900); v.zoom(1);
        } },

      /* ── docs on the same function, then explain ───────────────────────────────────────────── */
      { id: "docs", title: "Docs + explain", chapter: "Agent", run: function (v, T) {
          v.caption(T.docs); v.wait(500);
          v.keys("␣ a d"); v.input(2, "docs · claude/haiku", "what to stress? (Enter to skip)"); v.wait(600); v.key("⏎", 220); v.dropInput();
          v.spin(4, "docs · claude/haiku", 900);
          v.diff(2, ["// Archive moves a note out of the active list.", "//", "// It refuses a note that is already done (ErrDone); any", "// repository error comes back wrapped as \"archive note\"."], 2, S2, { at: 2 });
          v.wait(1800); v.key("⏎", 240); v.acceptDiff(); v.wait(700);
          v.cursor(6); v.keys("␣ a e");
          v.stream("explain · claude/haiku", "**Archive** loads the note by id, refuses it with `ErrDone` when it is already done, then saves it with the status `archived`. A repository error comes back wrapped (`archive note: …`), so callers can still match it with `errors.Is`.",
            { col: 4, foot: S2 + " · Esc closes" });
          v.wait(1700); v.key("Esc", 260); v.float(null); v.wait(300);
        } },

      /* ── fix block: the diagnostic, the minimal change ─────────────────────────────────────── */
      { id: "fix", title: "Fix", chapter: "Agent", run: function (v, T) {
          v.caption(T.fix);
          v.set(["func (s *noteService) Get(ctx context.Context, id string) (*domain.Note, error) {", "\tn, err := s.repo.FindByID(ctx, id)", "\tif err != nil {", "\t\treturn nil, err", "\t}", "\treturn nil, nil", "}"], "note_service.go", "NORMAL");
          v.cursor(1); v.showCursor(false); v.diag(1, "error", "compiler · UnusedVar", "declared and not used: n"); v.wait(1300);
          v.keys("␣ a F"); v.input(0, "fix block · claude/sonnet"); v.wait(600); v.key("⏎", 220); v.dropInput();
          v.spin(0, "fix block · claude/sonnet", 1000);
          v.zoom(1.3, 0, 0);
          v.diff(6, ["\treturn n, nil"], 1, "0.9s · 1.2k→60 tok · $0.0004", { at: 0 }); v.wait(1600);
          v.key("⏎", 220); v.acceptDiff(); v.clearDiag(); v.wait(1200); v.zoom(1);
        } },

      /* ── a lens finds it, fix inline repairs it ────────────────────────────────────────────── */
      { id: "lens", title: "Lens", chapter: "Agent", run: function (v, T) {
          v.caption(T.lens);
          v.set(["func Find(db *sql.DB, name string) (*Note, error) {", "\trow := db.QueryRow(\"SELECT id, title FROM notes WHERE title = '\" + name + \"'\")", "\tn := &Note{}", "\tif err := row.Scan(&n.ID, &n.Title); err != nil {", "\t\treturn nil, err", "\t}", "\treturn n, nil", "}"], "query.go", "NORMAL");
          v.cursor(1); v.showCursor(false); v.wait(900);
          v.keys("␣ a L s"); v.spin(1, "lens security · claude/sonnet", 1100);
          v.diag(1, "warn", "security", "SQL injection: `name` is concatenated into the query. Use a placeholder."); v.done(1, "1 finding · " + "1.1s · 1.6k→41 tok · $0.0052");
          v.zoom(1.25, 0, 0); v.wait(1500);
          v.keys("␣ a f"); v.input(1, "fix inline · claude/sonnet"); v.wait(500); v.key("⏎", 220); v.dropInput();
          v.spin(1, "fix inline · claude/sonnet", 900);
          v.diff(1, ["\trow := db.QueryRow(\"SELECT id, title FROM notes WHERE title = $1\", name)"]); v.wait(1500);
          v.key("⏎", 220); v.acceptDiff(); v.clearDiag(); v.wait(1100); v.zoom(1);
        } },

      /* ── convert: a JSON sample becomes Go types ──────────────────────────────────────────── */
      { id: "convert", title: "Convert", chapter: "Agent", run: function (v, T) {
          v.caption(T.convert);
          v.set(["package billing", "", "{", "  \"id\": \"in_1042\",", "  \"customer\": { \"name\": \"Ada\", \"email\": \"ada@example.com\" },", "  \"lines\": [{ \"sku\": \"PRO-M\", \"qty\": 2, \"price\": 19.5 }],", "  \"paid_at\": null", "}"], "invoice.go", "NORMAL");
          v.cursor(4); v.showCursor(false); v.wait(1000);
          v.keys("␣ a t"); v.input(2, "convert · claude/haiku", "root type name (Enter to skip)"); v.wait(300); v.typeInput("Invoice", 60); v.wait(250); v.key("⏎", 220); v.dropInput();
          v.spin(2, "convert · claude/haiku", 1000);
          v.diff(2, ["type Invoice struct {", "\tID       string     `json:\"id\"`", "\tCustomer Customer   `json:\"customer\"`", "\tLines    []Line     `json:\"lines\"`", "\tPaidAt   *time.Time `json:\"paid_at\"`", "}", "",
            "type Customer struct {", "\tName  string `json:\"name\"`", "\tEmail string `json:\"email\"`", "}", "", "type Line struct {", "\tSKU   string  `json:\"sku\"`", "\tQty   int     `json:\"qty\"`", "\tPrice float64 `json:\"price\"`", "}"], 6, "0.9s · 0.6k→160 tok · $0.0002", { at: 2, imp: "time" });
          v.wait(2000); v.key("⏎", 220); v.acceptDiff(); v.cursor(2); v.wait(1300);
        } },

      /* ── tests in a split ──────────────────────────────────────────────────────────────────── */
      { id: "tests", title: "Tests", chapter: "Agent", run: function (v, T) {
          v.caption(T.tests);
          v.set(["func Rename(r Repo, id int, title string) error {", "\tn, err := r.Get(id)", "\tif err != nil {", "\t\treturn err", "\t}", "\tif title == \"\" {", "\t\treturn ErrEmpty", "\t}", "\tn.Title = title", "\treturn r.Save(n)", "}"], "note_service.go", "NORMAL");
          v.cursor(0); v.showCursor(false); v.wait(900);
          v.keys("␣ a T w"); v.input(0, "test write · claude/sonnet", "what to cover? (Enter to skip)"); v.wait(500); v.key("⏎", 220); v.dropInput();
          v.spin(0, "test write · claude/sonnet", 1100);
          v.split("note_service_test.go", ["package application", "", "import (", "\t\"errors\"", "\t\"testing\"", ")", ""]);
          v.splitDiff(["func TestRename(t *testing.T) {", "\tcases := []struct {", "\t\tname, title string", "\t\twant        error", "\t}{", "\t\t{\"ok\", \"new\", nil},", "\t\t{\"empty\", \"\", ErrEmpty},", "\t}", "\tfor _, c := range cases {", "\t\tt.Run(c.name, func(t *testing.T) {", "\t\t\tif err := Rename(fakeRepo(), 1, c.title); !errors.Is(err, c.want) {", "\t\t\t\tt.Fatalf(\"got %v, want %v\", err, c.want)", "\t\t\t}", "\t\t})", "\t}", "}"]);
          v.wait(2000); v.key("⏎", 220); v.splitAccept(); v.wait(1200); v.unsplit();
        } },

      /* ── fix all: several proposals, one confirmation, a queue ─────────────────────────────── */
      { id: "fixall", title: "Fix all", chapter: "Agent", run: function (v, T) {
          v.caption(T.fixall);
          v.set(["func (s *noteService) Count(ctx context.Context) int {", "\treturn s.repo.Total(ctx)", "}", "func (s *noteService) Get(ctx context.Context, id string) (*domain.Note, error) {", "\tn, err := s.repo.FindByID(ctx, id)", "\treturn nil, nil", "}", "func (s *noteService) Rename(ctx context.Context, id, title string) error {", "\treturn s.repo.Save(ctx, id, title)", "}"], "note_service.go", "NORMAL");
          v.cursor(0); v.showCursor(false);
          v.diag(1, "error", "gopls", "s.repo.Total undefined (type domain.NoteRepository has no method Total)", 1, 4);
          v.diag(4, "error", "gopls", "declared and not used: n", 2, 4); v.diag(5, "warn", "agent", "returning nil, nil hides a missing note", 3, 4);
          v.diag(8, "error", "gopls", "not enough arguments in call to s.repo.Save", 4, 4); v.wait(1000);
          v.keys("␣ a A a");
          v.ov({ kind: "modal", title: "fix all", lines: ["3 proposals · claude/sonnet", MU("~2.3k tokens · ~$0.0012"), "", FILE("note_service.go", "Rename"), FILE("note_service.go", "Get · 2 problems"), FILE("note_service.go", "Count"), YES("Run")] });
          v.wait(1800); v.key("y", 260); v.ov(null);
          v.spin(7, "fix all 1/3 · claude/sonnet", 600, "fix all 1/3");
          v.diff(8, ["\treturn s.repo.Save(ctx, &domain.Note{ID: id, Title: title})"], 1, "0.9s · 1.2k→60 tok · $0.0004", { at: 7, q: "1/3 · &lt;leader&gt;aA] next" });
          v.spin(3, "fix all 2/3 · claude/sonnet", 600, "fix all 2/3");
          v.diff(4, ["\treturn s.repo.FindByID(ctx, id)"], 2, "0.9s · 1.2k→60 tok · $0.0004", { at: 3, q: "2/3 · &lt;leader&gt;aA] next" });
          v.spin(0, "fix all 3/3 · claude/sonnet", 600, "fix all 3/3");
          v.diff(1, ["\treturn s.repo.Count(ctx)"], 1, "0.9s · 1.2k→60 tok · $0.0004", { at: 0, q: "3/3 · &lt;leader&gt;aA] next" });
          v.toast("<b>Agent fix all: 3 proposals ready</b> · &lt;leader&gt;aA] next · &lt;leader&gt;aAy accept all", 1700);
          v.keys("␣ a A y");
          v.ov({ kind: "modal", title: "accept all", lines: ["Accept 3 proposals?", "", FILE("note_service.go", MU("3")), YES("Accept all")] });
          v.wait(1300); v.key("y", 260); v.ov(null); v.acceptDiff(); v.clearDiag();
          v.toast("<b>Agent: 3 of 3 accepted</b> (u undoes each one)", 1800);
        } },

      /* ── the kit: a statement card, then a whole build ─────────────────────────────────────── */
      { id: "kit", title: "Build", chapter: "Build", run: function (v, T) {
          v.card("statement", { eyebrow: T.kit.eyebrow, lines: T.kit.lines, rows: T.kit.rows, size: 100, rowGap: 220, sweep: 420 });
          v.wait(1000);
          v.caption(T.build); v.layout("full", 0); v.tree(["internal", "internal/domain"]); v.open("internal/domain/note.go", 2); v.showCursor(false);
          var files = ["go.mod", "internal/domain/note.go", "internal/domain/note_test.go", "internal/application/note_service.go", "internal/infrastructure/note_repo.go", "internal/transport/note_handler.go", "cmd/api/main.go", "README.md"];
          var models = [["h2", "Models"], ["", "1 plan   <b>claude/haiku</b>   main"], ["", "2 files  <b>claude/sonnet</b>  main"], ["", "3 fixes  <b>claude/haiku</b>   main"], [""]];
          v.wait(3600); v.cardOut(); v.wait(700);
          v.keys("␣ a S b b"); v.wait(200);
          v.ov({ kind: "report", title: "notesapi", hint: " · ⏎ plan · 1 2 3 tier · ± fixes · q close ", lines: [["", h.steps(-1)], [""], ["it", "$0.000 · 0 in · 0% cached · 0m00s"], [""]].concat(models, [["h2", "Documents"], ["", "● AGENTS.md 7.9k · ● STACK.md 19.7k · ● DESIGN.md 6.8k · ● SPEC.md 15.4k"], [""], ["", "<b>⏎ plan</b> · 1 request · ~14.8k in · ~$0.004"]]) });
          v.wait(1800); v.key("⏎", 240); v.agent("⠹ build planning"); v.wait(900); v.agent(null);
          v.ov({ kind: "report", title: "notesapi", hint: " · ⏎ build · x skip · 2 3 tier · n replan · q ", lines: [["", h.steps(1)], [""], ["it", "$0.005 · 19.7k in · 0% cached · 0m29s"], [""]].concat(models, [["h2", "Estimate"], ["", "<b>8 files · ~41k in · ~$0.012 with the cache</b>"], ["it", "(~$0.05 without it: the documents are shared by every file)"], [""], ["h2", "Files"]], files.map(function (f) { return ["", "○ <code>" + f + "</code>"]; })) });
          v.wait(2000); v.key("⏎", 240);
          for (var i = 0; i <= files.length; i++) {
            var bar = "█".repeat(Math.round(24 * i / files.length)) + "░".repeat(24 - Math.round(24 * i / files.length)), cost = (0.005 + i * 0.0018).toFixed(3);
            v.ov({ kind: "report", title: "notesapi", hint: " · x stop · q hide, it goes on · p prompt ", lines: [["", h.steps(2)], [""], ["", bar + "  " + i + "/" + files.length], ["it", "$" + cost + " · " + (20 + i * 6) + "k in · " + (i ? 61 : 0) + "% cached · 0m" + (30 + i * 9) + "s"], [""], ["h2", "Files"]].concat(
              files.map(function (f, k) { return ["", (k < i ? "● " : k === i ? '<span class="ck">⠹</span> ' : "○ ") + "<code>" + f + "</code>"]; })) });
            v.agent(i < files.length ? "build " + i + "/" + files.length + " · $" + cost : null); v.wait(380);
          }
          v.ov({ kind: "report", title: "notesapi", hint: " · ⏎ open · p prompt · r recheck · n replan · q ", lines: [["", h.steps(6)], [""], ["", "<b>✓ built · 8 files · checks pass</b>"], ["it", "$0.019 · 68k in · 61% cached · 1m42s"], [""], ["h2", "Checks"], ["", "● go mod tidy · ● gofmt (fixed itself) · ● go build · ● go vet · ● go test"], [""], ["h2", "Wrote"], ["", "● docs/adr/0002-postgres-with-pgx.md · ● PROGRESS.md (Now / Done / Open / Next)"]] });
          v.agent(null); v.wait(2600); v.ov(null); v.wait(300);
        } },

      /* ── ship: commit panel with an AI draft, staged review, release ───────────────────────── */
      { id: "commit", title: "Commit", chapter: "Ship", run: function (v, T) {
          v.tree(null); v.layout("split"); v.caption(T.commit);
          v.open("internal/application/note_service.go", 12); v.showCursor(false); v.wait(900);
          v.keys("␣ G c");
          var panel = { staged: [["M ", "internal/application/note_service.go", "+24 −3"], ["A ", "internal/domain/errors.go", "+9"]], unstaged: [["M ", "README.md", "+12 −4"]], msg: "", chip: "", ai: "<b>claude/haiku</b> · Ctrl-g to draft · reads 2 files, 3.1k chars" };
          v.commit(panel); v.wait(1100); v.key("Ctrl+g", 240);
          for (var k = 0; k < 10; k++) { (function (f) { v.cpDo(function (c) { c.ai = f + " drafting…"; }); })(SPIN[k]); v.wait(90); }
          v.cpDo(function (c) { c.msg = "feat(notes): archive a note, refuse done ones"; c.chip = "feat(notes) · 45/72"; c.ai = "drafted by claude/haiku · 2.1s · u undo · Ctrl-g redo"; });
          v.wait(1600); v.key("Ctrl+s", 260); v.commit(null);
          v.toast("<b>✔ Committed</b> a1f3c2e feat(notes): archive a note, refuse done ones · 2 files +33 −3", 2000);
        } },
      { id: "review", title: "Review staged", chapter: "Ship", run: function (v, T) {
          v.caption(T.review);
          v.set(["const (", "\tStatusPending Status = \"pending\"", "\tStatusDone    Status = \"done\"", ")", "", "// release key", "const releaseKey = \"AKIAIOSFODNN7EXAMPLE\"", "", "func Normalize(s string) string {", "\treturn strings.ToLower(s)", "}"], "status.go", "NORMAL");
          v.cursor(0); v.showCursor(false); v.wait(500);
          v.keys("␣ G c");
          var tail = " · Ctrl-g to draft · reads 1 file, 154 chars";
          v.commit({ staged: [["M ", "internal/domain/status.go", "+6"]], unstaged: [], msg: "", chip: "", ai: "<b>claude/haiku</b>" + tail }); v.wait(900); v.key("Ctrl+r", 260);
          v.cpDo(function (c) { c.ai = "<b>claude/haiku</b> · <span class=\"st\">reviewing what is staged…</span>" + tail; }); v.wait(1100);
          v.diag(6, "error", "staged review", "looks like an AWS access key", 1, 2); v.diag(9, "warn", "staged review", "the new value is not validated before it is used", 2, 2);
          v.cpDo(function (c) { c.ai = "<b>claude/haiku</b> · <span class=\"wr\">review: 2 findings (quickfix)</span> · Ctrl-g to draft"; });
          v.wait(1800); v.key("Esc", 250); v.commit(null); v.zoom(1.3, 0, 0.3); v.wait(1700); v.zoom(1);
        } },
      { id: "release", title: "Release", chapter: "Ship", run: function (v, T) {
          v.caption(T.release); v.clearDiag(); v.open("cmd/api/main.go", 3); v.showCursor(false); v.wait(700);
          v.keys("␣ G R c"); v.wait(200);
          v.ov({ kind: "modal", title: "CHANGELOG.md", hint: h.BTNS("y", "Write", "p", "n"), lines: [
            "<b>v1.3.0</b>" + MU("  minor bump from 1.2.4 · 4 commits"), "",
            MU("### Features"), MU("- **notes:** archive a note, refuse done ones (a1f3c2e)"), MU("- **api:** export a note as Markdown (9bd01aa)"), "",
            MU("### Fixes"), MU("- an empty title no longer crashes the list (4c2e9f0)")] });
          v.wait(2600); v.key("y", 260); v.ov(null);
          v.toast("<b>Release: CHANGELOG.md has v1.3.0</b> · then bump the version, commit, git tag v1.3.0", 1800);
        } },

      /* ── control: what it cost ─────────────────────────────────────────────────────────────── */
      { id: "usage", title: "Usage", chapter: "Ship", run: function (v, T) {
          v.caption(T.usage); v.open("internal/application/note_service.go", 5, 14); v.showCursor(false); v.wait(600);
          v.keys("␣ a h"); v.wait(200); v.key("Ctrl+s", 280);
          v.ov({ kind: "report", title: "Agent usage", hint: " · Y copy all · BS back · q close ", lines: [
            ["h2", "Today"], [""], ["", "● <b>14 runs</b> · 9 accepted · 2 refined · 3 from the cache (<b>0 tokens</b>)"], ["", "● <b>$0.1274</b> of $1.00 budget (12%)"], [""],
            ["h2", "Where the prompt goes (average chars per run)"], [""],
            ["", "system <b>911</b> · message <b>549</b> = target 86 + context 205 (callees 33, diagnostics 53, types 84)"], [""],
            ["h2", "Suggestions"], [""],
            ["", "● <code>refactor</code> on claude/sonnet: 1 of 7 proposals accepted (14%). A more specific instruction"],
            ["", "  usually helps; <code>settings.agent.tiers = { refactor = \"light\" }</code> makes it cheaper to be wrong."],
            ["", "● <code>refine</code> (Tab) corrects a proposal in place for about the price of a single run."]] });
          v.wait(3600); v.key("q", 250); v.ov(null); v.wait(300);
        } },

      /* ── yours: the terminal's palette, live ───────────────────────────────────────────────── */
      { id: "themes", title: "Themes", chapter: "Yours", run: function (v, T) {
          v.layout("full"); v.caption(T.themes); v.tree(["internal", "internal/application", "internal/domain"]); v.open("internal/application/note_service.go", 12, 10);
          v.wait(1100);
          ["t:tokyo-night", "t:catppuccin-mocha", "t:rose-pine", "t:nord", "t:kanagawa", "t:catppuccin-latte", "t:dracula", "t:everforest"].forEach(function (id, i) {
            if (i === 0) v.keys("␣ S a"); else v.key("Space S r", 0);
            v.pal(id); v.wait(i < 2 ? 800 : 560);
          });
          v.keys("␣ S d"); v.pal(null); v.wait(900);
        } },

      /* ── close: keys, then the one command ─────────────────────────────────────────────────── */
      { id: "outro", title: "Outro", chapter: "Yours", run: function (v, T) {
          v.card("keys", Object.assign({ sweep: 300 }, T.keys)); v.wait(4200);
          v.card("install", T.install); v.wait(6200);
        } }
    ]
  };
})();
