/* The brand kit's templates and its catalog. Read by brand/render.mjs through `window.__brand` (catalog + draw(i)); open
   brand/index.html?i=12 in a browser to look at one entry. Look = the landing's: its stylesheet (palette, Geist, flat) is
   injected from docs/index.html, so the kit follows the site. Copy lives in copy.js, the mark and the dot font in dots.js. */
(function () {
  "use strict";
  var D = DOTS, C = COPY, FM = C.formats;
  function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  function px(n) { return Math.round(n * 100) / 100 + "px"; }

  /* ── the landing's stylesheet ──────────────────────────────────────────────────────────────── */
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
  /* the landing's data lives in its script: read an array/object literal by name */
  function grab(src, name) {
    var at = src.indexOf("var " + name + " = "); if (at < 0) throw new Error("docs/index.html: `var " + name + "` not found");
    var i = src.indexOf("=", at) + 1; while (/\s/.test(src[i])) i++;
    var depth = 0, q = null;
    for (var j = i; j < src.length; j++) {
      var c = src[j];
      if (q) { if (c === "\\") j++; else if (c === q) q = null; continue; }
      if (c === '"' || c === "'") q = c; else if (c === "[" || c === "{") depth++;
      else if (c === "]" || c === "}") { if (--depth === 0) return Function("return " + src.slice(i, j + 1))(); }
    }
    throw new Error("docs/index.html: `var " + name + "` never closes");
  }
  var Col = {
    rgb: function (h) { return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]; },
    hex: function (r, g, b) { function c(v) { return Math.max(0, Math.min(255, Math.floor(v + 0.5))); } return "#" + [r, g, b].map(function (v) { return ("0" + c(v).toString(16)).slice(-2); }).join(""); },
    blend: function (a, b, t) { var x = Col.rgb(a), y = Col.rgb(b); return Col.hex(x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t); },
    lum: function (h) { var v = Col.rgb(h).map(function (c) { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }); return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]; },
    contrast: function (a, b) { var x = Col.lum(a), y = Col.lum(b); if (x < y) { var t = x; x = y; y = t; } return (x + 0.05) / (y + 0.05); },
    ensure: function (c, against, toward, min) { var r = c; for (var k = 1; k <= 12; k++) { if (Col.contrast(r, against) >= min) return r; r = Col.blend(c, toward, k * 0.08); } return r; }
  };
  var PALETTES = {}, MENU = {}, GN = {};
  /* "Agent ask" inside the Agent menu reads "ask": port of ui/flat/labels.lua, as on the landing */
  function trimLabel(parent, desc) {
    var known = {}; (parent || "").split(/\s+/).forEach(function (w) { if (w) known[w.toLowerCase()] = 1; });
    function said(word) { var w = word.toLowerCase().replace(/[^a-z0-9]+$/, ""); if (!/^[a-z0-9]/.test(w)) return false; if (known[w]) return true; return w.length >= 3 && Object.keys(known).some(function (k) { return k.indexOf(w) === 0; }); }
    var kept = desc.split(/\s+/).filter(function (w, i) { return !(said(w) || (i === 0 && /^(telescope|general|lsp)$/i.test(w))); });
    return kept.length ? kept.join(" ") : desc;
  }
  function derive(t) {
    var bg = t.bg, fg = t.fg, dark = Col.lum(bg) < 0.179, bl = Col.blend;
    function tint(x) { return bl(bg, fg, x); } function accent(h) { return Col.ensure(h, bg, fg, 3.0); }
    var red = accent(t.ansi[1]), yellow = accent(t.ansi[3]);
    return { "--bg": bg, "--deep": bl(bg, "#000000", dark ? 0.25 : 0.05), "--soft": tint(0.07), "--fg": fg, "--dim": Col.ensure(tint(0.62), tint(0.07), fg, 4.0), "--faint": Col.ensure(tint(0.34), tint(0.07), fg, 2.0),
      "--green": accent(t.ansi[2]), "--yellow": yellow, "--aqua": accent(t.ansi[6]), "--blue": accent(t.ansi[4]), "--red": red, "--purple": accent(t.ansi[5]), "--orange": bl(red, yellow, 0.5), "--on": dark ? bl(bg, "#000000", 0.45) : bl(bg, "#ffffff", 0.65) };
  }
  function palStyle(id) { var v = PALETTES[id]; if (!v) throw new Error("no terminal palette `" + id + "` in docs/index.html"); return Object.keys(v).map(function (k) { return k + ":" + v[k]; }).join(";"); }
  async function loadLanding() {
    var src = await (await fetch("../docs/index.html", { cache: "no-store" })).text();
    grab(src, "THEMES").forEach(function (t) { PALETTES[t[0]] = derive({ bg: t[2], fg: t[3], ansi: t[4] }); });
    MENU = grab(src, "MENU"); GN = grab(src, "GN");
    var st = document.createElement("style");
    st.textContent = stripMedia(src.slice(src.indexOf("<style>") + 7, src.indexOf("</style>"))).replace(/url\(fonts\//g, "url(../docs/fonts/");
    document.head.insertBefore(st, document.head.firstChild);
  }

  /* ── geometry: u is 1% of the short side (of the height on banners); p is the page margin ────── */
  function geo(W, H, extra) {
    var r = W / H, o = r >= 2.6 ? "banner" : r >= 1.3 ? "land" : r >= 0.9 ? "sq" : r >= 0.6 ? "port" : "tall";
    var u = (o === "banner" ? H : Math.min(W, H)) / 100;
    return Object.assign({ W: W, H: H, r: r, o: o, u: u, p: (o === "banner" ? 4.5 : 6) * u, b: 0 }, extra || {});
  }

  /* ── building blocks ───────────────────────────────────────────────────────────────────────── */
  function mark(color, h, pattern) {
    var m = D.mark({ pattern: pattern || "heavyN", on: color, off: null, r: 4, gap: 3 });
    return D.svg(m, { height: h, width: h * m.w / m.h, label: "Leader" });
  }
  /* the mark as a big watermark: lit dots at the page's ink with low opacity, the unlit grid barely there */
  function ghost(g, o) {
    o = o || {};
    var m = D.mark({ pattern: "heavyN", on: "currentColor", off: null, r: 4, gap: 3 });
    var land = g.o === "land" || g.o === "banner", h = o.h || (land ? g.H * 0.84 : Math.min(g.H * 0.5, g.W * 0.9)), w = h * m.w / m.h;
    var left = o.left != null ? o.left : g.W - w - (land ? g.p * 1.4 : g.p * 0.8), top = o.top != null ? o.top : land ? (g.H - h) / 2 : g.p + g.u * 10;
    return '<div class="b-ghost" style="left:' + px(left) + ";top:" + px(top) + ";opacity:" + (o.op || 0.12) + '">' + D.svg(m, { height: h, width: w }) + "</div>";
  }
  function field(g, o) {
    o = o || {}; var dp = o.dp || g.u * 2.4;
    return '<div class="b-field" style="--dp:' + px(dp) + ";--dr:" + px(dp * 0.075) + ";--mask:" + (o.mask || "linear-gradient(to left,#000 0,transparent 78%)") + ";opacity:" + (o.op || 0.16) + '"></div>';
  }
  function brandRow(g, right, o) {
    o = o || {}; var h = g.u * (o.k || 4.4);
    return '<div class="b-brand" style="left:' + px(o.x != null ? o.x : g.p) + ";top:" + px(o.y != null ? o.y : g.p) + ";width:" + px(o.w || g.W - 2 * g.p) + ";height:" + px(h) + '"><span class="b-logo">' + mark("currentColor", h) +
      '<b style="font-size:' + px(h * 0.76) + '">Leader</b></span>' + (right ? '<span class="b-mono" style="font-size:' + px(g.u * 1.8) + '">' + esc(right) + "</span>" : "") + "</div>";
  }
  function keycaps(keys, g, mt, k) {
    return '<div class="b-kb" style="margin-top:' + px(mt) + (k ? ";font-size:" + px(k) : "") + '">' + keys.split(" ").map(function (x) { return "<span>" + esc(x) + "</span>"; }).join("") + "</div>";
  }
  function shotBox(name, x, y, w, h, pos, chip) {
    return '<div class="b-shot" style="left:' + px(x) + ";top:" + px(y) + ";width:" + px(w) + ";height:" + px(h) + '"><img src="shots/' + name + '.png" style="object-position:' + (pos || "0% 0%") + '">' + (chip ? '<span class="b-chip">' + esc(chip) + "</span>" : "") + "</div>";
  }
  /* split a sentence into lines of about n characters */
  function wrap(text, n) {
    var words = text.split(" "), lines = [], cur = "";
    words.forEach(function (w) { if (cur && (cur + " " + w).length > n) { lines.push(cur); cur = w; } else cur = cur ? cur + " " + w : w; });
    if (cur) lines.push(cur); return lines;
  }

  /* a text column: eyebrow, headline, sub, keycaps, extra. The headline is fitted to the box after layout (fitCols). */
  function col(s, g, o) {
    var u = g.u, h = "", lines = s.lines || [];
    if (s.eyebrow && o.eyebrow !== false) h += '<div class="b-eb" style="margin-bottom:' + px(u * 2.6) + (o.ebPx ? ";font-size:" + px(o.ebPx) : "") + '">' + esc(s.eyebrow) + "</div>";
    h += '<h1 class="b-hl" style="font-size:' + px(o.max) + '">' + lines.map(function (l, i) { return '<span class="b-ln' + (i === s.accent ? " ac" : "") + '"><span>' + esc(l) + "</span></span>"; }).join("") + "</h1>";
    var body = s.sub || s.lead;
    if (body) h += '<p class="b-sub" style="margin-top:' + px(u * 3) + ";font-size:" + px(o.subPx || u * 2.9) + ";max-width:" + px(o.subW || o.w) + '">' + body + "</p>";
    if (s.keys && o.keys !== false) h += keycaps(s.keys, g, u * 3.4, o.keyPx);
    if (o.extra) h += o.extra;
    return '<div class="b-col" data-fitcol="' + o.max + '" data-align="' + (o.align || "start") + '" style="left:' + px(o.x) + ";top:" + px(o.y) + ";width:" + px(o.w) + ";height:" + px(o.h) + '">' + h + "</div>";
  }
  /* binary search the headline size so the widest line fits the column and everything fits its height; then align */
  function contentH(c) { var a = c.firstElementChild.getBoundingClientRect(), z = c.lastElementChild.getBoundingClientRect(); return z.bottom - a.top; }
  function fitCols(root) {
    [].forEach.call(root.querySelectorAll("[data-fitcol]"), function (c) {
      var h1 = c.querySelector(".b-hl"), lo = 10, hi = +c.dataset.fitcol, best = lo;
      for (var i = 0; i < 15; i++) {
        var mid = (lo + hi) / 2; h1.style.fontSize = mid + "px";
        var wide = Math.max.apply(null, [].map.call(h1.querySelectorAll(".b-ln>span"), function (x) { return x.getBoundingClientRect().width; }));
        if (wide <= c.clientWidth + 0.5 && contentH(c) <= c.clientHeight + 0.5) { best = mid; lo = mid; } else hi = mid;
      }
      h1.style.fontSize = best + "px";
      var free = c.clientHeight - contentH(c), al = c.dataset.align;
      if (free > 0 && al !== "start") c.style.paddingTop = (al === "end" ? free : free / 2) + "px";
    });
  }

  /* ── designs: one per piece kind; each returns the canvas's inner html ─────────────────────── */
  var DS = {};

  DS.poster = function (s, g) {
    var h = "", u = g.u, top = g.p + u * 8.5;
    if (s.ghost) h += field(g) + ghost(g, { op: g.o === "land" ? 0.11 : 0.13 });
    h += brandRow(g, C.handle);
    h += col(s, g, { x: g.p, y: top, w: g.o === "land" ? g.W * 0.72 : g.W - 2 * g.p, h: g.H - g.p - g.b - top, align: "end", max: g.H * 0.5 });
    return h;
  };

  DS.shot = function (s, g) {
    var h = "", u = g.u, p = g.p, W = g.W, H = g.H, top = p + u * 8.5, bleed = !g.b;
    h += brandRow(g, C.handle);
    if (g.o === "land") {
      var sw = Math.round(W * 0.56), shh = Math.round(sw * 630 / 1120), sx = W - p - sw, sy = Math.round((H - shh) / 2 + u * 3);
      h += col(s, g, { x: p, y: top, w: sx - p - u * 4, h: H - top - p, align: "center", max: H * 0.3 });
      h += shotBox(s.shot, sx, sy, sw, shh);
    } else {
      var sy2 = Math.round(H * (g.o === "sq" ? 0.5 : g.o === "port" ? 0.52 : 0.53)), bottom = bleed ? H : H - g.b, tall = g.o === "tall";
      h += col(s, g, { x: p, y: top, w: W - 2 * p, h: sy2 - top - u * 3, align: tall ? "center" : "start", max: H * 0.2, subPx: tall ? u * 3.5 : undefined, keyPx: tall ? u * 1.15 : undefined });
      h += shotBox(s.shot, p, sy2, bleed ? W - p : W - 2 * p, bottom - sy2, "0% 0%");
    }
    return h;
  };

  /* a number in dot-matrix (a 5×7 font, the unlit grid faintly visible, like a Nothing glyph display) */
  function dotsText(str, hpx) {
    var t = D.text(str, { pitch: 10, on: "currentColor", off: "currentColor", offOpacity: 0.14, offScale: 0.5 });
    return D.svg(t, { height: hpx, width: hpx * t.w / t.h, label: str });
  }
  DS.stat = function (s, g) {
    var u = g.u, h = "", top = g.p + u * 8.5, boxH = g.H - g.p - g.b - top, availW = g.W - 2 * g.p, uk = 0.36;
    var rN = (s.num.length * 6 - 1) / 7, rU = (s.unit.length * 6 - 1) / 7, saysPx = g.o === "land" ? u * 3.3 : u * 3.1;
    var reserve = u * 4.4 + u * 4 + saysPx * 1.35 * (g.o === "land" ? 2.2 : 3.2);
    var hN = Math.min(boxH - reserve, availW / (rN + 0.13 + uk * rU));
    var dots = '<div style="display:flex;align-items:flex-end;gap:' + px(hN * 0.13) + ";height:" + px(hN) + '">' + dotsText(s.num, hN) + dotsText(s.unit, hN * uk) + "</div>";
    var inner = '<div class="b-eb" style="margin-bottom:' + px(u * 4) + '">' + esc(s.eyebrow) + "</div>" + dots +
      '<p class="b-sub" style="margin-top:' + px(u * 4) + ";font-size:" + px(saysPx) + ";max-width:" + px(g.o === "land" ? g.W * 0.5 : availW) + ';color:var(--fgc)">' + esc(s.says) + "</p>";
    h += brandRow(g, C.handle);
    h += '<div class="b-abs" style="left:' + px(g.p) + ";top:" + px(top) + ";width:" + px(availW) + ";height:" + px(boxH) + ';display:flex;flex-direction:column;justify-content:center">' + inner + "</div>";
    return h;
  };

  DS.keys = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, top = p + u * 8.5, h = brandRow(g, C.handle);
    var cols = g.o === "land" || g.o === "sq" ? 4 : 2, rws = C.keys.length / cols;
    var colH = g.o === "land" ? H * 0.3 : g.o === "sq" ? H * 0.27 : g.o === "port" ? H * 0.2 : H * 0.22;
    h += col(s, g, { x: p, y: top, w: W - 2 * p, h: colH, align: "start", max: H * 0.2, subPx: u * 2.8, subW: W * 0.6 });
    var gy = top + colH + u * 3, gh = H - p - g.b - gy, gap = u * 1.4, tw = (W - 2 * p - gap * (cols - 1)) / cols, th = (gh - gap * (rws - 1)) / rws;
    var tiles = C.keys.map(function (k, i) {
      return '<div class="b-tile' + (i === s.hot ? " hot" : "") + '"><b style="font-size:' + px(Math.min(th * 0.5, tw * 0.42)) + '">' + esc(k[0]) + "</b><span>" + esc(k[1]) + "</span></div>";
    }).join("");
    h += '<div class="b-abs" style="display:grid;grid-template-columns:repeat(' + cols + ",1fr);grid-template-rows:repeat(" + rws + ",1fr);gap:" + px(gap) + ";left:" + px(p) + ";top:" + px(gy) + ";width:" + px(W - 2 * p) + ";height:" + px(gh) + '">' + tiles + "</div>";
    return h;
  };

  DS.install = function (s, g) {
    var u = g.u, p = g.p, top = p + u * 8.5, h = brandRow(g, C.handle);
    var cmdPx = g.o === "land" ? u * 2.15 : g.o === "sq" ? u * 2.5 : u * 2.7;
    var cmd = '<div class="b-cmd" style="margin-top:' + px(u * 4.5) + ";font-size:" + px(cmdPx) + '"><code><i>$ </i>' + esc(C.install).replace(/\//g, "/<wbr>") + '</code><span class="b-btn">Copy</span></div>' +
      '<p class="b-fine" style="font-size:' + px(u * 2.2) + '">' + C.installFine + "</p>";
    h += col(s, g, { x: p, y: top, w: g.W - 2 * p, h: g.H - top - p - g.b, align: "center", max: g.H * 0.3, extra: cmd });
    return h;
  };

  DS.rows = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, top = p + u * 8.5, h = brandRow(g, C.handle), rws = s.rows;
    function rowsHtml(titlePx, descPx) {
      return rws.map(function (r, i) { return '<div class="b-row' + (i === s.hot ? " hot" : "") + '"><h3 style="font-size:' + px(titlePx) + '">' + esc(r[0]) + '</h3><p style="font-size:' + px(descPx) + '">' + esc(r[1]) + "</p></div>"; }).join("");
    }
    if (g.o === "land") {
      var rx = W * 0.47;
      h += col(s, g, { x: p, y: top, w: rx - p - u * 3, h: H - top - p, align: "center", max: H * 0.32 });
      h += '<div class="b-rows" style="left:' + px(rx) + ";top:" + px(top - u) + ";width:" + px(W - p - rx) + ";height:" + px(H - top - p + u) + ';align-content:center">' + rowsHtml(u * 4.3, u * 2.4) + "</div>";
    } else {
      var two = g.o === "sq", colH = H * (g.o === "sq" ? 0.3 : g.o === "port" ? 0.3 : 0.27), ry = top + colH + u * 2;
      h += col(s, g, { x: p, y: top, w: W - 2 * p, h: colH, align: "start", max: H * 0.2 });
      h += '<div class="b-rows" style="left:' + px(p) + ";top:" + px(ry) + ";width:" + px(W - 2 * p) + ";height:" + px(H - p - g.b - ry) + ";grid-template-columns:" + (two ? "1fr 1fr" : "1fr") + ';align-content:start">' + rowsHtml(two ? u * 3.6 : u * 4.6, two ? u * 2.2 : u * 2.6) + "</div>";
    }
    return h;
  };

  /* the same editor in several terminal palettes */
  DS.themes = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, top = p + u * 8.5, h = brandRow(g, C.handle);
    var n = g.o === "sq" ? 4 : g.o === "tall" ? 8 : g.o === "land" && g.W < 1500 ? 3 : 6, cols = g.o === "land" ? 3 : 2, rws = n / cols, gap = u * 1.2;
    var list = s.themes.slice(0, n), tw = (W - 2 * p - gap * (cols - 1)) / cols, th = tw * 630 / 1120, gh = th * rws + gap * (rws - 1), gy = H - p - g.b - gh;
    h += col(s, g, { x: p, y: top, w: W - 2 * p, h: gy - top - u * 3, align: "start", max: H * 0.2 });
    list.forEach(function (t, i) {
      h += shotBox("theme-" + t, p + (i % cols) * (tw + gap), gy + Math.floor(i / cols) * (th + gap), tw, th, "0% 0%", s.names[t]);
    });
    return h;
  };
  DS.duo = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, top = p + u * 8.5, h = brandRow(g, C.handle), gap = u * 1.4;
    if (g.o === "land") {
      var tw = (W - 2 * p - gap) / 2, th = tw * 630 / 1120, gy = H - p - th;
      h += col(s, g, { x: p, y: top, w: W - 2 * p, h: gy - top - u * 3, align: "start", max: H * 0.2 });
      h += shotBox("theme-" + s.a, p, gy, tw, th, "0% 0%", s.names[0]) + shotBox("theme-" + s.b, p + tw + gap, gy, tw, th, "0% 0%", s.names[1]);
    } else {
      var w2 = W - 2 * p, h2 = Math.min(w2 * 630 / 1120 * 1.15, (H * 0.62 - gap) / 2), gy2 = H - p - g.b - h2 * 2 - gap;
      h += col(s, g, { x: p, y: top, w: W - 2 * p, h: gy2 - top - u * 3, align: "start", max: H * 0.2 });
      h += shotBox("theme-" + s.a, p, gy2, w2, h2, "0% 0%", s.names[0]) + shotBox("theme-" + s.b, p, gy2 + h2 + gap, w2, h2, "0% 0%", s.names[1]);
    }
    return h;
  };

  /* a keystroke tip: big keycaps and one sentence (carousel "tips") */
  DS.tip = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, h = brandRow(g, C.handle);
    var ks = s.keys.split(" "), kp = Math.min(u * 9.5, (W - 2 * p) / (ks.length * 2.9));
    var say = wrap(s.say, 20), caps = '<div class="b-kb" style="gap:' + px(kp * 0.18) + ";margin:" + px(u * 2.4) + ' 0 0">' + ks.map(function (k) { return '<span style="font-size:' + px(kp * 0.52) + ";padding:" + px(kp * 0.36) + " " + px(kp * 0.5) + '">' + esc(k) + "</span>"; }).join("") + "</div>";
    h += col({ eyebrow: s.tag, lines: say, accent: -1 }, g, { x: p, y: p + u * 8.5, w: W - 2 * p, h: H - 2 * p - u * 8.5 - g.b, align: "center", max: H * 0.12, extra: caps, ebPx: u * 2 });
    return h;
  };

  /* ── banners, wallpapers and social covers ─────────────────────────────────────────────────── */
  DS.banner = function (s, g) {
    var u = g.u, h = field(g, { dp: u * 5.2, op: 0.2 }) + ghost(g, { op: 0.14 });
    var box = s.safe || { x: g.p, y: g.p, w: g.W * 0.62, h: g.H - 2 * g.p };
    var sub = s.sub && box.h > g.H * 0.55 ? s.sub : null;
    h += col({ eyebrow: s.eyebrow, lines: s.lines, accent: s.accent == null ? 1 : s.accent, sub: sub }, g, { x: box.x, y: box.y, w: box.w, h: box.h, align: "center", max: g.H * 0.4, subPx: u * 4.6, ebPx: u * 3.4 });
    return h;
  };
  DS.wallpaper = function (s, g) {
    var u = g.u, tall = g.r < 1;
    var h = field(g, { dp: u * 2.8, op: 0.14, mask: tall ? "linear-gradient(to bottom,transparent 0,#000 80%)" : "linear-gradient(to left,#000 0,transparent 80%)" });
    h += ghost(g, { op: tall ? 0.15 : 0.13 });
    h += col({ eyebrow: "Leader", lines: ["Press Space."], accent: -1 }, g, { x: g.p, y: tall ? g.H - g.p - g.H * 0.17 : g.H - g.p - g.H * 0.2, w: g.W - 2 * g.p, h: tall ? g.H * 0.17 : g.H * 0.2, align: "end", max: tall ? g.W * 0.2 : g.H * 0.12, ebPx: u * 2 });
    return h;
  };

  /* ── wallpapers: seven compositions (the collection is in copy.js) ─────────────────────────── */
  function circ(x, y, r) { return '<circle cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="' + r.toFixed(1) + '"/>'; }
  function wpSvg(g, inner) { return '<div class="b-wp"><svg xmlns="http://www.w3.org/2000/svg" width="' + g.W + '" height="' + g.H + '" viewBox="0 0 ' + g.W + " " + g.H + '">' + inner + "</svg></div>"; }

  /* a field of dots where the lit ones, bigger, draw a giant N (the N's own dots sit on every 4th node of the field) */
  DS.wpGrid = function (s, g) {
    var W = g.W, H = g.H, P = Math.min(W * 0.62 / 32, H * 0.74 / 48), cols = Math.floor(W / P), rws = Math.floor(H / P);
    var ox = (W - (cols - 1) * P) / 2, oy = (H - (rws - 1) * P) / 2, n0c = Math.round((cols - 29) / 2), n0r = Math.round((rws - 45) / 2), pat = D.PATTERNS.heavyN, lit = {}, on = [], off = [];
    for (var r = 0; r < 12; r++) for (var c = 0; c < 8; c++) if (pat[r][c] === "X") lit[(n0c + 4 * c) + "," + (n0r + 4 * r)] = 1;
    for (var j = 0; j < rws; j++) for (var i = 0; i < cols; i++) {
      if (lit[i + "," + j]) on.push(circ(ox + i * P, oy + j * P, P * 1.5)); else off.push(circ(ox + i * P, oy + j * P, P * 0.11));
    }
    return wpSvg(g, '<g style="fill:var(--unlit)">' + off.join("") + '</g><g style="fill:var(--lit)">' + on.join("") + "</g>");
  };

  /* real braille: "leader space" repeated, one cell per letter (2×4 dots), the rows drifting like a line of text */
  var BR = { a: "1", b: "12", c: "14", d: "145", e: "15", f: "124", g: "1245", h: "125", i: "24", j: "245", k: "13", l: "123", m: "134", n: "1345", o: "135", p: "1234", q: "12345", r: "1235", s: "234", t: "2345", u: "136", v: "1236", w: "2456", x: "1346", y: "13456", z: "1356" };
  var BRPOS = { 1: [0, 0], 2: [0, 1], 3: [0, 2], 4: [1, 0], 5: [1, 1], 6: [1, 2], 7: [0, 3], 8: [1, 3] };
  DS.wpBraille = function (s, g) {
    var W = g.W, H = g.H, d = H / ((H > W ? 34 : 19) * 6), adv = 3.2 * d, text = "leader space ", cells = Math.ceil(W / adv) + 1, rws = Math.ceil(H / (6 * d)) + 1;
    var x0 = (W - cells * adv) / 2 + d * 0.8, y0 = (H - rws * 6 * d) / 2 + d * 1.5, off = [], rowsOn = [];
    for (var r = 0; r < rws; r++) {
      var on = [], shift = (r * 5) % text.length;
      for (var c = 0; c < cells; c++) {
        var ch = text[(c + shift) % text.length], dots = BR[ch] || "";
        for (var k = 1; k <= 8; k++) {
          var pos = BRPOS[k], x = x0 + c * adv + pos[0] * d, y = y0 + r * 6 * d + pos[1] * d;
          if (dots.indexOf(String(k)) >= 0) on.push(circ(x, y, d * 0.4)); else off.push(circ(x, y, d * 0.12));
        }
      }
      rowsOn.push('<g style="fill:var(--lit);opacity:' + (0.3 + 0.7 * (0.5 + 0.5 * Math.sin(r * 0.8))).toFixed(2) + '">' + on.join("") + "</g>");
    }
    return wpSvg(g, '<g style="fill:var(--unlit)">' + off.join("") + "</g>" + rowsOn.join(""));
  };

  /* the keyboard of "Press Space.": a grid of keys, the Agent key lit */
  DS.wpKeys = function (s, g) {
    var W = g.W, H = g.H, cols = W > H ? (W / H > 2 ? 8 : 6) : 3, gap = g.u * 0.9, T = (W - gap * (cols + 1)) / cols, rws = Math.ceil((H - gap) / (T + gap)), oy = (H - (rws * (T + gap) - gap)) / 2, keys = C.keys, hot = -1, best = 1e9, h = "";
    for (var i = 0; i < rws * cols; i++) { var dx = (i % cols) - (cols - 1) / 2, dy = Math.floor(i / cols) - (rws - 1) / 2, dd = dx * dx + dy * dy; if (i % keys.length === 0 && dd < best) { best = dd; hot = i; } }
    for (var j = 0; j < rws * cols; j++) {
      var k = keys[j % keys.length], x = gap + (j % cols) * (T + gap), y = oy + Math.floor(j / cols) * (T + gap);
      h += '<div class="b-keytile' + (j === hot ? " hot" : "") + '" style="left:' + px(x) + ";top:" + px(y) + ";width:" + px(T) + ";height:" + px(T) + ";font-size:" + px(T * 0.5) + '"><b>' + esc(k[0]) + "</b><span>" + esc(k[1]) + "</span></div>";
    }
    return '<div class="b-wp">' + h + "</div>";
  };

  /* big dot-matrix text with the unlit grid showing */
  DS.wpDots = function (s, g) {
    var W = g.W, H = g.H, lines = s.lines, n = Math.max.apply(null, lines.map(function (l) { return l.length; })), ratio = (n * 6 - 1) / 7;
    var hl = Math.min(W * 0.86 / ratio, H * 0.8 / (lines.length + (lines.length - 1) * 0.28));
    return '<div class="b-wp" style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:' + px(hl * 0.28) + ';color:var(--lit)"><div style="display:flex;flex-direction:column;gap:' + px(hl * 0.28) + '">' + lines.map(function (l) { return dotsText(l, hl); }).join("") + "</div></div>";
  };

  /* the mark and almost nothing else */
  DS.wpMinimal = function (s, g) {
    var m = Math.min(g.W, g.H), mh = m * 0.17;
    return '<div class="b-wp" style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:' + px(mh * 0.36) + ';color:var(--lit)"><span style="display:flex">' + mark("currentColor", mh) + "</span>" +
      '<span class="b-mono" style="font-size:' + px(m * 0.021) + ';letter-spacing:.24em;color:var(--dimc)">PRESS SPACE</span></div>';
  };

  /* the real editor, large, on the palette's own color */
  DS.wpEditor = function (s, g) {
    var W = g.W, H = g.H, sw = Math.round(Math.min(W * 0.7, H * 0.8 * 1120 / 630)), sh = Math.round(sw * 630 / 1120);
    return '<div class="b-wp" style="color:var(--fgc)">' + field(g, { dp: g.u * 3, op: 0.12, mask: "radial-gradient(circle at center,transparent 30%,#000 100%)" }) + shotBox(s.shot, Math.round((W - sw) / 2), Math.round((H - sh) / 2), sw, sh) + brandRow(g, C.handle) + "</div>";
  };

  /* ── wallpapers with words: phrases, languages, terms, key cheat sheets ───────────────────── */
  /* a phrase, as big as it fits (the landing's headline voice) */
  DS.wpPhrase = function (s, g) {
    var u = g.u, h = brandRow(g, C.handle), top = g.p + u * 9, mono = s.mono ? " b-hl-mono" : "";
    var c = col({ lines: s.lines, accent: s.accent == null ? -1 : s.accent, sub: s.sub }, g, { x: g.p, y: top, w: g.W - 2 * g.p, h: g.H - top - g.p, align: "center", max: g.H * 0.36, subPx: u * (g.W > g.H ? 4.2 : 4.4) });
    return h + c.replace('class="b-hl"', 'class="b-hl' + mono + '"');
  };

  /* syntax colors: the landing's (red keywords, green strings, yellow calls, aqua types, purple literals, dim comments) */
  var KW = {
    go: "func|return|if|else|for|range|type|struct|interface|var|const|package|import|switch|case|go|defer|map|chan|nil|true|false",
    rust: "fn|let|mut|use|pub|struct|impl|enum|match|if|else|for|in|return|const|mod|self|loop|while|move|true|false",
    python: "def|return|if|else|elif|for|in|import|from|class|None|True|False|with|as|while|not|and|or|pass",
    typescript: "const|let|var|function|return|if|else|for|of|in|import|from|export|type|interface|class|new|async|await|string|number|boolean|true|false|null",
    dart: "void|const|final|var|return|if|else|for|class|import|new|async|await|true|false|null",
    swift: "import|let|var|func|return|if|else|for|in|class|struct|enum|guard|true|false|nil",
    java: "public|class|static|void|return|if|else|for|new|import|package|true|false|null",
    kotlin: "fun|val|var|return|if|else|for|in|class|import|when|object|true|false|null",
    lua: "local|function|return|if|then|else|end|for|do|in|while|nil|true|false",
    sql: "SELECT|FROM|WHERE|ORDER|BY|DESC|ASC|LIMIT|AND|OR|INSERT|INTO|VALUES|UPDATE|SET|JOIN|ON|GROUP|AS"
  };
  var CM = { go: "//", rust: "//", typescript: "//", dart: "//", swift: "//", java: "//", kotlin: "//", python: "#", lua: "--", sql: "--" };
  function hlCode(src, lang) {
    if (lang === "html") return esc(src).replace(/(&lt;\/?)([a-z0-9]+)/g, '<span style="color:var(--red)">$1$2</span>');
    if (lang === "css") return esc(src).replace(/^(\s*)([a-z-]+)(:)/gm, '$1<span style="color:var(--yellow)">$2</span>$3').replace(/^([a-z.#][\w .#-]*)(\s*\{)/gm, '<span style="color:var(--aqua)">$1</span>$2').replace(/(\d+[a-z%]*)(;)/g, '<span style="color:var(--purple)">$1</span>$2');
    if (lang === "markdown") return esc(src).replace(/^(#+ .*)$/gm, '<b style="color:var(--yellow)">$1</b>').replace(/^(- )/gm, '<span style="color:var(--red)">$1</span>');
    var cm = CM[lang] ? CM[lang].replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&") + ".*$" : "(?!)", kw = new RegExp("^(?:" + KW[lang] + ")$");
    var re = new RegExp("(" + cm + ')|("(?:[^"\\\\]|\\\\.)*"|\'(?:[^\'\\\\]|\\\\.)*\'|`(?:[^`\\\\]|\\\\.)*`)|(\\b\\d+(?:\\.\\d+)?\\b)|([A-Za-z_]\\w*)(?=\\()|([A-Za-z_]\\w*)|([\\s\\S])', "gm");
    return src.replace(re, function (m, c, str, num, call, id, other) {
      if (c) return '<span style="color:var(--faint);font-style:italic">' + esc(c) + "</span>";
      if (str) return '<span style="color:var(--green)">' + esc(str) + "</span>";
      if (num) return '<span style="color:var(--purple)">' + num + "</span>";
      if (call) return '<span style="color:var(--' + (kw.test(call) ? "red" : "yellow") + ')">' + call + "</span>";
      if (id) return kw.test(id) ? '<span style="color:var(--red)">' + id + "</span>" : /^[A-Z]\w*$/.test(id) || /^(string|error|int|bool|String|Int|str|number)$/.test(id) ? '<span style="color:var(--aqua)">' + id + "</span>" : id;
      return esc(other);
    });
  }

  /* one programming language: its name, a snippet in the editor's colors, and what Leader brings for it */
  DS.wpLang = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, wide = W / H > 1.3, h = brandRow(g, C.handle), top = p + u * 9;
    var lines = s.code, nChars = Math.max.apply(null, lines.map(function (l) { return l.replace(/\t/g, "    ").length; })), pad = u * 3.2;
    var info = '<div class="b-mono" style="font-size:' + px(u * (wide ? 2.6 : 3)) + ';margin-top:' + px(u * 2) + ';color:var(--lit);letter-spacing:.04em">' + esc(s.ext) + "</div>" +
      '<p class="b-sub" style="font-size:' + px(u * (wide ? 2.8 : 3.3)) + ";margin-top:" + px(u * 2.2) + ';color:var(--fgc)">' + esc(s.stack) + "</p>" + (s.key ? keycaps(s.key, g, u * 3, u * 1.0) : "");
    var pw, ph, px0, py0, fs;
    if (wide) {
      pw = W * 0.5; px0 = W - p - pw; fs = Math.min((pw - 2 * pad) / (nChars * 0.62 + 2.6), (H * 0.62 - 2 * pad) / (lines.length * 1.7)); ph = lines.length * fs * 1.7 + 2 * pad; py0 = (H - ph) / 2 + u * 3;
      h += col({ eyebrow: "Language", lines: [s.name], accent: -1 }, g, { x: p, y: top, w: W - pw - 2 * p - u * 7, h: H - top - p, align: "center", max: H * 0.3, extra: info, keys: false, subW: W * 0.4 });
    } else {
      pw = W - 2 * p; px0 = p; fs = Math.min((pw - 2 * pad) / (nChars * 0.62 + 2.6), u * 6.2); ph = lines.length * fs * 1.7 + 2 * pad; py0 = H * 0.42;
      h += col({ eyebrow: "Language", lines: [s.name], accent: -1 }, g, { x: p, y: top, w: W - 2 * p, h: py0 - top - u * 3, align: "end", max: H * 0.1, keys: false });
      h += '<div class="b-abs" style="left:' + px(p) + ";top:" + px(py0 + ph + u * 3) + ";width:" + px(W - 2 * p) + '">' + info + "</div>";
    }
    var nums = lines.map(function (_, i) { return i + 1; }).join("\n");
    h += '<div class="b-code" style="left:' + px(px0) + ";top:" + px(py0) + ";width:" + px(pw) + ";height:" + px(ph) + ";padding:" + px(pad) + ";font-size:" + px(fs) + '"><pre class="b-ln-no">' + nums + "</pre><pre>" + hlCode(lines.join("\n").replace(/\t/g, "    "), s.lang) + "</pre></div>";
    return h;
  };

  /* a glossary entry */
  DS.wpTerm = function (s, g) {
    var u = g.u, wide = g.W / g.H > 1.3, h = brandRow(g, C.handle), top = g.p + u * 9;
    var extra = "";
    if (s.keys || s.keysNote) extra = '<div class="b-eb" style="margin-top:' + px(u * 5) + ";margin-bottom:" + px(u * 1.6) + '">In Leader</div>' + (s.keys ? keycaps(s.keys, g, 0, u * 1.0) : "") + (s.keysNote ? '<p class="b-sub" style="margin-top:' + px(u * 1.8) + ";font-size:" + px(u * 2.6) + '">' + esc(s.keysNote) + "</p>" : "");
    var c = col({ eyebrow: s.pos, lines: s.term.split(" ").length > 1 && !wide ? s.term.split(" ") : [s.term], accent: -1, sub: s.def }, g, { x: g.p, y: top, w: wide ? g.W * 0.8 : g.W - 2 * g.p, h: g.H - top - g.p, align: "center", max: g.H * 0.3, subPx: u * (wide ? 4.2 : 4.4), subW: wide ? g.W * 0.58 : g.W - 2 * g.p, extra: extra, keys: false, ebPx: u * 2.2 });
    return h + c;
  };

  /* a key cheat sheet from a real which-key menu */
  DS.wpCheat = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, wide = W / H > 1.3, items = s.keys.map(function (k) {
      var e = (MENU[s.path] || []).filter(function (x) { return x[0] === k; })[0]; if (!e) throw new Error("cheat " + s.id + ": no key " + k + " in the `" + s.path + "` menu of the landing");
      var label = (s.labels && s.labels[k]) || trimLabel(GN[s.path], e[1]).replace(/^(\w)/, function (m) { return m.toUpperCase(); }); return { k: k, label: label + (e[2] ? " …" : "") };
    }), h = brandRow(g, C.handle), top = p + u * 9;
    var head = col({ eyebrow: "Keys", lines: [s.title], accent: -1, keys: "Space " + s.path.split("").join(" ") }, g, { x: p, y: top, w: W - 2 * p, h: wide ? H * 0.27 : H * 0.17, align: "start", max: wide ? H * 0.2 : H * 0.1, keyPx: u * (wide ? 1.1 : 1.2) });
    h += head;
    var cols = wide ? (W / H > 2 ? 4 : 3) : 1, ry = top + (wide ? H * 0.28 : H * 0.19), rw = W - 2 * p, rh = H - p - ry, rws = Math.ceil(items.length / cols), cw = rw / cols, ch = rh / rws;
    var fs = Math.min(ch * 0.42, cw * 0.1);
    h += items.map(function (it, i) {
      var c = Math.floor(i / rws), r = i % rws;
      return '<div class="b-abs" style="left:' + px(p + c * cw) + ";top:" + px(ry + r * ch) + ";width:" + px(cw - u * 2) + ";height:" + px(ch) + ';display:flex;align-items:center;gap:' + px(fs * 0.6) + ';font-size:' + px(fs) + '"><span class="b-kc">' + esc(it.k) + '</span><span class="b-kl">' + esc(it.label) + "</span></div>";
    }).join("");
    return h;
  };

  /* ── the mark and the logos ────────────────────────────────────────────────────────────────── */
  DS.markOnly = function (s, g) {
    var hh = g.H * (s.k || 0.56), ink = s.ink || "var(--green)";
    return '<div class="b-abs" style="inset:0;display:flex;align-items:center;justify-content:center;color:' + ink + '">' + mark("currentColor", hh, s.pattern) + "</div>";
  };
  DS.lockupH = function (s, g) {
    var ink = s.ink, mh = g.H * 0.46, fs = mh * 0.86;
    return '<div class="b-abs" style="inset:0;display:flex;align-items:center;justify-content:center;gap:' + px(mh * 0.34) + ";color:" + ink + '"><span style="display:flex;color:' + (s.markInk || ink) + '">' + mark("currentColor", mh) + '</span><b style="font:600 ' + px(fs) + '/1 Geist,sans-serif;letter-spacing:-.04em">Leader</b></div>';
  };
  DS.lockupV = function (s, g) {
    var ink = s.ink, mh = g.H * 0.5, fs = mh * 0.34;
    return '<div class="b-abs" style="inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:' + px(mh * 0.16) + ";color:" + ink + '"><span style="display:flex;color:' + (s.markInk || ink) + '">' + mark("currentColor", mh) + '</span><b style="font:600 ' + px(fs) + '/1 Geist,sans-serif;letter-spacing:-.04em">Leader</b></div>';
  };
  DS.wordDots = function (s, g) {
    var t = D.text("LEADER", { pitch: 10, on: "currentColor", off: "currentColor", offOpacity: 0.14, offScale: 0.5, spacing: 1.6 }), hh = Math.min(g.H * 0.5, g.W * 0.84 * t.h / t.w);
    return '<div class="b-abs" style="inset:0;display:flex;align-items:center;justify-content:center;color:' + s.ink + '">' + D.svg(t, { height: hh, width: hh * t.w / t.h, label: "Leader" }) + "</div>";
  };
  DS.favicon = function (s, g) {
    var m = D.mark({ pattern: "classicN", on: s.ink, off: null, r: 4.1 }), hh = g.H * 0.76;
    return '<div class="b-abs" style="inset:0;display:flex;align-items:center;justify-content:center">' + D.svg(m, { height: hh, width: hh * m.w / m.h, label: "Leader" }) + "</div>";
  };

  /* the brand board: what the identity is made of */
  DS.board = function (s, g) {
    var u = g.u, p = g.p, W = g.W, H = g.H, cs = getComputedStyle(document.documentElement), v = function (n) { return cs.getPropertyValue(n).trim(); }, h = "";
    h += '<div class="b-abs" style="left:' + px(p) + ";top:" + px(p) + ";width:" + px(H * 0.46) + ";height:" + px(H * 0.46) + ';background:var(--deep);display:flex;align-items:center;justify-content:center;color:var(--green)">' + mark("currentColor", H * 0.3) + "</div>";
    h += '<div class="b-abs" style="left:' + px(p + H * 0.46 + u * 1.5) + ";top:" + px(p) + ";width:" + px(H * 0.46) + ";height:" + px(H * 0.46) + ';background:var(--yellow);display:flex;align-items:center;justify-content:center;color:var(--on)">' + mark("currentColor", H * 0.3) + "</div>";
    h += '<div class="b-abs" style="left:' + px(p) + ";top:" + px(p + H * 0.46 + u * 1.5) + ";width:" + px(H * 0.46) + ";height:" + px(H * 0.2) + ';background:var(--green);color:var(--on);display:flex;align-items:center;justify-content:center">' +
      '<span style="display:flex;align-items:center;gap:' + px(u * 1.6) + '">' + mark("currentColor", H * 0.1) + '<b style="font:600 ' + px(H * 0.075) + '/1 Geist,sans-serif;letter-spacing:-.04em">Leader</b></span></div>';
    h += '<div class="b-abs" style="left:' + px(p + H * 0.46 + u * 1.5) + ";top:" + px(p + H * 0.46 + u * 1.5) + ";width:" + px(H * 0.46) + ";height:" + px(H * 0.2) + ';background:var(--fg);color:var(--bg);display:flex;align-items:center;justify-content:center">' + dotsText("LEADER", H * 0.07) + "</div>";
    var rx = p + H * 0.92 + u * 5, rw = W - rx - p, cw = rw;
    h += '<div class="b-abs" style="left:' + px(rx) + ";top:" + px(p) + ";width:" + px(rw) + '"><div class="b-eb">Identity</div><h1 class="b-hl" style="font-size:' + px(u * 8.4) + ';margin-top:' + px(u * 1.5) + '">Leader</h1>' +
      '<p class="b-note" style="font-size:' + px(u * 2.2) + ";margin-top:" + px(u * 2.4) + '">The mark is an N made of dots, grouped in braille cells of 2×4 like a braille character. Numerals and the wordmark use a 5×7 dot-matrix with the unlit grid faintly showing, like a display. Dots are the only round shape in a flat, square system.</p></div>';
    var sw = [["deep", v("--deep")], ["soft", v("--soft")], ["fg", v("--fg")], ["green", v("--green")], ["yellow", v("--yellow")], ["aqua", v("--aqua")], ["on", v("--on")], ["red", v("--red")]], sy = p + u * 31, sh = u * 11, sg = u * 1;
    var swW = (cw - sg * 3) / 4;
    h += sw.map(function (c, i) {
      var light = ["fg", "green", "yellow", "aqua"].indexOf(c[0]) >= 0;
      return '<div class="b-sw" style="left:' + px(rx + (i % 4) * (swW + sg)) + ";top:" + px(sy + Math.floor(i / 4) * (sh + sg)) + ";width:" + px(swW) + ";height:" + px(sh) + ";background:" + c[1] + ";color:" + (light ? "var(--on)" : "var(--fg)") + '"><span>' + c[0] + "</span><span style=\"opacity:.7\">" + c[1] + "</span></div>";
    }).join("");
    var ty = sy + (sh + sg) * 2 + u * 3;
    h += '<div class="b-abs" style="left:' + px(rx) + ";top:" + px(ty) + ";width:" + px(cw) + '"><div class="b-eb" style="margin-bottom:' + px(u * 1.4) + '">Type</div>' +
      '<div style="font:600 ' + px(u * 6.4) + '/1 Geist,sans-serif;letter-spacing:-.055em">Geist <span style="color:var(--dim)">Aa</span></div>' +
      '<div style="font:500 ' + px(u * 2.6) + '/1.3 \'Geist Mono\',monospace;margin-top:' + px(u * 1.4) + ';color:var(--dim)">Geist Mono · Space a F · 0123456789</div></div>';
    h += '<div class="b-abs" style="left:' + px(rx) + ";top:" + px(H - p - u * 9) + ";width:" + px(cw) + '"><div class="b-eb" style="margin-bottom:' + px(u * 1.2) + '">Rules</div><p class="b-note" style="font-size:' + px(u * 2) + '">Green mark on dark, ink on yellow, green, aqua and cream. Never recolor outside the palette. Clear space is one dot cell. Below 48 px use the 5×7 favicon mark.</p></div>';
    return h;
  };

  /* ── the catalog ───────────────────────────────────────────────────────────────────────────── */
  var CAT = [];
  function add(e) { CAT.push(e); return e; }
  function piece(id) { return C.pieces.filter(function (x) { return x.id === id; })[0]; }
  function render(s, W, H, extra, kind) {
    var g = geo(W, H, extra), inner = DS[kind || s.kind](s, g), tr = s.transparent;
    return '<div class="b-cv b-s-' + (s.bg || "bg") + (tr ? " transparent" : "") + '"' + (s.theme ? ' data-theme="' + s.theme + '"' : "") + ' style="width:' + W + "px;height:" + H + "px;--u:" + px(g.u) + '">' + inner + (g.pg ? pager(g, s) : "") + "</div>";
  }
  function pager(g, s) {
    var u = g.u, dots = "";
    for (var i = 0; i < g.pg.n; i++) dots += '<i class="' + (i === g.pg.i ? "on" : "") + '"></i>';
    return '<div class="b-pg" style="left:' + px(g.p) + ";bottom:" + px(g.p * 0.6) + ";width:" + px(g.W - 2 * g.p) + ";height:" + px(u * 3) + '"><span class="b-mono" style="font-size:' + px(u * 1.9) + ';color:var(--dimc)">' + String(g.pg.i + 1).padStart(2, "0") + " / " + String(g.pg.n).padStart(2, "0") + '</span><span class="b-dots">' + dots + '</span><span class="b-mono" style="font-size:' + px(u * 1.9) + '">' + (g.pg.i < g.pg.n - 1 ? "Swipe →" : "sazardev/leader") + "</span></div>";
  }

  var PINS = ["for-working", "decided", "type-less", "red-line", "write-it-down", "press-space", "one-command", "colors", "20ms", "commits"];
  C.pieces.forEach(function (p) {
    var fk = ["land", "og", "square", "p45", "story"].concat(PINS.indexOf(p.id) >= 0 ? ["pin"] : []);
    fk.forEach(function (k) {
      add({ dir: FM[k].dir, name: p.id, w: FM[k].w, h: FM[k].h, fmt: k, piece: p, use: FM[k].use, draw: function () { return render(p, FM[k].w, FM[k].h); } });
    });
  });

  /* carousels: Instagram/LinkedIn 4:5 */
  function carousel(name, specs, caption) {
    specs.forEach(function (s, i) {
      var g0 = geo(1080, 1350), pgb = g0.p * 0.6 + g0.u * 3 + g0.u * 3;
      add({ dir: "carousel/" + name, name: String(i + 1).padStart(2, "0"), w: 1080, h: 1350, fmt: "p45", piece: Object.assign({}, s, { caption: i === 0 ? caption : null }), use: "Instagram / LinkedIn carousel, slide " + (i + 1) + " of " + specs.length,
        draw: function () { return render(s, 1080, 1350, { b: pgb, pg: { i: i, n: specs.length } }); } });
    });
  }
  carousel("launch", C.carousels.launch.map(piece), "Leader, in seven slides: what it is, what it decided for you, what the agent does, how to start. " + C.hashtags);
  carousel("agent", C.carousels.agent.map(piece), "An agent that only speaks when you ask: six moments of Leader's inline agent. " + C.hashtags);
  carousel("tips", C.tips.map(function (t, i) { return { kind: "tip", bg: t.bg, keys: t.keys, say: t.say, tag: "Tip " + String(i + 1).padStart(2, "0") }; }), C.tipsCaption + " " + C.hashtags);

  /* banners and covers */
  var NAVY = { lines: C.banner.lines, sub: C.banner.sub };
  [["x-header", 1500, 500, "bg", { x: 330, y: 56, w: 640, h: 388 }], ["x-header-yellow", 1500, 500, "yellow", { x: 330, y: 56, w: 640, h: 388 }],
   ["linkedin-banner", 1584, 396, "deep", { x: 400, y: 48, w: 620, h: 300 }], ["linkedin-banner-yellow", 1584, 396, "yellow", { x: 400, y: 48, w: 620, h: 300 }],
   ["facebook-cover", 1640, 624, "bg", null], ["github-readme-banner", 1280, 320, "deep", null],
   ["youtube-banner", 2560, 1440, "deep", { x: 507, y: 508, w: 1546, h: 424 }]].forEach(function (b) {
    add({ dir: "banners", name: b[0], w: b[1], h: b[2], use: { "x-header": "X / Twitter header (1500×500). The profile photo covers the lower left, text starts to its right", "linkedin-banner": "LinkedIn profile or company banner (1584×396)", "facebook-cover": "Facebook page cover (shown at 820×312, exported at 2×)", "github-readme-banner": "Top of the GitHub README or an organization profile", "youtube-banner": "YouTube channel art: the text sits in the safe area that every device shows" }[b[0].replace(/-yellow$/, "")],
      draw: function () { return render(Object.assign({ bg: b[3], safe: b[4] }, NAVY), b[1], b[2], null, "banner"); } });
  });
  add({ dir: "banners", name: "github-social-preview", w: 1280, h: 640, use: "GitHub repository social preview (Settings → Social preview) and any 2:1 card", draw: function () { return render(Object.assign({ bg: "deep", eyebrow: "Leader", safe: { x: 80, y: 90, w: 700, h: 460 } }, { lines: C.banner.lines, sub: C.banner.sub }), 1280, 640, null, "banner"); } });

  /* wallpapers: every design in its palettes and sizes (copy.js) */
  var WPKIND = { ghost: "wallpaper", grid: "wpGrid", braille: "wpBraille", keys: "wpKeys", dots: "wpDots", minimal: "wpMinimal", editor: "wpEditor" };
  C.wallpapers.forEach(function (w) {
    w.f.split("").forEach(function (k) {
      var F = C.wallpaperFormats[k];
      add({ dir: F.dir, name: w.id, w: F.w, h: F.h, use: F.use, draw: function () {
        var g = geo(F.w, F.h), inner = DS[WPKIND[w.design]](w, g);
        return '<div class="b-cv b-s-' + (w.bg || "deep") + '"' + (w.theme ? ' data-theme="' + w.theme + '"' : "") + ' style="width:' + F.w + "px;height:" + F.h + "px;--u:" + px(g.u) + (w.pal ? ";" + palStyle(w.pal) : "") + '">' + inner + "</div>";
      } });
    });
  });

  /* wallpapers with words: each family has its own design and data in copy.js */
  function wpAdd(list, design, kind) {
    list.forEach(function (w) {
      w.f.split("").forEach(function (k) {
        var F = C.wallpaperFormats[k];
        add({ dir: F.dir, name: kind + "-" + w.id, w: F.w, h: F.h, use: F.use, draw: function () {
          var g = geo(F.w, F.h), inner = DS[design](w, g);
          return '<div class="b-cv b-s-' + (w.bg || "deep") + '"' + (w.theme ? ' data-theme="' + w.theme + '"' : "") + ' style="width:' + F.w + "px;height:" + F.h + "px;--u:" + px(g.u) + (w.pal ? ";" + palStyle(w.pal) : "") + '">' + inner + "</div>";
        } });
      });
    });
  }
  wpAdd(C.wpPhrases, "wpPhrase", "phrase"); wpAdd(C.wpLangs, "wpLang", "lang"); wpAdd(C.wpTerms, "wpTerm", "term"); wpAdd(C.wpCheats, "wpCheat", "cheat");

  /* logos: marks on colors, transparent marks, lockups, wordmark, avatars, favicons, the board */
  var G = "var(--green)", INK = "var(--on)", CREAM = "var(--fg)", PAPER = "#1d2021";
  [["mark-green-on-dark", "deep", G], ["mark-ink-on-yellow", "yellow", INK], ["mark-ink-on-green", "green", INK], ["mark-ink-on-aqua", "aqua", INK], ["mark-cream-on-dark", "bg", CREAM]].forEach(function (m) {
    add({ dir: "logo", name: m[0], w: 1024, h: 1024, use: "Square mark on a solid color: app icon, avatar, sticker, slide corner", draw: function () { return render({ bg: m[1], ink: m[2] }, 1024, 1024, null, "markOnly"); } });
  });
  add({ dir: "logo", name: "mark-ink-on-cream", w: 1024, h: 1024, use: "Square mark on the light theme", draw: function () { return render({ bg: "bg", theme: "light", ink: "#3c3836" }, 1024, 1024, null, "markOnly"); } });
  [["mark-green", G, "dark"], ["mark-cream", CREAM, "dark"], ["mark-ink", PAPER, null]].forEach(function (m) {
    add({ dir: "logo", name: m[0] + "-transparent", w: 1024, h: 1024, transparent: true, use: "Transparent PNG of the mark in one color, for any background", draw: function () { return render({ bg: "bg", transparent: true, ink: m[1] }, 1024, 1024, null, "markOnly"); } });
  });
  [["lockup-horizontal-on-dark", "deep", CREAM, G, false], ["lockup-horizontal-on-light", "bg", "#3c3836", "#3c3836", false, "light"], ["lockup-horizontal-cream", "bg", CREAM, G, true], ["lockup-horizontal-ink", "bg", PAPER, PAPER, true]].forEach(function (m) {
    add({ dir: "logo", name: m[0], w: 1800, h: 540, transparent: m[4], use: m[4] ? "Mark + name, transparent PNG" : "Mark + name on a solid background", draw: function () { return render({ bg: m[1], theme: m[5], ink: m[2], markInk: m[3], transparent: m[4] }, 1800, 540, null, "lockupH"); } });
  });
  [["lockup-stacked-on-dark", "deep", CREAM, G, false], ["lockup-stacked-cream", "bg", CREAM, G, true], ["lockup-stacked-ink", "bg", PAPER, PAPER, true]].forEach(function (m) {
    add({ dir: "logo", name: m[0], w: 1200, h: 1200, transparent: m[4], use: m[4] ? "Stacked mark + name, transparent PNG" : "Stacked mark + name on a solid background", draw: function () { return render({ bg: m[1], ink: m[2], markInk: m[3], transparent: m[4] }, 1200, 1200, null, "lockupV"); } });
  });
  [["wordmark-dots-cream", "deep", CREAM, false], ["wordmark-dots-green", "deep", G, false], ["wordmark-dots-ink", "yellow", INK, false]].forEach(function (m) {
    add({ dir: "logo", name: m[0], w: 2400, h: 600, use: "LEADER set in the dot-matrix font: for headers, stickers and animated intros", draw: function () { return render({ bg: m[1], ink: m[2] }, 2400, 600, null, "wordDots"); } });
  });
  [["avatar-dark", "deep", G], ["avatar-yellow", "yellow", INK], ["avatar-green", "green", INK]].forEach(function (m) {
    add({ dir: "social", name: m[0], w: 800, h: 800, use: "Profile picture (X, LinkedIn, GitHub, Instagram, YouTube, Discord): the mark has the margins every platform's circular crop needs", draw: function () { return render({ bg: m[1], ink: m[2], k: 0.5 }, 800, 800, null, "markOnly"); } });
  });
  [16, 32, 48, 64, 180, 192, 512].forEach(function (n) {
    add({ dir: "logo/favicon", name: "favicon-" + n, w: n, h: n, use: n === 180 ? "apple-touch-icon" : n >= 192 ? "Web app / PWA icon" : "Browser tab favicon (5×7 mark: readable at small sizes)", draw: function () { return render({ bg: "deep", ink: "#b8bb26" }, n, n, null, "favicon"); } });
  });
  add({ dir: "logo", name: "brand-board", w: 1920, h: 1080, use: "One page with the mark, its colorways, the palette, the type and the rules", draw: function () { return render({ bg: "bg" }, 1920, 1080, null, "board"); } });

  /* ── the page API ──────────────────────────────────────────────────────────────────────────── */
  var root = document.getElementById("root");
  function draw(i) {
    var e = CAT[i]; root.innerHTML = e.draw(); fitCols(root);
    var imgs = [].slice.call(root.querySelectorAll("img"));
    return Promise.all(imgs.map(function (im) { return im.decode().catch(function () {}); })).then(function () { return document.fonts.ready; }).then(function () {
      var bad = [], cv = root.firstChild.getBoundingClientRect();
      [].forEach.call(root.querySelectorAll(".b-col"), function (c) {
        var wide = Math.max.apply(null, [].map.call(c.querySelectorAll(".b-ln>span"), function (x) { return x.getBoundingClientRect().width; }).concat([0]));
        if (contentH(c) > c.clientHeight + 1) bad.push("text taller than its box");
        if (wide > c.clientWidth + 1) bad.push("headline wider than its box");
        var f = parseFloat(c.querySelector(".b-hl").style.fontSize); if (f < 24 && e.w > 200) bad.push("headline only " + Math.round(f) + "px");
        [].forEach.call(c.children, function (k) { var r = k.getBoundingClientRect(); if (r.right > cv.right + 1 || r.left < cv.left - 1 || r.bottom > cv.bottom + 1) bad.push("past the canvas"); });
      });
      return { w: e.w, h: e.h, transparent: !!e.transparent, warn: bad.filter(function (x, i) { return bad.indexOf(x) === i; }) };
    });
  }
  /* a contact sheet of the rendered files of some folders (render.mjs screenshots it) */
  function sheet(title, blurb, dirs, cell) {
    var h = '<div class="b-sheet"><h1>' + esc(title) + "</h1><p>" + esc(blurb) + '</p>';
    dirs.forEach(function (d) {
      var items = CAT.filter(function (e) { return e.dir === d; });
      if (!items.length) return;
      var fm = Object.keys(FM).filter(function (k) { return FM[k].dir === d; })[0];
      h += '<h1 style="font-size:24px;margin:26px 0 4px">' + esc(d) + "</h1><p style=\"margin-bottom:14px\">" + esc((fm ? FM[fm].w + "×" + FM[fm].h + " · " + FM[fm].use : (items[0].use || ""))) + '</p><div class="g">';
      items.forEach(function (e) {
        var sc = Math.min(cell.w / e.w, cell.h / e.h), w = Math.round(e.w * sc), hh = Math.round(e.h * sc);
        h += '<figure><img src="out/' + e.dir + "/" + e.name + '.png" width="' + w + '" height="' + hh + '"><figcaption>' + esc(e.name) + " · " + e.w + "×" + e.h + "</figcaption></figure>";
      });
      h += "</div>";
    });
    root.innerHTML = h + "</div>";
    return Promise.all([].map.call(root.querySelectorAll("img"), function (im) { return im.decode().catch(function () {}); })).then(function () { return Math.ceil(root.firstChild.getBoundingClientRect().height); });
  }

  loadLanding().then(function () { return Promise.all([document.fonts.load("600 80px Geist"), document.fonts.load('500 20px "Geist Mono"'), document.fonts.load("400 20px Geist")]); }).then(function () { return document.fonts.ready; }).then(function () {
    window.__brand = { ready: true, catalog: CAT.map(function (e, i) { return { i: i, dir: e.dir, name: e.name, w: e.w, h: e.h, fmt: e.fmt || null, transparent: !!e.transparent, use: e.use || "", id: e.piece ? e.piece.id : null, caption: e.piece && e.piece.caption || "" }; }), draw: draw, sheet: sheet };
    var q = new URLSearchParams(location.search);
    if (q.get("i") != null) draw(+q.get("i"));
  }).catch(function (err) { console.error(err); window.__brand = { error: String(err && err.stack || err) }; });
})();
