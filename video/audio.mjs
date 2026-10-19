/* The soundtrack, mixed offline from the video's own timeline: zero dependencies (ffmpeg only decodes samples).

   Three layers, all deterministic (seeded noise, no clocks):
   - keys: a recorded mechanical keyboard (Holy Panda, audio/keys, MIT) for every character typed and every key chip,
     with a release sound after each press, small pitch/level/pan variations and a short room;
   - effects: synthesized UI sounds for the agent and the panels (think, propose, accept, toast, which-key, whooshes…);
   - music: an original score (lofi house: 808-ish kick, clap, swung hats, sub bass, FM electric piano, saw pad, plucked
     arp, risers and impacts) whose sections start exactly on scene cuts, so drops land on the picture. Or any file.

   Every cue comes from engine.js (`__video.cues`); sections and levels come from story.js (`STORY.audio`). */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

export const SR = 48000;
const TAU = Math.PI * 2;

/* ── small DSP kit ───────────────────────────────────────────────────────────────────────────── */
function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const db = (x) => Math.pow(10, x / 20);
/* zero-delay-feedback state variable filter (lp / bp / hp in one pass) */
class SVF {
  constructor() { this.a = 0; this.b = 0; this.lp = 0; this.bp = 0; this.hp = 0; }
  run(x, fc, q) {
    const g = Math.tan(Math.PI * Math.min(Math.max(fc, 20), SR * 0.45) / SR), k = 1 / q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const v3 = x - this.b, v1 = a1 * this.a + a2 * v3, v2 = this.b + a2 * this.a + a3 * v3;
    this.a = 2 * v1 - this.a; this.b = 2 * v2 - this.b;
    this.lp = v2; this.bp = v1; this.hp = x - k * v1 - v2; return this;
  }
}
/* band-limited saw (polyBLEP) */
function blep(t, dt) {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
}
/* a stereo bus */
class Bus {
  constructor(n) { this.L = new Float32Array(n); this.R = new Float32Array(n); this.n = n; }
  add(i, l, r) { if (i >= 0 && i < this.n) { this.L[i] += l; this.R[i] += r; } }
  mono(i, x, pan = 0) { this.add(i, x * Math.cos((pan + 1) * Math.PI / 4), x * Math.sin((pan + 1) * Math.PI / 4)); }
}
/* Freeverb (Jezar): 8 combs + 4 allpasses per side */
function reverb(bus, out, { room = 0.82, damp = 0.35, wet = 1 } = {}) {
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617], aps = [556, 441, 341, 225], spread = 23;
  for (const [src, dst, off] of [[bus.L, out.L, 0], [bus.R, out.R, spread]]) {
    const cb = combs.map((c) => ({ buf: new Float32Array(Math.round((c + off) * SR / 44100)), i: 0, f: 0 }));
    const ab = aps.map((a) => ({ buf: new Float32Array(Math.round((a + off) * SR / 44100)), i: 0 }));
    for (let n = 0; n < bus.n; n++) {
      const x = src[n] * 0.015; let y = 0;
      for (const c of cb) { const o = c.buf[c.i]; c.f = o * (1 - damp) + c.f * damp; c.buf[c.i] = x + c.f * room; if (++c.i >= c.buf.length) c.i = 0; y += o; }
      for (const a of ab) { const o = a.buf[a.i]; const v = -y + o; a.buf[a.i] = y + o * 0.5; if (++a.i >= a.buf.length) a.i = 0; y = v; }
      dst[n] += y * wet;
    }
  }
}
/* stereo ping-pong delay */
function delay(bus, out, secs, fb, wet) {
  const d = Math.round(secs * SR), bl = new Float32Array(d), br = new Float32Array(d), lp = [0, 0];
  for (let n = 0, i = 0; n < bus.n; n++, i = (i + 1) % d) {
    const yl = bl[i], yr = br[i];
    lp[0] += (yr - lp[0]) * 0.35; lp[1] += (yl - lp[1]) * 0.35;
    bl[i] = bus.L[n] + bus.R[n] * 0.5 + lp[0] * fb; br[i] = lp[1] * fb;
    out.L[n] += yl * wet; out.R[n] += yr * wet;
  }
}

