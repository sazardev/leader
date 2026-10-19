/* Every word the brand kit prints, in one place: change copy here, re-run `node brand/render.mjs`.
   Pieces are looked up by id in brand.js (kind decides the layout); `caption` is the text to post with the image. */
var COPY = {
  name: "Leader",
  tagline: "Neovim, for working.",
  handle: "sazardev/leader",
  url: "github.com/sazardev/leader",
  install: "curl -fsSL https://raw.githubusercontent.com/sazardev/leader/master/install.sh | bash",
  installFine: "Linux · macOS · WSL. Windows: <code>irm …/install.ps1 | iex</code>. Pick languages with <code>--lang go</code>.",
  hashtags: "#neovim #vim #devtools #developers #ai #opensource",

  /* where each size is used (printed in USAGE.md and on the catalog sheets) */
  formats: {
    land:   { w: 1920, h: 1080, dir: "landscape",    use: "YouTube thumbnail/cover, X and LinkedIn video or image posts, Facebook, presentations, blog headers" },
    og:     { w: 1200, h: 630,  dir: "link-preview", use: "Link previews (Open Graph): LinkedIn, Facebook, X summary card, Slack, Discord, WhatsApp, Hacker News, dev.to" },
    square: { w: 1080, h: 1080, dir: "square",       use: "Instagram, LinkedIn, Facebook, Threads, Bluesky, Mastodon" },
    p45:    { w: 1080, h: 1350, dir: "portrait",     use: "Instagram feed (4:5 takes the most room), LinkedIn, Facebook, Threads" },
    story:  { w: 1080, h: 1920, dir: "story",        use: "Instagram and Facebook Stories, Reels/TikTok/Shorts cover, WhatsApp status" },
    pin:    { w: 1000, h: 1500, dir: "pinterest",    use: "Pinterest pins (2:3)" }
  },

  /* the eight keys of "Press Space." (the landing's tiles) */
  keys: [["a", "Agent"], ["G", "Git"], ["g", "Go"], ["C", "Comments"], ["x", "Diagnostics"], ["f", "Find"], ["P", "Session"], ["S", "Settings"]],

  /* the pieces. kind: poster | shot | stat | rows | keys | install | themes | duo.  bg: bg deep yellow aqua green; theme: "light" */
  pieces: [
    { id: "for-working", kind: "poster", bg: "bg", ghost: true, eyebrow: "A Neovim framework", lines: ["Neovim,", "for working."], accent: 1,
      sub: "<b>Fast. Minimal. Opinionated.</b> And an agent that only speaks when you ask.",
      caption: "Leader: a small Neovim framework made to work in. ~20 ms to a usable editor, one key per context, and an AI agent that only speaks when you ask. One command to install." },
    { id: "new-era", kind: "poster", bg: "deep", ghost: true, eyebrow: "The agent era", lines: ["Built for", "the new era", "of coding."], accent: 2,
      sub: "A small Neovim framework for people who work in the terminal and want an agent that stays out of the way.",
      caption: "Neovim for the agent era, without the chat window: one-shot actions on the code under your cursor, a diff you accept with Enter, and a budget that stops runaway spend." },
    { id: "local-first", kind: "poster", bg: "yellow", eyebrow: "Opinions", lines: ["Spend nothing", "you don't have to."], accent: -1,
      sub: "Local analysis first. A model only when nothing else can answer.",
      caption: "Leader runs completion, code search, architecture checks and changelogs on your machine. The model is for what only a model can do, and every run shows its cost." },
    { id: "lazy", kind: "poster", bg: "bg", theme: "light", eyebrow: "Opinions", lines: ["Lazy, or", "it doesn't ship."], accent: 1,
      sub: "Every plugin waits for an event, a filetype or a key.",
      caption: "Startup in ~20 ms is not an accident: in Leader every plugin is lazy, or it doesn't ship." },
    { id: "one-file", kind: "poster", bg: "deep", ghost: true, eyebrow: "Opinions", lines: ["One file,", "one thing."], accent: 1,
      sub: "Add a language, a plugin or an action by adding a file.",
      caption: "Extending Leader means adding a file: a language, a plugin, an agent action. The registries find it on their own." },

    { id: "20ms", kind: "stat", bg: "yellow", eyebrow: "Startup", num: "20", unit: "ms", says: "To a usable editor. Nothing loads until it has a reason to.",
      caption: "~20 ms from keypress to a usable editor. Leader loads nothing until it has a reason to." },
    { id: "zero-tokens", kind: "stat", bg: "deep", eyebrow: "Local first", num: "0", unit: "tokens", says: "Go completion, code search, architecture checks and the changelog run on your machine.",
      caption: "Zero tokens for the things a computer can do by itself: completion, search, architecture analysis, changelogs." },
    { id: "four-docs", kind: "stat", bg: "aqua", eyebrow: "From documents to code", num: "4", unit: "docs", says: "AGENTS, STACK, DESIGN and SPEC. From presets or your words. Then build from them.",
      caption: "Four documents describe the project (AGENTS, STACK, DESIGN, SPEC) and Leader builds it from them, one layer or one feature at a time." },
    { id: "one-yes", kind: "stat", bg: "bg", eyebrow: "Fix all", num: "1", unit: "yes", says: "Every problem in the file, one confirmation, with the total cost up front.",
      caption: "Fix the whole file with one confirmation: one proposal per function, the total cost shown before anything runs." },
    { id: "one-key", kind: "stat", bg: "green", eyebrow: "Keyboard", num: "1", unit: "key", says: "Space, then one letter per context. It only shows what applies to where you are.",
      caption: "Press Space. One letter per context, and a menu that only shows what applies to the file you are in." },

    { id: "press-space", kind: "keys", bg: "aqua", eyebrow: "Keyboard", lines: ["Press Space."], accent: -1, lead: "One letter per context. It only shows what applies to where you are.", hot: 0,
      caption: "Everything in Leader starts with Space: a for the agent, G for Git, g for Go, f to find. One letter per context." },
    { id: "one-command", kind: "install", bg: "green", eyebrow: "Install", lines: ["One command."], accent: -1,
      caption: "Install Leader with one command. It asks nothing, links the config, installs the plugins and the language servers you use, and never overwrites an existing config without a backup." },
    { id: "decided", kind: "rows", bg: "deep", eyebrow: "Opinions", lines: ["Decided", "for you."], accent: 1, hot: 0,
      rows: [["Lazy, or it doesn't ship.", "Every plugin waits for an event, a filetype or a key."], ["One file, one thing.", "Add a language, a plugin or an action by adding a file."],
             ["Spend nothing you don't have to.", "Local analysis first. A model only when nothing else can answer."], ["Everything is a key.", "Press Space, then one letter."]],
      caption: "Leader is opinionated on purpose: lazy plugins, one file per responsibility, local analysis before any model, everything one key away." },
    { id: "write-it-down", kind: "rows", bg: "bg", eyebrow: "From documents to code", lines: ["Write it down.", "Build it a piece", "at a time."], accent: 2, hot: 1,
      rows: [["Four documents.", "AGENTS, STACK, DESIGN and SPEC. From presets or your words."], ["One layer.", "Foundation, domain or screens, each from its document."],
             ["One feature.", "Describe it. It lands in SPEC.md, then it is built end to end."], ["It remembers why.", "Decisions become ADRs. PROGRESS.md says what is left."]],
      caption: "Write the project down once. Leader builds one layer or one feature at a time from your documents, records the decisions as ADRs and keeps PROGRESS.md up to date." },

    { id: "type-less", kind: "shot", bg: "deep", shot: "complete-missing", eyebrow: "Go completion · 0 tokens", lines: ["Type less.", "It knows your code."], accent: 1,
      sub: "Errors wrapped with context, <b>missing interface methods</b>, constructors, mappers. Local, instant, free.",
      caption: "Start typing a method and Leader offers every method the interface still lacks, with their signatures. Local completion, no tokens." },
    { id: "agent-asks", kind: "shot", bg: "bg", shot: "implement", eyebrow: "Inline agent", lines: ["An agent that", "speaks when", "you ask."], accent: 2, keys: "Space a i",
      sub: "One-shot actions on the function under your cursor. No chat, no sidebar.",
      caption: "Write the signature and its comment, press Space a i, accept the diff with Enter. No chat window: the result is in your code." },
    { id: "red-line", kind: "shot", bg: "deep", shot: "fix", eyebrow: "Inline agent · fix block", lines: ["Red line?", "One key."], accent: 1, keys: "Space a F",
      sub: "The smallest change that makes the block coherent. <b>Enter</b> accepts, <b>Esc</b> rejects, <b>Tab</b> refines.",
      caption: "A diagnostic on your code? Space a F proposes the smallest change that fixes it, as an inline diff you accept with Enter." },
    { id: "whole-file", kind: "shot", bg: "bg", shot: "fixall-queue", eyebrow: "Agent advanced · fix all", lines: ["The whole file.", "One yes."], accent: 1, keys: "Space a A a",
      sub: "One proposal per function, <b>one confirmation</b> with the total cost. They wait in a queue.",
      caption: "Fix every problem in a file with one confirmation. The proposals wait in a queue you walk with ] and [, and y accepts them all." },
    { id: "lens", kind: "shot", bg: "deep", shot: "lens-finding", eyebrow: "Lenses", lines: ["Look for one", "thing. Find it."], accent: 1, keys: "Space a L s",
      sub: "Security, errors, concurrency, performance. Findings land on their line. Code outside the topic costs <b>0 tokens</b>.",
      caption: "Lenses look for one thing: security, errors, concurrency, performance. The finding shows on its line, and one more key fixes it." },
    { id: "convert", kind: "shot", bg: "bg", shot: "convert", eyebrow: "Inline agent · convert", lines: ["Paste JSON.", "Get types."], accent: 1, keys: "Space a t",
      sub: "JSON, a <b>CREATE TABLE</b> or a curl command become ready code in the file's language.",
      caption: "Paste a JSON sample, a CREATE TABLE or a curl command and Space a t turns it into types or a client in the language of the file." },
    { id: "docs", kind: "shot", bg: "deep", shot: "docs-explain", eyebrow: "Inline agent · docs + explain", lines: ["Comments", "that say why."], accent: 1, keys: "Space a d",
      sub: "It returns <b>only the comment</b>, so your code can't change. Ask for an explanation without leaving the line.",
      caption: "Docs that cannot touch your code: the model returns only the comment. And Space a e explains the function under the cursor in a float." },
    { id: "tests", kind: "shot", bg: "bg", shot: "tests", eyebrow: "Agent tests", lines: ["Tests, next", "to the code."], accent: 1, keys: "Space a T w",
      sub: "Table-driven, in the right file, in your style. Gaps and mocks too.",
      caption: "Space a T w writes the test next to the code, in a split, table-driven. Gaps and mocks have their own keys." },
    { id: "build", kind: "shot", bg: "yellow", shot: "build-run", eyebrow: "Build with agent", lines: ["Plan, write,", "check, fix."], accent: -1, keys: "Space a S b b",
      sub: "You review the plan once. The build checks itself and repairs what fails.",
      caption: "Build with agent: plan, review once, write, check, fix. It keeps going in the background and the statusline shows where it is." },
    { id: "commits", kind: "shot", bg: "bg", shot: "commit", eyebrow: "Commits", lines: ["Commits that", "write themselves."], accent: 1, keys: "Space G c",
      sub: "Conventional Commits checked live. It <b>says what it reads before spending</b>.",
      caption: "One panel to stage, write and validate a Conventional Commit, with an AI draft that tells you what it reads before it spends anything." },
    { id: "caught", kind: "shot", bg: "deep", shot: "review", eyebrow: "Review staged", lines: ["Caught before", "it shipped."], accent: 1, keys: "Ctrl r",
      sub: "Free local checks first, then one numbered request. Findings go to the quickfix.",
      caption: "Review what is staged before you commit: a leaked key, an unvalidated value. Local checks first, then one request." },
    { id: "release", kind: "shot", bg: "aqua", shot: "release", eyebrow: "Release kit", lines: ["Changelog and", "version. Done."], accent: -1, keys: "Space G R c",
      sub: "The next semver and the changelog from your commits. <b>0 tokens</b>. Nothing pushes by itself.",
      caption: "The next version and the changelog straight from your Conventional Commits, a PR description and a release checklist. Nothing pushes, tags or deploys by itself." },
    { id: "budget", kind: "shot", bg: "bg", shot: "usage", eyebrow: "Agent history", lines: ["Every token,", "accounted for."], accent: 1, keys: "Space a h",
      sub: "Time, tokens and cost on every run. A daily budget. Identical answers come back from the cache for free.",
      caption: "Every agent run is logged with its prompt, tokens and cost, and a daily budget stops runaway spend. Identical answers come back from a cache at no cost." },
    { id: "which-key", kind: "shot", bg: "aqua", shot: "whichkey", eyebrow: "Keyboard", lines: ["Space, then", "one letter."], accent: -1,
      sub: "A menu that only shows what applies to where you are.",
      caption: "Press Space and Leader shows what is possible in the file you are in, nothing more." },

    { id: "colors", kind: "themes", bg: "bg", eyebrow: "Appearance", lines: ["Your terminal's", "colors. Everywhere."], accent: 1,
      themes: ["tokyo-night", "catppuccin-mocha", "rose-pine", "nord", "kanagawa", "everforest", "dracula", "catppuccin-latte"],
      names: { "tokyo-night": "Tokyo Night", "catppuccin-mocha": "Catppuccin Mocha", "rose-pine": "Rosé Pine", "nord": "Nord", "kanagawa": "Kanagawa", "everforest": "Everforest", "dracula": "Dracula", "catppuccin-latte": "Catppuccin Latte" },
      caption: "Leader reads your terminal's palette and derives every color from it: the editor, the menus, the diffs. Change the terminal theme and everything follows." },
    { id: "dark-light", kind: "duo", bg: "deep", eyebrow: "Appearance", lines: ["Dark or light.", "Same editor."], accent: 1, a: "catppuccin-mocha", b: "catppuccin-latte", names: ["Catppuccin Mocha", "Catppuccin Latte"],
      caption: "Dark in the evening, light in the morning: Leader follows your terminal's palette, contrast checked." }
  ],

  /* carousels (1080×1350): lists of piece ids, plus tips */
  carousels: {
    launch: ["for-working", "decided", "type-less", "red-line", "write-it-down", "press-space", "one-command"],
    agent: ["agent-asks", "red-line", "lens", "whole-file", "commits", "caught"]
  },
  tips: [
    { keys: "Space f f", say: "Find any file by typing a few letters.", bg: "deep" },
    { keys: "Space f w", say: "Search the whole project, live, with a preview.", bg: "yellow" },
    { keys: "Space a e", say: "Explain the function under the cursor.", bg: "bg" },
    { keys: "Space x d", say: "Read the diagnostics of this line, in full.", bg: "aqua" },
    { keys: "Space G c", say: "Commit with a message the model drafts and checks.", bg: "deep" },
    { keys: "Space S p", say: "Change settings live. No restart.", bg: "green" }
  ],
  tipsCaption: "Six keys to start with in Leader. Press Space and the menu shows the rest.",

  /* wallpapers: formats (d desktop, p phone, u ultrawide, k 4K) and the collection. design: ghost grid braille keys dots minimal editor;
     pal = a terminal palette from the landing's picker (derived like Neovim derives it), bg = a landing panel, theme "light" = gruvbox light */
  wallpaperFormats: {
    d: { w: 2560, h: 1440, dir: "wallpapers/desktop",   use: "Desktop wallpaper 16:9 (QHD; scales to 1080p and most laptops)" },
    p: { w: 1170, h: 2532, dir: "wallpapers/phone",     use: "Phone wallpaper (iPhone 12-15 size; fits most phones when set to fill)" },
    u: { w: 3440, h: 1440, dir: "wallpapers/ultrawide", use: "Ultrawide 21:9 desktop wallpaper" },
    k: { w: 3840, h: 2160, dir: "wallpapers/4k",        use: "4K / UHD desktop wallpaper" }
  },
  wallpapers: [
    { id: "ghost-gruvbox", design: "ghost", bg: "deep", f: "dpuk" }, { id: "ghost-yellow", design: "ghost", bg: "yellow", f: "dpu" },
    { id: "ghost-green", design: "ghost", bg: "green", f: "dp" }, { id: "ghost-aqua", design: "ghost", bg: "aqua", f: "dp" },

    { id: "grid-gruvbox", design: "grid", bg: "deep", f: "dpuk" }, { id: "grid-yellow", design: "grid", bg: "yellow", f: "dpu" },
    { id: "grid-tokyo-night", design: "grid", pal: "tokyo-night", f: "dpuk" }, { id: "grid-catppuccin-mocha", design: "grid", pal: "catppuccin-mocha", f: "dpuk" },
    { id: "grid-rose-pine", design: "grid", pal: "rose-pine", f: "dp" }, { id: "grid-nord", design: "grid", pal: "nord", f: "dpk" },
    { id: "grid-kanagawa", design: "grid", pal: "kanagawa", f: "dp" }, { id: "grid-everforest", design: "grid", pal: "everforest", f: "dp" },
    { id: "grid-dracula", design: "grid", pal: "dracula", f: "dpk" }, { id: "grid-one-dark", design: "grid", pal: "one-dark", f: "dp" },
    { id: "grid-catppuccin-latte", design: "grid", pal: "catppuccin-latte", f: "dpk" }, { id: "grid-solarized-light", design: "grid", pal: "solarized-light", f: "dp" },
    { id: "grid-gruvbox-light", design: "grid", bg: "bg", theme: "light", f: "dp" },

    { id: "braille-gruvbox", design: "braille", bg: "deep", f: "dpu" }, { id: "braille-yellow", design: "braille", bg: "yellow", f: "dp" },
    { id: "braille-green", design: "braille", bg: "green", f: "dp" }, { id: "braille-tokyo-night", design: "braille", pal: "tokyo-night", f: "dp" },
    { id: "braille-nord", design: "braille", pal: "nord", f: "dp" }, { id: "braille-rose-pine", design: "braille", pal: "rose-pine", f: "dp" },
    { id: "braille-gruvbox-light", design: "braille", bg: "bg", theme: "light", f: "dp" },

    { id: "keys-aqua", design: "keys", bg: "aqua", f: "dpu" }, { id: "keys-gruvbox", design: "keys", bg: "deep", f: "dp" }, { id: "keys-yellow", design: "keys", bg: "yellow", f: "dp" },

    { id: "dots-press-space", design: "dots", bg: "deep", lines: ["PRESS", "SPACE"], f: "dpu" }, { id: "dots-leader", design: "dots", bg: "yellow", lines: ["LEADER"], f: "dpu" },
    { id: "dots-20ms", design: "dots", bg: "green", lines: ["20MS"], f: "dp" }, { id: "dots-press-space-dracula", design: "dots", pal: "dracula", lines: ["PRESS", "SPACE"], f: "dp" },
    { id: "dots-leader-gruvbox-light", design: "dots", bg: "bg", theme: "light", lines: ["LEADER"], f: "dp" },
    { id: "dots-lgtm", design: "dots", pal: "tokyo-night", lines: ["LGTM"], f: "dpu" }, { id: "dots-ship-it", design: "dots", bg: "green", lines: ["SHIP", "IT"], f: "dp" },
    { id: "dots-todo", design: "dots", bg: "aqua", lines: ["TODO"], f: "dpu" }, { id: "dots-hello-world", design: "dots", pal: "everforest", lines: ["HELLO", "WORLD"], f: "dp" },
    { id: "dots-0-errors", design: "dots", bg: "deep", lines: ["0", "ERRORS"], f: "dp" }, { id: "dots-build-ok", design: "dots", pal: "nord", lines: ["BUILD", "OK"], f: "dp" },
    { id: "dots-focus", design: "dots", pal: "rose-pine", lines: ["FOCUS"], f: "dpu" }, { id: "dots-null", design: "dots", bg: "bg", theme: "light", lines: ["NULL"], f: "dpu" },
    { id: "dots-merged", design: "dots", pal: "catppuccin-mocha", lines: ["MERGED"], f: "dpu" }, { id: "dots-deploy", design: "dots", pal: "one-dark", lines: ["DEPLOY"], f: "dpu" },
    { id: "dots-404", design: "dots", bg: "yellow", lines: ["404", "NOT FOUND"], f: "dp" }, { id: "dots-fixed", design: "dots", pal: "kanagawa", lines: ["FIXED"], f: "dpu" },

    { id: "minimal-gruvbox", design: "minimal", bg: "deep", f: "dp" }, { id: "minimal-yellow", design: "minimal", bg: "yellow", f: "dp" },
    { id: "minimal-green", design: "minimal", bg: "green", f: "dp" }, { id: "minimal-gruvbox-light", design: "minimal", bg: "bg", theme: "light", f: "dp" },
    { id: "minimal-tokyo-night", design: "minimal", pal: "tokyo-night", f: "dp" }, { id: "minimal-nord", design: "minimal", pal: "nord", f: "dp" },

    { id: "editor-gruvbox", design: "editor", bg: "deep", shot: "fix", f: "du" }, { id: "editor-tokyo-night", design: "editor", pal: "tokyo-night", shot: "theme-tokyo-night", f: "du" },
    { id: "editor-catppuccin-mocha", design: "editor", pal: "catppuccin-mocha", shot: "theme-catppuccin-mocha", f: "du" }, { id: "editor-rose-pine", design: "editor", pal: "rose-pine", shot: "theme-rose-pine", f: "du" },
    { id: "editor-nord", design: "editor", pal: "nord", shot: "theme-nord", f: "du" }, { id: "editor-kanagawa", design: "editor", pal: "kanagawa", shot: "theme-kanagawa", f: "du" }
  ],

  /* more wallpapers, with words. Same fields as above (pal / bg / theme, f = formats); the languages' tools are the ones Leader really
     declares (nvim/lua/languages/*.lua) and the keys are the real menus (read from the landing's keymap dump). */
  wpPhrases: [
    { id: "ship-it", bg: "yellow", lines: ["Ship it."], f: "dpuk" },
    { id: "read-the-error", pal: "tokyo-night", lines: ["Read the", "error."], accent: 1, sub: "It usually tells you.", f: "dpu" },
    { id: "one-thing-at-a-time", pal: "nord", lines: ["One thing", "at a time."], accent: 1, f: "dpu" },
    { id: "commit-early", bg: "deep", lines: ["Commit early.", "Commit small."], accent: 1, f: "dpuk" },
    { id: "delete-code", pal: "rose-pine", lines: ["Delete code.", "Keep the feature."], accent: 1, f: "dpu" },
    { id: "name-things-well", bg: "green", lines: ["Name things", "well."], f: "dpu" },
    { id: "less-code", pal: "catppuccin-latte", lines: ["Less code,", "fewer bugs."], accent: 1, f: "dpuk" },
    { id: "fix-the-cause", pal: "kanagawa", lines: ["Fix the cause,", "not the symptom."], accent: 1, f: "dpu" },
    { id: "works-on-my-machine", bg: "aqua", lines: ["It works", "on my machine."], sub: "Then ship the Dockerfile.", f: "dpu" },
    { id: "make-it-boring", pal: "everforest", lines: ["Make it", "boring."], accent: 1, sub: "Boring code ships.", f: "dp" },
    { id: "write-it-down", bg: "bg", theme: "light", lines: ["Write it", "down."], accent: 1, sub: "Future you is a different person.", f: "dpuk" },
    { id: "focus", pal: "dracula", lines: ["Focus."], accent: 0, sub: "One buffer. One task.", f: "dpu" },
    { id: "neovim-for-working", bg: "deep", lines: ["Neovim,", "for working."], accent: 1, f: "dpuk" },
    { id: "type-less", pal: "catppuccin-mocha", lines: ["Type less.", "Ask when it", "matters."], accent: 2, f: "dp" },
    { id: "local-first", pal: "one-dark", lines: ["Local first.", "Tokens last."], accent: 1, f: "dpu" },
    { id: "press-space", bg: "aqua", lines: ["Press", "Space."], sub: "Everything starts here.", f: "dp" },
    { id: "git-commit", pal: "solarized-dark", mono: true, lines: ["git commit", "-m \"it works\""], accent: 1, f: "dpu" },
    { id: "nvim-dot", bg: "deep", mono: true, lines: ["$ nvim ."], accent: 0, sub: "Then press Space.", f: "dpu" }
  ],

  wpLangs: [
    { id: "go", name: "Go", ext: ".go", lang: "go", key: "Space g", bg: "deep", f: "dpu",
      stack: "gopls · goimports + gofumpt · golangci-lint · custom Go completion",
      code: ["package main", "", "import \"fmt\"", "", "func main() {", "\tfmt.Println(\"Hello, Leader\")", "}"] },
    { id: "rust", name: "Rust", ext: ".rs", lang: "rust", key: "Space r", pal: "dracula", f: "dpu",
      stack: "rust-analyzer · rustfmt · codelldb · cargo tests in the editor",
      code: ["fn main() {", "    let name = \"Leader\";", "    println!(\"Hello, {name}\");", "}"] },
    { id: "python", name: "Python", ext: ".py", lang: "python", key: "Space p", pal: "tokyo-night", f: "dpu",
      stack: "basedpyright + ruff · ruff format · pytest in the editor · debugpy",
      code: ["def main() -> None:", "    name = \"Leader\"", "    print(f\"Hello, {name}\")", "", "if __name__ == \"__main__\":", "    main()"] },
    { id: "typescript", name: "TypeScript", ext: ".ts", lang: "typescript", key: "Space t", pal: "catppuccin-mocha", f: "dpu",
      stack: "vtsls · eslint · biome · prettier · vitest, jest and bun in the editor",
      code: ["const greet = (name: string): string =>", "  `Hello, ${name}`;", "", "console.log(greet(\"Leader\"));"] },
    { id: "dart", name: "Dart", ext: ".dart", lang: "dart", key: "Space d", pal: "nord", f: "dpu",
      stack: "Dart language server · flutter-tools · dart format · build_runner watch · tests in the editor",
      code: ["void main() {", "  const name = 'Leader';", "  print('Hello, $name');", "}"] },
    { id: "swift", name: "Swift", ext: ".swift", lang: "swift", key: "Space i", pal: "rose-pine", f: "dpu",
      stack: "sourcekit-lsp · swift format · swiftlint · SwiftPM tests in the editor",
      code: ["import Foundation", "", "let name = \"Leader\"", "print(\"Hello, \\(name)\")"] },
    { id: "java", name: "Java", ext: ".java", lang: "java", key: "Space j", pal: "kanagawa", f: "dp",
      stack: "Gradle and Maven: run, build, test, check, clean",
      code: ["public class Main {", "    public static void main(String[] args) {", "        System.out.println(\"Hello, Leader\");", "    }", "}"] },
    { id: "kotlin", name: "Kotlin", ext: ".kt", lang: "kotlin", key: "Space k", pal: "solarized-dark", f: "dp",
      stack: "Gradle and Maven: run, build, test, check, clean",
      code: ["fun main() {", "    val name = \"Leader\"", "    println(\"Hello, $name\")", "}"] },
    { id: "lua", name: "Lua", ext: ".lua", lang: "lua", key: "", pal: "everforest", f: "dpu",
      stack: "lua_ls · stylua · the language this whole config is written in",
      code: ["local name = \"Leader\"", "", "print((\"Hello, %s\"):format(name))"] },
    { id: "sql", name: "SQL", ext: ".sql", lang: "sql", key: "Space Q", pal: "one-dark", f: "dpu",
      stack: "sqls · sql-formatter · run the statement under the cursor against your database",
      code: ["SELECT id, title", "FROM notes", "WHERE status = 'done'", "ORDER BY id DESC", "LIMIT 10;"] },
    { id: "html", name: "HTML", ext: ".html", lang: "html", key: "", bg: "bg", theme: "light", f: "dp",
      stack: "html language server · emmet · prettier",
      code: ["<main>", "  <h1>Hello, Leader</h1>", "  <p>Neovim, for working.</p>", "</main>"] },
    { id: "css", name: "CSS", ext: ".css", lang: "css", key: "Space s", pal: "catppuccin-latte", f: "dp",
      stack: "css language server · prettier · tailwind and astro too",
      code: ["main {", "  display: grid;", "  place-items: center;", "  min-height: 100vh;", "}"] },
    { id: "markdown", name: "Markdown", ext: ".md", lang: "markdown", key: "Space m", pal: "catppuccin-mocha", f: "dp",
      stack: "markdownlint · prettier · its own Space m menu",
      code: ["# Leader", "", "Neovim, for working.", "", "- Fast", "- Minimal", "- Opinionated"] }
  ],

  wpTerms: [
    { id: "refactor", term: "refactor", pos: "verb", def: "To restructure code without changing what it does.", keys: "Space a R", pal: "tokyo-night", f: "dpu" },
    { id: "idempotent", term: "idempotent", pos: "adjective", def: "Doing it twice has the same effect as doing it once.", bg: "yellow", f: "dpu" },
    { id: "race-condition", term: "race condition", pos: "noun", def: "When the result depends on which thread gets there first.", keys: "Space a L c", keysNote: "the concurrency lens looks for it", pal: "dracula", f: "dpu" },
    { id: "cache", term: "cache", pos: "noun", def: "Remembering an answer so you don't compute it twice.", keys: "Space a A k", keysNote: "identical agent requests come back for free", bg: "green", f: "dpu" },
    { id: "lint", term: "lint", pos: "noun", def: "A tool that reads your code and complains before the compiler does.", keys: "Space g v", keysNote: "in Go files", pal: "nord", f: "dpu" },
    { id: "diff", term: "diff", pos: "noun", def: "What changed between two versions.", keys: "Space G d", pal: "everforest", f: "dpu" },
    { id: "regression", term: "regression", pos: "noun", def: "Something that used to work.", keysNote: "the agent checks what it accepts for new problems", bg: "aqua", f: "dpu" },
    { id: "yak-shaving", term: "yak shaving", pos: "noun", def: "Doing a chain of small tasks to avoid the real one.", bg: "deep", f: "dpu" }
  ],

  /* key cheat sheets: path is the which-key menu ("a" = <leader>a), keys the entries to show, in order */
  wpCheats: [
    { id: "agent", title: "Agent", path: "a", keys: ["i", "f", "F", "e", "d", "r", "R", "t", "n", "h", "L", "A"], pal: "tokyo-night", f: "dpu" },
    { id: "find", title: "Find", path: "f", keys: ["f", "w", "r", "s", "b", "o", "m"], labels: { f: "Find files", w: "Live grep", r: "Replace in project", s: "Project symbols", b: "Buffers", o: "Old files", m: "Format file" }, bg: "yellow", f: "dpu" },
    { id: "git", title: "Git", path: "G", keys: ["c", "m", "M", "d", "b", "r", "f", "v", "R", "a", "t", "i"], labels: { c: "Commit", m: "Commit + AI", M: "Auto commit", d: "Diff", b: "Blame", r: "Repo history", f: "File history", v: "Review staged", R: "Release", a: "Amend", t: "Status", i: "Ignore rules" }, pal: "catppuccin-mocha", f: "dpu" },
    { id: "go", title: "Go", path: "g", keys: ["r", "m", "f", "e", "T", "a", "s", "t", "v", "b", "c", "S"], labels: { r: "Run", m: "Test all", f: "Format", e: "if err != nil", T: "Add test", a: "JSON tags", s: "Fill struct", t: "Mod tidy", v: "Lint", b: "Build", c: "Test + cover", S: "Setup" }, bg: "deep", f: "dpu" },
    { id: "diagnostics", title: "Diagnostics", path: "x", keys: ["d", "x", "n", "p", "a", "e", "l", "c"], labels: { d: "Line popup", x: "Project list", n: "Next block", p: "Previous block", a: "Inline blocks", e: "Copy all", l: "Copy line", c: "Collapse blocks" }, pal: "nord", f: "dpu" },
    { id: "files", title: "Files", path: "F", keys: ["n", "N", "r", "m", "c", "x", "u", "y"], labels: { n: "New file", N: "New folder", r: "Rename", m: "Move", c: "Duplicate", x: "Delete", u: "Undo delete", y: "Copy path" }, bg: "green", f: "dpu" },
    { id: "settings", title: "Settings", path: "S", keys: ["p", "t", "f", "l", "M", "u", "i"], labels: { p: "Panel", t: "Toggle theme", f: "Format on save", l: "Plugins", M: "Tools", u: "Update config", i: "Info" }, pal: "rose-pine", f: "dp" }
  ],

  /* banners */
  banner: { lines: ["Neovim,", "for working."], sub: "~20 ms. One key per context. An agent that speaks when you ask." }
};
