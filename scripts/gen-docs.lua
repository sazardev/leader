-- ── docs/docs/index.html from the repository's Markdown ──────────────────────
-- The web documentation (the landing page's /docs/) is GENERATED: README.md, CHEATSHEET.md (itself generated from the
-- real keymaps), CHANGELOG.md, every guide in docs/cheatsheets/ and AGENTS.md, rendered into one static page with the landing's flat
-- look (same palette and fonts, no external requests, no build step to view it). Never edit the HTML: edit the Markdown.
--
--   nvim -u NONE -l scripts/gen-docs.lua            write docs/docs/index.html
--   nvim -u NONE -l scripts/gen-docs.lua --check    exit 1 if it is not up to date
--   … --worktree                                    read the files as they are on disk (default: as they are staged)
--
-- By default the Markdown is read from the git INDEX: the page always describes what is being committed, never
-- half-written work in the working tree (the pre-commit hook regenerates it). Renders the subset the docs use: headings,
-- paragraphs, nested lists, tables (pipes inside code spans are kept), fenced code (also inside list items),
-- blockquotes, rules, code spans, bold, italics and links (links between the docs become anchors of this page).
local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local OUT = ROOT .. "/docs/docs/index.html"
local REPO = "https://github.com/sazardev/leader/blob/master/"

local check = vim.tbl_contains(arg, "--check")
local worktree = vim.tbl_contains(arg, "--worktree")

