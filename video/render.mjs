#!/usr/bin/env node
/* Renders video/index.html frame by frame into an MP4. Zero dependencies: a static server (node:http), Chromium driven
   over the DevTools protocol (Node's built-in WebSocket) and ffmpeg reading the frames from a pipe.

   Every frame is a pure function of time: the page exposes window.__video.seek(ms), nothing animates on its own, so the
   output is identical on every run and does not depend on how fast the machine is.

     node video/render.mjs                       full video → video/out/leader.mp4
     node video/render.mjs --serve               preview in a browser (prints the URL; Space plays, ←/→ seek)
     node video/render.mjs --still 41.5          one PNG at 41.5 s → video/out/still-41.5.png (--stills 2,8,12 for several)
     node video/render.mjs --scene agent         only one scene (by id), handy while editing the story
     node video/render.mjs --fps 60 --scale 2    60 fps, 3840×2160
     node video/render.mjs --music track.mp3     use a music file instead of the generated score (keys and effects stay)
     node video/render.mjs --remux               only redo the sound on the last render (seconds, not minutes)
     node video/render.mjs --audio-only          write the soundtrack to video/out/soundtrack.wav (the preview plays it)
     node video/render.mjs --no-audio            a silent video
     node video/render.mjs --theme t:tokyo-night render with a terminal palette instead of gruvbox (ids as on the landing)
*/
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { mix, writeWav } from "./audio.mjs";
import { serve, launch as launchChromium, openPage as openPageCdp } from "./cdp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "..");

/* ── options ─────────────────────────────────────────────────────────────────────────────────── */
const argv = process.argv.slice(2);
function opt(name, dflt) {
  const i = argv.indexOf("--" + name);
  if (i < 0) return dflt;
  const v = argv[i + 1];
  return v === undefined || v.startsWith("--") ? true : v;
}
const O = {
  serve: opt("serve", false),
  still: opt("still", null),
  scene: opt("scene", null),
  fps: Number(opt("fps", 30)),
  scale: Number(opt("scale", 1)),
  out: opt("out", null),
  music: opt("music", opt("audio", null)),
  noAudio: opt("no-audio", false),
  remux: opt("remux", false),
  audioOnly: opt("audio-only", false),
  theme: opt("theme", null),
  crf: Number(opt("crf", 16)),
  chromium: opt("chromium", process.env.CHROMIUM || null),
  eval: opt("eval", null),
  stills: opt("stills", null),
};

/* the server, Chromium and page handle are shared with brand/render.mjs */
/* ── sound: mix the cues into a WAV, then loudness-normalize (two-pass EBU R128) while muxing ── */
async function soundtrack(info) {
  const t0 = Date.now();
  const inter = mix({ cues: info.cues, scenes: info.scenes, from: info.from || 0, to: info.duration, audio: info.audio || {}, root: HERE, musicFile: O.music || null });
  const wav = path.join(HERE, "out", ".mix-" + process.pid + ".wav");
  writeWav(wav, inter);
  process.stdout.write(" mixed in " + ((Date.now() - t0) / 1000).toFixed(1) + "s");
  return wav;
}
function run(cmd, args) {
  return new Promise((r, j) => { const p = spawn(cmd, args, { stdio: ["ignore", "ignore", "pipe"] }); let err = ""; p.stderr.on("data", (d) => (err += d)); p.on("exit", (c) => (c === 0 ? r(err) : j(new Error(cmd + " failed:\n" + err.slice(-2000))))); });
}
async function mux(video, wav, out) {
  const target = "I=-14:TP=-1.5:LRA=11";                       /* streaming loudness (YouTube, X, LinkedIn normalize to about -14) */
  const m = JSON.parse((await run("ffmpeg", ["-hide_banner", "-i", wav, "-af", "loudnorm=" + target + ":print_format=json", "-f", "null", "-"])).match(/\{[\s\S]*\}/)[0]);
  const af = `loudnorm=${target}:measured_I=${m.input_i}:measured_TP=${m.input_tp}:measured_LRA=${m.input_lra}:measured_thresh=${m.input_thresh}:offset=${m.target_offset}:linear=true,aresample=48000`;
  fs.copyFileSync(wav, path.join(HERE, "out", "soundtrack.wav"));   /* the preview plays this one */
  await run("ffmpeg", ["-y", "-hide_banner", "-i", video, "-i", wav, "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-af", af, "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart", out]);
  fs.rmSync(wav, { force: true });
}

