#!/usr/bin/env node
/* Real screenshots of the editor for the brand kit: the video's page, paused on a moment of the story, captured alone at
   2240×1260 (the editor is 1120×630 CSS px at 2×). Nothing is faked: it is the same mock the landing and the video show.

     node brand/shots.mjs                  every shot in SHOTS → brand/shots/<id>.png
     node brand/shots.mjs --probe 12,16.4  numbered candidates at those seconds → brand/shots/_probe/ (to pick moments)
     node brand/shots.mjs --only fix,lens  just those ids

   A moment is "scene+offset" (seconds into a scene of video/story.js) or plain seconds. A shot may use a terminal palette. */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { serve, launch, openPage } from "../video/cdp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const SHOTS = [
  { id: "complete-iferr",     at: "complete+3.4" },
  { id: "complete-missing",   at: "complete+8.2" },
  { id: "implement",          at: "implement+6.2" },
  { id: "docs-explain",       at: "docs+10.0" },
  { id: "fix",                at: "fix+4.3" },
  { id: "lens-finding",       at: "lens+4.6" },
  { id: "lens-fix",           at: "lens+8.6" },
  { id: "convert",            at: "convert+6.1" },
  { id: "tests",              at: "tests+6.3" },
  { id: "fixall-queue",       at: "fixall+8.1" },
  { id: "fixall-confirm",     at: "fixall+4.4" },
  { id: "build-plan",         at: "kit+10.0" },
  { id: "build-run",          at: "kit+13.6" },
  { id: "build-done",         at: "kit+17.0" },
  { id: "commit",             at: "commit+5.6" },
  { id: "review",             at: "review+5.4" },
  { id: "release",            at: "release+3.8" },
  { id: "usage",              at: "usage+3.2" },
  { id: "whichkey",           at: "implement+2.0" },
  /* the same moment in six terminal palettes (the "your colors" collage) */
  ...["tokyo-night", "catppuccin-mocha", "rose-pine", "nord", "kanagawa", "catppuccin-latte", "dracula", "everforest"].map((t) => ({ id: "theme-" + t, at: "themes+0.4", theme: "t:" + t, scene: "themes" }))
];

const argv = process.argv.slice(2), opt = (n) => { const i = argv.indexOf("--" + n); return i < 0 ? null : argv[i + 1]; };
const only = (opt("only") || "").split(",").filter(Boolean), probe = opt("probe");

const srv = await serve(), b = await launch();
const base = "http://127.0.0.1:" + srv.address().port + "/video/";
try {
  const pages = new Map();                                              /* one page per theme: the palette is read at load */
  async function page(theme) {
    if (!pages.has(theme || "")) {
      const q = new URLSearchParams({ render: "1", shot: "1" }); if (theme) q.set("theme", theme);
      pages.set(theme || "", await openPage(b, base + "?" + q, 1920, 1080, { scale: 2, ready: "window.__video ? (window.__video.error || 'ready') : ''" }));
    }
    return pages.get(theme || "");
  }
  const p0 = await page(null);
  const scenes = await p0.evalJs("__video.scenes");
  const when = (at) => { const m = String(at).match(/^([a-z0-9-]+)\+([\d.]+)$/); if (!m) return Number(at) * 1000; const sc = scenes.find((s) => s.id === m[1]); if (!sc) throw new Error("no scene " + m[1]); return sc.from + Number(m[2]) * 1000; };
  async function grab(pg, ms, file) {
    await pg.evalJs(`(() => { __video.seek(${ms}); const f = document.getElementById("frame"); f.style.transform = "translate(0px,0px) scale(1)"; })()`);
    fs.writeFileSync(file, await pg.shot({ x: 0, y: 0, width: 1120, height: 630 }));
  }
  if (probe) {
    const dir = path.join(HERE, "shots", "_probe"); fs.mkdirSync(dir, { recursive: true });
    for (const t of probe.split(",")) { await grab(p0, Number(t) * 1000, path.join(dir, "t" + t + ".png")); console.log(path.join(dir, "t" + t + ".png")); }
  } else {
    fs.mkdirSync(path.join(HERE, "shots"), { recursive: true });
    for (const s of SHOTS) {
      if (only.length && !only.includes(s.id)) continue;
      const file = path.join(HERE, "shots", s.id + ".png");
      await grab(await page(s.theme), when(s.at), file); console.log(file);
    }
  }
} finally { await b.close(); srv.close(); }
