/* Shared by video/render.mjs and brand/render.mjs: a static server over the repo root (pages read ../docs/index.html and
   ../docs/fonts), Chromium driven over the DevTools protocol (Node's built-in WebSocket) and a page handle.
   No dependencies: Chromium (or Chrome) must be installed. */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".woff2": "font/woff2", ".json": "application/json", ".png": "image/png", ".svg": "image/svg+xml" };
export function serve() {
  return new Promise((resolve) => {
    const srv = http.createServer((req, res) => {
      let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
      if (p.endsWith("/")) p += "index.html";
      const file = path.resolve(ROOT, "." + p);
      if (!file.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
      fs.readFile(file, (err, buf) => {
        if (err) { res.writeHead(404); return res.end("not found"); }
        res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream", "cache-control": "no-store" });
        res.end(buf);
      });
    });
    srv.listen(0, "127.0.0.1", () => resolve(srv));
  });
}

/* ── a tiny DevTools protocol client ─────────────────────────────────────────────────────────── */
function findChromium(chromium) {
  const names = [chromium, "chromium", "chromium-browser", "google-chrome", "google-chrome-stable"].filter(Boolean);
  for (const n of names) {
    if (n.includes("/") && fs.existsSync(n)) return n;
    for (const dir of (process.env.PATH || "").split(path.delimiter)) {
      const f = path.join(dir, n);
      if (fs.existsSync(f)) return f;
    }
  }
  throw new Error("Chromium not found: install it or pass --chromium /path/to/chrome");
}
export async function launch(chromium) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "leader-chromium-"));
  const proc = spawn(findChromium(chromium || process.env.CHROMIUM), ["--headless=new", "--remote-debugging-port=0", "--user-data-dir=" + profile, "--no-first-run",
    "--no-default-browser-check", "--hide-scrollbars", "--mute-audio", "--disable-gpu", "--font-render-hinting=none", "about:blank"],
    { stdio: ["ignore", "ignore", "pipe"] });
  const wsUrl = await new Promise((resolve, reject) => {
    let buf = "";
    proc.stderr.on("data", (d) => { buf += d; const m = buf.match(/DevTools listening on (ws:\/\/\S+)/); if (m) resolve(m[1]); });
    proc.on("exit", (c) => reject(new Error("Chromium exited (" + c + "):\n" + buf)));
    setTimeout(() => reject(new Error("Chromium did not start:\n" + buf)), 20000);
  });
  const ws = new WebSocket(wsUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const pending = new Map();
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.j(new Error(m.error.message)) : p.r(m.result); }
  };
  const send = (method, params = {}, sessionId) => new Promise((r, j) => { const i = ++id; pending.set(i, { r, j }); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });
  const close = () => new Promise((r) => {
    try { ws.close(); } catch {}
    const done = () => { try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 8, retryDelay: 150 }); } catch {} r(); };   /* cleanup must never fail a render */
    if (proc.exitCode !== null) return done();
    proc.once("exit", done); proc.kill();
    setTimeout(() => { proc.kill("SIGKILL"); }, 3000);
  });
  return { send, close };
}
/* opens `url` at w×h (device pixel ratio `scale`) and waits until `ready` (a JS expression) is truthy; a string result is an error */
export async function openPage(b, url, w, h, { scale = 1, ready = "true", transparent = false } = {}) {
  const { targetId } = await b.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await b.send("Target.attachToTarget", { targetId, flatten: true });
  const s = (m, p) => b.send(m, p, sessionId);
  await s("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: scale, mobile: false });
  if (transparent) await s("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });   /* PNGs with alpha */
  await s("Page.enable"); await s("Runtime.enable");
  await s("Page.navigate", { url });
  const evalJs = async (expr) => {
    const r = await s("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error("page: " + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
    return r.result.value;
  };
  for (let i = 0; i < 300; i++) {
    const st = await evalJs(ready).catch(() => "");
    if (st === "ready" || st === true) break;
    if (st) throw new Error(st);
    await new Promise((r) => setTimeout(r, 100));
    if (i === 299) throw new Error("the page never got ready");
  }
  const shot = async (clip) => Buffer.from((await s("Page.captureScreenshot", { format: "png", optimizeForSpeed: true, captureBeyondViewport: false, ...(clip ? { clip: { ...clip, scale: 1 } } : {}) })).data, "base64");
  /* resize without reloading (the page re-lays itself out on its own `resize` handling, or the caller reloads) */
  const resize = (w2, h2) => s("Emulation.setDeviceMetricsOverride", { width: w2, height: h2, deviceScaleFactor: scale, mobile: false });
  return { evalJs, shot, resize, navigate: (u) => s("Page.navigate", { url: u }) };
}