/* ── main ────────────────────────────────────────────────────────────────────────────────────── */
const srv = await serve();
const base = "http://127.0.0.1:" + srv.address().port + "/video/";
const query = (extra) => { const q = new URLSearchParams(extra); if (O.theme) q.set("theme", O.theme); if (O.scene) q.set("scene", O.scene); return base + "?" + q; };

if (O.serve) {
  console.log("preview: " + query({}));
  console.log("Space play/pause · ←/→ 1 s · Shift+←/→ scene · Home start · Ctrl-C stops the server");
} else {
  const b = await launchChromium(O.chromium);
  try {
    const page = await openPageCdp(b, query({ render: "1" }), 1920, 1080, { scale: O.scale,
      ready: "window.__video ? (window.__video.error || 'ready') : ''" });      /* the page sets __video once fonts and the landing's data are in */
    const info = await page.evalJs("({ from: __video.from, duration: __video.duration, scenes: __video.scenes, cues: __video.cues, audio: __video.audio })");
    fs.mkdirSync(path.join(HERE, "out"), { recursive: true });

    const outFile = O.out || path.join(HERE, "out", O.scene ? "scene-" + O.scene + ".mp4" : "leader.mp4");
    const silent = outFile.replace(/\.mp4$/, ".silent.mp4");
    if (O.audioOnly || O.remux) {
      const wav = await soundtrack(info);
      if (O.remux) { if (!fs.existsSync(silent)) throw new Error("no " + silent + ": render once first"); await mux(silent, wav, outFile); console.log(outFile); }
      else { fs.copyFileSync(wav, path.join(HERE, "out", "soundtrack.wav")); fs.rmSync(wav, { force: true }); console.log(path.join(HERE, "out", "soundtrack.wav")); }
    } else if (O.eval) {                                            /* debugging: print what an expression returns in the page */
      console.log(JSON.stringify(await page.evalJs(O.eval), null, 2));
    } else if (O.stills) {                                   /* several stills in one go: --stills 2,8.5,12 */
      for (const sec of String(O.stills).split(",")) {
        await page.evalJs(`__video.seek(${Number(sec) * 1000})`);
        const file = path.join(HERE, "out", "still-" + sec + ".png");
        fs.writeFileSync(file, await page.shot()); console.log(file);
      }
    } else if (O.still !== null) {
      const t = Number(O.still) * 1000;
      await page.evalJs(`__video.seek(${t})`);
      const file = O.out || path.join(HERE, "out", "still-" + O.still + ".png");
      fs.writeFileSync(file, await page.shot());
      console.log(file);
    } else {
      const from = info.from || 0, to = info.duration;
      const frames = Math.ceil(((to - from) / 1000) * O.fps);
      const out = O.noAudio ? outFile : silent;
      const secs = frames / O.fps;
      const args = ["-y", "-hide_banner", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(O.fps), "-i", "-"];
      args.push("-c:v", "libx264", "-preset", "slow", "-crf", String(O.crf), "-pix_fmt", "yuv420p", "-movflags", "+faststart", out);
      const ff = spawn("ffmpeg", args, { stdio: ["pipe", "inherit", "inherit"] });
      const ffDone = new Promise((r, j) => ff.on("exit", (c) => (c === 0 ? r() : j(new Error("ffmpeg exited " + c)))));
      const t0 = Date.now();
      for (let i = 0; i < frames; i++) {
        await page.evalJs(`__video.seek(${from + (i * 1000) / O.fps})`);
        const png = await page.shot();
        if (!ff.stdin.write(png)) await new Promise((r) => ff.stdin.once("drain", r));
        if (i % O.fps === 0 || i === frames - 1) {
          const el = (Date.now() - t0) / 1000, eta = (el / (i + 1)) * (frames - i - 1);
          process.stdout.write(`\r  frame ${i + 1}/${frames} · ${((i + 1) / O.fps).toFixed(1)}s of ${secs.toFixed(1)}s · eta ${Math.round(eta)}s   `);
        }
      }
      ff.stdin.end(); await ffDone;
      if (!O.noAudio) { process.stdout.write("\n  sound…"); await mux(silent, await soundtrack(info), outFile); }
      console.log("\n" + outFile + "  (" + secs.toFixed(1) + " s, " + O.fps + " fps, " + 1920 * O.scale + "×" + 1080 * O.scale + (O.noAudio ? ", silent" : "") + ")");
    }
  } finally { await b.close(); srv.close(); }
}