/* ── samples ─────────────────────────────────────────────────────────────────────────────────── */
function decode(file) {
  const r = spawnSync("ffmpeg", ["-v", "error", "-i", file, "-ac", "2", "-ar", String(SR), "-f", "f32le", "-"], { maxBuffer: 1 << 30 });
  if (r.status !== 0) throw new Error("ffmpeg could not decode " + file + ": " + r.stderr);
  const f = new Float32Array(r.stdout.buffer, r.stdout.byteOffset, r.stdout.length / 4);
  const n = f.length / 2, L = new Float32Array(n), R = new Float32Array(n);
  for (let i = 0; i < n; i++) { L[i] = f[2 * i]; R[i] = f[2 * i + 1]; }
  return { L, R, n };
}
function loadKeys(dir) {
  const has = (f) => fs.existsSync(path.join(dir, f));
  const press = fs.readdirSync(dir).filter((f) => /^GENERIC_R\d\.(mp3|wav|ogg)$/i.test(f)).sort().map((f) => decode(path.join(dir, f)));
  const one = (f) => (has(f) ? decode(path.join(dir, f)) : null);
  return { press, space: one("SPACE.mp3"), enter: one("ENTER.mp3"), back: one("BACKSPACE.mp3"),
    up: one("release/GENERIC.mp3"), upSpace: one("release/SPACE.mp3"), upEnter: one("release/ENTER.mp3") };
}
/* play a sample at time t (s) with a gain, a pan and a playback rate (linear interpolation) */
function play(bus, s, t, gain, pan = 0, rate = 1) {
  if (!s) return;
  const at = Math.round(t * SR), len = Math.floor(s.n / rate), gl = gain * Math.cos((pan + 1) * Math.PI / 4) * 1.41, gr = gain * Math.sin((pan + 1) * Math.PI / 4) * 1.41;
  for (let i = 0; i < len; i++) {
    const x = i * rate, j = x | 0, f = x - j, j2 = Math.min(j + 1, s.n - 1);
    bus.add(at + i, (s.L[j] + (s.L[j2] - s.L[j]) * f) * gl, (s.R[j] + (s.R[j2] - s.R[j]) * f) * gr);
  }
}

