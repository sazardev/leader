#!/usr/bin/env node
/* Publishes the brand kit: thumbnails and a manifest for the wallpapers page of the site, flat release assets (one file per
   wallpaper named <device>-<name>.png, one zip per device, the two kit zips, the video) and, only with --release, the GitHub release.

     node brand/publish.mjs                  prepare: docs/wallpapers/{manifest.json,thumbs/} + brand/out/release/
     node brand/publish.mjs --release        also create the tag and the GitHub release and upload the assets
     node brand/publish.mjs --tag brand-2    another release (default brand-1); --repo owner/name (default: origin)

   The release tag points to an ORPHAN commit (no branch, not reachable from master): `git describe --tags`, which the release
   kit (<leader>GRc) uses to find "the commits since the last tag", never sees it. Needs the rendered kit (node brand/render.mjs),
   ffmpeg with libwebp, python3 (zip) and, for --release, gh logged in as someone who can write to the repo. */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url)), ROOT = path.resolve(HERE, ".."), OUT = path.join(HERE, "out"), REL = path.join(OUT, "release");
const WEB = path.join(ROOT, "docs", "wallpapers");
const argv = process.argv.slice(2), opt = (n, d) => { const i = argv.indexOf("--" + n); return i < 0 ? d : (argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : true); };
const TAG = opt("tag", "brand-1"), DO_RELEASE = !!opt("release", false);
const sh = (cmd, args, o = {}) => { const r = spawnSync(cmd, args, { encoding: "utf8", ...o }); if (r.status !== 0 && !o.soft) throw new Error(`${cmd} ${args.slice(0, 4).join(" ")} failed:\n${(r.stderr || "").slice(-1500)}`); return (r.stdout || "").trim(); };
const REPO = opt("repo", null) || sh("git", ["-C", ROOT, "remote", "get-url", "origin"]).replace(/^.*github\.com[/:]/, "").replace(/\.git$/, "");
const COPY = new Function(fs.readFileSync(path.join(HERE, "copy.js"), "utf8") + "; return COPY;")();

/* ── what each wallpaper is ─────────────────────────────────────────────────────────────────── */
const DEVICES = { phone: { label: "Phone", dir: "phone" }, desktop: { label: "Desktop", dir: "desktop" }, ultrawide: { label: "Ultrawide", dir: "ultrawide" }, uhd: { label: "4K", dir: "4k" } };
const PALNAME = { gruvbox: "Gruvbox", "gruvbox-light": "Gruvbox light", yellow: "Yellow", green: "Green", aqua: "Aqua", "tokyo-night": "Tokyo Night", "catppuccin-mocha": "Catppuccin Mocha", "catppuccin-latte": "Catppuccin Latte",
  "rose-pine": "Rosé Pine", nord: "Nord", kanagawa: "Kanagawa", everforest: "Everforest", dracula: "Dracula", "one-dark": "One Dark", "solarized-light": "Solarized light", "solarized-dark": "Solarized dark" };
const DESIGN = { ghost: "The N", grid: "Dot grid", braille: "Braille", keys: "Keyboard", dots: "Dot-matrix words", minimal: "Minimal", editor: "Editor", phrase: "Phrases", lang: "Languages", term: "Terms", cheat: "Key cheat sheets" };
const LIGHT = new Set(["gruvbox-light", "catppuccin-latte", "solarized-light"]), COLOR = new Set(["yellow", "green", "aqua"]);
const FORMAT_DEVICE = { d: "desktop", p: "phone", u: "ultrawide", k: "uhd" };
const palette = (e) => e.pal || (e.theme === "light" ? "gruvbox-light" : e.bg && e.bg !== "deep" && e.bg !== "bg" ? e.bg : "gruvbox");
const cap = (s) => s.replace(/^(\w)/, (m) => m.toUpperCase());

const entries = [];
for (const w of COPY.wallpapers) entries.push({ file: w.id, design: w.design, e: w, title: w.lines ? w.lines.join(" ") : cap(DESIGN[w.design] || w.design) });
for (const w of COPY.wpPhrases) entries.push({ file: "phrase-" + w.id, design: "phrase", e: w, title: w.lines.join(" ") });
for (const w of COPY.wpLangs) entries.push({ file: "lang-" + w.id, design: "lang", e: w, title: w.name });
for (const w of COPY.wpTerms) entries.push({ file: "term-" + w.id, design: "term", e: w, title: w.term });
for (const w of COPY.wpCheats) entries.push({ file: "cheat-" + w.id, design: "cheat", e: w, title: w.title + " keys" });

