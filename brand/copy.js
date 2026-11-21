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

  /* language cheat sheets: one wallpaper per theme, each with 12 entries (signature + description + one example). */
  wpCheatSheets: [
    {
      id: "go",
      name: "Go",
      ac: "var(--green)",
      f: "dpuk",
      intro: "Twelve corners of the standard library, one line of code each — the whole sheet at a glance.",
      primary: {
        sig: "fmt.Println(\"Hello, Leader\")",
        desc: "Start here: the smallest Go program prints something and moves on.",
        ex: "fmt.Println(\"Hello, Leader\")"
      },
      items: [
        {
          name: "Time",
          sig: "time.Unix(sec, nsec)",
          desc: "Create a time.Time from Unix epoch seconds plus nanoseconds.",
          ex: "time.Unix(1700000000, 0).UTC()"
        },
        {
          name: "Strings",
          sig: "strings.Split(s, sep)",
          desc: "Split a string into a []string at every separator.",
          ex: "strings.Split(\"a,b,c\", \",\")"
        },
        {
          name: "Slices",
          sig: "slices.Sort(xs)",
          desc: "Sort any ordered slice in place. Go 1.21+, no comparator needed.",
          ex: "slices.Sort([]int{3, 1, 2})"
        },
        {
          name: "Errors",
          sig: "fmt.Errorf(\"...: %w\", err)",
          desc: "Wrap an error and keep errors.Is / errors.As working.",
          ex: "fmt.Errorf(\"open config: %w\", err)"
        },
        {
          name: "Concurrency",
          sig: "go func() { ... }()",
          desc: "Run work in a goroutine; pair with sync.WaitGroup to wait for it.",
          ex: "wg.Add(1); go work(&wg)"
        },
        {
          name: "Maps",
          sig: "v, ok := m[k]",
          desc: "Read a value and check it exists — the comma-ok idiom.",
          ex: "if v, ok := counts[\"go\"]; ok { }"
        },
        {
          name: "Context",
          sig: "context.WithTimeout(ctx, d)",
          desc: "Bound work by time; always call the returned cancel.",
          ex: "context.WithTimeout(ctx, 2*time.Second)"
        },
        {
          name: "JSON",
          sig: "json.Marshal(v)",
          desc: "Encode any value into JSON bytes. Returns ([]byte, error).",
          ex: "b, err := json.Marshal(user)"
        },
        {
          name: "Formatting",
          sig: "fmt.Printf(\"%+v\", x)",
          desc: "Print a value with its field names — ideal for inspecting structs.",
          ex: "fmt.Printf(\"%+v\\n\", user)"
        },
        {
          name: "Channels",
          sig: "make(chan T, n)",
          desc: "Create a buffered channel; unbuffered when the capacity is zero.",
          ex: "ch := make(chan int, 10)"
        },
        {
          name: "Files",
          sig: "os.ReadFile(name)",
          desc: "Read a whole file into []byte; it closes the file for you.",
          ex: "b, err := os.ReadFile(\"go.mod\")"
        },
        {
          name: "Defer",
          sig: "defer f.Close()",
          desc: "Run a call when the surrounding function returns — LIFO order.",
          ex: "defer f.Close()"
        }
      ]
    },
    {
      f: "dpuk",
      id: "time",
      name: "Time",
      ac: "var(--green)",
      intro: "Instants, durations, layouts and clocks — the whole time package on one sheet.",
      primary: {
        sig: "time.Now()",
        desc: "The current instant, carrying a monotonic reading so Sub and Since stay safe.",
        ex: "now := time.Now()"
      },
      items: [
        {
          name: "Now",
          sig: "time.Now()",
          desc: "Current instant; includes a monotonic reading for safe subtraction.",
          ex: "now := time.Now()"
        },
        {
          name: "Unix",
          sig: "time.Unix(sec, nsec)",
          desc: "Build a Time from Unix epoch seconds plus nanoseconds.",
          ex: "time.Unix(1700000000, 0)"
        },
        {
          name: "Date",
          sig: "time.Date(y, mo, d, h, mi, s, ns, loc)",
          desc: "Construct a Time in a given location.",
          ex: "time.Date(2026, 11, 20, 9, 0, 0, 0, time.UTC)"
        },
        {
          name: "Format",
          sig: "t.Format(layout)",
          desc: "Render with the reference layout Mon Jan 2 15:04:05 2006.",
          ex: "t.Format(time.RFC3339)"
        },
        {
          name: "Parse",
          sig: "time.Parse(layout, s)",
          desc: "Parse a string into a Time (UTC unless a zone is given).",
          ex: "time.Parse(time.RFC3339, s)"
        },
        {
          name: "Add",
          sig: "t.Add(d) / t.AddDate(y, mo, d)",
          desc: "Shift by a duration or by calendar units.",
          ex: "t.Add(2 * time.Hour)"
        },
        {
          name: "Sub",
          sig: "t.Sub(u)",
          desc: "The Duration between two instants.",
          ex: "d := t.Sub(start)"
        },
        {
          name: "Since",
          sig: "time.Since(t)",
          desc: "Shortcut for time.Now().Sub(t) — timing made easy.",
          ex: "fmt.Println(time.Since(start))"
        },
        {
          name: "Until",
          sig: "time.Until(t)",
          desc: "Shortcut for t.Sub(time.Now()) — time left until a deadline.",
          ex: "if time.Until(deadline) < 0 { }"
        },
        {
          name: "Sleep",
          sig: "time.Sleep(d)",
          desc: "Pause the current goroutine for at least d.",
          ex: "time.Sleep(100 * time.Millisecond)"
        },
        {
          name: "Ticker",
          sig: "time.NewTicker(d)",
          desc: "Repeating ticks on a channel — remember to Stop() it.",
          ex: "ticker := time.NewTicker(time.Second)"
        },
        {
          name: "After",
          sig: "<-time.After(d)",
          desc: "A channel that receives once, after the duration elapses.",
          ex: "select { case <-time.After(time.Second): }"
        }
      ]
    },
    {
      f: "dpuk",
      id: "strings",
      name: "Strings",
      ac: "var(--yellow)",
      intro: "Split, join, trim, search and build — without allocating more than you need.",
      primary: {
        sig: "strings.Join(xs, \", \")",
        desc: "Concatenate a slice with a separator in a single pass.",
        ex: "s := strings.Join(xs, \", \")"
      },
      items: [
        {
          name: "Split",
          sig: "strings.Split(s, sep)",
          desc: "Split into a []string at every separator.",
          ex: "strings.Split(\"a,b,c\", \",\")"
        },
        {
          name: "Join",
          sig: "strings.Join(xs, sep)",
          desc: "Join a slice of strings into one value.",
          ex: "strings.Join(xs, \", \")"
        },
        {
          name: "Contains",
          sig: "strings.Contains(s, sub)",
          desc: "Is the substring anywhere in s?",
          ex: "strings.Contains(s, \"go\")"
        },
        {
          name: "HasPrefix",
          sig: "strings.HasPrefix(s, p)",
          desc: "Prefix check — its sibling HasSuffix checks the end.",
          ex: "strings.HasPrefix(s, \"pkg/\")"
        },
        {
          name: "TrimSpace",
          sig: "strings.TrimSpace(s)",
          desc: "Strip leading and trailing whitespace.",
          ex: "strings.TrimSpace(line)"
        },
        {
          name: "ReplaceAll",
          sig: "strings.ReplaceAll(s, old, new)",
          desc: "Replace every occurrence of a substring.",
          ex: "strings.ReplaceAll(s, \"\\t\", \"  \")"
        },
        {
          name: "Fields",
          sig: "strings.Fields(s)",
          desc: "Split on runs of whitespace, dropping empties.",
          ex: "words := strings.Fields(s)"
        },
        {
          name: "Builder",
          sig: "var b strings.Builder",
          desc: "Efficient repeated concatenation without copies.",
          ex: "b.WriteString(\"leader\")"
        },
        {
          name: "Index",
          sig: "strings.Index(s, sub)",
          desc: "First byte index of sub, or -1 when absent.",
          ex: "i := strings.Index(s, \"go\")"
        },
        {
          name: "Count",
          sig: "strings.Count(s, sub)",
          desc: "Number of non-overlapping occurrences.",
          ex: "n := strings.Count(s, \"a\")"
        },
        {
          name: "ToLower",
          sig: "strings.ToLower(s) / ToUpper(s)",
          desc: "Case conversion for the whole string.",
          ex: "strings.ToLower(s)"
        },
        {
          name: "TrimPrefix",
          sig: "strings.TrimPrefix(s, p)",
          desc: "Remove a prefix, but only if it is there.",
          ex: "strings.TrimPrefix(s, \"./\")"
        }
      ]
    },
    {
      f: "dpuk",
      id: "slices",
      name: "Slices",
      ac: "var(--aqua)",
      intro: "The Go 1.21+ slices package: sort, search, copy and reshape with zero ceremony.",
      primary: {
        sig: "append(xs, v)",
        desc: "Grow a slice, reallocating only when capacity runs out.",
        ex: "xs = append(xs, 4)"
      },
      items: [
        {
          name: "append",
          sig: "append(xs, v)",
          desc: "Add a value; may reallocate when capacity is full.",
          ex: "xs = append(xs, 4)"
        },
        {
          name: "make",
          sig: "make([]T, 0, n)",
          desc: "Preallocate with length 0 and capacity n.",
          ex: "xs := make([]int, 0, 10)"
        },
        {
          name: "Sort",
          sig: "slices.Sort(xs)",
          desc: "Sort any ordered slice in place.",
          ex: "slices.Sort(xs)"
        },
        {
          name: "SortFunc",
          sig: "slices.SortFunc(xs, cmp)",
          desc: "Sort with a comparison function.",
          ex: "slices.SortFunc(xs, less)"
        },
        {
          name: "Contains",
          sig: "slices.Contains(xs, v)",
          desc: "Membership test for any comparable element.",
          ex: "if slices.Contains(xs, 2) { }"
        },
        {
          name: "Index",
          sig: "slices.Index(xs, v)",
          desc: "First index of v, or -1 when absent.",
          ex: "i := slices.Index(xs, 2)"
        },
        {
          name: "Clone",
          sig: "slices.Clone(xs)",
          desc: "Copy the elements into a new slice.",
          ex: "ys := slices.Clone(xs)"
        },
        {
          name: "Delete",
          sig: "slices.Delete(xs, i, j)",
          desc: "Remove the half-open range [i:j).",
          ex: "xs = slices.Delete(xs, 1, 2)"
        },
        {
          name: "Copy",
          sig: "copy(dst, src)",
          desc: "Copy into an existing slice; returns how many were copied.",
          ex: "n := copy(dst, src)"
        },
        {
          name: "Reverse",
          sig: "slices.Reverse(xs)",
          desc: "Reverse the elements in place.",
          ex: "slices.Reverse(xs)"
        },
        {
          name: "Compact",
          sig: "slices.Compact(xs)",
          desc: "Drop consecutive duplicates — sort first for all.",
          ex: "xs = slices.Compact(xs)"
        },
        {
          name: "BinSearch",
          sig: "slices.BinarySearch(xs, v)",
          desc: "Find v in a sorted slice; returns index and found.",
          ex: "i, ok := slices.BinarySearch(xs, 2)"
        }
      ]
    },
    {
      f: "dpuk",
      id: "errors",
      name: "Errors",
      ac: "var(--red)",
      intro: "Sentinels, wrapping, inspection and recovery — errors are values, not exceptions.",
      primary: {
        sig: "fmt.Errorf(\"open config: %w\", err)",
        desc: "Add context while keeping the cause inspectable with Is and As.",
        ex: "return fmt.Errorf(\"open config: %w\", err)"
      },
      items: [
        {
          name: "New",
          sig: "errors.New(\"msg\")",
          desc: "Make a simple sentinel error to compare against.",
          ex: "var ErrNotFound = errors.New(\"not found\")"
        },
        {
          name: "Wrap",
          sig: "fmt.Errorf(\"...: %w\", err)",
          desc: "Add context and preserve the original cause.",
          ex: "return fmt.Errorf(\"read: %w\", err)"
        },
        {
          name: "Is",
          sig: "errors.Is(err, target)",
          desc: "Walk the chain looking for a sentinel.",
          ex: "if errors.Is(err, os.ErrNotExist) { }"
        },
        {
          name: "As",
          sig: "errors.As(err, &target)",
          desc: "Walk the chain looking for a concrete type.",
          ex: "var pe *os.PathError; errors.As(err, &pe)"
        },
        {
          name: "Unwrap",
          sig: "errors.Unwrap(err)",
          desc: "Return the direct cause of a wrapped error.",
          ex: "cause := errors.Unwrap(err)"
        },
        {
          name: "Join",
          sig: "errors.Join(e1, e2)",
          desc: "Combine several errors into one chain.",
          ex: "err := errors.Join(e1, e2)"
        },
        {
          name: "Panic",
          sig: "panic(v)",
          desc: "Unwind the stack — reserve for programmer errors.",
          ex: "panic(\"unreachable\")"
        },
        {
          name: "Recover",
          sig: "defer func(){ _ = recover() }()",
          desc: "Regain control after a panic; only works inside a defer.",
          ex: "defer func() { _ = recover() }()"
        },
        {
          name: "Errorf",
          sig: "fmt.Errorf(\"bad id: %d\", id)",
          desc: "Build a fresh error with formatted detail.",
          ex: "return fmt.Errorf(\"id %d invalid\", id)"
        },
        {
          name: "Sentinel",
          sig: "var ErrX = errors.New(\"...\")",
          desc: "A package-level value callers can compare with Is.",
          ex: "var ErrClosed = errors.New(\"closed\")"
        },
        {
          name: "Custom",
          sig: "func (e *E) Error() string",
          desc: "Any type with Error() satisfies the error interface.",
          ex: "func (e *PathErr) Error() string { ... }"
        },
        {
          name: "Multi %w",
          sig: "fmt.Errorf(\"a: %w, b: %w\", e1, e2)",
          desc: "Wrap several causes in one error (Go 1.20+).",
          ex: "err := fmt.Errorf(\"a: %w, b: %w\", e1, e2)"
        }
      ]
    },
    {
      f: "dpuk",
      id: "concurrency",
      name: "Concurrency",
      ac: "var(--purple)",
      intro: "Goroutines, wait groups, locks and select — the whole concurrency toolkit.",
      primary: {
        sig: "go f()",
        desc: "Start f in a goroutine; it runs alongside the caller, not after it.",
        ex: "go work()"
      },
      items: [
        {
          name: "go",
          sig: "go f()",
          desc: "Launch a goroutine; the caller does not wait for it.",
          ex: "go work()"
        },
        {
          name: "WaitGroup",
          sig: "wg.Add(1); wg.Done(); wg.Wait()",
          desc: "Wait for a set of goroutines to finish.",
          ex: "defer wg.Done()"
        },
        {
          name: "Mutex",
          sig: "mu.Lock(); mu.Unlock()",
          desc: "Guard shared state against concurrent access.",
          ex: "mu.Lock(); defer mu.Unlock()"
        },
        {
          name: "Once",
          sig: "once.Do(f)",
          desc: "Run f exactly once, even under a race.",
          ex: "once.Do(initConfig)"
        },
        {
          name: "select",
          sig: "select { case <-ch: ... }",
          desc: "Wait on several channel operations at once.",
          ex: "select { case v := <-ch: use(v) }"
        },
        {
          name: "chan",
          sig: "make(chan T, n)",
          desc: "Communicate by passing values, not by sharing memory.",
          ex: "ch := make(chan int, 1)"
        },
        {
          name: "WithCancel",
          sig: "context.WithCancel(parent)",
          desc: "Signal a whole tree of goroutines to stop.",
          ex: "ctx, cancel := context.WithCancel(ctx)"
        },
        {
          name: "NumCPU",
          sig: "runtime.NumCPU()",
          desc: "How many logical CPUs this machine offers.",
          ex: "workers := runtime.NumCPU()"
        },
        {
          name: "RWMutex",
          sig: "mu.RLock(); mu.RUnlock()",
          desc: "Allow many readers, but only one writer.",
          ex: "mu.RLock(); defer mu.RUnlock()"
        },
        {
          name: "Atomic",
          sig: "atomic.AddInt64(&n, 1)",
          desc: "Lock-free counter from the sync/atomic package.",
          ex: "atomic.AddInt64(&n, 1)"
        },
        {
          name: "sync.Map",
          sig: "var m sync.Map; m.Store(k, v)",
          desc: "A map built for concurrent use.",
          ex: "val, ok := m.Load(k)"
        },
        {
          name: "Semaphore",
          sig: "sem := make(chan struct{}, n)",
          desc: "A buffered channel used as a concurrency limiter.",
          ex: "sem <- struct{}{}; defer func(){ <-sem }()"
        }
      ]
    },
    {
      f: "dpuk",
      id: "maps",
      name: "Maps",
      ac: "var(--blue)",
      intro: "Lookups, presence checks, iteration and the maps helpers — all the hash-map idioms.",
      primary: {
        sig: "v, ok := m[k]",
        desc: "Distinguish a zero value from a missing key — the comma-ok idiom.",
        ex: "if v, ok := m[\"go\"]; ok { }"
      },
      items: [
        {
          name: "Literal",
          sig: "map[string]int{\"go\": 1}",
          desc: "Build a map from key/value pairs.",
          ex: "m := map[string]int{\"go\": 1}"
        },
        {
          name: "Insert",
          sig: "m[k] = v",
          desc: "Set a key, overwriting any previous value.",
          ex: "m[\"rust\"] = 2"
        },
        {
          name: "Lookup",
          sig: "v, ok := m[k]",
          desc: "Read a value and check the key exists.",
          ex: "v, ok := m[\"go\"]"
        },
        {
          name: "Delete",
          sig: "delete(m, k)",
          desc: "Remove a key — a no-op when it is absent.",
          ex: "delete(m, \"go\")"
        },
        {
          name: "Len",
          sig: "len(m)",
          desc: "Count the entries currently in the map.",
          ex: "n := len(m)"
        },
        {
          name: "Range",
          sig: "for k, v := range m",
          desc: "Iterate over pairs — order is unspecified.",
          ex: "for k, v := range m { }"
        },
        {
          name: "Clone",
          sig: "maps.Clone(m)",
          desc: "Shallow-copy a map into a new one.",
          ex: "cp := maps.Clone(m)"
        },
        {
          name: "Equal",
          sig: "maps.Equal(a, b)",
          desc: "Compare two maps by keys and values.",
          ex: "if maps.Equal(a, b) { }"
        },
        {
          name: "Keys",
          sig: "maps.Keys(m)",
          desc: "An iterator over the keys (Go 1.23+).",
          ex: "for k := range maps.Keys(m) { }"
        },
        {
          name: "Copy",
          sig: "maps.Copy(dst, src)",
          desc: "Copy all entries into another map.",
          ex: "maps.Copy(dst, src)"
        },
        {
          name: "DeleteFunc",
          sig: "maps.DeleteFunc(m, f)",
          desc: "Remove every entry matching a predicate.",
          ex: "maps.DeleteFunc(m, isZero)"
        },
        {
          name: "Nested",
          sig: "if in, ok := outer[k]; ok",
          desc: "Guard a chained lookup before indexing deeper.",
          ex: "if v, ok := m[k1][k2]; ok { }"
        }
      ]
    },
    {
      f: "dpuk",
      id: "context",
      name: "Context",
      ac: "var(--green)",
      intro: "Deadlines, cancellation and request-scoped values — pass it down, never store it.",
      primary: {
        sig: "context.WithTimeout(ctx, 2*time.Second)",
        desc: "Bound work by time; always call the returned cancel to free resources.",
        ex: "ctx, cancel := context.WithTimeout(ctx, 2*time.Second)"
      },
      items: [
        {
          name: "Background",
          sig: "context.Background()",
          desc: "The root context for main, tests and top-level calls.",
          ex: "ctx := context.Background()"
        },
        {
          name: "TODO",
          sig: "context.TODO()",
          desc: "A placeholder when it is not yet clear which context to use.",
          ex: "ctx := context.TODO()"
        },
        {
          name: "WithCancel",
          sig: "context.WithCancel(parent)",
          desc: "Manual cancellation of a context tree.",
          ex: "ctx, cancel := context.WithCancel(ctx)"
        },
        {
          name: "WithTimeout",
          sig: "context.WithTimeout(parent, d)",
          desc: "A deadline after a duration from now.",
          ex: "ctx, cancel := context.WithTimeout(ctx, time.Second)"
        },
        {
          name: "WithDeadline",
          sig: "context.WithDeadline(parent, t)",
          desc: "A deadline at a specific instant.",
          ex: "ctx, cancel := context.WithDeadline(ctx, t)"
        },
        {
          name: "WithValue",
          sig: "context.WithValue(parent, k, v)",
          desc: "Attach request-scoped data for downstream code.",
          ex: "ctx = context.WithValue(ctx, key, val)"
        },
        {
          name: "Done",
          sig: "<-ctx.Done()",
          desc: "A channel closed when the context is cancelled.",
          ex: "select { case <-ctx.Done(): return }"
        },
        {
          name: "Err",
          sig: "ctx.Err()",
          desc: "Why the context was cancelled, if it was.",
          ex: "if errors.Is(ctx.Err(), context.DeadlineExceeded) { }"
        },
        {
          name: "Cause",
          sig: "context.Cause(ctx)",
          desc: "The error behind the cancellation (Go 1.20+).",
          ex: "err := context.Cause(ctx)"
        },
        {
          name: "WithoutCancel",
          sig: "context.WithoutCancel(ctx)",
          desc: "Detach cancellation but keep the values.",
          ex: "ctx = context.WithoutCancel(ctx)"
        },
        {
          name: "AfterFunc",
          sig: "context.AfterFunc(ctx, f)",
          desc: "Run f in a goroutine when ctx is cancelled.",
          ex: "stop := context.AfterFunc(ctx, cleanup)"
        },
        {
          name: "CancelCause",
          sig: "context.WithCancelCause(parent)",
          desc: "Cancel with a reason retrievable via Cause.",
          ex: "ctx, cancel := context.WithCancelCause(ctx)"
        }
      ]
    },
    {
      f: "dpuk",
      id: "json",
      name: "JSON",
      ac: "var(--yellow)",
      intro: "Marshal, unmarshal, stream and tag — everything encoding/json does, at a glance.",
      primary: {
        sig: "json.Marshal(v)",
        desc: "Encode any value into JSON bytes; returns ([]byte, error).",
        ex: "b, err := json.Marshal(user)"
      },
      items: [
        {
          name: "Marshal",
          sig: "json.Marshal(v)",
          desc: "Encode a value into a []byte.",
          ex: "b, err := json.Marshal(user)"
        },
        {
          name: "Indent",
          sig: "json.MarshalIndent(v, \"\", \"  \")",
          desc: "Human-readable output with indentation.",
          ex: "b, err := json.MarshalIndent(user, \"\", \"  \")"
        },
        {
          name: "Unmarshal",
          sig: "json.Unmarshal(b, &v)",
          desc: "Decode bytes into a value — always pass a pointer.",
          ex: "err := json.Unmarshal(b, &user)"
        },
        {
          name: "Encoder",
          sig: "json.NewEncoder(w).Encode(v)",
          desc: "Stream an encoding to any io.Writer.",
          ex: "json.NewEncoder(os.Stdout).Encode(user)"
        },
        {
          name: "Decoder",
          sig: "json.NewDecoder(r).Decode(&v)",
          desc: "Stream a decoding from any io.Reader.",
          ex: "json.NewDecoder(resp.Body).Decode(&user)"
        },
        {
          name: "Tags",
          sig: "`json:\"name,omitempty\"`",
          desc: "Rename a field and drop it when it is empty.",
          ex: "Name string `json:\"name,omitempty\"`"
        },
        {
          name: "RawMessage",
          sig: "json.RawMessage",
          desc: "Hold a fragment of JSON to decode later.",
          ex: "var raw json.RawMessage"
        },
        {
          name: "Valid",
          sig: "json.Valid(b)",
          desc: "Check syntax without decoding the value.",
          ex: "if !json.Valid(b) { }"
        },
        {
          name: "Skip field",
          sig: "`json:\"-\"`",
          desc: "Leave a field out of the encoding entirely.",
          ex: "Secret string `json:\"-\"`"
        },
        {
          name: "Number",
          sig: "json.Number",
          desc: "Keep numbers as strings to avoid float rounding.",
          ex: "dec.UseNumber()"
        },
        {
          name: "Strict",
          sig: "dec.DisallowUnknownFields()",
          desc: "Reject keys that have no matching struct field.",
          ex: "dec.DisallowUnknownFields()"
        },
        {
          name: "No escape",
          sig: "enc.SetEscapeHTML(false)",
          desc: "Do not escape <, > and & inside strings.",
          ex: "enc.SetEscapeHTML(false)"
        }
      ]
    },
    {
      f: "dpuk",
      id: "formatting",
      name: "Formatting",
      ac: "var(--aqua)",
      intro: "Verbs, widths and writers — fmt covers printing and formatting in one package.",
      primary: {
        sig: "fmt.Printf(\"%+v\", x)",
        desc: "Print a value with its field names — the debugging default.",
        ex: "fmt.Printf(\"%+v\\n\", user)"
      },
      items: [
        {
          name: "Printf",
          sig: "fmt.Printf(format, args)",
          desc: "Formatted output to standard output.",
          ex: "fmt.Printf(\"n=%d\\n\", n)"
        },
        {
          name: "Sprintf",
          sig: "fmt.Sprintf(format, args)",
          desc: "The same formatting, returned as a string.",
          ex: "s := fmt.Sprintf(\"%d\", n)"
        },
        {
          name: "Fprintf",
          sig: "fmt.Fprintf(w, format, args)",
          desc: "Write formatted text to any io.Writer.",
          ex: "fmt.Fprintf(os.Stderr, \"err: %v\", err)"
        },
        {
          name: "Println",
          sig: "fmt.Println(a, b)",
          desc: "Print values separated by spaces, then a newline.",
          ex: "fmt.Println(\"id:\", id)"
        },
        {
          name: "%v family",
          sig: "%v, %+v, %#v",
          desc: "Value, with field names, in Go syntax.",
          ex: "fmt.Printf(\"%+v\\n\", u)"
        },
        {
          name: "Scalars",
          sig: "%q, %d, %t",
          desc: "Quoted string, decimal integer, boolean.",
          ex: "fmt.Printf(\"%q %d\", s, n)"
        },
        {
          name: "Floats",
          sig: "%f, %.2f",
          desc: "Floating point, with a fixed number of decimals.",
          ex: "fmt.Printf(\"%.2f\", 3.14159)"
        },
        {
          name: "%T",
          sig: "%T",
          desc: "Print the dynamic type of a value.",
          ex: "fmt.Printf(\"%T\\n\", v)"
        },
        {
          name: "Print",
          sig: "fmt.Print(a, b)",
          desc: "Like Println, but without the trailing newline.",
          ex: "fmt.Print(\"id=\", id)"
        },
        {
          name: "Sprint",
          sig: "fmt.Sprint(a, b)",
          desc: "Like Print, returned as a string.",
          ex: "s := fmt.Sprint(\"id=\", id)"
        },
        {
          name: "Width",
          sig: "%5d, %-5s, %05d",
          desc: "Width, left-align and zero-padding.",
          ex: "fmt.Printf(\"%05d\", 42)"
        },
        {
          name: "Scan",
          sig: "fmt.Scan(&x)",
          desc: "Read formatted input into a variable.",
          ex: "fmt.Scan(&name)"
        }
      ]
    },
    {
      f: "dpuk",
      id: "channels",
      name: "Channels",
      ac: "var(--purple)",
      intro: "Send, receive, close and select — channels are the pipes of Go concurrency.",
      primary: {
        sig: "ch := make(chan int, 10)",
        desc: "A buffered channel: senders block only once the buffer is full.",
        ex: "ch := make(chan int, 10)"
      },
      items: [
        {
          name: "Make",
          sig: "make(chan T)",
          desc: "Unbuffered: send and receive rendezvous.",
          ex: "ch := make(chan int)"
        },
        {
          name: "Buffered",
          sig: "make(chan T, n)",
          desc: "Buffer up to n values before a sender blocks.",
          ex: "ch := make(chan int, 10)"
        },
        {
          name: "Send",
          sig: "ch <- v",
          desc: "Send a value; blocks when the channel is full.",
          ex: "ch <- result"
        },
        {
          name: "Receive",
          sig: "v := <-ch",
          desc: "Receive a value; blocks when the channel is empty.",
          ex: "v := <-ch"
        },
        {
          name: "Receive ok",
          sig: "v, ok := <-ch",
          desc: "ok is false once the channel is closed and drained.",
          ex: "v, ok := <-ch"
        },
        {
          name: "Close",
          sig: "close(ch)",
          desc: "Signal that no more values will be sent.",
          ex: "close(ch)"
        },
        {
          name: "Range",
          sig: "for v := range ch",
          desc: "Drain values until the channel is closed.",
          ex: "for v := range ch { use(v) }"
        },
        {
          name: "Directional",
          sig: "<-chan T / chan<- T",
          desc: "Restrict a parameter to receive-only or send-only.",
          ex: "func drain(ch <-chan int)"
        },
        {
          name: "Default",
          sig: "select { default: ... }",
          desc: "Make a select non-blocking when nothing is ready.",
          ex: "select { case ch <- v: default: }"
        },
        {
          name: "Nil chan",
          sig: "var ch chan T",
          desc: "A nil channel blocks forever — useful to disable a case.",
          ex: "var ch chan int // disabled"
        },
        {
          name: "Done signal",
          sig: "done := make(chan struct{})",
          desc: "Closing it broadcasts to every receiver at once.",
          ex: "close(done)"
        },
        {
          name: "Pipeline",
          sig: "for v := range in { out <- f(v) }",
          desc: "Turn one channel into another in a stage.",
          ex: "go func(){ for v := range in { out <- f(v) } }()"
        }
      ]
    },
    {
      f: "dpuk",
      id: "files",
      name: "Files",
      ac: "var(--blue)",
      intro: "Read, write, open and join — os and filepath for everyday file work.",
      primary: {
        sig: "os.ReadFile(name)",
        desc: "Read a whole file into memory; the descriptor is closed for you.",
        ex: "b, err := os.ReadFile(\"go.mod\")"
      },
      items: [
        {
          name: "ReadFile",
          sig: "os.ReadFile(name)",
          desc: "Read an entire file into a []byte.",
          ex: "b, err := os.ReadFile(\"go.mod\")"
        },
        {
          name: "WriteFile",
          sig: "os.WriteFile(name, b, 0644)",
          desc: "Write bytes, creating or truncating the file.",
          ex: "os.WriteFile(\"out.txt\", b, 0644)"
        },
        {
          name: "Open",
          sig: "os.Open(name)",
          desc: "Open a read-only handle — close it yourself.",
          ex: "f, err := os.Open(\"go.mod\"); defer f.Close()"
        },
        {
          name: "Create",
          sig: "os.Create(name)",
          desc: "Create or truncate a file for writing.",
          ex: "f, err := os.Create(\"out.txt\")"
        },
        {
          name: "Stat",
          sig: "os.Stat(name)",
          desc: "Get FileInfo: size, mode and modification time.",
          ex: "info, err := os.Stat(\"go.mod\")"
        },
        {
          name: "MkdirAll",
          sig: "os.MkdirAll(path, 0755)",
          desc: "Create a directory tree, including parents.",
          ex: "os.MkdirAll(\"data/tmp\", 0755)"
        },
        {
          name: "Remove",
          sig: "os.Remove(name)",
          desc: "Delete a file or an empty directory.",
          ex: "os.Remove(\"out.txt\")"
        },
        {
          name: "Join",
          sig: "filepath.Join(a, b)",
          desc: "Build a path with the OS's separator.",
          ex: "p := filepath.Join(dir, \"go.mod\")"
        },
        {
          name: "ReadDir",
          sig: "os.ReadDir(name)",
          desc: "List the entries of a directory, sorted by name.",
          ex: "entries, err := os.ReadDir(\".\")"
        },
        {
          name: "CreateTemp",
          sig: "os.CreateTemp(dir, pattern)",
          desc: "Create a uniquely named temporary file.",
          ex: "f, err := os.CreateTemp(\"\", \"leader-*\")"
        },
        {
          name: "Rename",
          sig: "os.Rename(old, new)",
          desc: "Move or rename a path.",
          ex: "os.Rename(\"a.txt\", \"b.txt\")"
        },
        {
          name: "WalkDir",
          sig: "filepath.WalkDir(root, fn)",
          desc: "Visit every file and folder under a root.",
          ex: "filepath.WalkDir(root, visit)"
        }
      ]
    },
    {
      f: "dpuk",
      id: "defer",
      name: "Defer",
      ac: "var(--green)",
      intro: "Cleanup that runs on the way out — LIFO order, arguments now, execution later.",
      primary: {
        sig: "defer f.Close()",
        desc: "Close a resource when the function returns, however it returns.",
        ex: "defer f.Close()"
      },
      items: [
        {
          name: "Basic",
          sig: "defer f()",
          desc: "Run f when the surrounding function returns.",
          ex: "defer log.Println(\"done\")"
        },
        {
          name: "Close",
          sig: "defer f.Close()",
          desc: "The canonical resource-cleanup pattern.",
          ex: "defer rows.Close()"
        },
        {
          name: "Unlock",
          sig: "defer mu.Unlock()",
          desc: "Release a lock on every exit path.",
          ex: "defer mu.Unlock()"
        },
        {
          name: "Done",
          sig: "defer wg.Done()",
          desc: "Balance an Add(1) in a single line.",
          ex: "defer wg.Done()"
        },
        {
          name: "Recover",
          sig: "defer func(){ _ = recover() }()",
          desc: "Regain control after a panic, inside a defer.",
          ex: "defer func() { _ = recover() }()"
        },
        {
          name: "Args now",
          sig: "defer f(x)",
          desc: "Arguments are evaluated at the defer, not at the call.",
          ex: "defer cleanup(path)"
        },
        {
          name: "Closure",
          sig: "defer func(){ ... }()",
          desc: "A closure reads variables at execution time.",
          ex: "defer func(){ log.Println(err) }()"
        },
        {
          name: "LIFO",
          sig: "defer a(); defer b()",
          desc: "Last deferred runs first: b, then a.",
          ex: "defer a(); defer b()"
        },
        {
          name: "Timing",
          sig: "defer func(){ log.Println(time.Since(t)) }()",
          desc: "Measure a whole function in one line.",
          ex: "defer func(){ log.Println(time.Since(t)) }()"
        },
        {
          name: "Flush",
          sig: "defer w.Flush()",
          desc: "Flush a buffered writer on the way out.",
          ex: "defer bufioWriter.Flush()"
        },
        {
          name: "In a loop",
          sig: "for ... { defer f.Close() }",
          desc: "Careful: they pile up until the function returns.",
          ex: "for _, f := range fs { defer f.Close() }"
        },
        {
          name: "Named return",
          sig: "defer func(){ err = wrap(err) }()",
          desc: "With a named result, a defer can change it.",
          ex: "defer func(){ err = wrap(err) }()"
        }
      ]
    },
    {
      "id": "python",
      "name": "Python",
      "lang": "python",
      "ac": "var(--yellow)",
      "f": "dpuk",
      "intro": "Twelve corners of the language, one line of code each — the whole sheet at a glance.",
      "primary": {
        "sig": "print(\"Hello, Leader\")",
        "desc": "Start here: the smallest Python program prints something and moves on.",
        "ex": "print(\"Hello, Leader\")"
      },
      "items": [
        {
          "name": "Syntax",
          "sig": "def greet(name: str) -> str:",
          "desc": "Indentation defines the block; four spaces, no braces.",
          "ex": "return f\"Hello, {name}\""
        },
        {
          "name": "Types",
          "sig": "x: int = 42",
          "desc": "Annotations document the value and let basedpyright check it.",
          "ex": "name: str = \"Leader\""
        },
        {
          "name": "Strings",
          "sig": "f\"{name=}\"",
          "desc": "An f-string interpolates; the = suffix prints the expression too.",
          "ex": "f\"{name=}\""
        },
        {
          "name": "Lists",
          "sig": "[x * 2 for x in xs]",
          "desc": "A comprehension builds a list in one readable line.",
          "ex": "[x * 2 for x in range(3)]"
        },
        {
          "name": "Dicts",
          "sig": "d.get(key, default)",
          "desc": "Read a key without raising KeyError when it is absent.",
          "ex": "d.get(\"missing\", 0)"
        },
        {
          "name": "Sets",
          "sig": "{1, 2} | {2, 3}",
          "desc": "Set union removes duplicates; membership is O(1).",
          "ex": "{1, 2} | {2, 3}"
        },
        {
          "name": "Loops",
          "sig": "for i, x in enumerate(xs):",
          "desc": "Index and value together, no manual counter.",
          "ex": "for i, x in enumerate(xs):"
        },
        {
          "name": "Functions",
          "sig": "def f(x: int = 0) -> int:",
          "desc": "Default values, annotations and a return type in one line.",
          "ex": "def f(x: int = 0) -> int: return x"
        },
        {
          "name": "Classes",
          "sig": "@dataclass",
          "desc": "Generates __init__, __repr__ and equality from the fields.",
          "ex": "@dataclass\nclass User:\n    name: str"
        },
        {
          "name": "Errors",
          "sig": "except ValueError as e:",
          "desc": "Catch the specific error; keep the traceback with raise.",
          "ex": "except ValueError as e:"
        },
        {
          "name": "Files",
          "sig": "Path(\"data.txt\").read_text()",
          "desc": "Read a whole file with pathlib, no manual close.",
          "ex": "Path(\"data.txt\").read_text()"
        },
        {
          "name": "Modules",
          "sig": "if __name__ == \"__main__\":",
          "desc": "Run main only when the file is executed, not when imported.",
          "ex": "if __name__ == \"__main__\":\n    main()"
        }
      ]
    },
    {
      "id": "python-data",
      "name": "Data",
      "lang": "python",
      "ac": "var(--aqua)",
      "f": "dpuk",
      "intro": "The pandas moves you use every day: read, filter, group, join and write the result back.",
      "primary": {
        "sig": "df.groupby(\"city\")[\"sales\"].sum()",
        "desc": "Split, aggregate and combine — the core pandas move.",
        "ex": "df.groupby(\"city\")[\"sales\"].sum()"
      },
      "items": [
        {
          "name": "Read",
          "sig": "pd.read_csv(\"data.csv\")",
          "desc": "Read a CSV into a DataFrame; dtype and parse_dates are your friends.",
          "ex": "pd.read_csv(\"data.csv\")"
        },
        {
          "name": "Select",
          "sig": "df[[\"city\", \"sales\"]]",
          "desc": "Select columns; double brackets keep a DataFrame.",
          "ex": "df[[\"city\", \"sales\"]]"
        },
        {
          "name": "Filter",
          "sig": "df[df.sales > 100]",
          "desc": "Boolean mask: keep the rows where the condition is true.",
          "ex": "df[df.sales > 100]"
        },
        {
          "name": "Assign",
          "sig": "df.assign(total=df.qty * df.price)",
          "desc": "Add or replace columns without mutating the original.",
          "ex": "df.assign(total=df.qty * df.price)"
        },
        {
          "name": "Sort",
          "sig": "df.sort_values(\"sales\", ascending=False)",
          "desc": "Order rows by one or more columns.",
          "ex": "df.sort_values(\"sales\", ascending=False)"
        },
        {
          "name": "Group",
          "sig": "df.groupby(\"city\")[\"sales\"].sum()",
          "desc": "Split by key, aggregate and combine the result.",
          "ex": "df.groupby(\"city\")[\"sales\"].sum()"
        },
        {
          "name": "Agg",
          "sig": "df.groupby(\"city\").agg(mean=\"sales\")",
          "desc": "Named aggregation: one column per output, named by you.",
          "ex": "df.groupby(\"city\").agg(mean=(\"sales\", \"mean\"))"
        },
        {
          "name": "Merge",
          "sig": "df.merge(other, on=\"id\", how=\"left\")",
          "desc": "Join two DataFrames; left keeps every row of df.",
          "ex": "df.merge(other, on=\"id\", how=\"left\")"
        },
        {
          "name": "Pivot",
          "sig": "df.pivot_table(index=\"city\", values=\"sales\")",
          "desc": "Rows to columns with an aggregation; the spreadsheet pivot.",
          "ex": "df.pivot_table(index=\"city\", values=\"sales\", aggfunc=\"sum\")"
        },
        {
          "name": "Dates",
          "sig": "pd.to_datetime(df[\"date\"])",
          "desc": "Parse strings into datetime64 so resampling and .dt work.",
          "ex": "pd.to_datetime(df[\"date\"])"
        },
        {
          "name": "Parquet",
          "sig": "df.to_parquet(\"data.parquet\")",
          "desc": "Typed, compressed and faster than CSV; needs pyarrow.",
          "ex": "df.to_parquet(\"data.parquet\")"
        },
        {
          "name": "Plot",
          "sig": "df.plot.bar(x=\"city\", y=\"sales\")",
          "desc": "Quick plot from a DataFrame; returns a matplotlib Axes.",
          "ex": "df.plot.bar(x=\"city\", y=\"sales\")"
        }
      ]
    },
    {
      "id": "python-numpy",
      "name": "NumPy",
      "lang": "python",
      "ac": "var(--blue)",
      "f": "dpuk",
      "intro": "Arrays, shapes and vectorized math — the layer pandas and scikit-learn are built on.",
      "primary": {
        "sig": "arr = np.array([1, 2, 3])",
        "desc": "The ndarray: one dtype, contiguous memory, vectorized math.",
        "ex": "arr = np.array([1, 2, 3])"
      },
      "items": [
        {
          "name": "Array",
          "sig": "np.array([1, 2, 3])",
          "desc": "Build an ndarray from any sequence.",
          "ex": "np.array([1, 2, 3])"
        },
        {
          "name": "Arange",
          "sig": "np.arange(0, 10, 2)",
          "desc": "Evenly spaced values in a half-open range.",
          "ex": "np.arange(0, 10, 2)"
        },
        {
          "name": "Linspace",
          "sig": "np.linspace(0, 1, 5)",
          "desc": "A fixed number of points, endpoints included.",
          "ex": "np.linspace(0, 1, 5)"
        },
        {
          "name": "Reshape",
          "sig": "arr.reshape(2, 3)",
          "desc": "Change the shape without copying when the layout allows it.",
          "ex": "arr.reshape(2, 3)"
        },
        {
          "name": "Slicing",
          "sig": "arr[1:4]",
          "desc": "Views, not copies: slice assignment changes the original.",
          "ex": "arr[1:4]"
        },
        {
          "name": "Mask",
          "sig": "arr[arr > 0]",
          "desc": "Boolean indexing keeps the values where the mask is true.",
          "ex": "arr[arr > 0]"
        },
        {
          "name": "Where",
          "sig": "np.where(cond, a, b)",
          "desc": "Vectorized if/else: choose element by element.",
          "ex": "np.where(arr > 0, arr, 0)"
        },
        {
          "name": "Concat",
          "sig": "np.concatenate([a, b])",
          "desc": "Join arrays along an existing axis; np.stack adds one.",
          "ex": "np.concatenate([a, b])"
        },
        {
          "name": "Broadcast",
          "sig": "a[:, None] + b[None, :]",
          "desc": "Shapes align from the right; add axes to broadcast.",
          "ex": "a[:, None] + b[None, :]"
        },
        {
          "name": "Stats",
          "sig": "arr.mean(axis=0)",
          "desc": "Reduce along an axis; axis=0 goes down the rows.",
          "ex": "arr.mean(axis=0)"
        },
        {
          "name": "RNG",
          "sig": "rng = np.random.default_rng(42)",
          "desc": "The modern generator: reproducible, no global state.",
          "ex": "rng.normal(size=100)"
        },
        {
          "name": "Save",
          "sig": "np.savez(\"data.npz\", arr=arr)",
          "desc": "Store several arrays in one compressed file.",
          "ex": "np.savez(\"data.npz\", arr=arr)"
        }
      ]
    },
    {
      "id": "python-plotting",
      "name": "Plotting",
      "lang": "python",
      "ac": "var(--purple)",
      "f": "dpuk",
      "intro": "The object-oriented matplotlib API, plus the seaborn shortcut for DataFrames.",
      "primary": {
        "sig": "fig, ax = plt.subplots()",
        "desc": "The object-oriented API: draw on ax, then save fig.",
        "ex": "fig, ax = plt.subplots()"
      },
      "items": [
        {
          "name": "Subplots",
          "sig": "fig, ax = plt.subplots(figsize=(8, 4))",
          "desc": "One figure and one Axes; the basis of every plot.",
          "ex": "fig, ax = plt.subplots()"
        },
        {
          "name": "Plot",
          "sig": "ax.plot(x, y, marker=\"o\")",
          "desc": "Line plot; markers make individual points visible.",
          "ex": "ax.plot(x, y, marker=\"o\")"
        },
        {
          "name": "Scatter",
          "sig": "ax.scatter(x, y, c=colors)",
          "desc": "Two numeric variables, one point per observation.",
          "ex": "ax.scatter(x, y)"
        },
        {
          "name": "Bar",
          "sig": "ax.bar(labels, values)",
          "desc": "Compare categories; horizontal is ax.barh.",
          "ex": "ax.bar(labels, values)"
        },
        {
          "name": "Hist",
          "sig": "ax.hist(values, bins=30)",
          "desc": "The distribution of one numeric variable.",
          "ex": "ax.hist(values, bins=30)"
        },
        {
          "name": "Labels",
          "sig": "ax.set(xlabel=\"x\", ylabel=\"y\", title=\"Plot\")",
          "desc": "Label the axes and title in one call.",
          "ex": "ax.set(xlabel=\"x\", title=\"Plot\")"
        },
        {
          "name": "Legend",
          "sig": "ax.legend(loc=\"best\")",
          "desc": "Show the label of each plotted series.",
          "ex": "ax.legend()"
        },
        {
          "name": "Limits",
          "sig": "ax.set_xlim(0, 10)",
          "desc": "Zoom or pad an axis; set_ylim for the other.",
          "ex": "ax.set_xlim(0, 10)"
        },
        {
          "name": "Layout",
          "sig": "fig.tight_layout()",
          "desc": "Stop labels from colliding before you save.",
          "ex": "fig.tight_layout()"
        },
        {
          "name": "Save",
          "sig": "fig.savefig(\"plot.png\", dpi=150)",
          "desc": "Write PNG, PDF or SVG; dpi matters for raster.",
          "ex": "fig.savefig(\"plot.png\", dpi=150)"
        },
        {
          "name": "Style",
          "sig": "plt.style.use(\"ggplot\")",
          "desc": "A quick global look; seaborn has its own themes.",
          "ex": "plt.style.use(\"ggplot\")"
        },
        {
          "name": "Seaborn",
          "sig": "sns.scatterplot(data=df, x=\"x\", y=\"y\")",
          "desc": "DataFrame-aware plotting with sensible defaults.",
          "ex": "sns.scatterplot(data=df, x=\"x\", y=\"y\")"
        }
      ]
    },
    {
      "id": "python-jupyter",
      "name": "Jupyter",
      "lang": "python",
      "ac": "var(--green)",
      "f": "dpuk",
      "intro": "Lab, kernels, magics and the shortcuts that turn a notebook into a workbench.",
      "primary": {
        "sig": "uv run jupyter lab",
        "desc": "Launch JupyterLab inside the project's uv environment.",
        "ex": "uv run jupyter lab"
      },
      "items": [
        {
          "name": "Launch",
          "sig": "uv run jupyter lab",
          "desc": "Run it from the project root so the kernel sees .venv.",
          "ex": "uv run jupyter lab"
        },
        {
          "name": "Kernel",
          "sig": "Python 3.14 (pydata-book)",
          "desc": "Select the project kernel; it carries pandas and NumPy.",
          "ex": "Kernel → Change kernel"
        },
        {
          "name": "Run",
          "sig": "%run script.py",
          "desc": "Execute a Python file in the notebook namespace.",
          "ex": "%run script.py"
        },
        {
          "name": "Time",
          "sig": "%timeit sum(range(1000))",
          "desc": "Measure a statement; %%timeit measures a whole cell.",
          "ex": "%timeit sum(range(1000))"
        },
        {
          "name": "Shell",
          "sig": "!uv add seaborn",
          "desc": "Run a shell command; prefix with ! in a cell.",
          "ex": "!uv add seaborn"
        },
        {
          "name": "Help",
          "sig": "pd.DataFrame?",
          "desc": "Show the docstring; ?? shows the source when available.",
          "ex": "pd.DataFrame?"
        },
        {
          "name": "Plots",
          "sig": "%matplotlib inline",
          "desc": "Render matplotlib figures inside the notebook.",
          "ex": "%matplotlib inline"
        },
        {
          "name": "Display",
          "sig": "display(df.head())",
          "desc": "Render a rich object; the last expression also displays.",
          "ex": "display(df.head())"
        },
        {
          "name": "Export",
          "sig": "jupyter nbconvert --to html nb.ipynb",
          "desc": "Run and export a notebook to HTML or PDF.",
          "ex": "jupyter nbconvert --to html nb.ipynb"
        },
        {
          "name": "Widgets",
          "sig": "interact(f, x=(0, 10))",
          "desc": "Sliders and controls for interactive exploration.",
          "ex": "interact(f, x=(0, 10))"
        },
        {
          "name": "Restart",
          "sig": "Kernel → Restart & Run All",
          "desc": "A clean state: imports, variables and outputs rebuilt.",
          "ex": "Restart & Run All"
        },
        {
          "name": "Install",
          "sig": "uv add jupyterlab ipykernel",
          "desc": "Notebook tooling belongs to the project, not the global Python.",
          "ex": "uv add jupyterlab ipykernel"
        }
      ]
    },
    {
      "id": "python-types",
      "name": "Types",
      "lang": "python",
      "ac": "var(--red)",
      "f": "dpuk",
      "intro": "Annotations that pay for themselves: basedpyright turns them into navigation and errors.",
      "primary": {
        "sig": "def greet(name: str) -> str:",
        "desc": "Annotate the input and the output; basedpyright checks both.",
        "ex": "def greet(name: str) -> str:"
      },
      "items": [
        {
          "name": "Annotate",
          "sig": "x: int = 42",
          "desc": "A variable annotation documents intent and catches mistakes.",
          "ex": "x: int = 42"
        },
        {
          "name": "Optional",
          "sig": "str | None",
          "desc": "The value may be missing; narrow it with an if before use.",
          "ex": "name: str | None = None"
        },
        {
          "name": "Containers",
          "sig": "list[str]",
          "desc": "Built-in generics: list, dict, tuple and set.",
          "ex": "names: list[str] = []"
        },
        {
          "name": "Dict",
          "sig": "dict[str, int]",
          "desc": "Key and value types; use TypedDict for fixed keys.",
          "ex": "counts: dict[str, int] = {}"
        },
        {
          "name": "TypedDict",
          "sig": "class User(TypedDict):",
          "desc": "A dictionary with a fixed set of typed keys.",
          "ex": "class User(TypedDict):\n    name: str"
        },
        {
          "name": "Protocol",
          "sig": "class Closeable(Protocol):",
          "desc": "Structural typing: any object with the method fits.",
          "ex": "class Closeable(Protocol):\n    def close(self) -> None: ..."
        },
        {
          "name": "Dataclass",
          "sig": "@dataclass",
          "desc": "Fields become the constructor, repr and equality.",
          "ex": "@dataclass\nclass User:\n    name: str"
        },
        {
          "name": "Literal",
          "sig": "Literal[\"r\", \"w\"]",
          "desc": "Only these exact values are allowed.",
          "ex": "mode: Literal[\"r\", \"w\"] = \"r\""
        },
        {
          "name": "TypeVar",
          "sig": "T = TypeVar(\"T\")",
          "desc": "A generic function that preserves the input type.",
          "ex": "def first(xs: list[T]) -> T:"
        },
        {
          "name": "Cast",
          "sig": "cast(int, value)",
          "desc": "Tell the checker what you know; no runtime conversion.",
          "ex": "n = cast(int, value)"
        },
        {
          "name": "Reveal",
          "sig": "reveal_type(value)",
          "desc": "Ask basedpyright what type it inferred.",
          "ex": "reveal_type(df)"
        },
        {
          "name": "Check",
          "sig": "basedpyright .",
          "desc": "The same analyzer as the LSP, over the whole project.",
          "ex": "basedpyright ."
        }
      ]
    },
    {
      "id": "python-files",
      "name": "Files",
      "lang": "python",
      "ac": "var(--yellow)",
      "f": "dpuk",
      "intro": "pathlib for paths, csv/json for the formats, parquet when the data gets big.",
      "primary": {
        "sig": "Path(\"data.csv\").read_text()",
        "desc": "pathlib: one object for paths, reading and writing.",
        "ex": "Path(\"data.csv\").read_text()"
      },
      "items": [
        {
          "name": "Path",
          "sig": "Path(\"data\") / \"file.csv\"",
          "desc": "Join paths with /; no string concatenation.",
          "ex": "Path(\"data\") / \"file.csv\""
        },
        {
          "name": "Read",
          "sig": "Path(\"data.csv\").read_text()",
          "desc": "Read text with UTF-8 by default; pass encoding explicitly.",
          "ex": "Path(\"data.csv\").read_text(encoding=\"utf-8\")"
        },
        {
          "name": "Write",
          "sig": "Path(\"out.txt\").write_text(text)",
          "desc": "Create or truncate the file in one call.",
          "ex": "Path(\"out.txt\").write_text(text)"
        },
        {
          "name": "Bytes",
          "sig": "Path(\"img.png\").read_bytes()",
          "desc": "Binary data as bytes; write_bytes for the reverse.",
          "ex": "Path(\"img.png\").read_bytes()"
        },
        {
          "name": "Glob",
          "sig": "list(Path(\"data\").glob(\"*.csv\"))",
          "desc": "Iterate matching paths; rglob searches recursively.",
          "ex": "list(Path(\"data\").glob(\"*.csv\"))"
        },
        {
          "name": "Exists",
          "sig": "Path(\"data.csv\").exists()",
          "desc": "Check before opening; is_file and is_dir narrow further.",
          "ex": "if path.exists():"
        },
        {
          "name": "Mkdir",
          "sig": "Path(\"out\").mkdir(parents=True)",
          "desc": "Create a directory tree; exist_ok avoids races.",
          "ex": "Path(\"out\").mkdir(parents=True, exist_ok=True)"
        },
        {
          "name": "Iterdir",
          "sig": "for p in Path(\".\").iterdir():",
          "desc": "List the entries of a directory, one Path at a time.",
          "ex": "for p in Path(\".\").iterdir():"
        },
        {
          "name": "CSV",
          "sig": "csv.DictReader(f)",
          "desc": "Rows as dictionaries keyed by the header.",
          "ex": "for row in csv.DictReader(f):"
        },
        {
          "name": "JSON",
          "sig": "json.loads(text)",
          "desc": "Parse JSON into Python objects; json.dump writes it.",
          "ex": "data = json.loads(text)"
        },
        {
          "name": "Parquet",
          "sig": "pd.read_parquet(\"data.parquet\")",
          "desc": "Typed columnar data; needs pyarrow in the project.",
          "ex": "pd.read_parquet(\"data.parquet\")"
        },
        {
          "name": "Copy",
          "sig": "shutil.copy2(src, dst)",
          "desc": "Copy a file with its metadata; copytree for folders.",
          "ex": "shutil.copy2(src, dst)"
        }
      ]
    },
    {
      "id": "python-errors",
      "name": "Errors",
      "lang": "python",
      "ac": "var(--red)",
      "f": "dpuk",
      "intro": "Catch what you can handle, add context and let everything else reach the top with its traceback.",
      "primary": {
        "sig": "try: ... except ValueError as e:",
        "desc": "Catch what you can handle; let the rest bubble up.",
        "ex": "except ValueError as e:"
      },
      "items": [
        {
          "name": "Try",
          "sig": "try:",
          "desc": "Run the risky part in a guarded block.",
          "ex": "try:\n    parse(text)"
        },
        {
          "name": "Except",
          "sig": "except ValueError as e:",
          "desc": "Catch a specific exception and keep it for the message.",
          "ex": "except ValueError as e:"
        },
        {
          "name": "Else",
          "sig": "else:",
          "desc": "Runs only when the try block did not raise.",
          "ex": "else:\n    use(value)"
        },
        {
          "name": "Finally",
          "sig": "finally:",
          "desc": "Always runs: close the file, release the lock.",
          "ex": "finally:\n    f.close()"
        },
        {
          "name": "Raise",
          "sig": "raise ValueError(\"bad id\")",
          "desc": "Signal an error with a clear message.",
          "ex": "raise ValueError(\"bad id\")"
        },
        {
          "name": "Custom",
          "sig": "class ConfigError(Exception):",
          "desc": "A named error callers can catch specifically.",
          "ex": "class ConfigError(Exception): ..."
        },
        {
          "name": "From",
          "sig": "raise RuntimeError(\"load\") from err",
          "desc": "Keep the original cause in the traceback chain.",
          "ex": "raise RuntimeError(\"load\") from err"
        },
        {
          "name": "Assert",
          "sig": "assert x > 0, \"x must be positive\"",
          "desc": "A developer check; not for user input, it can be disabled.",
          "ex": "assert x > 0"
        },
        {
          "name": "Suppress",
          "sig": "contextlib.suppress(FileNotFoundError)",
          "desc": "Ignore one expected error around a block.",
          "ex": "with suppress(FileNotFoundError):"
        },
        {
          "name": "Log",
          "sig": "logging.exception(\"load failed\")",
          "desc": "Log the message and the active traceback at ERROR.",
          "ex": "except Exception:\n    logging.exception(\"load failed\")"
        },
        {
          "name": "Traceback",
          "sig": "traceback.print_exc()",
          "desc": "Print the current exception with its stack.",
          "ex": "traceback.print_exc()"
        },
        {
          "name": "Group",
          "sig": "except* ValueError as eg:",
          "desc": "Handle several errors at once with ExceptionGroup.",
          "ex": "except* ValueError as eg:"
        }
      ]
    },
    {
      "id": "python-classes",
      "name": "Classes",
      "lang": "python",
      "ac": "var(--aqua)",
      "f": "dpuk",
      "intro": "Plain classes, dataclasses and protocols: the shortest path from data to behavior.",
      "primary": {
        "sig": "@dataclass",
        "desc": "The default for records: fields, constructor, repr and equality.",
        "ex": "@dataclass\nclass User:\n    name: str"
      },
      "items": [
        {
          "name": "Class",
          "sig": "class User:",
          "desc": "A namespace for data and behavior.",
          "ex": "class User:"
        },
        {
          "name": "Init",
          "sig": "def __init__(self, name: str):",
          "desc": "Set up the instance; self is explicit.",
          "ex": "def __init__(self, name: str):"
        },
        {
          "name": "Dataclass",
          "sig": "@dataclass",
          "desc": "Generated methods from annotated fields.",
          "ex": "@dataclass\nclass User:\n    name: str"
        },
        {
          "name": "Repr",
          "sig": "def __repr__(self) -> str:",
          "desc": "A developer-facing representation, useful in debuggers.",
          "ex": "return f\"User({self.name!r})\""
        },
        {
          "name": "Property",
          "sig": "@property",
          "desc": "A method read like an attribute; add a setter if needed.",
          "ex": "@property\ndef total(self) -> float:"
        },
        {
          "name": "Inherit",
          "sig": "class Admin(User):",
          "desc": "Reuse the parent and override what changes.",
          "ex": "class Admin(User):"
        },
        {
          "name": "Super",
          "sig": "super().__init__(name)",
          "desc": "Call the parent implementation without naming it.",
          "ex": "super().__init__(name)"
        },
        {
          "name": "Classmethod",
          "sig": "@classmethod",
          "desc": "A factory that receives the class, not the instance.",
          "ex": "@classmethod\ndef from_row(cls, row):"
        },
        {
          "name": "Staticmethod",
          "sig": "@staticmethod",
          "desc": "A function that belongs to the class namespace only.",
          "ex": "@staticmethod\ndef parse(text: str):"
        },
        {
          "name": "Slots",
          "sig": "__slots__ = (\"name\",)",
          "desc": "Fixed attributes, less memory per instance.",
          "ex": "__slots__ = (\"name\",)"
        },
        {
          "name": "Protocol",
          "sig": "class Closeable(Protocol):",
          "desc": "Structural typing without inheritance.",
          "ex": "class Closeable(Protocol): ..."
        },
        {
          "name": "ABC",
          "sig": "class Repo(ABC):",
          "desc": "An abstract base: subclasses must implement the methods.",
          "ex": "class Repo(ABC): ..."
        }
      ]
    },
    {
      "id": "python-async",
      "name": "Async",
      "lang": "python",
      "ac": "var(--purple)",
      "f": "dpuk",
      "intro": "One event loop, many concurrent tasks: await, gather, timeouts and structured concurrency.",
      "primary": {
        "sig": "asyncio.run(main())",
        "desc": "The entry point: one event loop, one top-level coroutine.",
        "ex": "asyncio.run(main())"
      },
      "items": [
        {
          "name": "Async def",
          "sig": "async def fetch():",
          "desc": "A coroutine: calling it returns an awaitable, not the result.",
          "ex": "async def fetch():"
        },
        {
          "name": "Await",
          "sig": "await fetch()",
          "desc": "Yield control until the awaitable finishes.",
          "ex": "data = await fetch()"
        },
        {
          "name": "Gather",
          "sig": "await asyncio.gather(a(), b())",
          "desc": "Run several coroutines concurrently and collect results.",
          "ex": "await asyncio.gather(a(), b())"
        },
        {
          "name": "Task",
          "sig": "asyncio.create_task(fetch())",
          "desc": "Schedule work now; await the task when you need it.",
          "ex": "task = asyncio.create_task(fetch())"
        },
        {
          "name": "Sleep",
          "sig": "await asyncio.sleep(0.1)",
          "desc": "Yield to the loop; never use time.sleep in async code.",
          "ex": "await asyncio.sleep(0.1)"
        },
        {
          "name": "Timeout",
          "sig": "asyncio.timeout(2)",
          "desc": "Cancel the block when it takes too long (3.11+).",
          "ex": "async with asyncio.timeout(2):"
        },
        {
          "name": "Thread",
          "sig": "await asyncio.to_thread(f)",
          "desc": "Run blocking code in a worker thread.",
          "ex": "await asyncio.to_thread(f)"
        },
        {
          "name": "Queue",
          "sig": "asyncio.Queue()",
          "desc": "Producer/consumer handoff without locks.",
          "ex": "q = asyncio.Queue()"
        },
        {
          "name": "Lock",
          "sig": "asyncio.Lock()",
          "desc": "Mutual exclusion inside one event loop.",
          "ex": "async with lock:"
        },
        {
          "name": "Semaphore",
          "sig": "asyncio.Semaphore(10)",
          "desc": "Limit how many coroutines run at once.",
          "ex": "async with sem:"
        },
        {
          "name": "TaskGroup",
          "sig": "async with asyncio.TaskGroup() as tg:",
          "desc": "Structured concurrency: wait for all, cancel on failure.",
          "ex": "tg.create_task(fetch())"
        },
        {
          "name": "Cancel",
          "sig": "task.cancel()",
          "desc": "Request cancellation; the task sees CancelledError.",
          "ex": "task.cancel()"
        }
      ]
    },
    {
      "id": "python-testing",
      "name": "Testing",
      "lang": "python",
      "ac": "var(--green)",
      "f": "dpuk",
      "intro": "pytest, fixtures and the editor shortcuts that turn a failing test into a diagnostic.",
      "primary": {
        "sig": "def test_total():",
        "desc": "A test is a function named test_ that asserts the behavior.",
        "ex": "def test_total():\n    assert total(df) == 6"
      },
      "items": [
        {
          "name": "Pytest",
          "sig": "uv run pytest -q",
          "desc": "Discover and run tests from the project root.",
          "ex": "uv run pytest -q"
        },
        {
          "name": "Assert",
          "sig": "assert result == 6",
          "desc": "Plain assert; pytest rewrites it to show the values.",
          "ex": "assert result == 6"
        },
        {
          "name": "Raises",
          "sig": "with pytest.raises(ValueError):",
          "desc": "Assert that the block raises the expected error.",
          "ex": "with pytest.raises(ValueError):"
        },
        {
          "name": "Fixture",
          "sig": "@pytest.fixture",
          "desc": "Shared setup injected by name into tests.",
          "ex": "@pytest.fixture\ndef df(): ..."
        },
        {
          "name": "Parametrize",
          "sig": "@pytest.mark.parametrize(\"x\", [1, 2])",
          "desc": "Run the same test once per case.",
          "ex": "@pytest.mark.parametrize(\"x\", [1, 2])"
        },
        {
          "name": "tmp_path",
          "sig": "def test_write(tmp_path):",
          "desc": "A fresh temporary directory per test.",
          "ex": "path = tmp_path / \"out.txt\""
        },
        {
          "name": "Monkeypatch",
          "sig": "monkeypatch.setenv(\"APP_ENV\", \"test\")",
          "desc": "Patch environment, attributes or cwd for one test.",
          "ex": "monkeypatch.setenv(\"APP_ENV\", \"test\")"
        },
        {
          "name": "Marks",
          "sig": "@pytest.mark.slow",
          "desc": "Label tests; run them with -m slow or skip them.",
          "ex": "@pytest.mark.slow"
        },
        {
          "name": "Approx",
          "sig": "pytest.approx(0.1 + 0.2)",
          "desc": "Compare floats with a tolerance instead of ==.",
          "ex": "assert 0.1 + 0.2 == pytest.approx(0.3)"
        },
        {
          "name": "Coverage",
          "sig": "uv run pytest --cov",
          "desc": "Report which lines the tests executed.",
          "ex": "uv run pytest --cov"
        },
        {
          "name": "Menu",
          "sig": "<leader>pm",
          "desc": "Run the test under the cursor and mark the result.",
          "ex": "<leader>pm"
        },
        {
          "name": "Doctest",
          "sig": "python -m doctest file.py",
          "desc": "Run the examples embedded in docstrings.",
          "ex": "python -m doctest file.py"
        }
      ]
    },
    {
      "id": "python-packaging",
      "name": "Packaging",
      "lang": "python",
      "ac": "var(--blue)",
      "f": "dpuk",
      "intro": "uv is the whole toolchain: Python, virtualenv, dependencies, lockfile, runner and build.",
      "primary": {
        "sig": "uv add pandas",
        "desc": "Add a runtime dependency and update pyproject and uv.lock.",
        "ex": "uv add pandas"
      },
      "items": [
        {
          "name": "Init",
          "sig": "uv init --app my-app",
          "desc": "A new project with pyproject, .python-version and src/.",
          "ex": "uv init --app my-app"
        },
        {
          "name": "Add",
          "sig": "uv add pandas numpy",
          "desc": "Resolve, install and record the dependencies.",
          "ex": "uv add pandas numpy"
        },
        {
          "name": "Dev",
          "sig": "uv add --dev pytest ruff",
          "desc": "Tools for development, not for the package runtime.",
          "ex": "uv add --dev pytest ruff"
        },
        {
          "name": "Sync",
          "sig": "uv sync",
          "desc": "Create or repair .venv from the lockfile.",
          "ex": "uv sync"
        },
        {
          "name": "Lock",
          "sig": "uv lock",
          "desc": "Resolve versions and write uv.lock without installing.",
          "ex": "uv lock"
        },
        {
          "name": "Upgrade",
          "sig": "uv lock --upgrade",
          "desc": "Move every dependency to the latest allowed version.",
          "ex": "uv lock --upgrade"
        },
        {
          "name": "Run",
          "sig": "uv run python app.py",
          "desc": "Run inside the project environment, no activation.",
          "ex": "uv run python app.py"
        },
        {
          "name": "uvx",
          "sig": "uvx ruff check .",
          "desc": "Run a tool once without adding it to the project.",
          "ex": "uvx ruff check ."
        },
        {
          "name": "pyproject",
          "sig": "[project]",
          "desc": "The source of truth: name, Python range and dependencies.",
          "ex": "[project]\nname = \"my-app\""
        },
        {
          "name": "Venv",
          "sig": "uv venv --python 3.14",
          "desc": "Create .venv with a specific interpreter.",
          "ex": "uv venv --python 3.14"
        },
        {
          "name": "Build",
          "sig": "uv build",
          "desc": "Build sdist and wheel into dist/.",
          "ex": "uv build"
        },
        {
          "name": "Pin",
          "sig": "uv python pin 3.14",
          "desc": "Write .python-version so everyone uses the same Python.",
          "ex": "uv python pin 3.14"
        }
      ]
    },
    {
      "id": "python-leader",
      "name": "Leader",
      "lang": "python",
      "ac": "var(--yellow)",
      "f": "dpuk",
      "intro": "The Python menu and the keys you will use while writing, testing and running the code.",
      "primary": {
        "sig": "Space p",
        "desc": "The Python menu: run, test, uv, Jupyter, lint and format.",
        "ex": "Space p"
      },
      "items": [
        {
          "name": "Complete",
          "sig": "<C-Space>",
          "desc": "Suggestions from basedpyright and the buffer; Enter inserts.",
          "ex": "<C-Space>"
        },
        {
          "name": "Hover",
          "sig": "K",
          "desc": "Documentation and signature of the symbol under the cursor.",
          "ex": "K"
        },
        {
          "name": "Signature",
          "sig": "<C-k>",
          "desc": "The function signature while you type the arguments.",
          "ex": "<C-k>"
        },
        {
          "name": "Symbols",
          "sig": "gO",
          "desc": "Functions and classes in the current file.",
          "ex": "gO"
        },
        {
          "name": "Definition",
          "sig": "gd",
          "desc": "Jump to where the symbol is defined.",
          "ex": "gd"
        },
        {
          "name": "References",
          "sig": "grr",
          "desc": "Every use of the symbol in the project.",
          "ex": "grr"
        },
        {
          "name": "Rename",
          "sig": "grn",
          "desc": "Rename the symbol and all its references.",
          "ex": "grn"
        },
        {
          "name": "Actions",
          "sig": "<leader>ca",
          "desc": "Quick fixes, Ruff fixes and Add import.",
          "ex": "<leader>ca"
        },
        {
          "name": "Hints",
          "sig": "<leader>ph",
          "desc": "Toggle call-argument names and return types.",
          "ex": "<leader>ph"
        },
        {
          "name": "Ruff",
          "sig": "<leader>pv",
          "desc": "Lint the project; px fixes what it can.",
          "ex": "<leader>pv"
        },
        {
          "name": "Types",
          "sig": "<leader>py",
          "desc": "Run basedpyright over the whole project.",
          "ex": "<leader>py"
        },
        {
          "name": "Jupyter",
          "sig": "<leader>pj",
          "desc": "Launch JupyterLab with uv run.",
          "ex": "<leader>pj"
        }
      ]
    }
  ],

  /* banners */
  banner: { lines: ["Neovim,", "for working."], sub: "~20 ms. One key per context. An agent that speaks when you ask." }
};