/* ── effects (synthesized) ───────────────────────────────────────────────────────────────────── */
function tone(bus, t, f, dur, gain, { pan = 0, attack = 0.002, decay = dur, shape = "sine", glide = 0, fm = 0, fmRatio = 2 } = {}) {
  const at = Math.round(t * SR), n = Math.round(dur * SR); let ph = 0, mph = 0;
  for (let i = 0; i < n; i++) {
    const s = i / SR, env = Math.min(1, s / attack) * Math.exp(-s / decay) * (i > n - 240 ? (n - i) / 240 : 1);
    const fr = f * (1 + glide * Math.min(1, s / dur));
    mph += TAU * fr * fmRatio / SR; ph += TAU * fr / SR + fm * Math.exp(-s / (decay * 0.4)) * Math.cos(mph) * TAU * fr * fmRatio / SR;
    let x = Math.sin(ph);
    if (shape === "tri") x = (2 / Math.PI) * Math.asin(x);
    bus.mono(at + i, x * env * gain, pan);
  }
}
function noise(bus, t, dur, gain, { from = 800, to = 4000, q = 1.4, pan = 0, panTo = pan, curve = (p) => Math.sin(Math.PI * p), hp = 0, seed = 1 } = {}) {
  const at = Math.round(t * SR), n = Math.round(dur * SR), r = rng(seed), f = new SVF(), h = new SVF();
  for (let i = 0; i < n; i++) {
    const p = i / n, fc = from * Math.pow(to / from, p);
    let x = f.run(r() * 2 - 1, fc, q).bp;
    if (hp) x = h.run(x, hp, 0.7).hp;
    bus.mono(at + i, x * curve(p) * gain, pan + (panTo - pan) * p);
  }
}
const FX = {
  whoosh(b, c, r) { noise(b, c.t, 0.95, 0.55, { from: c.out ? 2400 : 300, to: c.out ? 280 : 3200, q: 0.9, pan: c.out ? 0.5 : -0.5, panTo: c.out ? -0.5 : 0.5, curve: (p) => Math.pow(Math.sin(Math.PI * Math.pow(p, 0.8)), 2), seed: 11 + (c.t | 0) }); },
  swish(b, c) { noise(b, c.t, 0.45, 0.12, { from: 1800, to: 5200, q: 1.2, pan: -0.3, panTo: 0.3, curve: (p) => Math.pow(Math.sin(Math.PI * p), 3), seed: 7 + (c.t | 0) }); },
  swell(b, c) { noise(b, c.t, 1.0, 0.16, { from: 200, to: 1400, q: 0.8, curve: (p) => Math.pow(Math.sin(Math.PI * p), 2), seed: 5 }); tone(b, c.t, 55, 1.0, 0.12, { attack: 0.3, decay: 0.5 }); },
  zoom(b, c) { noise(b, c.t, 0.8, 0.06, { from: c.s > 1 ? 400 : 1600, to: c.s > 1 ? 1600 : 400, q: 1, curve: (p) => Math.pow(Math.sin(Math.PI * p), 2), seed: 3 }); },
  wk(b, c) { tone(b, c.t, 2350, 0.05, 0.05, { decay: 0.012, pan: 0.2 }); noise(b, c.t, 0.04, 0.04, { from: 6000, to: 6000, q: 2, curve: (p) => 1 - p }); },
  menu(b, c) { tone(b, c.t, 1760, 0.06, 0.05, { decay: 0.015 }); tone(b, c.t + 0.035, 2637, 0.07, 0.04, { decay: 0.02 }); },
  open(b, c) { noise(b, c.t, 0.22, 0.12, { from: 500, to: 3000, q: 1.1, curve: (p) => Math.pow(Math.sin(Math.PI * p), 2) }); tone(b, c.t + 0.02, 660, 0.12, 0.04, { decay: 0.05, glide: 0.5 }); },
  close(b, c) { noise(b, c.t, 0.18, 0.08, { from: 2600, to: 500, q: 1.1, curve: (p) => Math.pow(Math.sin(Math.PI * p), 2) }); },
  /* the agent starts: three soft glassy notes going up */
  think(b, c, r) { [0, 0.07, 0.14].forEach((d, i) => tone(b, c.t + d, mtof([81, 84, 88, 86, 91][(i + (c.t * 7 | 0)) % 5]), 0.4, 0.035, { decay: 0.12, fm: 0.6, fmRatio: 3.5, pan: -0.3 + i * 0.3 })); },
  /* a proposal shows up: a round bubble */
  propose(b, c) { tone(b, c.t, 520, 0.18, 0.12, { decay: 0.06, glide: 0.9 }); tone(b, c.t + 0.06, 1040, 0.2, 0.05, { decay: 0.06, fm: 0.5 }); },
  /* accepted: a bright two-note FM bell, a fifth apart */
  accept(b, c) { tone(b, c.t, mtof(81), 0.9, 0.09, { decay: 0.28, fm: 1.4, fmRatio: 3.5 }); tone(b, c.t + 0.09, mtof(88), 1.1, 0.08, { decay: 0.35, fm: 1.2, fmRatio: 3.5, pan: 0.2 }); },
  success(b, c) { [76, 81, 85, 88].forEach((m, i) => tone(b, c.t + i * 0.07, mtof(m), 1.2, 0.07, { decay: 0.4, fm: 1, fmRatio: 3.5, pan: -0.3 + i * 0.2 })); },
  insert(b, c) { tone(b, c.t, 880, 0.12, 0.06, { decay: 0.04, glide: 0.4 }); },
  done(b, c) { tone(b, c.t, mtof(84), 0.5, 0.05, { decay: 0.15, fm: 0.8, fmRatio: 3.5 }); },
  note(b, c) { tone(b, c.t, 1320, 0.09, 0.05, { shape: "tri", decay: 0.04 }); tone(b, c.t + 0.06, 1760, 0.12, 0.045, { shape: "tri", decay: 0.05 }); },
  diag(b, c) { const e = c.sev === "error"; tone(b, c.t, e ? 330 : 440, 0.12, 0.05, { shape: "tri", decay: 0.05 }); tone(b, c.t + 0.07, e ? 247 : 392, 0.16, 0.05, { shape: "tri", decay: 0.06 }); },
  ting(b, c) { tone(b, c.t, c.on ? 3136 : 2349, 0.6, 0.05, { decay: 0.16, fm: 0.8, fmRatio: 2.76, pan: 0.25 }); },
  tick(b, c) { tone(b, c.t, 2000 + c.n * 60, 0.03, 0.05, { decay: 0.008 }); },
  tile(b, c) { tone(b, c.t, mtof(74 + [0, 2, 4, 7, 9, 12, 14, 16][c.n % 8]), 0.25, 0.035, { decay: 0.07, fm: 0.4, fmRatio: 2 }); },
  impact(b, c) {
    tone(b, c.t, 62, 1.6, 0.5, { attack: 0.003, decay: 0.45, glide: -0.45 });
    noise(b, c.t, 0.6, 0.35, { from: 3000, to: 200, q: 0.7, curve: (p) => Math.exp(-p * 6) });
  }
};

