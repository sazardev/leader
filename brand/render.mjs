#!/usr/bin/env node
/* Renders the whole brand kit into brand/out/: every image at its exact pixel size, the logo as SVG, the favicon as .ico,
   contact sheets per folder and USAGE.md (which image goes where, with the text to post). Needs Chromium and ffmpeg (for
   the .ico only); no npm packages.

     node brand/shots.mjs                  first: real screenshots of the editor (brand/shots/*.png)
     node brand/render.mjs                 then: everything
     node brand/render.mjs --only square   one folder (or any `dir/name` substring: --only 20ms, --only carousel/tips)
     node brand/render.mjs --list          print the catalog
     node brand/render.mjs --no-sheets     skip the contact sheets
   Copy: brand/copy.js · templates: brand/brand.js · the mark and the dot font: brand/dots.js. */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { serve, launch, openPage } from "../video/cdp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, "out");
const require = createRequire(import.meta.url);
const argv = process.argv.slice(2), opt = (n) => { const i = argv.indexOf("--" + n); return i < 0 ? null : (argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : true); };
const only = opt("only"), listOnly = opt("list"), noSheets = opt("no-sheets");

const DOTS = require("./dots.js");
const srv = await serve(), b = await launch(process.env.CHROMIUM);
const base = "http://127.0.0.1:" + srv.address().port + "/brand/";
try {
  const page = await openPage(b, base, 1920, 1080, { scale: 1, transparent: true, ready: "window.__brand ? (window.__brand.error || 'ready') : ''" });
  const cat = await page.evalJs("__brand.catalog");
  if (listOnly) { for (const e of cat) console.log(`${e.dir}/${e.name}  ${e.w}×${e.h}`); process.exit(0); }

  const todo = cat.filter((e) => !only || (e.dir + "/" + e.name).includes(only));
  fs.mkdirSync(OUT, { recursive: true });
  const t0 = Date.now(), warnings = [];
  for (const [n, e] of todo.entries()) {
    await page.resize(e.w, e.h);
    const r = await page.evalJs(`__brand.draw(${e.i})`);
    if (r.warn && r.warn.length) warnings.push(`${e.dir}/${e.name}: ${r.warn.join("; ")}`);
    const file = path.join(OUT, e.dir, e.name + ".png");
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, await page.shot());
    if (n % 10 === 0 || n === todo.length - 1) process.stdout.write(`\r  ${n + 1}/${todo.length} · ${e.dir}/${e.name}                    `);
  }
  console.log(`\n  ${todo.length} images in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  if (warnings.length) { console.log(`  ${warnings.length} layout warnings:`); for (const w of warnings) console.log("   · " + w); }

  if (!only) {
    /* the mark as vector, in the palette's colors */
    const svgDir = path.join(OUT, "logo", "svg"); fs.mkdirSync(svgDir, { recursive: true });
    const colors = { green: "#b8bb26", cream: "#ebdbb2", ink: "#1d2021", yellow: "#fabd2f" };
    for (const [name, c] of Object.entries(colors)) {
      fs.writeFileSync(path.join(svgDir, `mark-${name}.svg`), DOTS.svg(DOTS.mark({ pattern: "heavyN", on: c, off: null, r: 4, gap: 3 }), { pad: 8, label: "Leader" }) + "\n");
    }
    fs.writeFileSync(path.join(svgDir, "mark-green-grid.svg"), DOTS.svg(DOTS.mark({ pattern: "heavyN", on: colors.green, off: colors.green, r: 4, gap: 3, offOpacity: 0.16, offScale: 0.5 }), { pad: 8, label: "Leader" }) + "\n");
    fs.writeFileSync(path.join(svgDir, "favicon.svg"), DOTS.svg(DOTS.mark({ pattern: "classicN", on: colors.green, off: null, r: 4.1 }), { pad: 7, bg: "#202020", label: "Leader" }) + "\n");
    fs.writeFileSync(path.join(svgDir, "wordmark-dots-green.svg"), DOTS.svg(DOTS.text("LEADER", { pitch: 10, on: colors.green, off: colors.green, offOpacity: 0.16, offScale: 0.5, spacing: 1.6 }), { pad: 8, label: "Leader" }) + "\n");
    /* favicon.ico from the 16/32/48 PNGs */
    const fav = (n) => path.join(OUT, "logo", "favicon", `favicon-${n}.png`);
    const ico = spawnSync("ffmpeg", ["-y", "-hide_banner", "-loglevel", "error", "-i", fav(16), "-i", fav(32), "-i", fav(48), "-map", "0", "-map", "1", "-map", "2", path.join(OUT, "logo", "favicon", "favicon.ico")]);
    if (ico.status !== 0) console.warn("  (favicon.ico skipped: ffmpeg could not write it)");
  }

  if (!only && !noSheets) {
    const groups = [
      ["01-landscape", "Landscape and link previews", "16:9 for video and posts, 1.91:1 for link previews.", ["landscape", "link-preview"], { w: 596, h: 336 }],
      ["02-square-portrait", "Square and portrait", "1:1 and 4:5, the Instagram, LinkedIn and Facebook feed.", ["square", "portrait"], { w: 300, h: 375 }],
      ["03-story-pinterest", "Stories and Pinterest", "9:16 for Stories, Reels, Shorts and TikTok; 2:3 for Pinterest.", ["story", "pinterest"], { w: 230, h: 400 }],
      ["04-carousels", "Carousels", "Instagram and LinkedIn, 4:5. Slide order is the file order.", ["carousel/launch", "carousel/agent", "carousel/tips"], { w: 250, h: 313 }],
      ["05-banners-social", "Banners, covers and profile pictures", "Headers for each network and avatars.", ["banners", "social"], { w: 700, h: 330 }],
      ["06-logo", "Logo", "The mark, lockups, the dot-matrix wordmark, favicons and the brand board.", ["logo", "logo/favicon"], { w: 360, h: 270 }],
      ["07-wallpapers-desktop", "Wallpapers: desktop", "Designs with and without words, in gruvbox and the terminal palettes (Tokyo Night, Nord, Rosé Pine, Dracula…), dark and light.", ["wallpapers/desktop"], { w: 350, h: 197 }],
      ["08-wallpapers-ultrawide-4k", "Wallpapers: ultrawide and 4K", "The same collection for 21:9 and 4K screens.", ["wallpapers/ultrawide", "wallpapers/4k"], { w: 560, h: 235 }],
      ["09-wallpapers-phone", "Wallpapers: phone", "The collection for phones (1170×2532).", ["wallpapers/phone"], { w: 150, h: 325 }]
    ];
    for (const [file, title, blurb, dirs, cell] of groups) {
      const h = await page.evalJs(`__brand.sheet(${JSON.stringify(title)}, ${JSON.stringify(blurb)}, ${JSON.stringify(dirs)}, ${JSON.stringify(cell)})`);
      await page.resize(1920, Math.min(h, 16000));
      await page.evalJs("document.fonts.ready.then(() => true)");
      fs.writeFileSync(path.join(OUT, `catalog-${file}.png`), await page.shot());
    }
    console.log("  contact sheets: out/catalog-*.png");
  }

  if (!only) fs.writeFileSync(path.join(OUT, "USAGE.md"), await usage(cat));
  if (!only) console.log("  usage guide: out/USAGE.md");
} finally { await b.close(); srv.close(); }

/* USAGE.md: sizes, then every piece with its files and the text to post, then the rest */
async function usage(cat) {
  const copy = JSON.parse(await (async () => {
    /* copy.js is a browser global: read it by evaluating it in a function scope */
    const src = fs.readFileSync(path.join(HERE, "copy.js"), "utf8");
    return JSON.stringify(new Function(src + "; return COPY;")());
  })());
  const L = [];
  L.push("# Leader brand kit: what goes where", "", "Generated by `node brand/render.mjs`. Every image is exported at the exact size of its platform; copy and captions live in `brand/copy.js`.", "");
  L.push("## Sizes", "", "| Folder | Size | Use |", "|---|---|---|");
  for (const f of Object.values(copy.formats)) L.push(`| \`${f.dir}/\` | ${f.w}×${f.h} | ${f.use} |`);
  L.push("| `carousel/` | 1080×1350 | Instagram and LinkedIn carousels (slides numbered in order) |", "| `banners/` | per platform | X, LinkedIn, Facebook, YouTube, GitHub README and social preview |", "| `wallpapers/` | desktop, phone, ultrawide, 4K | Wallpaper collection (see below) |", "| `social/` | 800×800 | Profile pictures |", "| `logo/` | various | Mark, lockups, wordmark, favicons, brand board (+ `logo/svg/` vector) |", "");
  L.push("## Posts: one piece, five sizes", "", "Each piece exists in every size, so the same message can go to every network. `Caption` is the text to post with it.", "");
  for (const p of copy.pieces) {
    const files = cat.filter((e) => e.id === p.id && !e.dir.startsWith("carousel"));
    L.push(`### ${p.id}: ${(p.lines || [p.num + " " + p.unit]).join(" ")}`, "", `Files: ${files.map((e) => `\`${e.dir}/${e.name}.png\``).join(" · ")}`, "", `Caption: ${p.caption}`, "");
  }
  L.push("## Carousels", "", "Post the slides in file order.", "");
  for (const s of ["launch", "agent", "tips"]) {
    const sl = cat.filter((e) => e.dir === "carousel/" + s);
    L.push(`- \`carousel/${s}/\` (${sl.length} slides): ${sl[0].caption.replace(/\s+#.*$/, "")}`);
  }
  L.push("", "## Banners and profile pictures", "");
  for (const e of cat.filter((x) => ["banners", "social"].includes(x.dir))) L.push(`- \`${e.dir}/${e.name}.png\` (${e.w}×${e.h}): ${e.use}`);
  L.push("", "## Wallpapers", "", "A collection to give away: designs with and without words, each in several palettes (gruvbox, yellow, green, aqua, the terminal palettes of the landing's picker, and light).", "");
  for (const [k, f] of Object.entries(copy.wallpaperFormats)) L.push(`- \`${f.dir}/\` (${f.w}×${f.h}, ${cat.filter((e) => e.dir === f.dir).length} images): ${f.use}`);
  L.push("", "| Design | What it is |", "|---|---|", "| `ghost-*` | The N as a large watermark, with \"Press Space.\" |", "| `grid-*` | A field of dots where the lit ones draw a giant N (in every palette) |", "| `braille-*` | \"leader space\" written in real braille, row after row |", "| `keys-*` | The keyboard of \"Press Space.\", the Agent key lit |", "| `dots-*` | Words in a dot-matrix display: PRESS SPACE, LEADER, 20MS, LGTM, SHIP IT, TODO, HELLO WORLD, 0 ERRORS, NULL, 404… |", "| `phrase-*` | One big, clear phrase: programmer maxims (Ship it. Read the error. Commit early. Commit small.) and Leader's own lines |", "| `lang-*` | A programming language: its name, a snippet in the editor's colors, the tools Leader brings for it and its menu key (Go, Rust, Python, TypeScript, Dart, Swift, Java, Kotlin, Lua, SQL, HTML, CSS, Markdown) |", "| `term-*` | A glossary entry (refactor, idempotent, race condition, cache, lint, diff…) and, when there is one, the Leader key that helps |", "| `cheat-*` | A key cheat sheet taken from the real menus: Agent, Find, Git, Go, Diagnostics, Files, Settings |", "| `minimal-*` | The mark and almost nothing else (good under desktop icons) |", "| `editor-*` | The real editor, large, on the palette's own color (desktop and ultrawide) |", "",
    "To set one: Windows, right-click the image → Set as desktop background. macOS, System Settings → Wallpaper → Add Photo. GNOME, Settings → Background. KDE, right-click the desktop → Configure Desktop and Wallpaper. iPhone, Photos → Share → Use as Wallpaper. Android, Gallery → Set as wallpaper.", "");
  L.push("", "## Logo", "", "- `logo/mark-*.png`: the N on a solid color. `logo/mark-*-transparent.png`: one color, any background.", "- `logo/lockup-*`: mark + name; `logo/wordmark-dots-*`: LEADER in the dot-matrix font.", "- `logo/svg/`: the mark as vector. `logo/favicon/`: PNG sizes and `favicon.ico`.", "- `logo/brand-board.png`: the identity on one page.", "");
  L.push("## Suggested rollout", "", "1. Launch day: `carousel/launch/` on Instagram and LinkedIn; `link-preview/for-working.png` as the card of the GitHub link; `landscape/for-working.png` on X.",
    "2. Then one piece a day, alternating a number (`20ms`, `zero-tokens`, `one-yes`) with a screenshot piece (`red-line`, `type-less`, `commits`).", "3. Weekly: a tips slide set (`carousel/tips/`) or the agent carousel.", "4. Always: `one-command` and `press-space` as the closing image of any thread.", "", `Hashtags: ${copy.hashtags}`, "");
  return L.join("\n");
}