const KB = (f) => Math.round(fs.statSync(f).size / 1024);
fs.mkdirSync(WEB, { recursive: true }); fs.rmSync(REL, { recursive: true, force: true }); fs.mkdirSync(REL, { recursive: true });
const thumbs = path.join(WEB, "thumbs"); fs.rmSync(thumbs, { recursive: true, force: true });
const items = [], counts = {};
let made = 0;
for (const en of entries) {
  const pal = palette(en.e), tone = LIGHT.has(pal) ? "light" : COLOR.has(pal) ? "color" : "dark", files = {};
  for (const f of en.e.f) {
    const dev = FORMAT_DEVICE[f], src = path.join(OUT, "wallpapers", DEVICES[dev].dir, en.file + ".png");
    if (!fs.existsSync(src)) throw new Error("missing " + path.relative(ROOT, src) + ": run `node brand/render.mjs` first");
    const F = COPY.wallpaperFormats[f], asset = `${dev === "uhd" ? "4k" : dev}-${en.file}.png`, tw = dev === "phone" ? 300 : 640, th = Math.round(tw * F.h / F.w);
    const thumb = `thumbs/${dev}/${en.file}.webp`; fs.mkdirSync(path.join(WEB, "thumbs", dev), { recursive: true });
    sh("ffmpeg", ["-y", "-v", "error", "-i", src, "-vf", `scale=${tw}:${th}:flags=lanczos`, "-c:v", "libwebp", "-quality", "74", path.join(WEB, thumb)]);
    fs.copyFileSync(src, path.join(REL, asset)); made++;
    files[dev] = { asset, thumb, w: F.w, h: F.h, kb: KB(src), tw, th }; counts[dev] = (counts[dev] || 0) + 1;
  }
  items.push({ id: en.file, title: en.title, design: en.design, palette: pal, tone, files });
}
process.stdout.write(`  ${items.length} wallpapers, ${made} files, thumbnails in docs/wallpapers/thumbs\n`);

/* ── zips: one per device, and the rest of the kit ──────────────────────────────────────────── */
function zip(name, roots, rename) {
  const stage = fs.mkdtempSync(path.join(OUT, ".stage-")), top = path.join(stage, name.replace(/\.zip$/, ""));
  for (const [from, to] of roots) { fs.mkdirSync(path.dirname(path.join(top, to)), { recursive: true }); fs.cpSync(path.join(OUT, from), path.join(top, to), { recursive: true }); }
  sh("python3", ["-m", "zipfile", "-c", path.join(REL, name), path.basename(top)], { cwd: stage });
  fs.rmSync(stage, { recursive: true, force: true });
}
const devices = Object.entries(DEVICES).map(([id, d]) => {
  const name = `leader-wallpapers-${id === "uhd" ? "4k" : id}.zip`;
  zip(name, [[`wallpapers/${d.dir}`, "."]]);
  const f = COPY.wallpaperFormats[{ phone: "p", desktop: "d", ultrawide: "u", uhd: "k" }[id]];
  return { id, label: d.label, size: `${f.w}×${f.h}`, w: f.w, h: f.h, count: counts[id] || 0, zip: name, zipMB: +(fs.statSync(path.join(REL, name)).size / 1e6).toFixed(1) };
});
zip("leader-brand-kit-1-landscape-square-logo.zip", ["landscape", "link-preview", "square", "banners", "social", "logo", "USAGE.md", "catalog-01-landscape.png", "catalog-05-banners-social.png", "catalog-06-logo.png"].map((x) => [x, x]));
zip("leader-brand-kit-2-portrait-story-carousel.zip", ["portrait", "story", "pinterest", "carousel", "USAGE.md", "catalog-02-square-portrait.png", "catalog-03-story-pinterest.png", "catalog-04-carousels.png"].map((x) => [x, x]));
fs.copyFileSync(path.join(OUT, "USAGE.md"), path.join(REL, "leader-brand-USAGE.md"));
const video = path.join(ROOT, "video", "out", "leader.mp4"); if (fs.existsSync(video)) fs.copyFileSync(video, path.join(REL, "leader-video-1080p.mp4"));