/* ── keys ────────────────────────────────────────────────────────────────────────────────────── */
function keys(bus, room, K, cues, from, gain) {
  const r = rng(42);
  for (const c of cues) {
    if (c.k !== "key") continue;
    const t = c.t / 1000 - from, pan = (r() - 0.5) * 0.35, g = gain * db((r() - 0.5) * 3), rate = 1 + (r() - 0.5) * 0.06;
    const s = c.key === "space" ? K.space : c.key === "enter" ? K.enter : K.press[Math.floor(r() * K.press.length)];
    const up = c.key === "space" ? K.upSpace : c.key === "enter" ? K.upEnter : K.up;
    const big = c.key === "space" || c.key === "enter" ? 1.1 : 1;
    play(bus, s, t, g * big, pan, rate); play(room, s, t, g * 0.5, pan, rate);
    play(bus, up, t + 0.07 + r() * 0.04, g * 0.5, pan, rate);
  }
}

/* ── the score ───────────────────────────────────────────────────────────────────────────────── */
/* D minor: Dm9 · Bbmaj9 · Fmaj7 · Cadd9, voiced close; roots for the bass */
const PROG = [{ root: 38, pad: [53, 57, 60, 64], ep: [57, 60, 64, 65] }, { root: 34, pad: [50, 53, 57, 60], ep: [53, 57, 60, 62] },
  { root: 41, pad: [52, 57, 60, 65], ep: [57, 60, 64, 69] }, { root: 36, pad: [52, 55, 60, 62], ep: [55, 60, 62, 64] }];
/* what each part plays (levels 0..1) */
const PARTS = {
  intro: { pad: 2, cut: 1400, ep: "sparse" },
  lift: { pad: 1, cut: [1000, 3200], ep: "sparse", kick: "quarter", hats: 0.4, rise: true },
  groove: { pad: 0.8, cut: 3000, ep: "stabs", kick: "four", clap: 1, hats: 1, bass: 1 },
  groove2: { pad: 0.8, cut: 3400, ep: "stabs", kick: "four", clap: 1, hats: 1, ghost: 1, bass: 1, arp: 0.6, open: 1 },
  break: { pad: 1.7, cut: 1100, ep: "sparse" },
  drive: { pad: 0.9, cut: 4400, ep: "stabs", kick: "four", clap: 1, hats: 1, ghost: 1, bass: 1, arp: 1, open: 1, shaker: 1 },
  outro: { pad: 1.8, cut: [2200, 700], ep: "sparse", end: true }
};

