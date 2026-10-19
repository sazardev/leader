/* The video engine: a storyboard (story.js) is compiled into a timeline of events, and any frame is drawn from time
   alone (seek(ms)). Nothing animates on its own: fades, slides, the spinner, typing, the cursor blink and the camera are
   all computed from the frame's time, so render.mjs gets the same video on every run, at any fps.

   The look is not copied: the landing's stylesheet and its data (which-key menus generated from the real keymaps, the
   shared mini project, the terminal palettes, the dashboard art) are read from docs/index.html when the page loads.
   The editor below is a port of the landing's scripted mock (docs/index.html, "the editor mock"); keep them in sync. */
var VIDEO = (function () {
  "use strict";
  var SW = 1920, SH = 1080, EW = 1120, EH = 630, BAR = 72;
  var FR = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
  var $ = function (id) { return document.getElementById(id); };
  var L = {}; /* data read from the landing: GN, MENU, PROJ, ARTS, THEMES */

  /* ── time helpers ───────────────────────────────────────────────────────────────────────────── */
  function clamp(x, a, b) { return x < a ? a : x > b ? b : x; }
  function prog(t, t0, dur) { return dur <= 0 ? (t >= t0 ? 1 : 0) : clamp((t - t0) / dur, 0, 1); }
  function bezier(x1, y1, x2, y2) {
    function b(u, a, c) { return 3 * a * u * (1 - u) * (1 - u) + 3 * c * u * u * (1 - u) + u * u * u; }
    return function (x) {
      if (x <= 0) return 0; if (x >= 1) return 1;
      var lo = 0, hi = 1, u = x;
      for (var i = 0; i < 26; i++) { u = (lo + hi) / 2; if (b(u, x1, x2) < x) lo = u; else hi = u; }
      return b(u, y1, y2);
    };
  }
  var EASE = bezier(0.2, 0.7, 0.1, 1);    /* the landing's reveal curve */
  var INOUT = bezier(0.65, 0, 0.35, 1);   /* camera and layout moves */
  function lerp(a, b, p) { return a + (b - a) * p; }

  /* ── the landing as the source of truth ─────────────────────────────────────────────────────── */
  function grab(src, name) {
    var at = src.indexOf("var " + name + " = ");
    if (at < 0) throw new Error("docs/index.html: `var " + name + "` not found");
    var i = src.indexOf("=", at) + 1; while (/\s/.test(src[i])) i++;
    var depth = 0, q = null;
    for (var j = i; j < src.length; j++) {
      var c = src[j];
      if (q) { if (c === "\\") j++; else if (c === q) q = null; continue; }
      if (c === '"' || c === "'") q = c;
      else if (c === "[" || c === "{") depth++;
      else if (c === "]" || c === "}") { if (--depth === 0) return Function("return " + src.slice(i, j + 1))(); }
    }
    throw new Error("docs/index.html: `var " + name + "` never closes");
  }
  function stripMedia(css) {
    var out = "", i = 0;
    for (;;) {
      var at = css.indexOf("@media", i); if (at < 0) return out + css.slice(i);
      out += css.slice(i, at);
      var d = 0, j = css.indexOf("{", at);
      for (; j < css.length; j++) { if (css[j] === "{") d++; else if (css[j] === "}" && --d === 0) break; }
      i = j + 1;
    }
  }
  /* port of ui/flat/labels.lua (as on the landing): "Agent ask" inside the Agent menu reads "ask" */
  function trimLabel(parent, desc) {
    var known = {};
    (parent || "").split(/\s+/).forEach(function (w) { if (w) known[w.toLowerCase()] = 1; });
    function said(word) {
      var w = word.toLowerCase().replace(/[^a-z0-9]+$/, "");
      if (!/^[a-z0-9]/.test(w)) return false;
      if (known[w]) return true;
      return w.length >= 3 && Object.keys(known).some(function (k) { return k.indexOf(w) === 0; });
    }
    var kept = desc.split(/\s+/).filter(function (w, i) { return !(said(w) || (i === 0 && /^(telescope|general|lsp)$/i.test(w))); });
    return kept.length ? kept.join(" ") : desc;
  }
  async function loadLanding() {
    var src = await (await fetch("../docs/index.html", { cache: "no-store" })).text();
    var css = src.slice(src.indexOf("<style>") + 7, src.indexOf("</style>"));
    var st = document.createElement("style");
    st.textContent = stripMedia(css).replace(/url\(fonts\//g, "url(../docs/fonts/");
    document.head.insertBefore(st, document.head.querySelector("link[rel=stylesheet]"));
    ["GN", "MENU", "PROJ", "ARTS", "THEMES"].forEach(function (n) { L[n] = grab(src, n); });
    L.THEMES = L.THEMES.map(function (t) { return { id: "t:" + t[0], name: t[1], bg: t[2], fg: t[3], ansi: t[4] }; });
    Object.keys(L.MENU).forEach(function (p) { L.MENU[p].forEach(function (it) { it[1] = trimLabel(L.GN[p], it[1]); }); });
    L.PATHS = Object.keys(L.PROJ).sort();
  }

  /* terminal palette -> the page's variables (port of appearance/terminal_theme.lua, as on the landing) */
  var Col = {
    rgb: function (h) { return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]; },
    hex: function (r, g, b) { function c(v) { return Math.max(0, Math.min(255, Math.floor(v + 0.5))); } return "#" + [r, g, b].map(function (v) { return ("0" + c(v).toString(16)).slice(-2); }).join(""); },
    blend: function (a, b, t) { var x = Col.rgb(a), y = Col.rgb(b); return Col.hex(x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t); },
    lum: function (h) { var v = Col.rgb(h).map(function (c) { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }); return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]; },
    contrast: function (a, b) { var x = Col.lum(a), y = Col.lum(b); if (x < y) { var t = x; x = y; y = t; } return (x + 0.05) / (y + 0.05); },
    ensure: function (c, against, toward, min) { var r = c; for (var s = 1; s <= 12; s++) { if (Col.contrast(r, against) >= min) return r; r = Col.blend(c, toward, s * 0.08); } return r; }
  };
  function derive(t) {
    var bg = t.bg, fg = t.fg, dark = Col.lum(bg) < 0.179, bl = Col.blend;
    function tint(x) { return bl(bg, fg, x); }
    function accent(h) { return Col.ensure(h, bg, fg, 3.0); }
    var red = accent(t.ansi[1]), green = accent(t.ansi[2]), yellow = accent(t.ansi[3]), blue = accent(t.ansi[4]), magenta = accent(t.ansi[5]), cyan = accent(t.ansi[6]);
    return { dark: dark, vars: {
      "--bg": bg, "--deep": bl(bg, "#000000", dark ? 0.25 : 0.05), "--soft": tint(0.07), "--fg": fg,
      "--dim": Col.ensure(tint(0.62), tint(0.07), fg, 4.0), "--faint": Col.ensure(tint(0.34), tint(0.07), fg, 2.0),
      "--green": green, "--yellow": yellow, "--aqua": cyan, "--blue": blue, "--red": red, "--purple": magenta, "--orange": bl(red, yellow, 0.5),
      "--on": dark ? bl(bg, "#000000", 0.45) : bl(bg, "#ffffff", 0.65)
    } };
  }
  var VARS = ["--bg", "--deep", "--soft", "--fg", "--dim", "--faint", "--green", "--yellow", "--aqua", "--blue", "--red", "--purple", "--orange", "--on"];
  function paint(el, id) {
    var t = id && L.THEMES.filter(function (x) { return x.id === id; })[0], v = t && derive(t).vars;
    VARS.forEach(function (k) { if (v) el.style.setProperty(k, v[k]); else el.style.removeProperty(k); });
    return t ? derive(t).dark : null;
  }

  /* ── the editor mock (port of the landing's) ───────────────────────────────────────────────── */
  function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  var KW = /^(func|return|if|else|for|range|type|struct|interface|var|const|package|import|switch|case|go|defer|map|chan)$/;
  function hl(t) {
    return t.replace(/([\u0001\u0002\u0003\u0004\u0005\u0006])|(\/\/.*$)|("(?:[^"\\]|\\.)*")|([A-Za-z_]\w*)(?=\()|([A-Za-z_]\w*)|([\s\S])/g, function (m, mk, c, str, call, id, other) {
      if (mk) return mk === "\u0001" ? '<span class="mk">' : mk === "\u0005" ? '<span class="fk">' : mk === "\u0002" || mk === "\u0006" ? "</span>" : mk === "\u0003" ? '<span class="cur"></span>' : '<span class="cur m"></span>';
      if (c) return '<span class="sy-c">' + esc(c) + "</span>";
      if (str) return '<span class="sy-s">' + esc(str) + "</span>";
      if (call) return '<span class="' + (KW.test(call) ? "sy-k" : "sy-f") + '">' + call + "</span>";
      if (id) {
        if (KW.test(id)) return '<span class="sy-k">' + id + "</span>";
        if (/^(nil|true|false)$/.test(id)) return '<span class="sy-n">' + id + "</span>";
        if (/^[A-Z]\w*$/.test(id) || /^(string|error|int|bool|any|float64|int64)$/.test(id)) return '<span class="sy-t">' + id + "</span>";
        return id;
      }
      return esc(other);
    });
  }
  function fresh(L, t) {
    if (L.fresh == null) return "";
    var p = prog(t, L.fresh, 1400); if (p >= 1) return "";
    return ' style="background:color-mix(in srgb,var(--yellow) ' + (28 * (1 - p)).toFixed(1) + '%,transparent)"';
  }
  function rowsHtml(ed, lines, o, tally, t) {
    var out = [], num = 0;
    lines.forEach(function (L, i) {
      if (L.kind === "input") {
        var lb = L.label.split(" · "), meta = lb.length > 1 ? lb.pop() : "";
        out.push('<div class="inp"><div><b>✦ ' + esc(lb.join(" · ")) + "</b>" + (meta ? "<u>· " + esc(meta) + "</u>" : "") + "<i>Enter run · Ctrl-J newline · Up history · Esc cancel</i></div><div>" + (L.val ? esc(L.val) + '<span class="cur"></span>' : "<i>" + esc(L.ph) + "</i>") + "</div></div>"); return;
      }
      if (L.kind === "hint") { out.push('<div class="ah"> Enter accept · Esc reject · Tab refine · ' + L.n + " change" + (L.n > 1 ? "s" : "") + (L.imp ? " · import: " + L.imp : "") + (L.stats ? " · " + L.stats : "") + (L.q ? " · " + L.q : "") + "</div>"); return; }
      var sign = L.cls === "ad" ? " " : null;
      if (!sign) num++;
      var isCur = o.cur === i, nc = "";
      if (L.diag) {
        if (L.diag.sev === "error") { nc = " e"; tally.e++; } else if (L.diag.sev === "warn") { nc = " w"; tally.w++; } else nc = " d";
      } else if (isCur && !sign) nc = " cl";
      var text = L.t.replace(/\t/g, "    "), pop = "";
      if (isCur && o.showCursor) text = L.cc != null ? text.slice(0, L.cc) + "\u0003" + text.slice(L.cc) : text + "\u0003";
      if (o.pop && isCur) {
        var dk = o.pop.docs && o.pop.docs[o.pop.sel];
        pop = '<div class="pop" style="left:calc(var(--gut) + ' + Math.max(0, L.t.replace(/\t/g, "    ").length - o.pop.back) + 'ch)"><div class="pl">' +
          o.pop.items.map(function (it, k) { return '<div class="' + (k === o.pop.sel ? "s" : "") + '"><span>' + esc(it[0]) + "</span><span>" + esc(it[1]) + "</span></div>"; }).join("") + "</div>" +
          (dk ? '<div class="pd"><pre>' + hl(dk[0]) + "</pre><hr><p>" + esc(dk[1]) + "</p></div>" : "") + "</div>";
      }
      if (o.fl && isCur) pop += '<div class="fl2 ' + (o.fl.up ? "up" : "dn") + '" style="left:calc(var(--gut) + ' + o.fl.col + 'ch)">' + flHtml(o.fl) + "</div>";
      var vt = "", tg = L.tg;
      if (ed.spin && ed.spin.ref === L) { vt = '<span class="vt"> ' + FR[Math.floor(t / 100) % FR.length] + " " + esc(ed.spin.label) + " · " + ((t - ed.spin.t0) / 1000).toFixed(1) + "s </span>"; tg = true; }
      else if (L.vt && (L.vtUntil == null || t < L.vtUntil)) vt = '<span class="vt' + (L.vtk ? " " + L.vtk : "") + '">' + esc(L.vt) + "</span>";
      out.push('<div class="r' + (L.cls ? " " + L.cls : "") + (L.gs ? " g" + L.gs : "") + (L.k ? " " + L.k : "") + (tg ? " tg" : "") + (isCur ? " foc" : "") + '"' + fresh(L, t) + '><span class="n' + nc + '">' + (sign || num) + '</span><span class="t">' + (L.cls === "ad" ? esc(text) : hl(text)) + "</span>" + vt + pop + "</div>");
      if (L.diag && o.blocks !== false) {
        var d = L.diag, cls = d.sev === "warn" ? " w" : d.sev === "info" ? " i" : "";
        out.push('<div class="blk' + cls + '"><span>' + esc(d.msg) + "  <i>" + esc(d.src) + "</i></span><em>" + (d.at || 1) + "/" + (d.of || 1) + "</em></div>");
      }
    });
    return out.join("");
  }
  /* floats: hover, signature, diagnostics, or the streaming answer of explain/ask (agent/output/text.lua) */
  function flHtml(fl) {
    if (fl.kind !== "stream") return fl.html;
    var body = esc(fl.text).replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>").replace(/`([^`]+)`/g, "<code>$1</code>");
    return '<div class="ttl2">✦ ' + esc(fl.title) + '</div><div class="md2">' + body + (fl.done ? "" : '<span class="cur"></span>') + "</div>" + (fl.foot ? '<div class="ft">' + esc(fl.foot) + "</div>" : "");
  }
  function lineNo(lines, cur) { var n = 0; for (var i = 0; i <= cur && i < lines.length; i++) if (!lines[i].kind && lines[i].cls !== "rm" && lines[i].cls !== "ad") n++; return Math.max(n, 1); }

  /* nvim-tree rows from paths, folders first (as on the landing) */
  function treeRows(paths, open) {
    var node = { d: {}, f: [] };
    paths.forEach(function (p) {
      var parts = p.split("/").filter(Boolean), cur = node;
      parts.forEach(function (x, i) { if (i === parts.length - 1) cur.f.push(x); else { cur.d[x] = cur.d[x] || { d: {}, f: [] }; cur = cur.d[x]; } });
    });
    var rows = [];
    (function walk(nd, pre, depth) {
      Object.keys(nd.d).sort().forEach(function (k) { var p = pre + k; rows.push({ name: k, dir: true, depth: depth, path: p }); if (open.indexOf(p) >= 0) walk(nd.d[k], p + "/", depth + 1); });
      nd.f.sort().forEach(function (f) { rows.push({ name: f, dir: false, depth: depth, path: pre + f }); });
    })(node, "", 0);
    return rows;
  }

  /* overlays (as on the landing): modal, report, terminal, dashboard, picker */
  function cols(cells, widths) { return " " + cells.map(function (c, i) { var plain = c.replace(/<[^>]+>/g, ""); return c + " ".repeat(Math.max(1, widths[i] - plain.length)); }).join(" "); }
  var OV = {
    modal: function (o) {
      return '<div class="md"><h6>' + esc(o.title.toUpperCase()) + "</h6>" + o.lines.map(function (l) { return "<div>" + (l || "&nbsp;") + "</div>"; }).join("") +
        (o.input != null ? '<div class="in">' + esc(o.input) + '<span class="cur"></span></div>' : "") + (o.hint ? (o.hint.indexOf('class="bts"') >= 0 ? o.hint : '<div class="ft2">' + o.hint + "</div>") : "") + "</div>";
    },
    report: function (o) {
      return '<div class="rp"><div class="tt"> ' + esc(o.title) + (o.hint || " · Y copy all · q close ") + "</div>" + o.lines.map(function (l) {
        return '<div class="' + (l[0] || "") + '">' + (l[0] === "h1" ? "▣ " : l[0] === "h2" ? "◎ " : "") + (l[1] || "") + "</div>";
      }).join("") + "</div>";
    },
    term: function (o) {
      return '<div class="tm">' + o.lines.map(function (l) { return '<div class="' + (l[0] || "") + '">' + esc(l[1]) + "</div>"; }).join("") + (o.prompt != null ? '<div><span class="ok">~/notesapi</span> $ ' + esc(o.prompt) + '<span class="cur"></span></div>' : "") + "</div>";
    },
    dash: function (o) {
      return '<div class="ds"><pre>' + esc(o.art) + '</pre><div class="gi2">' + esc(o.repo) + '</div><div class="gi3">' + esc(o.user) + "</div>" +
        o.buttons.map(function (b, i) { return '<div class="bt' + (i === o.sel ? " s" : "") + '"><span>' + esc(b[0]) + "</span><kbd>" + esc(b[1]) + "</kbd></div>"; }).join("") + "</div>";
    },
    dd: function (o) {
      var w = [0, 0];
      o.rows.forEach(function (r) { w[0] = Math.max(w[0], r[0].length); w[1] = Math.max(w[1], r[1].length); });
      var items = o.rows.slice(0, 14).map(function (r, j) { return '<div class="it' + (j === o.sel ? " s" : "") + '">' + esc(r[0].padEnd(w[0]) + "  " + r[1].padEnd(w[1]) + "  " + r[2]) + "</div>"; }).join("");
      return '<div class="tel" style="inset:8px 12% 8px"><div class="lf" style="flex:1"><div class="bx rs" style="justify-content:flex-start;padding:2px 0"><div class="rl" style="justify-content:flex-start">' + items + "</div></div>" +
        '<div class="bx pr"><h6>' + esc(o.title.toUpperCase()) + '</h6><div class="pq">&gt; <span class="cur"></span><em>' + o.rows.length + " / " + o.rows.length + "</em></div></div></div></div>";
    }
  };
  /* the commit panel (commit/panel.lua), as on the landing */
  function cpHtml(c) {
    function rows(list, off) { return list.map(function (r) { return '<div class="rw' + (off ? " off" : "") + '"><b>' + (off ? "○" : "●") + "</b>" + esc(r[0]) + "  " + esc(r[1]) + "<em>" + esc(r[2]) + "</em></div>"; }).join(""); }
    return '<div class="fl"><div class="ttl t0"><span><b>◆ Commit</b> · main → origin/main <i>↑' + (c.ahead || 1) + '</i></span><span></span></div>' +
      '<div class="ttl"><span>Staged · ' + c.staged.length + " file" + (c.staged.length === 1 ? "" : "s") + ' — goes in the commit</span><span></span></div><div class="bd">' + rows(c.staged) + "</div>" +
      (c.unstaged && c.unstaged.length ? '<div class="ttl"><span>Not staged · ' + c.unstaged.length + ' — NOT included</span><span></span></div><div class="bd">' + rows(c.unstaged, true) + "</div>" : "") +
      '<div class="kh">Space stage · a all · u none · p diff · Tab message · Ctrl-g AI · Ctrl-r review · q cancel</div></div>' +
      '<div class="fl"><div class="ttl t1"><span><b>Message</b>' + (c.msg ? "" : " · type(scope): subject") + "</span>" + (c.msg ? '<span class="chip">✔ ' + esc(c.chip) + "</span>" : "") + '</div><div class="bd">' + (c.msg ? esc(c.msg) : "&nbsp;") + "</div>" +
      '<div class="kh">Ctrl-s commit · Ctrl-g AI draft · Ctrl-r review · Ctrl-t type · Ctrl-o scope · Tab files · q cancel</div></div>' +
      '<div class="ai"><b>✦ AI</b> ' + c.ai + "</div>";
  }

  /* ── state ──────────────────────────────────────────────────────────────────────────────────── */
  /* where the editor sits: split = next to the headline (the landing's "stage"), full = below a one-line caption */
  var LAY = {
    split: { x: SW - 96 - EW * 1.05, y: BAR + (SH - BAR - EH * 1.05) / 2, s: 1.05 },
    full: { x: 160, y: 150, s: 1600 / EW },
    wide: { x: (SW - EW * 1.62) / 2, y: SH - 34 - EH * 1.62, s: 1.62 }
  };
  function newEd() {
    return { lines: [{ t: "" }], cur: 0, mode: "NORMAL", file: "", path: "", pop: null, wk: null, split: null, cp: null, agent: null, fl: null,
      blocks: true, tree: null, ov: null, note: null, showCursor: true, spin: null, lastType: -1e9, scroll: 0, scroll2: 0, pal: null };
  }
  function initState() {
    return { ed: newEd(), chips: [], cap: null, capPrev: null, cards: [], chapter: "",
      lay: { from: LAY.split, to: LAY.split, mode: "split", t0: 0, dur: 0 }, cam: { from: { s: 1, x: 0.5, y: 0.5 }, to: { s: 1, x: 0.5, y: 0.5 }, t0: 0, dur: 0 } };
  }
  function layAt(l, t) { var p = INOUT(prog(t, l.t0, l.dur)); return { x: lerp(l.from.x, l.to.x, p), y: lerp(l.from.y, l.to.y, p), s: lerp(l.from.s, l.to.s, p) }; }
  function camAt(c, t) { var p = INOUT(prog(t, c.t0, c.dur)); return { s: lerp(c.from.s, c.to.s, p), x: lerp(c.from.x, c.to.x, p), y: lerp(c.from.y, c.to.y, p) }; }
  function clone(o) { return o == null ? o : JSON.parse(JSON.stringify(o)); }

  /* ── the director: the API story.js writes with. Every call schedules events at the current time and moves it ─ */
  function compile(story) {
    var EV = [], T = 0, seed = 20261019, pace = story.pace || 1, scenes = [], CUES = [];
    function at(t, fn) { EV.push({ t: t, i: EV.length, fn: fn }); }
    /* audio cues: what audio.mjs plays and when (keys, panels, proposals, whooshes…), from the same timeline */
    function cueAt(t, k, o) { CUES.push(Object.assign({ t: t, k: k }, o || {})); }
    function cue(k, o) { cueAt(T, k, o); }
    function keyCue(ch) { cue("key", { key: ch === " " ? "space" : ch === "\n" ? "enter" : "key" }); }
    /* a chip's label -> the keys it stands for: "Ctrl+g" is two presses, "Space S r" three */
    function pressCues(label) {
      var parts = String(label).split(/[ +]/).filter(Boolean);
      parts.forEach(function (k, i) {
        var kind = /^(⏎|Enter)$/.test(k) ? "enter" : /^(␣|Space)$/.test(k) ? "space" : "key";
        cueAt(T + i * (label.indexOf("+") > 0 ? 45 : 90), "key", { key: kind });
      });
    }
    function now(fn) { at(T, fn); }
    function adv(ms) { T += ms * pace; }
    function rnd() { seed = (seed * 16807) % 2147483647; return seed / 2147483647; }
    function chip(label) { now(function (S, t) { S.chips.push({ label: { "␣": "Space", "⏎": "Enter", "⇥": "Tab" }[label] || label, t0: t }); }); }
    function ed(fn) { now(function (S, t) { fn(S.ed, t, S); }); }
    var STATS = story.stats || "1.4s · 2.1k→58 tok · $0.0071";

    var v = {
      L: L, STATS: STATS, h: H,
      get now() { return T; },
      wait: function (ms) { adv(ms); },
      do: function (fn) { ed(fn); },
      chapter: function (name) { now(function (S) { S.chapter = name; }); },

      /* ── framing ── */
      layout: function (mode, ms) { now(function (S, t) { S.lay = { from: layAt(S.lay, t), to: LAY[mode], mode: mode, t0: t, dur: ms == null ? 1000 : ms }; }); },
      caption: function (c) {
        now(function (S, t) {
          if (S.cap) { S.capPrev = S.cap; S.capPrev.out = t; }
          S.cap = c ? Object.assign({}, c, { t0: t + (S.capPrev ? 160 : 0) }) : null;
        });
      },
      /* zoom the camera on a point of the editor (0..1 of its width and height); zoom(1) goes back */
      zoom: function (s, x, y, ms) { now(function (S, t) { S.cam = { from: camAt(S.cam, t), to: { s: s, x: x == null ? 0.5 : x, y: y == null ? 0.5 : y }, t0: t, dur: ms == null ? 900 : ms }; }); },
      card: function (kind, o) {
        var id = scenes.length + ":" + EV.length;
        now(function (S, t) { S.cards.forEach(function (c) { if (c.tEnd == null && c.tOut == null) c.tEnd = t + 900; }); S.cards.push({ id: id, kind: kind, o: o, t0: t, instant: !!(o && o.instant) }); });
      },
      cardOut: function () { now(function (S, t) { S.cards.forEach(function (c) { if (c.tEnd == null && c.tOut == null) c.tOut = t; }); }); },

      /* ── editor ── */
      open: function (path, row, cc) {
        ed(function (e) {
          e.lines = L.PROJ[path].map(function (x) { return { t: x }; }); e.file = path.split("/").pop(); e.path = path;
          e.cur = row || 0; if (cc != null) e.lines[e.cur].cc = cc; e.mode = "NORMAL"; e.pop = e.fl = e.ov = e.split = null; e.scroll = 0; e.showCursor = true;
        });
      },
      set: function (lines, file, mode) {
        ed(function (e) {
          e.lines = lines.map(function (x) { return { t: x }; }); e.cur = lines.length - 1; e.mode = mode || "NORMAL"; e.file = file; e.path = e.path && file ? e.path.replace(/[^/]*$/, file) : file;
          e.pop = e.fl = e.ov = e.split = e.cp = null; e.scroll = 0; e.showCursor = true;
        });
      },
      cursor: function (r, cc) { ed(function (e) { e.lines.forEach(function (x) { delete x.cc; }); e.cur = r; if (cc != null) e.lines[r].cc = cc; }); },
      showCursor: function (on) { ed(function (e) { e.showCursor = on; }); },
      mode: function (m) { ed(function (e) { e.mode = m; }); },
      type: function (str, ms) {
        for (var i = 0; i < str.length; i++) {
          (function (ch) { ed(function (e, t) { e.lines[e.cur].t += ch; e.lastType = t; }); })(str[i]); keyCue(str[i]);
          adv((ms || 34) + rnd() * 22);
        }
      },
      nl: function (indent) { keyCue("\n"); ed(function (e, t) { e.lines.splice(e.cur + 1, 0, { t: indent || "" }); e.cur++; e.lastType = t; }); },
      pop: function (items, sel, back, docs) { ed(function (e) { e.pop = { items: items, sel: sel, back: back || 0, docs: docs || null }; }); },
      sel: function (i) { ed(function (e) { if (e.pop) e.pop.sel = i; }); },
      accept: function (lines) {
        ed(function (e, t) {
          e.pop = null; var at = e.cur;
          e.lines.splice.apply(e.lines, [at, 1].concat(lines.map(function (x) { return { t: x, fresh: t, gs: "a" }; }))); e.cur = at + lines.length - 1; e.lastType = t;
        });
      },
      key: function (k, ms) { chip(k); pressCues(k); adv(ms == null ? 300 : ms); },
      /* a leader sequence with the which-key panel, timed like the real one: keys("␣ a f") */
      keys: function (seq) {
        var ks = seq.split(" "), path = "", labels = [];
        ks.forEach(function (k, i) {
          chip(k); pressCues(k); if (i === 0) cue("wk");
          if (i === 0) { ed(function (e, t) { e.wk = { path: [], items: L.MENU[""], press: null, since: t }; }); adv(300); return; }
          ed(function (e) { if (e.wk) e.wk.press = k; }); adv(220);
          path += k; var m = L.MENU[path];
          if (!m && i < ks.length - 1) throw new Error("keys(\"" + seq + "\"): no menu at <leader>" + path);
          if (m && i < ks.length - 1) { labels.push(L.GN[path]); var lb = labels.slice(); ed(function (e) { e.wk = { path: lb, items: m, press: null, since: -1e9 }; }); adv(250); }
          else { ed(function (e) { e.wk = null; }); adv(80); }
        });
      },
      diag: function (i, sev, src, msg, n, of) { ed(function (e) { e.lines[i].diag = { sev: sev, src: src, msg: msg, at: n || 1, of: of || 1 }; }); },
      clearDiag: function () { ed(function (e) { e.lines.forEach(function (x) { delete x.diag; }); }); },
      blocks: function (on) { ed(function (e) { e.blocks = on; }); },
      input: function (i, label, ph) { ed(function (e) { e.lines.splice(i, 0, { kind: "input", label: label, ph: ph || "hint for the fix (Enter to skip)" }); if (e.cur >= i) e.cur++; }); },
      typeInput: function (str, ms) {
        ed(function (e) { var x = e.lines.filter(function (y) { return y.kind === "input"; })[0]; if (x) x.val = ""; });
        for (var i = 0; i < str.length; i++) {
          (function (ch) { ed(function (e, t) { var x = e.lines.filter(function (y) { return y.kind === "input"; })[0]; if (x) x.val += ch; e.lastType = t; }); })(str[i]); keyCue(str[i]);
          adv((ms || 40) + rnd() * 20);
        }
      },
      dropInput: function () { ed(function (e) { var at = e.lines.findIndex(function (x) { return x.kind === "input"; }); if (at >= 0) { e.lines.splice(at, 1); if (at <= e.cur) e.cur--; } }); },
      /* running (agent/ui/status.lua): veil on the target, the chip at the right of its first line, `⠋ agent …` in the statusline */
      spin: function (i, label, ms, status) {
        ed(function (e, t) { e.spin = { ref: e.lines[i], label: label, t0: t }; e.agent = "agent " + (status || label.split(" · ")[0]); });
        adv(ms);
        ed(function (e) { e.spin = null; e.agent = null; });
      },
      done: function (i, text, ms) { ed(function (e, t) { var x = e.lines[i]; x.vt = " ✓ " + text + " "; x.vtk = "dn"; x.vtUntil = t + (ms || 2600); }); },
      /* a proposal (agent/ui/preview.lua): old lines red in place, new ones as virtual rows below, the hint row above */
      diff: function (i, added, removed, stats, o) {
        o = o || {};
        ed(function (e) {
          var n = removed == null ? 1 : removed, at = o.at == null ? i : o.at;
          for (var k = 0; k < n; k++) e.lines[i + k].cls = "rm";
          e.lines.splice.apply(e.lines, [i + n, 0].concat(added.map(function (x) { return { t: x, cls: "ad" }; })));
          e.lines.splice(at, 0, { kind: "hint", n: o.n || 1, stats: stats || STATS, q: o.q, imp: o.imp }); if (e.cur >= at) e.cur++;
        });
      },
      undiff: function () {
        ed(function (e) { e.lines = e.lines.filter(function (x) { return x.kind !== "hint" && x.cls !== "ad"; }); e.lines.forEach(function (x) { delete x.cls; }); e.cur = Math.min(e.cur, e.lines.length - 1); });
      },
      rmLines: function (idxs, stats) {
        ed(function (e) {
          idxs.forEach(function (i) { e.lines[i].cls = "rm"; });
          var at = Math.min.apply(null, idxs); e.lines.splice(at, 0, { kind: "hint", n: idxs.length, stats: stats || STATS }); if (e.cur >= at) e.cur++;
        });
      },
      acceptDiff: function () {
        ed(function (e, t) {
          var before = e.lines.length;
          e.lines = e.lines.filter(function (x) { return x.cls !== "rm" && x.kind !== "hint"; });
          e.cur = Math.max(0, Math.min(e.cur - (before - e.lines.length), e.lines.length - 1));
          e.lines.forEach(function (x) { if (x.cls === "ad") { delete x.cls; x.fresh = t; x.gs = "c"; } });
        });
      },
      line: function (row, text, gs) { ed(function (e, t) { e.lines[row].t = text; e.lines[row].fresh = t; if (gs) e.lines[row].gs = gs; }); },
      insertLines: function (at, arr, gs) { ed(function (e, t) { e.lines.splice.apply(e.lines, [at, 0].concat(arr.map(function (x) { return { t: x, fresh: t, gs: gs || "a" }; }))); }); },
      note: function (html) { ed(function (e, t) { e.note = html ? { html: html, since: t } : null; }); },
      toast: function (html, ms) { v.note(html); adv(ms || 2000); v.note(null); },
      split: function (file, lines) { ed(function (e) { e.split = { file: file, lines: lines.map(function (x) { return { t: x }; }), cur: lines.length - 1 }; }); },
      splitDiff: function (added, stats) {
        ed(function (e) { e.split.lines = e.split.lines.concat([{ kind: "hint", n: 1, stats: stats || STATS }], added.map(function (x) { return { t: x, cls: "ad" }; })); e.split.cur = e.split.lines.length - 1; });
      },
      splitAccept: function () {
        ed(function (e, t) { e.split.lines = e.split.lines.filter(function (x) { return x.kind !== "hint"; }); e.split.lines.forEach(function (x) { if (x.cls === "ad") { delete x.cls; x.fresh = t; x.gs = "a"; } }); });
      },
      unsplit: function () { ed(function (e) { e.split = null; }); },
      ov: function (o) { var c = clone(o); ed(function (e, t) { e.ov = c ? Object.assign(clone(c), { since: e.ov ? e.ov.since : t }) : null; }); },
      ovDo: function (fn) { ed(function (e, t) { if (e.ov) fn(e.ov, t); }); },
      ovType: function (key, str, ms) {
        for (var i = 0; i < str.length; i++) {
          (function (ch) { ed(function (e) { if (e.ov) e.ov[key] += ch; }); })(str[i]); keyCue(str[i]);
          adv((ms || 55) + rnd() * 25);
        }
      },
      commit: function (o) { var c = clone(o); ed(function (e, t) { e.cp = c ? Object.assign(clone(c), { since: e.cp ? e.cp.since : t }) : null; }); },
      cpDo: function (fn) { ed(function (e, t) { if (e.cp) fn(e.cp, t); }); },
      float: function (html, col, up) { ed(function (e) { e.fl = html ? { html: html, col: col, up: !!up } : null; }); },
      /* explain / ask: the answer streams into a float next to the code, a few words at a time */
      stream: function (title, text, o) {
        o = o || {};
        ed(function (e) { e.fl = { kind: "stream", title: title, text: "", col: o.col || 4, up: !!o.up, foot: null }; });
        var words = text.match(/\S+\s*/g) || [];
        for (var i = 0; i < words.length; i += 2) {
          (function (chunk) { ed(function (e, t) { if (e.fl) { e.fl.text += chunk; e.lastType = t; } }); })(words.slice(i, i + 2).join(""));
          adv((o.ms || 70) + rnd() * 40);
        }
        ed(function (e) { if (e.fl) { e.fl.done = true; e.fl.foot = o.foot || null; } });
      },
      agent: function (text) { ed(function (e) { e.agent = text; }); },
      tree: function (open) { ed(function (e) { e.tree = open ? { open: open } : null; }); },
      pal: function (id) { ed(function (e) { e.pal = id; }); }
    };

    /* the rest of the cues hang from the API calls themselves (compile-time state only says open vs closed) */
    var open = { ov: false, cp: false }, layMode = "split";
    function wrap(name, before) { var fn = v[name]; v[name] = function () { before.apply(null, arguments); return fn.apply(null, arguments); }; }
    wrap("spin", function () { cue("think"); });
    wrap("stream", function () { cue("think"); });
    ["diff", "rmLines", "splitDiff"].forEach(function (n) { wrap(n, function () { cue("propose"); }); });
    ["acceptDiff", "splitAccept"].forEach(function (n) { wrap(n, function () { cue("accept"); }); });
    wrap("accept", function () { cue("insert"); });
    wrap("pop", function () { cue("menu"); });
    wrap("diag", function (i, sev) { cue("diag", { sev: sev }); });
    wrap("done", function () { cue("done"); });
    wrap("note", function (h) { if (h) cue("note"); });
    wrap("ov", function (o) { if (o && !open.ov) cue("open"); if (!o && open.ov) cue("close"); open.ov = !!o; });
    wrap("commit", function (o) { if (o && !open.cp) cue("open"); if (!o && open.cp) cue("close"); open.cp = !!o; });
    wrap("caption", function (c) { if (c) cue("swish"); });
    wrap("layout", function (m, ms) { if (m !== layMode && ms !== 0) cue("swell"); layMode = m; });
    wrap("zoom", function (s) { cue("zoom", { s: s }); });
    wrap("pal", function (id) { cue("ting", { on: !!id }); });
    wrap("cardOut", function () { cue("whoosh", { out: true }); });
    wrap("card", function (kind, o) {
      o = o || {};
      if (!o.instant) cue("whoosh", { up: true });
      if (kind === "speed") {                                  /* a tick each time the counter passes a twentieth of its way */
        var p = 0;
        for (var k = 1; k <= 20; k++) { while (p < 1 && EASE(p) < k / 20) p += 0.002; cueAt(T + 250 + p * (o.countMs || 1700), "tick", { n: k }); }
      }
      if (kind === "install") {                                /* the command types itself, then "Copied" */
        var ms = o.typeMs || 26, at0 = T + 900;
        for (var c = 0; c < o.cmd.length; c++) cueAt(at0 + c * ms, "key", { key: o.cmd[c] === " " ? "space" : "key" });
        cueAt(at0 + o.cmd.length * ms + 700, "success");
      }
      if (kind === "keys") for (var j = 0; j < o.tiles.length; j++) cueAt(T + 900 + o.tiles.length * 80 + j * (o.sweep || 320), "tile", { n: j });
      if (kind === "statement" && o.sweep) for (var r = 0; r < o.rows.length; r++) cueAt(T + 700 + o.rows.length * (o.rowGap || 260) + 300 + r * o.sweep, "tile", { n: r });
    });
    v.sfx = function (k, o) { cue(k, o); };

    story.scenes.forEach(function (sc) {
      var start = T;
      if (sc.chapter) v.chapter(sc.chapter);
      sc.run(v, story.text || {});
      scenes.push({ id: sc.id, title: sc.title || sc.id, from: start, to: T });
    });
    EV.sort(function (a, b) { return a.t - b.t || a.i - b.i; });
    CUES.sort(function (a, b) { return a.t - b.t; });
    return { events: EV, duration: T, scenes: scenes, cues: CUES };
  }

  /* helpers the story uses for overlay text (as on the landing) */
  var H = {
    esc: esc, cols: cols,
    MU: function (t) { return '<span class="mu">' + t + "</span>"; },
    BTNS: function (key, label, kind, cancelKey) { return '<div class="bts"><span class="bt ' + (kind || "p") + '">' + key + " " + label + '</span><span class="bt">' + (cancelKey || "n") + " Cancel</span></div>"; },
    YES: function (label, kind) { return H.BTNS("y", label || "Yes", kind || "p", "n"); },
    FILE: function (f, t) { return '  <span class="f">' + f + "</span>  " + t; },
    hover: function (sig, doc, foot) { return "<pre>" + hl(sig) + "</pre><hr><p>" + esc(doc) + '</p><div class="ft">' + esc(foot) + "</div>"; },
    diagFloat: function (items) { return '<div class="hd">Diagnostics:</div>' + items.map(function (d, i) { return '<div><span class="' + d[0] + '">' + (i + 1) + ". " + esc(d[1]) + '</span> <span class="src">[' + esc(d[2]) + "]</span></div>"; }).join(""); },
    steps: function (at) {
      return ["plan", "review", "write", "check", "fix", "done"].map(function (n, i) { return i < at ? "<b>" + n + "</b>" : i === at ? '<span class="ck">' + n + "</span>" : '<span class="ck off">' + n + "</span>"; }).join(" ━ ");
    }
  };

  /* ── drawing a frame ────────────────────────────────────────────────────────────────────────── */
  var el = {};
  function capHtml(c, mode, t) {
    var lines = c.lines || [], acc = c.accent == null ? (lines.length > 1 ? lines.length - 1 : -1) : c.accent;
    function y(k) {
      if (c.out != null) return -110 * INOUT(prog(t, c.out + k * 50, 520));
      return 110 * (1 - EASE(prog(t, c.t0 + k * 110, 1100)));
    }
    var fadeIn = EASE(prog(t, c.t0 + 380, 900)), fadeOut = c.out != null ? 1 - prog(t, c.out, 300) : 1;
    var h = (c.eyebrow ? '<span class="eb"><span style="transform:translateY(' + y(0).toFixed(2) + '%)">' + esc(c.eyebrow) + "</span></span>" : "") +
      '<h2 style="font-size:' + (c.fs && c.fs[mode] ? c.fs[mode] : "") + 'px">' + lines.map(function (ln, k) { return '<span class="ln' + (k === acc ? " ac" : "") + '"><span style="transform:translateY(' + y(k + 1).toFixed(2) + '%)">' + esc(ln) + "</span></span>"; }).join("") + "</h2>";
    if (c.sub) h += '<p class="sub" style="opacity:' + (fadeIn * fadeOut).toFixed(3) + ";transform:translateY(" + (24 * (1 - fadeIn)).toFixed(1) + 'px)">' + c.sub + "</p>";
    if (c.keys) {
      var kp = EASE(prog(t, c.t0 + 560, 700)) * fadeOut;
      h += '<div class="kb" style="opacity:' + kp.toFixed(3) + '">' + c.keys.split(" ").map(function (k) { return "<span>" + esc(k) + "</span>"; }).join("") + "</div>";
    }
    return h;
  }
  function placeCap(node, mode) {
    node.className = "cap " + mode;
    if (mode === "split") { node.style.left = "96px"; node.style.top = (BAR + (SH - BAR) / 2) + "px"; node.style.transform = "translateY(-50%)"; node.style.width = (LAY.split.x - 96 - 64) + "px"; }
    else { node.style.left = LAY.full.x + "px"; node.style.top = "80px"; node.style.transform = ""; node.style.width = ""; }
  }
  /* headlines are sized to fit their column once, then reused (deterministic: same text, same size) */
  function fit(c, node, mode) {
    c.fs = c.fs || {};
    if (c.fs[mode]) return;
    var h2 = node.querySelector("h2"); if (!h2) return;
    var max = mode === "split" ? LAY.split.x - 96 - 64 : SW - 2 * LAY.full.x, base = mode === "split" ? 84 : 46;
    h2.style.fontSize = base + "px";
    var w = Math.max.apply(null, [].map.call(h2.querySelectorAll(".ln > span"), function (s) { return s.scrollWidth; }).concat([1]));
    if (mode === "full") w = h2.scrollWidth;
    c.fs[mode] = Math.floor(w > max ? base * max / w : base);
  }

  function drawCaptions(S, t) {
    var mode = S.lay.mode === "full" ? "full" : "split", html = [];
    el.cap.innerHTML = "";
    [S.capPrev, S.cap].forEach(function (c) {
      if (!c) return;
      if (c.out != null && t > c.out + 900) return;
      if (t < c.t0 - 1) return;
      var node = document.createElement("div"); placeCap(node, mode);
      node.innerHTML = capHtml(c, mode, t); el.cap.appendChild(node);
      if (!c.fs || !c.fs[mode]) { fit(c, node, mode); node.innerHTML = capHtml(c, mode, t); }
      html.push(node);
    });
  }

  function drawEditor(S, t) {
    var e = S.ed, tally = { e: 0, w: 0 };
    var lay = layAt(S.lay, t), cam = camAt(S.cam, t);
    el.frame.style.transform = "translate(" + lay.x.toFixed(2) + "px," + lay.y.toFixed(2) + "px) scale(" + lay.s.toFixed(5) + ")";
    el.cam.style.transform = "translate(" + (cam.x * EW * (1 - cam.s)).toFixed(2) + "px," + (cam.y * EH * (1 - cam.s)).toFixed(2) + "px) scale(" + cam.s.toFixed(5) + ")";
    /* a terminal palette repaints the whole frame (headline, bar, editor), like the config repaints Neovim */
    if (e.pal !== el.pal) { el.pal = e.pal; paint(el.stage, e.pal); }

    var html = "";
    if (e.tree) {
      var rows = treeRows(L.PATHS, e.tree.open);
      html += '<div class="tree">' + rows.map(function (r) {
        return '<div class="tn' + (r.dir ? " d" : "") + (r.path === e.path ? " cf" : "") + '" style="padding-left:calc(12px + ' + r.depth * 2 + 'ch)">' + (r.dir ? (e.tree.open.indexOf(r.path) >= 0 ? "▾ " : "▸ ") : "  ") + esc(r.name) + "</div>";
      }).join("") + "</div>";
    }
    html += '<div class="pn" id="pn1">' + rowsHtml(e, e.lines, { cur: e.cur, showCursor: e.showCursor && !e.split, pop: e.pop, fl: e.fl, blocks: e.blocks }, tally, t) + "</div>";
    if (e.split) html += '<div class="pn" id="pn2">' + rowsHtml(e, e.split.lines, { cur: e.split.cur, showCursor: e.showCursor }, tally, t) + "</div>";
    el.code.innerHTML = html;
    e.scroll = keep(el.code.querySelector("#pn1"), e.scroll);
    if (e.split) e.scroll2 = keep(el.code.querySelector("#pn2"), e.scroll2);

    el.ed.classList.toggle("ins", e.mode === "INSERT"); el.ed.classList.toggle("vis", e.mode === "VISUAL");
    el.ed.classList.toggle("bo", t - e.lastType > 700 && Math.floor(t / 530) % 2 === 1);

    var target = e.split || e, nr = lineNo(target.lines, target.cur), tl = target.lines[target.cur];
    var colN = (tl && tl.t != null ? (tl.cc != null ? tl.cc : tl.t.replace(/\t/g, "    ").length) : 0) + 1;
    el.sl.innerHTML = '<span class="m">' + e.mode + '</span><span class="b">' + esc(e.split ? e.split.file : e.file || "[No Name]") + '</span><span class="c">⎇ main</span><span class="sp"></span>' +
      (e.agent ? '<span class="ag"> ' + FR[Math.floor(t / 100) % FR.length] + " " + esc(e.agent) + " </span>" : "") +
      (tally.e ? '<span class="dg e">E' + tally.e + "</span>" : "") + (tally.w ? '<span class="dg w">W' + tally.w + "</span>" : "") +
      '<span class="b">notesapi</span><span class="z">' + nr + ":" + colN + "</span>";

    if (e.wk) {
      var wp = EASE(prog(t, e.wk.since, 180));
      el.wk.innerHTML = "<ul>" + e.wk.items.map(function (it) {
        return '<li class="' + (e.wk.press === it[0] ? "p" : "") + '"><b>' + esc(it[0]) + "</b><u>➜</u>" + (it[2] ? "<s>" + esc(it[1]) + "</s>" : esc(it[1])) + "</li>";
      }).join("") + '</ul><div class="crumb"><span>Space' + e.wk.path.map(function (x) { return " » " + esc(x); }).join("") + "</span><span>Esc close · BS back</span></div>";
      el.wk.style.transform = "translateY(" + (120 * (1 - wp)).toFixed(1) + "%)"; el.wk.style.opacity = wp.toFixed(3);
    } else { el.wk.style.opacity = "0"; el.wk.innerHTML = ""; }

    if (e.cp) {
      var cp = EASE(prog(t, e.cp.since, 220));
      el.cp.innerHTML = cpHtml(e.cp); el.cp.classList.add("on");
      el.cp.style.opacity = cp.toFixed(3); el.cp.style.transform = "translate(-50%," + (10 * (1 - cp)).toFixed(1) + "px)";
    } else { el.cp.classList.remove("on"); el.cp.style.opacity = "0"; el.cp.innerHTML = ""; }

    if (e.ov) { el.ov2.innerHTML = OV[e.ov.kind](e.ov); el.ov2.classList.add("on"); el.ov2.style.opacity = prog(t, e.ov.since, 150).toFixed(3); }
    else { el.ov2.innerHTML = ""; el.ov2.classList.remove("on"); el.ov2.style.opacity = "0"; }

    if (e.note) { el.note.innerHTML = e.note.html; el.note.classList.add("on"); el.note.style.opacity = prog(t, e.note.since, 110).toFixed(3); }
    else { el.note.classList.remove("on"); el.note.style.opacity = "0"; }

    /* pressed keys: transient chips (fade in 160 ms, out from 950 ms), at most the last four */
    var live = S.chips.filter(function (c) { return t >= c.t0 && t - c.t0 < 1200; }).slice(-4);
    el.keys.innerHTML = live.map(function (c) {
      var a = t - c.t0, pin = prog(a, 0, 160), pout = prog(a, 950, 250);
      return '<span style="opacity:' + (pin * (1 - pout)).toFixed(3) + ";transform:translateY(" + (6 * (1 - pin)).toFixed(1) + 'px)">' + esc(c.label) + "</span>";
    }).join("");
  }
  /* like the landing's keepVisible: scroll only when the cursor row leaves the pane */
  function keep(pane, scroll) {
    if (!pane) return 0;
    pane.scrollTop = scroll;
    var row = pane.querySelector(".foc"); if (!row) return pane.scrollTop;
    var top = row.offsetTop, h = pane.clientHeight;
    if (top + 140 > pane.scrollTop + h) pane.scrollTop = top + 140 - h;
    if (top < pane.scrollTop + 20) pane.scrollTop = Math.max(0, top - 40);
    return pane.scrollTop;
  }

  /* ── cards: full-screen flat panels (the landing's sections) ───────────────────────────────── */
  function reveal(t, t0, k) { return 110 * (1 - EASE(prog(t, t0 + k * 120, 1100))); }
  function lines(arr, t, t0, from, acc) {
    return arr.map(function (ln, k) { return '<span class="ln' + (k === acc ? " ac" : "") + '"><span style="transform:translateY(' + reveal(t, t0, from + k).toFixed(2) + '%)">' + esc(ln) + "</span></span>"; }).join("");
  }
  function fade(t, t0, d) { var p = EASE(prog(t, t0, d || 900)); return "opacity:" + p.toFixed(3) + ";transform:translateY(" + (40 * (1 - p)).toFixed(1) + "px)"; }
  var CARD = {
    hero: function (o, t, t0) {
      var art = (L.ARTS[o.art || 0] || []).join("\n"), fl = -14 * (0.5 - 0.5 * Math.cos((2 * Math.PI * (t - t0)) / 7000));
      return { cls: "c-bg", html: '<h1>' + lines(o.lines, t, t0, 0, -1) + "</h1>" +
        '<p class="lede" style="' + fade(t, t0 + 500) + '">' + o.lede + "</p>" +
        '<div class="cmd" style="' + fade(t, t0 + 650) + '"><code><b>$ </b>' + esc(o.cmd) + '</code><span class="btn">Copy</span></div>' +
        '<div class="art" style="opacity:' + EASE(prog(t, t0 + 300, 1200)).toFixed(3) + ";transform:translateY(" + fl.toFixed(2) + 'px)">' + esc(art) + "</div>" };
    },
    speed: function (o, t, t0) {
      var p = EASE(prog(t, t0 + 250, o.countMs || 1700)), n = Math.round(o.to + (1 - p) * (o.from - o.to));
      return { cls: "c-yellow", html: '<span class="eb" style="' + fade(t, t0 + 100, 700) + '">' + esc(o.eyebrow) + "</span>" +
        '<div class="big" style="transform:translateY(' + ((1 - p) * 60).toFixed(1) + "px) scale(" + (0.94 + p * 0.06).toFixed(4) + ')">' + n + "<small>" + esc(o.unit) + "</small></div>" +
        '<p class="says" style="' + fade(t, t0 + 600) + '">' + esc(o.says) + "</p>" };
    },
    statement: function (o, t, t0) {
      /* rows come in one by one, then a green highlight walks down them (the landing's hover) */
      var gap = o.rowGap || 260, sweepAt = t0 + 700 + (o.rows || []).length * gap + 300;
      var rows = (o.rows || []).map(function (r, k) {
        var at = t0 + 700 + k * gap, hot = o.sweep && t >= sweepAt && Math.floor((t - sweepAt) / o.sweep) === k;
        return '<div class="row' + (hot ? " hot" : "") + '" style="' + fade(t, at, 900) + '"><h3>' + esc(r[0]) + "</h3><p>" + esc(r[1]) + "</p></div>";
      }).join("");
      return { cls: "c-" + (o.bg || "deep"), html: '<span class="eb" style="' + fade(t, t0 + 100, 700) + '">' + esc(o.eyebrow) + "</span>" +
        "<h2" + (o.size ? ' style="font-size:' + o.size + 'px"' : "") + ">" + lines(o.lines, t, t0, 0, o.lines.length > 1 ? o.lines.length - 1 : -1) + "</h2>" + (rows ? '<div class="rows">' + rows + "</div>" : "") +
        (o.lead ? '<p class="lead" style="' + fade(t, t0 + 500) + '">' + esc(o.lead) + "</p>" : "") };
    },
    keys: function (o, t, t0) {
      var base = t0 + 900 + o.tiles.length * 80, hotAt = Math.floor((t - base) / (o.sweep || 320));
      return { cls: "c-aqua", html: '<span class="eb" style="' + fade(t, t0 + 100, 700) + '">' + esc(o.eyebrow) + "</span><h2>" + lines(o.lines, t, t0, 0, -1) + "</h2>" +
        '<p class="lead" style="' + fade(t, t0 + 400) + '">' + esc(o.lead) + "</p>" +
        '<div class="tiles">' + o.tiles.map(function (k, i) {
          return '<div class="tile' + (t >= base && hotAt === i ? " hot" : "") + '" style="' + fade(t, t0 + 600 + i * 80, 900) + '"><b>' + esc(k[0]) + "</b><span>" + esc(k[1]) + "</span></div>";
        }).join("") + "</div>" };
    },
    install: function (o, t, t0) {
      var start = t0 + 900, n = clamp(Math.floor((t - start) / (o.typeMs || 26)), 0, o.cmd.length), doneAt = start + o.cmd.length * (o.typeMs || 26);
      var copied = t > doneAt + 700;
      return { cls: "c-green", html: '<span class="eb" style="' + fade(t, t0 + 100, 700) + '">' + esc(o.eyebrow) + "</span><h2>" + lines(o.lines, t, t0, 0, -1) + "</h2>" +
        '<div class="cmd" style="' + fade(t, t0 + 300) + '"><code><b>$ </b>' + esc(o.cmd.slice(0, n)) + (n < o.cmd.length || Math.floor(t / 530) % 2 ? '<span class="cur"></span>' : "") + '</code><span class="btn">' + (copied ? "Copied" : "Copy") + "</span></div>" +
        '<p class="fine" style="' + fade(t, t0 + 500) + '">' + o.fine + "</p>" +
        '<div class="sign" style="' + fade(t, t0 + 800) + '"><span class="logo"><i></i>' + esc(o.name) + "</span><span>" + esc(o.url) + "</span></div>" };
    }
  };
  function cardY(c, t) {
    if (c.tOut != null && t >= c.tOut) return -100 * INOUT(prog(t, c.tOut, 900));
    return c.instant ? 0 : 100 * (1 - EASE(prog(t, c.t0, 900)));
  }
  function drawCards(S, t) {
    var live = S.cards.filter(function (c) { return t >= c.t0 && !(c.tEnd != null && t >= c.tEnd) && !(c.tOut != null && t >= c.tOut + 900); });
    var keep = {}, covered = false, onTop = null;
    live.forEach(function (c) {
      keep[c.id] = 1;
      var node = el.cards.querySelector('[data-id="' + c.id + '"]');
      if (!node) { node = document.createElement("div"); node.dataset.id = c.id; el.cards.appendChild(node); }
      var r = CARD[c.kind](c.o, t, c.t0), y = cardY(c, t);
      node.className = "card " + r.cls; node.innerHTML = r.html; node.style.transform = "translateY(" + y.toFixed(3) + "%)";
      if (Math.abs(y) < 0.01) covered = true;
      if (y * SH / 100 < BAR / 2 && y * SH / 100 > -SH + BAR / 2) onTop = r.cls;
    });
    [].slice.call(el.cards.children).forEach(function (n) { if (!keep[n.dataset.id]) n.remove(); });
    return { covered: covered, onTop: onTop };
  }

  function drawBar(S, t, onTop, chapters) {
    el.bar.className = "vbar" + (onTop && /c-(yellow|aqua|green)/.test(onTop) ? " on-card" : "");
    el.bar.innerHTML = '<span class="logo"><i></i>Leader</span><nav>' + chapters.map(function (c) { return c === S.chapter ? "<b>" + esc(c) + "</b>" : "<span>" + esc(c) + "</span>"; }).join("") + "</nav>";
  }

  /* ── playback ───────────────────────────────────────────────────────────────────────────────── */
  var S = null, C = null, idx = 0, applied = -1, story = null;
  function seek(t) {
    if (t < applied || !S) { S = initState(); idx = 0; }
    while (idx < C.events.length && C.events[idx].t <= t) { C.events[idx].fn(S, C.events[idx].t); idx++; }
    applied = t;
    var cv = drawCards(S, t);
    if (!cv.covered) { drawEditor(S, t); drawCaptions(S, t); }
    drawBar(S, t, cv.onTop, story.chapters || []);
    el.prog.style.transform = "scaleX(" + (t / C.duration).toFixed(5) + ")";
  }

  async function start(st) {
    story = st;
    var q = new URLSearchParams(location.search);
    try {
      ["stage", "frame", "cam", "ed", "code", "wk", "cp", "ov2", "note", "sl", "cap", "cards"].forEach(function (k) { el[k] = $(k); });
      el.keys = $("edkeys"); el.bar = $("vbar"); el.prog = $("vprog");
      await loadLanding();
      var th = q.get("theme") || st.theme;
      if (th === "light") document.documentElement.dataset.theme = "light";
      else if (th && th !== "dark") { var dk = paint(document.documentElement, th); document.documentElement.dataset.theme = dk ? "dark" : "light"; }
      await document.fonts.load('600 80px Geist'); await document.fonts.load('400 13px "Geist Mono"'); await document.fonts.ready;
      C = compile(st);
      var sc = q.get("scene") && C.scenes.filter(function (s) { return s.id === q.get("scene"); })[0];
      if (q.get("scene") && !sc) throw new Error("no scene `" + q.get("scene") + "`: " + C.scenes.map(function (s) { return s.id; }).join(", "));
      var from = sc ? sc.from : 0, to = sc ? sc.to : C.duration;
      seek(from);
      if (q.get("shot")) document.body.classList.add("shot");            /* brand/shots.mjs: the editor alone, no headline, bar or cards */
      if (q.get("render")) document.body.classList.add("render");
      else preview(from, to);
      window.__video = { duration: to, from: from, scenes: C.scenes, seek: seek, cues: C.cues, audio: st.audio || {} };
    } catch (err) {
      console.error(err);
      window.__video = { error: String(err && err.stack || err) };
    }
  }

  function preview(from, to) {
    var stage = el.stage, playing = false, t = from, last = 0;
    function fitStage() { var s = Math.min(innerWidth / SW, (innerHeight - 56) / SH); stage.style.transform = "scale(" + s + ")"; }
    addEventListener("resize", fitStage); fitStage();
    var play = $("play"), time = $("time"), scrub = $("scrub"), jump = $("jump");
    jump.innerHTML = C.scenes.map(function (s, i) { return '<option value="' + i + '">' + (s.from / 1000).toFixed(1) + "s · " + esc(s.title) + "</option>"; }).join("");
    function show() {
      time.textContent = (t / 1000).toFixed(1) + " / " + (to / 1000).toFixed(1);
      scrub.value = String(Math.round(((t - from) / (to - from)) * 1000));
      var cur = 0; C.scenes.forEach(function (s, i) { if (t >= s.from) cur = i; }); jump.value = String(cur);
    }
    /* sound: the soundtrack written by `render.mjs --audio-only` (or a full render), kept in step with the playhead */
    var snd = new Audio("out/soundtrack.wav"); snd.preload = "auto";
    function sync() { if (!isNaN(snd.duration)) { snd.currentTime = t / 1000; if (playing) snd.play().catch(function () {}); else snd.pause(); } }
    function go(x) { t = clamp(x, from, to); seek(t); show(); sync(); }
    function loop(now) {
      if (!playing) return;
      t += now - last; last = now;
      if (t >= to) { t = to; playing = false; play.textContent = "Play"; snd.pause(); }
      seek(t); show(); if (playing) requestAnimationFrame(loop);
    }
    function toggle() { playing = !playing; play.textContent = playing ? "Pause" : "Play"; if (playing) { if (t >= to) t = from; last = performance.now(); requestAnimationFrame(loop); } sync(); }
    play.onclick = toggle;
    scrub.oninput = function () { go(from + (to - from) * scrub.value / 1000); };
    jump.onchange = function () { go(C.scenes[+jump.value].from); };
    addEventListener("keydown", function (e) {
      if (e.key === " ") { e.preventDefault(); toggle(); }
      else if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        var d = e.key === "ArrowRight" ? 1 : -1;
        if (e.shiftKey) { var i = +jump.value + d; if (C.scenes[i]) go(C.scenes[i].from); } else go(t + d * 1000);
      } else if (e.key === "Home") go(from);
    });
    show();
  }

  return { start: start, helpers: H };
})();