/* ── the manifest the wallpapers page reads ─────────────────────────────────────────────────── */
const designs = Object.keys(DESIGN).filter((d) => items.some((i) => i.design === d)).map((id) => ({ id, label: DESIGN[id], count: items.filter((i) => i.design === id).length }));
const pals = [...new Set(items.map((i) => i.palette))].map((id) => ({ id, label: PALNAME[id] || cap(id), tone: LIGHT.has(id) ? "light" : COLOR.has(id) ? "color" : "dark", count: items.filter((i) => i.palette === id).length }));
const manifest = { tag: TAG, repo: REPO, base: `https://github.com/${REPO}/releases/download/${TAG}/`, devices, designs, palettes: pals, items };
fs.writeFileSync(path.join(WEB, "manifest.json"), JSON.stringify(manifest) + "\n");
const assets = fs.readdirSync(REL).sort();
console.log(`  release assets: ${assets.length} files, ${(assets.reduce((n, f) => n + fs.statSync(path.join(REL, f)).size, 0) / 1e6).toFixed(0)} MB (brand/out/release)`);
console.log(`  manifest: docs/wallpapers/manifest.json (${(fs.statSync(path.join(WEB, "manifest.json")).size / 1024).toFixed(0)} KB)`);
if (!DO_RELEASE) { console.log("  (prepared only; add --release to publish)"); process.exit(0); }

/* ── the release ────────────────────────────────────────────────────────────────────────────── */
const src = sh("git", ["-C", ROOT, "rev-parse", "--short", "HEAD"]);
if (sh("git", ["-C", ROOT, "tag", "--list", TAG])) throw new Error(`tag ${TAG} already exists: pick another with --tag`);
const tree = sh("git", ["-C", ROOT, "hash-object", "-t", "tree", "-w", "--stdin"], { input: "" });
const commit = sh("git", ["-C", ROOT, "commit-tree", tree, "-m", `Brand assets (${TAG}), built from ${src}`]);
sh("git", ["-C", ROOT, "tag", TAG, commit]);
sh("git", ["-C", ROOT, "-c", "credential.helper=!gh auth git-credential", "push", "origin", `refs/tags/${TAG}`]);
const sizes = Object.fromEntries(devices.map((d) => [d.id, d]));
const notes = `Wallpapers, images and the video of Leader's brand kit, built from commit ${src}.

**Wallpapers**: ${items.length} designs in ${Object.values(counts).reduce((a, b) => a + b, 0)} files. Pick one by device on https://sazardev.github.io/leader/wallpapers/ or download a whole device:
${devices.map((d) => `- \`${d.zip}\`: ${d.label} ${d.size}, ${d.count} images (${d.zipMB} MB)`).join("\n")}

**Brand kit**: \`leader-brand-kit-1-landscape-square-logo.zip\` and \`leader-brand-kit-2-portrait-story-carousel.zip\` (every post size, carousels, banners, avatars, the logo and \`logo/svg\`), and \`leader-brand-USAGE.md\` (what goes where, with the text to post).

**Video**: \`leader-video-1080p.mp4\`.

Single wallpapers are named \`<device>-<design>.png\` (\`phone-\`, \`desktop-\`, \`ultrawide-\`, \`4k-\`). This release is not a version of the config: its tag points to a commit outside master.`;
const notesFile = path.join(OUT, ".release-notes.md"); fs.writeFileSync(notesFile, notes);
sh("gh", ["release", "create", TAG, "--repo", REPO, "--title", `Leader brand assets (${TAG})`, "--notes-file", notesFile, "--latest=false", "--verify-tag"]);
const files = assets.map((f) => path.join(REL, f));
for (let i = 0; i < files.length; i += 30) { sh("gh", ["release", "upload", TAG, "--repo", REPO, "--clobber", ...files.slice(i, i + 30)]); process.stdout.write(`\r  uploaded ${Math.min(i + 30, files.length)}/${files.length}`); }
console.log(`\n  https://github.com/${REPO}/releases/tag/${TAG}`);