function score(n, sections, music, bpm, seed) {
  const r = rng(seed), beat = 60 / bpm, st = beat / 4, swing = 0.1;
  const drums = new Bus(n), tonal = new Bus(n), arpBus = new Bus(n), send = new Bus(n), duck = new Float32Array(n).fill(1);
  const kick = (t, v) => {
    const at = Math.round(t * SR); let ph = 0;
    for (let i = 0; i < SR * 0.5; i++) {
      const s = i / SR, f = 54 + 140 * Math.exp(-s / 0.025);
      ph += TAU * f / SR;
      const x = Math.tanh(2.2 * Math.sin(ph) * Math.exp(-s / 0.2)) + (r() * 2 - 1) * Math.exp(-s / 0.002) * 0.35;
      drums.mono(at + i, x * 0.5 * v);
      const d = 1 - 0.4 * v * (s < 0.006 ? s / 0.006 : Math.exp(-(s - 0.006) / 0.11));
      if (at + i < n) duck[at + i] = Math.min(duck[at + i], d);
    }
  };
  const clap = (t, v) => {
    const at = Math.round(t * SR), f = new SVF();
    for (let i = 0; i < SR * 0.35; i++) {
      const s = i / SR; let e = Math.exp(-s / 0.11) * 0.6;
      for (const o of [0, 0.011, 0.022]) if (s >= o) e = Math.max(e, Math.exp(-(s - o) / 0.005));
      const x = f.run(r() * 2 - 1, 1500, 1.0).bp * e * 0.8 * v;
      drums.mono(at + i, x, 0.05); send.mono(at + i, x * 0.6);
    }
  };
  const hat = (t, v, open, pan = 0.25) => {
    const at = Math.round(t * SR), f = new SVF(), g = new SVF(), len = open ? 0.24 : 0.045;
    for (let i = 0; i < SR * len * 1.5; i++) {
      const s = i / SR, x = g.run(f.run(r() * 2 - 1, 7800, 0.8).hp, 9000, 0.7).hp * Math.exp(-s / (len / 2.5)) * v;
      drums.mono(at + i, x * 0.4, pan);
    }
  };
  const shaker = (t, v) => {
    const at = Math.round(t * SR), f = new SVF();
    for (let i = 0; i < SR * 0.06; i++) { const s = i / SR; drums.mono(at + i, f.run(r() * 2 - 1, 5600, 1.6).bp * Math.min(1, s / 0.008) * Math.exp(-s / 0.02) * v * 0.18, -0.35); }
  };
  const bass = (t, m, len, v) => {
    const at = Math.round(t * SR), f = mtof(m), nn = Math.round(len * SR); let ph = 0;
    for (let i = 0; i < nn + SR * 0.06; i++) {
      const s = i / SR, env = Math.min(1, s / 0.004) * (i < nn ? 0.75 + 0.25 * Math.exp(-s / 0.08) : 0.75 * Math.exp(-(i - nn) / SR / 0.02));
      ph += TAU * f / SR;
      tonal.mono(at + i, Math.tanh(1.6 * (Math.sin(ph) + 0.5 * Math.sin(2 * ph) + 0.22 * Math.sin(3 * ph))) * env * 0.2 * v);
    }
  };
  /* FM electric piano: a modulator at 1:1 whose index fades, plus a faint tine */
  const ep = (t, ms, len, v, pan = 0) => {
    for (const [k, m] of ms.entries()) {
      const at = Math.round((t + k * 0.006) * SR), f = mtof(m), nn = Math.round(len * SR); let pc = 0, pm = 0, pt = 0;
      const p = pan + (k - 1.5) * 0.18;
      for (let i = 0; i < nn + SR * 0.25; i++) {
        const s = i / SR, rel = i < nn ? 1 : Math.exp(-(i - nn) / SR / 0.08);
        pm += TAU * f / SR; pt += TAU * f * 14 / SR;
        const idx = (0.6 + 2.2 * v * Math.exp(-s / 0.25));
        pc += TAU * f / SR;
        const x = (Math.sin(pc + idx * Math.sin(pm)) + 0.06 * v * Math.sin(pt) * Math.exp(-s / 0.04)) * Math.exp(-s / 1.4) * Math.min(1, s / 0.002) * rel;
        tonal.mono(at + i, x * 0.21 * v, p); send.mono(at + i, x * 0.07 * v, p);
      }
    }
  };
  /* saw pad: three detuned voices per note through one moving low-pass */
  const pad = (t, ms, len, v, cut) => {
    for (const [k, m] of ms.entries()) {
      const at = Math.round(t * SR), nn = Math.round(len * SR), f = mtof(m), flt = new SVF(), ph = [r(), r(), r()], det = [-0.006, 0, 0.0065];
      const p = (k - 1.5) * 0.35;
      for (let i = 0; i < nn + SR * 0.8; i++) {
        const s = i / SR, env = Math.min(1, s / 0.45) * (i < nn ? 1 : Math.exp(-(i - nn) / SR / 0.35));
        let x = 0;
        for (let j = 0; j < 3; j++) { const dt = f * (1 + det[j]) / SR; ph[j] += dt; if (ph[j] >= 1) ph[j] -= 1; x += 2 * ph[j] - 1 - blep(ph[j], dt); }
        const c = (typeof cut === "function" ? cut(i / Math.max(1, nn)) : cut) * (1 + 0.12 * Math.sin(TAU * 0.18 * (t + s)));
        const y = flt.run(x / 3, c, 0.9).lp * env * 0.11 * v;
        tonal.mono(at + i, y, p); send.mono(at + i, y * 0.5, p);
      }
    }
  };
  const pluck = (t, m, v) => {
    const at = Math.round(t * SR), f = mtof(m), flt = new SVF(); let ph = 0;
    for (let i = 0; i < SR * 0.32; i++) {
      const s = i / SR, dt = f / SR; ph += dt; if (ph >= 1) ph -= 1;
      const sq = (ph < 0.5 ? 1 : -1) + blep(ph, dt) - blep((ph + 0.5) % 1, dt);
      const y = flt.run(sq, 900 + 4200 * Math.exp(-s / 0.05), 1.2).lp * Math.exp(-s / 0.11) * 0.14 * v;
      arpBus.mono(at + i, y, Math.sin(t * 3) * 0.4);
    }
  };
  const riser = (t0, t1) => {
    const at = Math.round(t0 * SR), nn = Math.round((t1 - t0) * SR), f = new SVF(); let ph = 0;
    for (let i = 0; i < nn; i++) {
      const p = i / nn, x = f.run(r() * 2 - 1, 400 * Math.pow(18, p), 1.6).bp * Math.pow(p, 2.2) * 0.35;
      ph += TAU * (180 + 900 * p * p) / SR;
      const y = x + Math.sin(ph) * Math.pow(p, 3) * 0.05;
      tonal.mono(at + i, y, Math.sin(p * 14) * 0.5 * p); send.mono(at + i, y * 0.8);
    }
  };

  sections.forEach((sec, si) => {
    const P = PARTS[sec.part]; if (!P) throw new Error("audio: unknown part `" + sec.part + "`");
    const t0 = sec.t, t1 = si + 1 < sections.length ? sections[si + 1].t : n / SR, steps = Math.floor((t1 - t0) / st);
    const next = sections[si + 1];
    if (next && next.drop && P.rise !== false) riser(Math.max(t0, next.t - 2.2), next.t);
    if (sec.drop) FX.impact(drums, { t: t0 });
    for (let s = 0; s < steps; s++) {
      const bar = Math.floor(s / 16), q = s % 16, ch = PROG[bar % 4], t = t0 + s * st + (q % 2 ? swing * st : 0), left = t1 - t;
      const hum = 0.85 + r() * 0.3;
      if (q === 0) {
        const barLen = Math.min(16 * st, t1 - t);
        const cut = Array.isArray(P.cut) ? (p) => { const a = (t - t0 + p * barLen) / (t1 - t0); return P.cut[0] * Math.pow(P.cut[1] / P.cut[0], a); } : P.cut;
        if (P.pad) pad(t, ch.pad, P.end && t + 16 * st >= t1 ? t1 - t : barLen, P.pad, cut);
        if (P.ep === "sparse" && (bar % 2 === 0)) ep(t, ch.ep, Math.min(16 * st * 2, left), 0.7);
      }
      if (P.ep === "stabs" && (q === 0 || q === 6 || q === 10)) ep(t, ch.ep, st * (q === 0 ? 3 : 1.6), (q === 0 ? 0.9 : 0.6) * hum, q === 6 ? -0.2 : 0.2);
      if (P.kick === "four" && q % 4 === 0) kick(t, 1);
      if (P.kick === "quarter" && q % 4 === 0) kick(t, 0.35 + 0.65 * (t - t0) / (t1 - t0));
      if (P.clap && (q === 4 || q === 12)) clap(t, P.clap * hum);
      if (P.hats && q % 4 === 2) hat(t, P.hats * hum, P.open && q === 14 && bar % 2 === 1);
      if (P.ghost && q % 2 === 1) hat(t, 0.35 * hum, false, -0.15);
      if (P.shaker && q % 2 === 0) shaker(t, hum);
      if (P.bass && [0, 3, 6, 8, 11, 14].includes(q)) bass(t, ch.root + (q === 14 ? 12 : 0), st * (q === 0 || q === 8 ? 1.8 : 0.9), q === 0 ? 1 : 0.8);
      if (P.arp) { const notes = ch.ep.map((m) => m + 12), order = [0, 1, 2, 3, 2, 1, 3, 2]; pluck(t, notes[order[q % 8]], P.arp * hum); }
    }
  });

  /* pump the tonal bus with the kick, then the sends */
  for (let i = 0; i < n; i++) { tonal.L[i] *= duck[i]; tonal.R[i] *= duck[i]; arpBus.L[i] *= duck[i]; arpBus.R[i] *= duck[i]; }
  const out = new Bus(n);
  for (const b of [drums, tonal, arpBus]) for (let i = 0; i < n; i++) { out.L[i] += b.L[i]; out.R[i] += b.R[i]; }
  delay(arpBus, out, st * 3, 0.38, 0.5);
  reverb(send, out, { room: 0.86, damp: 0.3, wet: music.reverb ?? 1 });
  /* fade the last seconds */
  const fade = Math.round((music.fadeOut ?? 3) * SR);
  for (let i = Math.max(0, n - fade); i < n; i++) { const g = (n - i) / fade; out.L[i] *= g; out.R[i] *= g; }
  return out;
}