-- the sidebar, in order: { id, title (nil = the file's own `#` heading), source, group }
local PAGES = {
  { "overview", "Overview", "README.md", "Start" },
  { "guides", "Workflows", "docs/cheatsheets/README.md", "Start" },
  { "keys", "Every key", "CHEATSHEET.md", "Start" },
  { "changelog", "Changelog", "CHANGELOG.md", "Start" },
  { "agent", "AI agent", "docs/cheatsheets/agent.md", "Features" },
  { "editing", "Undo and clipboard", "docs/cheatsheets/editing.md", "Features" },
  { "tasks", "Project tasks", "docs/cheatsheets/tasks.md", "Features" },
  { "gitignore", ".gitignore", "docs/cheatsheets/gitignore.md", "Features" },
  { "release", "Release", "docs/cheatsheets/release.md", "Features" },
  { "go", "Go", "docs/cheatsheets/go.md", "Languages" },
  { "dart-flutter", "Dart / Flutter", "docs/cheatsheets/dart-flutter.md", "Languages" },
  { "typescript", "TypeScript / JS", "docs/cheatsheets/typescript.md", "Languages" },
  { "python", "Python", "docs/cheatsheets/python.md", "Languages" },
  { "rust", "Rust", "docs/cheatsheets/rust.md", "Languages" },
  { "sql", "SQL", "docs/cheatsheets/sql.md", "Languages" },
  { "swift", "Swift", "docs/cheatsheets/swift.md", "Languages" },
  { "java-kotlin", "Java / Kotlin", "docs/cheatsheets/java-kotlin.md", "Languages" },
  { "lua", "Lua", "docs/cheatsheets/lua.md", "Languages" },
  { "markdown", "Markdown", "docs/cheatsheets/markdown.md", "Languages" },
  { "web", "Web", "docs/cheatsheets/web.md", "Languages" },
  { "data-formats", "Data formats", "docs/cheatsheets/data-formats.md", "Languages" },
  { "internals", "Architecture", "AGENTS.md", "Internals" },
}

-- ── reading ──────────────────────────────────────────────────────────────────

---@param path string relative to the repo
---@return string
local function read(path)
  if not worktree then
    local out = vim.system({ "git", "-C", ROOT, "show", ":" .. path }, { text = true }):wait()
    if out.code == 0 then
      return out.stdout
    end
  end
  local f = assert(io.open(ROOT .. "/" .. path, "r"), "missing " .. path)
  local text = f:read "*a"
  f:close()
  return text
end

-- ── inline ───────────────────────────────────────────────────────────────────

local function escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

--- GitHub's heading anchors: lowercase, punctuation out (hyphens and underscores stay), spaces to hyphens
local function slug(text)
  local s = text:lower():gsub("`", ""):gsub("<[^>]*>", "")
  s = s:gsub("[^%w%s%-_\128-\255]", ""):gsub("[\128-\255]+", ""):gsub("%s", "-")
  return s
end

-- where a page lives in this document, by the paths the Markdown uses to point at it
local PAGE_OF = {}
for _, p in ipairs(PAGES) do
  PAGE_OF[p[3]] = p[1]
  PAGE_OF[vim.fs.basename(p[3])] = PAGE_OF[vim.fs.basename(p[3])] or p[1]
end
PAGE_OF["README.md"] = "overview"
PAGE_OF["CHEATSHEET.md"] = "keys"
PAGE_OF["../../CHEATSHEET.md"] = "keys"
PAGE_OF["AGENTS.md"] = "internals"

local current_page -- id of the page being rendered (its own `#anchor` links stay inside it)
local current_dir -- folder of the Markdown file being rendered (relative links are resolved from it)

--- A link of the Markdown → where it goes on this site
local function href(url)
  if url:match "^%a[%w+.-]*:" then
    return url, true
  end
  local path, anchor = url:match "^([^#]*)#?(.*)$"
  if path == "" then
    return "#" .. current_page .. "--" .. anchor
  end
  local resolved = vim.fs.normalize(current_dir .. "/" .. path)
  local id = PAGE_OF[path] or PAGE_OF[resolved] or PAGE_OF[vim.fs.basename(path)]
  if not id and vim.fn.isdirectory(ROOT .. "/" .. resolved) == 1 then
    return REPO:gsub("/blob/", "/tree/") .. resolved, true
  end
  if not id then
    return REPO .. resolved, true -- a file of the repository: GitHub shows it
  end
  return "#" .. id .. (anchor ~= "" and ("--" .. anchor) or "")
end

---@param text string
---@return string html
local function inline(text)
  local saved = {}
  local function keep(html)
    saved[#saved + 1] = html
    return "\1" .. #saved .. "\2"
  end
  -- code spans first: nothing inside them is Markdown
  text = text:gsub("(`+)(.-)%1", function(_, code)
    return keep("<code>" .. escape(vim.trim(code)) .. "</code>")
  end)
  -- links: [text](url)
  text = text:gsub("%[([^%]]+)%]%(([^%)%s]+)%)", function(label, url)
    local to, external = href(url)
    return keep(
      ('<a href="%s"%s>'):format(escape(to), external and ' target="_blank" rel="noopener"' or "")
        .. inline(label)
        .. "</a>"
    )
  end)
  text = escape(text)
  text = text:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
  text = text:gsub("%f[%w%*]%*([^%*%s][^%*]-)%*", "<em>%1</em>")
  -- restore (a saved piece can hold another one: a code span inside a link)
  for _ = 1, 3 do
    text = text:gsub("\1(%d+)\2", function(n)
      return saved[tonumber(n)]
    end)
  end
  return text
end

-- ── blocks ───────────────────────────────────────────────────────────────────

--- Table cells: split on `|` outside code spans
local function cells(line)
  local out, cur, ticks = {}, {}, false
  line = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  for c in line:gmatch "." do
    if c == "`" then
      ticks = not ticks
    end
    if c == "|" and not ticks then
      out[#out + 1] = vim.trim(table.concat(cur))
      cur = {}
    else
      cur[#cur + 1] = c
    end
  end
  out[#out + 1] = vim.trim(table.concat(cur))
  return out
end

local LIST_ITEM = "^(%s*)([-*+]) (.*)$"
local ORDERED_ITEM = "^(%s*)(%d+)%. (.*)$"

---@param lines string[]
---@return string html, { level: integer, text: string, id: string }[] headings
local function render(lines)
  local out, headings, used = {}, {}, {}
  local i = 1

  local function heading(level, text)
    local base = current_page .. "--" .. slug(text)
    local id, n = base, 1
    while used[id] do
      id, n = base .. "-" .. n, n + 1
    end
    used[id] = true
    headings[#headings + 1] = { level = level, text = text, id = id }
    out[#out + 1] = ('<h%d id="%s"><a href="#%s">%s</a></h%d>'):format(level, id, id, inline(text), level)
  end

  local function fence_at(l)
    return l:match "^(%s*)```(.*)$"
  end

  --- A fenced block starting at line `start`; returns the html and the next line
  local function fence(start)
    local indent, lang = fence_at(lines[start])
    local body, j = {}, start + 1
    while j <= #lines and not lines[j]:match("^" .. indent .. "```%s*$") do
      body[#body + 1] = lines[j]:sub(#indent + 1)
      j = j + 1
    end
    lang = vim.trim(lang)
    return ("<pre%s><code>%s</code></pre>"):format(
      lang ~= "" and (' data-lang="%s"'):format(escape(lang)) or "",
      escape(table.concat(body, "\n"))
    ),
      j + 1
  end

  --- A list starting at `start` (nested by indentation); returns the html and the next line
  local function list(start)
    local html, j = {}, start
    local stack = {} -- { indent, tag }
    local open_item = false
    local pending = {} -- the text of the item being read: rendered once complete (bold can span its lines)
    local function flush()
      if #pending > 0 then
        html[#html + 1] = inline(table.concat(pending, " "))
        pending = {}
      end
    end
    local function close_to(indent)
      flush()
      while #stack > 0 and stack[#stack].indent > indent do
        html[#html + 1] = "</li></" .. stack[#stack].tag .. ">"
        table.remove(stack)
      end
    end
    while j <= #lines do
      local l = lines[j]
      local ind, _, text = l:match(LIST_ITEM)
      local tag = "ul"
      if not ind then
        ind, _, text = l:match(ORDERED_ITEM)
        tag = "ol"
      end
      if ind then
        local level = #ind
        close_to(level)
        if #stack == 0 or stack[#stack].indent < level then
          stack[#stack + 1] = { indent = level, tag = tag }
          html[#html + 1] = "<" .. tag .. "><li>"
        else
          html[#html + 1] = "</li><li>"
        end
        pending = { text }
        open_item = true
        j = j + 1
      elseif l:match "^%s*$" then
        -- a blank line: the list goes on only if what follows is indented or another item
        local next_line = lines[j + 1] or ""
        if next_line:match "^%s+%S" or next_line:match(LIST_ITEM) or next_line:match(ORDERED_ITEM) then
          j = j + 1
        else
          break
        end
      elseif fence_at(l) and l:match "^%s+" then
        flush()
        local block
        block, j = fence(j)
        html[#html + 1] = block
      elseif l:match "^%s+%S" and open_item then
        pending[#pending + 1] = vim.trim(l) -- continuation of the item
        j = j + 1
      else
        break
      end
    end
    close_to(-1)
    return table.concat(html), j
  end

  while i <= #lines do
    local l = lines[i]
    local hashes, htext = l:match "^(#+)%s+(.*)$"
    if fence_at(l) then
      local block
      block, i = fence(i)
      out[#out + 1] = block
    elseif hashes then
      heading(#hashes, vim.trim(htext))
      i = i + 1
    elseif l:match "^%s*$" then
      i = i + 1
    elseif l:match "^%s*<!%-%-" then
      -- an HTML comment (CHEATSHEET.md's "generated" note): not for the reader
      while i <= #lines and not lines[i]:match "%-%->" do
        i = i + 1
      end
      i = i + 1
    elseif l:match "^%-%-%-+%s*$" or l:match "^%*%*%*+%s*$" then
      out[#out + 1] = "<hr>"
      i = i + 1
    elseif l:match "^%s*|" and (lines[i + 1] or ""):match "^%s*|[%s:|-]+|%s*$" then
      local head = cells(l)
      local rows = {}
      i = i + 2
      while i <= #lines and lines[i]:match "^%s*|" do
        rows[#rows + 1] = cells(lines[i])
        i = i + 1
      end
      local html = { ('<div class="tbl%s"><table><thead><tr>'):format(#head >= 3 and " wide" or "") }
      for _, c in ipairs(head) do
        html[#html + 1] = "<th>" .. inline(c) .. "</th>"
      end
      html[#html + 1] = "</tr></thead><tbody>"
      -- on a phone each row becomes a card: with 3+ columns every value carries its column's name
      local labelled = #head >= 3
      for _, r in ipairs(rows) do
        html[#html + 1] = "<tr>"
        for k = 1, #head do
          local label = labelled and k > 1 and (' data-label="%s"'):format(escape((head[k]:gsub("`", "")))) or ""
          html[#html + 1] = "<td" .. label .. ">" .. inline(r[k] or "") .. "</td>"
        end
        html[#html + 1] = "</tr>"
      end
      html[#html + 1] = "</tbody></table></div>"
      out[#out + 1] = table.concat(html)
    elseif l:match "^>" then
      local quote = {}
      while i <= #lines and lines[i]:match "^>" do
        quote[#quote + 1] = lines[i]:gsub("^>%s?", "")
        i = i + 1
      end
      out[#out + 1] = "<blockquote>" .. inline(table.concat(quote, " ")) .. "</blockquote>"
    elseif l:match(LIST_ITEM) or l:match(ORDERED_ITEM) then
      local block
      block, i = list(i)
      out[#out + 1] = block
    else
      local para = {}
      while
        i <= #lines
        and not lines[i]:match "^%s*$"
        and not lines[i]:match "^#+%s"
        and not fence_at(lines[i])
        and not lines[i]:match(LIST_ITEM)
        and not lines[i]:match(ORDERED_ITEM)
        and not lines[i]:match "^>"
        and not lines[i]:match "^%s*|"
      do
        para[#para + 1] = vim.trim(lines[i])
        i = i + 1
      end
      out[#out + 1] = "<p>" .. inline(table.concat(para, " ")) .. "</p>"
    end
  end
  return table.concat(out, "\n"), headings
end

-- ── the page ─────────────────────────────────────────────────────────────────

local sections, nav, group_open = {}, {}, nil
for _, p in ipairs(PAGES) do
  local id, title, src, group = p[1], p[2], p[3], p[4]
  current_page, current_dir = id, vim.fs.dirname(src)
  local lines = vim.split(read(src), "\n", { plain = true })
  -- the file's own `# Title` becomes the page header
  local first = 1
  while lines[first] and lines[first]:match "^%s*$" do
    first = first + 1
  end
  if lines[first] and lines[first]:match "^# " then
    title = title or lines[first]:sub(3)
    table.remove(lines, first)
  end
  local body, headings = render(lines)
  sections[#sections + 1] = ('<section class="page" id="%s" data-title="%s">\n<p class="crumb">%s · <a href="%s" target="_blank" rel="noopener">%s</a></p>\n<h1>%s</h1>\n%s\n</section>'):format(
    id,
    escape(title),
    escape(group),
    REPO .. src,
    escape(src),
    escape(title),
    body
  )
  if group ~= group_open then
    nav[#nav + 1] = ('<p class="grp">%s</p>'):format(escape(group))
    group_open = group
  end
  local subs = {}
  for _, h in ipairs(headings) do
    if h.level == 2 then
      subs[#subs + 1] = ('<a href="#%s">%s</a>'):format(h.id, inline(h.text))
    end
  end
  nav[#nav + 1] = ('<div class="nav-page" data-page="%s"><a class="nav-top" href="#%s">%s</a>%s</div>'):format(
    id,
    id,
    escape(title),
    #subs > 0 and ('<div class="nav-sub">' .. table.concat(subs) .. "</div>") or ""
  )
end

local TEMPLATE = [==[<!doctype html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Docs — Leader</title>
<meta name="description" content="Documentation of Leader: install, every key, the AI agent, Go, Dart / Flutter, project tasks and how the config is built.">
<meta name="robots" content="index,follow,max-image-preview:large">
<meta name="theme-color" content="#282828">
<link rel="canonical" href="https://sazardev.github.io/leader/docs/">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Leader">
<meta property="og:url" content="https://sazardev.github.io/leader/docs/">
<meta property="og:title" content="Docs — Leader">
<meta property="og:description" content="Install, every key, the AI agent, Go, Dart / Flutter, project tasks and how Leader is built.">
<meta property="og:image" content="https://sazardev.github.io/leader/screenshots/og.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="apple-touch-icon" href="../apple-touch-icon.png">
<link rel="icon" type="image/png" sizes="192x192" href="../icon-192.png">
<link rel="preload" href="../fonts/Geist-Variable.woff2" as="font" type="font/woff2" crossorigin>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' fill='%23282828'/%3E%3Cpath d='M8 25V7l16 18V7' fill='none' stroke='%23b8bb26' stroke-width='3.4'/%3E%3C/svg%3E">
<!-- GENERATED by scripts/gen-docs.lua from the repository's Markdown. Do not edit: edit the .md files. -->
<style>
@font-face{font-family:Geist;src:url(../fonts/Geist-Variable.woff2) format("woff2");font-weight:100 900;font-display:swap}
@font-face{font-family:"Geist Mono";src:url(../fonts/GeistMono-Variable.woff2) format("woff2");font-weight:100 900;font-display:swap}
/* the landing page's palette (base46 gruvbox / gruvbox_light). Flat: no borders, no radius, no shadows */
:root,[data-theme=dark]{
  --bg:#282828;--deep:#202020;--soft:#323232;--fg:#ebdbb2;--dim:#a89984;--faint:#665c54;
  --green:#b8bb26;--yellow:#fabd2f;--aqua:#8ec07c;--blue:#83a598;--red:#fb4934;--purple:#d3869b;--orange:#fe8019;--on:#1d2021;
}
[data-theme=light]{
  --bg:#f2e5bc;--deep:#e9dcb3;--soft:#e3d6ad;--fg:#3c3836;--dim:#665c54;--faint:#a89984;
  --green:#79740e;--yellow:#b57614;--aqua:#427b58;--blue:#076678;--red:#9d0006;--purple:#8f3f71;--orange:#af3a03;--on:#f9f5d7;
}
*{box-sizing:border-box;margin:0;padding:0;border:0;border-radius:0}
:root,[data-theme=dark]{color-scheme:dark}[data-theme=light]{color-scheme:light} /* the browser's own parts (the page's scrollbar track) follow */
html{scroll-padding-top:84px;-webkit-text-size-adjust:100%}
body{background:var(--bg);color:var(--fg);font:400 16px/1.65 Geist,system-ui,-apple-system,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased;transition:background .3s,color .3s}
a{color:inherit;text-decoration:none}
button,input{font:inherit;color:inherit;background:none}
/* scrollbars in the theme's colors: thin, square, no track, no arrows (the page, the sidebar, code, search results).
   Chromium ignores ::-webkit-scrollbar as soon as scrollbar-width/-color are set, so those are for Firefox only */
@supports not selector(::-webkit-scrollbar){*{scrollbar-width:thin;scrollbar-color:color-mix(in srgb,var(--faint) 75%,transparent) transparent}}
::-webkit-scrollbar-button{display:none;width:0;height:0}
::-webkit-scrollbar{width:8px;height:8px}
::-webkit-scrollbar-track,::-webkit-scrollbar-corner{background:transparent}
::-webkit-scrollbar-thumb{background:color-mix(in srgb,var(--faint) 75%,transparent)}
::-webkit-scrollbar-thumb:hover{background:var(--dim)}
::selection{background:var(--green);color:var(--on)}
:focus-visible{outline:2px solid var(--green);outline-offset:2px}

/* ── top bar ──────────────────────────────────────────────────────────────── */
.bar{position:fixed;inset:0 0 auto 0;height:60px;z-index:50;background:var(--bg);display:flex;align-items:center;gap:24px;padding:0 24px}
.logo{font-weight:600;letter-spacing:-.02em;font-size:15px;display:flex;align-items:center;gap:10px;white-space:nowrap}
.logo i{width:12px;height:12px;background:var(--green);display:block}
.logo b{font-weight:400;color:var(--dim)}
.search{flex:1;max-width:520px;position:relative}
.search input{width:100%;height:36px;background:var(--deep);padding:0 44px 0 14px;font-size:14px}
.search input::placeholder{color:var(--faint)}
.search .k{position:absolute;right:8px;top:8px}
.k{font-family:"Geist Mono",monospace;font-size:12px;background:var(--soft);color:var(--dim);padding:1px 7px}
.bar nav{margin-left:auto;display:flex;gap:20px;align-items:center;font-size:14px;color:var(--dim)}
.bar nav a:hover,.bar nav button:hover{color:var(--fg)}
.bar nav button{cursor:pointer}
#menu{display:none}

/* search results: a filled block under the field, like the config's pickers */
.results{position:absolute;left:0;right:0;top:40px;background:var(--soft);max-height:min(70vh,560px);overflow-y:auto;overflow-x:hidden;display:none;overscroll-behavior:contain}
.results.on{display:block}
/* behind the results, the page steps back (the landing page's scrim) */
.scrim{position:fixed;inset:60px 0 0 0;background:color-mix(in srgb,var(--bg) 60%,transparent);z-index:45;display:none}
.scrim.on{display:block}
.results a{display:block;padding:9px 14px;font-size:14px;overflow-wrap:anywhere}
.results a small{display:block;color:var(--faint);font-size:12px}
.results a.sel{background:var(--blue);color:var(--on)}
.results a.sel small{color:var(--on);opacity:.75}
.results p{padding:12px 14px;color:var(--faint);font-size:14px}

/* ── layout ───────────────────────────────────────────────────────────────── */
.layout{display:grid;grid-template-columns:280px minmax(0,1fr);gap:56px;padding:60px 24px 0;max-width:1280px;margin:0 auto}
aside{position:sticky;top:60px;height:calc(100vh - 60px);overflow:auto;padding:28px 8px 40px 0;font-size:14px}
aside .grp{color:var(--faint);font-size:11px;letter-spacing:.12em;text-transform:uppercase;margin:22px 0 6px}
aside .grp:first-child{margin-top:0}
.nav-top{display:block;padding:4px 10px;color:var(--dim)}
.nav-top:hover{color:var(--fg)}
.nav-page.on .nav-top{background:var(--soft);color:var(--fg);font-weight:500}
.nav-sub{display:none;padding:4px 0 8px 10px}
.nav-page.on .nav-sub{display:block}
.nav-sub a{display:block;padding:3px 10px;color:var(--faint);font-size:13px;line-height:1.4}
.nav-sub a:hover,.nav-sub a.on{color:var(--fg)}
.nav-sub a.on{box-shadow:inset 2px 0 var(--green)}
main{padding:40px 0 120px;min-width:0;max-width:860px}

/* ── content ──────────────────────────────────────────────────────────────── */
.page+.page{margin-top:96px}
.js .page{display:none;margin-top:0}
.js .page.on{display:block;animation:in .35s cubic-bezier(.2,.7,.1,1)}
@keyframes in{from{opacity:0;transform:translateY(12px)}}
.crumb{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);margin-bottom:10px}
.crumb a:hover{color:var(--fg)}
h1{font-size:clamp(34px,4vw,48px);line-height:1.08;letter-spacing:-.03em;font-weight:600;margin-bottom:28px}
h2{font-size:26px;letter-spacing:-.02em;font-weight:600;margin:56px 0 14px;line-height:1.2}
h3{font-size:19px;font-weight:600;margin:36px 0 10px;line-height:1.3}
h4{font-size:16px;font-weight:600;margin:28px 0 8px;color:var(--dim)}
h2 a,h3 a,h4 a{position:relative}
h1 code,h2 code,h3 code,h4 code{background:none;padding:0;font-size:.88em;color:var(--aqua)}
h2 a:hover::after,h3 a:hover::after{content:"#";position:absolute;left:calc(100% + 10px);color:var(--faint)}
p,ul,ol,blockquote,pre,.tbl{margin:0 0 16px}
ul,ol{padding-left:22px}
li{margin:4px 0}
li>ul,li>ol{margin:4px 0 0}
li::marker{color:var(--faint)}
main a{color:var(--blue)}
main a:hover{text-decoration:underline;text-underline-offset:3px}
h2 a,h3 a,h4 a,main h2 a:hover,main h3 a:hover{color:inherit;text-decoration:none}
strong{font-weight:600}
em{color:var(--dim)}
code{font-family:"Geist Mono",ui-monospace,monospace;font-size:.86em;background:var(--soft);padding:1px 6px;word-break:break-word}
.code{position:relative;margin:0 0 16px}
pre{background:var(--deep);padding:16px 20px;overflow:auto;font-size:14px;line-height:1.55}
.code pre{margin:0;padding-right:76px}
pre code{background:none;padding:0;font-size:inherit;word-break:normal}
.copy{position:absolute;top:8px;right:8px;font:12px "Geist Mono",monospace;color:var(--faint);background:var(--soft);padding:3px 9px;cursor:pointer;transition:color .15s,background .15s}
.copy:hover{color:var(--fg)}
.copy.done{color:var(--on);background:var(--green)}
blockquote{background:var(--soft);padding:14px 18px;color:var(--dim);box-shadow:inset 3px 0 var(--aqua)}
hr{height:1px;background:var(--soft);margin:40px 0}
.tbl{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.5}
th{text-align:left;font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);font-weight:500;padding:8px 12px;background:var(--deep)}
td{padding:8px 12px;vertical-align:top}
tbody tr:nth-child(even) td{background:color-mix(in srgb,var(--soft) 55%,transparent)}
td:first-child code{white-space:nowrap}
.flash{animation:flash 1.6s ease-out}
@keyframes flash{0%,30%{background:color-mix(in srgb,var(--yellow) 30%,transparent)}}
.pager{display:flex;justify-content:space-between;gap:16px;margin-top:72px}
.pager a{background:var(--soft);padding:14px 18px;flex:1;color:var(--fg)}
.pager a:hover{background:color-mix(in srgb,var(--soft) 70%,var(--fg));text-decoration:none}
.pager a small{display:block;color:var(--faint);font-size:12px}
.pager a.next{text-align:right}
footer{color:var(--faint);font-size:13px;padding:40px 0 60px}
footer a{color:var(--dim)}

@media (max-width:900px){
  .layout{grid-template-columns:1fr;gap:0;padding:60px 18px 0}
  aside{position:fixed;inset:60px 0 0 0;height:auto;background:var(--bg);z-index:40;padding:20px 18px 40px;display:none;overscroll-behavior:contain}
  aside.open{display:block}
  body.menu-open{overflow:hidden}
  #menu{display:block}
  .bar{gap:12px;padding:0 14px}
  .logo b,.bar nav a,.search .k{display:none}
  .search{min-width:0}
  .search input{padding-right:12px;font-size:16px} /* 16px: iOS does not zoom into the field */
  .bar nav{gap:16px}
  .results{position:fixed;left:0;right:0;top:60px;max-height:calc(100vh - 60px)}
  main{padding:28px 0 96px}
  h1{margin-bottom:22px}
  h2{font-size:23px;margin-top:44px}
  pre{font-size:13px;padding:14px 16px;white-space:pre-wrap;overflow-wrap:anywhere} /* wrapped: no sideways scroll on a phone */
  .code pre{padding-right:16px;padding-top:40px}
  .nav-top{padding:7px 10px}
  .nav-sub a{padding:6px 10px}
  .pager{flex-direction:column}
}
@media (max-width:640px){
  /* tables become one card per row: no column squeezed to a word per line */
  .tbl table,.tbl tbody,.tbl tr,.tbl td{display:block;width:100%}
  .tbl thead{display:none}
  .tbl tr{background:var(--soft);padding:10px 14px;margin-bottom:6px}
  .tbl tbody tr:nth-child(even) td{background:none}
  .tbl td{padding:2px 0}
  .tbl td:first-child{font-weight:600}
  .tbl td:first-child code{white-space:normal}
  .tbl.wide td[data-label]{padding-top:6px}
  .tbl.wide td[data-label]::before{content:attr(data-label);display:block;font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);font-weight:500}
}
@media (max-width:520px){.logo{font-size:0;gap:0}}
@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
</style>
</head>
<body>
<header class="bar">
  <a class="logo" href="../"><i></i>Leader <b>/ docs</b></a>
  <div class="search">
    <input id="q" type="search" placeholder="Search the docs" autocomplete="off" spellcheck="false" aria-label="Search">
    <span class="k">/</span>
    <div class="results" id="results" role="listbox"></div>
  </div>
  <nav>
    <a class="home" href="../">Home</a>
    <a href="https://github.com/sazardev/leader" target="_blank" rel="noopener">GitHub</a>
    <button id="theme" aria-label="Light or dark">Theme</button>
    <button id="menu" aria-label="Menu">Menu</button>
  </nav>
</header>
<div class="scrim" id="scrim"></div>
<div class="layout">
<aside id="nav">
@NAV@
</aside>
<main id="main">
@SECTIONS@
<footer>Generated from the repository's Markdown (README.md, CHEATSHEET.md, docs/cheatsheets/, AGENTS.md) by <code>scripts/gen-docs.lua</code>: edit those, never this page. Keys come from the config's real keymaps.</footer>
</main>
</div>
<script>
(function () {
  var root = document.documentElement, $ = function (s, el) { return (el || document).querySelector(s); };
  var $$ = function (s, el) { return Array.prototype.slice.call((el || document).querySelectorAll(s)); };
  root.classList.add("js");

  /* ── theme: the same choice as the landing page (localStorage "theme"); a terminal theme picked there reads as
     dark or light here ─────────────────────────────────────────────────────── */
  function apply(mode) {
    root.dataset.theme = mode;
    $("meta[name=theme-color]").content = mode === "light" ? "#f2e5bc" : "#282828";
  }
  var saved = null; try { saved = localStorage.getItem("theme"); } catch (e) {}
  apply(saved === "light" || saved === "dark" ? saved : (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"));
  $("#theme").onclick = function () {
    var next = root.dataset.theme === "light" ? "dark" : "light";
    apply(next); try { localStorage.setItem("theme", next); } catch (e) {}
  };

  /* ── pages: one guide on screen at a time; #page or #page--section ───────── */
  var pages = $$(".page"), navs = $$(".nav-page");
  function pageOf(id) {
    var el = id && document.getElementById(id);
    var page = el && (el.classList.contains("page") ? el : el.closest(".page"));
    return { page: page || pages[0], el: el && !el.classList.contains("page") ? el : null };
  }
  function show(id, flash) {
    var t = pageOf(id);
    pages.forEach(function (p) { p.classList.toggle("on", p === t.page); });
    navs.forEach(function (n) { n.classList.toggle("on", n.dataset.page === t.page.id); });
    document.title = t.page.dataset.title + " — Leader docs";
    pager(t.page);
    if (t.el) {
      t.el.scrollIntoView();
      if (flash) { t.el.classList.remove("flash"); void t.el.offsetWidth; t.el.classList.add("flash"); }
    } else window.scrollTo(0, 0);
    menu(false);
    spy();
  }
  window.addEventListener("hashchange", function () { show(location.hash.slice(1), true); });

  /* previous / next guide under each page */
  function pager(page) {
    var old = $(".pager", page); if (old) old.remove();
    var i = pages.indexOf(page), html = '<nav class="pager">';
    if (i > 0) html += '<a href="#' + pages[i - 1].id + '"><small>Previous</small>' + pages[i - 1].dataset.title + "</a>";
    if (i < pages.length - 1) html += '<a class="next" href="#' + pages[i + 1].id + '"><small>Next</small>' + pages[i + 1].dataset.title + "</a>";
    page.insertAdjacentHTML("beforeend", html + "</nav>");
  }

  /* the section being read, marked in the sidebar */
  function spy() {
    var page = $(".page.on"); if (!page) return;
    var heads = $$("h2", page), cur = null;
    heads.forEach(function (h) { if (h.getBoundingClientRect().top < 120) cur = h.id; });
    $$(".nav-sub a").forEach(function (a) { a.classList.toggle("on", a.getAttribute("href") === "#" + cur); });
  }
  var ticking = false;
  window.addEventListener("scroll", function () {
    if (!ticking) { ticking = true; requestAnimationFrame(function () { ticking = false; spy(); }); }
  }, { passive: true });

  function menu(open) {
    $("#nav").classList.toggle("open", open);
    document.body.classList.toggle("menu-open", open);
    $("#menu").textContent = open ? "Close" : "Menu";
  }
  $("#menu").onclick = function () { menu(!$("#nav").classList.contains("open")); };
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") menu(false); });

  /* a Copy button on every code block */
  $$("main pre").forEach(function (pre) {
    var box = document.createElement("div"); box.className = "code";
    pre.parentNode.insertBefore(box, pre); box.appendChild(pre);
    var b = document.createElement("button"); b.className = "copy"; b.type = "button"; b.textContent = "Copy";
    b.onclick = function () {
      var text = pre.textContent, done = function () {
        b.textContent = "Copied"; b.classList.add("done");
        setTimeout(function () { b.textContent = "Copy"; b.classList.remove("done"); }, 1400);
      };
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () {});
    };
    box.appendChild(b);
  });

  /* ── search: headings, table rows (every key), list items and paragraphs ───── */
  var index = [];
  pages.forEach(function (page) {
    var title = page.dataset.title, section = title, n = 0;
    $$("h2,h3,h4,tr,li,p,blockquote", page).forEach(function (el) {
      if (el.matches("h2,h3,h4")) section = el.textContent;
      if (el.closest("thead") || el.classList.contains("crumb")) return;
      if (el.tagName === "LI" && el.querySelector("ul,ol")) return;
      var text = (el.tagName === "TR" ? $$("td", el).map(function (td) { return td.textContent; }).join("  ·  ") : el.textContent)
        .replace(/\s+/g, " ").trim();
      if (!text) return;
      if (!el.id) el.id = page.id + "--i" + (n++);
      index.push({ el: el, page: title, section: section, text: text, low: text.toLowerCase(), head: el.matches("h2,h3,h4") });
    });
  });
  var q = $("#q"), box = $("#results"), hits = [], sel = 0;
  function results(on) { box.classList.toggle("on", on); $("#scrim").classList.toggle("on", on); }
  function esc(s) { return s.replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function snippet(text, words) {
    var low = text.toLowerCase(), at = low.indexOf(words[0]), start = Math.max(0, at - 50);
    var s = (start > 0 ? "…" : "") + text.slice(start, start + 150) + (text.length > start + 150 ? "…" : "");
    return esc(s);
  }
  function search() {
    var words = q.value.toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) { results(false); return; }
    hits = index.filter(function (it) { return words.every(function (w) { return it.low.indexOf(w) >= 0; }); })
      .map(function (it) {
        var score = (it.head ? 0 : 10) + (it.low.indexOf(words[0]) === 0 ? 0 : 2) + Math.min(it.text.length / 80, 6);
        return { it: it, score: score };
      })
      .sort(function (a, b) { return a.score - b.score; }).slice(0, 40).map(function (h) { return h.it; });
    sel = 0;
    box.innerHTML = hits.length ? hits.map(function (it, i) {
      return '<a href="#' + it.el.id + '" class="' + (i === sel ? "sel" : "") + '">' + snippet(it.text, words) +
        "<small>" + esc(it.page + (it.section !== it.page ? " › " + it.section : "")) + "</small></a>";
    }).join("") : "<p>Nothing matches. Try fewer words.</p>";
    results(true);
  }
  function move(d) {
    var links = $$("a", box); if (!links.length) return;
    links[sel].classList.remove("sel"); sel = (sel + d + links.length) % links.length;
    links[sel].classList.add("sel"); links[sel].scrollIntoView({ block: "nearest" });
  }
  q.addEventListener("input", search);
  q.addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown" || (e.ctrlKey && e.key === "n")) { e.preventDefault(); move(1); }
    else if (e.key === "ArrowUp" || (e.ctrlKey && e.key === "p")) { e.preventDefault(); move(-1); }
    else if (e.key === "Enter" && hits[sel]) { e.preventDefault(); go(hits[sel].el.id); }
    else if (e.key === "Escape") { q.value = ""; results(false); q.blur(); }
  });
  box.addEventListener("click", function (e) {
    var a = e.target.closest("a"); if (!a) return;
    e.preventDefault(); go(a.getAttribute("href").slice(1));
  });
  function go(id) {
    results(false); q.blur();
    if (location.hash === "#" + id) show(id, true); else location.hash = id;
  }
  document.addEventListener("click", function (e) { if (!e.target.closest(".search")) results(false); });
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && document.activeElement !== q) { e.preventDefault(); q.focus(); q.select(); }
  });

  show(location.hash.slice(1), false);
})();
</script>
</body>
</html>
]==]

local html = TEMPLATE:gsub("@NAV@", function()
  return table.concat(nav, "\n")
end):gsub("@SECTIONS@", function()
  return table.concat(sections, "\n")
end)

if check then
  local f = io.open(OUT, "r")
  local current = f and f:read "*a" or ""
  if f then
    f:close()
  end
  if current ~= html then
    io.stderr:write "docs/docs/index.html is out of date: run scripts/gen-docs.sh\n"
    os.exit(1)
  end
  os.exit(0)
end

vim.fn.mkdir(vim.fs.dirname(OUT), "p")
local f = assert(io.open(OUT, "w"))
f:write(html)
f:close()
print(("docs/docs/index.html: %d pages, %d KB"):format(#PAGES, math.floor(#html / 1024)))