/* a track from a file instead of the score: cut to length, faded in and out */
function track(file, n, music) {
  const s = decode(file), out = new Bus(n), fi = Math.round((music.fadeIn ?? 0.5) * SR), fo = Math.round((music.fadeOut ?? 3) * SR), off = Math.round((music.offset ?? 0) * SR);
  for (let i = 0; i < n && i + off < s.n; i++) {
    const g = Math.min(1, i / fi, (n - i) / fo);
    out.L[i] = s.L[i + off] * g; out.R[i] = s.R[i + off] * g;
  }
  return out;
}

/* ── the mix ─────────────────────────────────────────────────────────────────────────────────── */
/* cues/scenes come from the page (ms); returns interleaved stereo float32 for [from, to) */
export function mix({ cues, scenes, from, to, audio = {}, root, musicFile }) {
  const n = Math.ceil(((to - from) / 1000) * SR), fromS = from / 1000;
  const lv = Object.assign({ keys: 0, fx: 4, music: -12, duck: 4 }, audio.levels || {});
  const master = new Bus(n), room = new Bus(n), fx = new Bus(n), kb = new Bus(n);

  const kdir = path.resolve(root, audio.keys || "audio/keys");
  keys(kb, room, loadKeys(kdir), cues, fromS, 0.9);

  const r = rng(7);
  for (const c of cues) {
    const f = FX[c.k]; if (!f || c.k === "key") continue;
    if (audio.mute && audio.mute.includes(c.k)) continue;
    f(fx, { ...c, t: c.t / 1000 - fromS }, r);
  }

  let music = null;
  const m = audio.music || {};
  if (musicFile || (m.file && !musicFile)) music = track(path.resolve(root, musicFile || m.file), n, m);
  else if (m !== false && m.score !== false) {
    /* sections: "scene" or "scene+seconds", resolved against the scenes, relative to the rendered range */
    const at = (spec) => {
      const [id, plus] = String(spec).split("+"), sc = scenes.find((s) => s.id === id);
      if (!sc) throw new Error("audio: no scene `" + id + "` for a music section");
      return (sc.from + (Number(plus) || 0) * 1000) / 1000 - fromS;
    };
    const secs = (m.sections || [{ at: scenes[0].id, part: "groove" }]).map((s) => ({ ...s, t: at(s.at) })).sort((a, b) => a.t - b.t);
    while (secs.length > 1 && secs[1].t <= 0) secs.shift();          /* rendering one scene: start in the section it is in */
    if (secs[0].t > 0) secs[0] = { ...secs[0], t: secs[0].t };
    music = score(n, secs.map((s) => ({ ...s, t: Math.max(0, s.t) })), m, m.bpm || 104, 1234);
  }

  const room2 = new Bus(n); reverb(room, room2, { room: 0.5, damp: 0.6, wet: 0.35 });
  const fx2 = new Bus(n); reverb(fx, fx2, { room: 0.75, damp: 0.4, wet: 0.5 });
  const gk = db(lv.keys), gf = db(lv.fx), gm = db(lv.music);
  /* the music steps back while you type: an envelope that follows the keys (attack 40 ms, release 700 ms) */
  const duck = new Float32Array(n), hold = new Uint8Array(n);
  for (const c of cues) if (c.k === "key") { const a = Math.round((c.t / 1000 - fromS) * SR); for (let i = Math.max(0, a); i < Math.min(n, a + SR * 0.15); i++) hold[i] = 1; }
  for (let i = 0, e = 0; i < n; i++) { e += (hold[i] - e) * (hold[i] > e ? 1 / (0.04 * SR) : 1 / (0.7 * SR)); duck[i] = db(-lv.duck * e); }
  const out = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) {
    let L = (kb.L[i] + room2.L[i]) * gk + (fx.L[i] + fx2.L[i]) * gf, R = (kb.R[i] + room2.R[i]) * gk + (fx.R[i] + fx2.R[i]) * gf;
    if (music) { L += music.L[i] * gm * duck[i]; R += music.R[i] * gm * duck[i]; }
    out[2 * i] = Math.tanh(L * 0.9) / 0.9; out[2 * i + 1] = Math.tanh(R * 0.9) / 0.9;    /* soft clip, only touches peaks */
  }
  return out;
}

export function writeWav(file, inter) {
  const n = inter.length, buf = Buffer.alloc(44 + n * 4);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write("WAVE", 8); buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(3, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 8, 28); buf.writeUInt16LE(8, 32); buf.writeUInt16LE(32, 34); buf.write("data", 36); buf.writeUInt32LE(n * 4, 40);
  Buffer.from(inter.buffer, inter.byteOffset, n * 4).copy(buf, 44);
  fs.writeFileSync(file, buf);
}
