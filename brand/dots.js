/* Leader's dot language: the mark (an N made of dots, grouped in braille cells of 2×4 like a braille character, with the
   unlit grid showing like the glyph display of a Nothing phone) and a 5×7 dot-matrix font for numerals and short words.
   Everything is SVG built from circles, so it scales to any size and takes the page's colors. Works in the browser
   (global `DOTS`) and in Node (`require`). The only round shapes in the brand: the rest of the system stays flat. */
(function (root) {
  "use strict";

  /* a 5×7 font: A-Z and 0-9 (and . and -) are enough for "20 MS", "0 TOKENS", "LGTM" and friends */
  var F = {
    "0": ".XXX.|X...X|X..XX|X.X.X|XX..X|X...X|.XXX.", "1": "..X..|.XX..|..X..|..X..|..X..|..X..|.XXX.",
    "2": ".XXX.|X...X|....X|...X.|..X..|.X...|XXXXX", "3": "XXXXX|...X.|..X..|...X.|....X|X...X|.XXX.",
    "4": "...X.|..XX.|.X.X.|X..X.|XXXXX|...X.|...X.", "5": "XXXXX|X....|XXXX.|....X|....X|X...X|.XXX.",
    "6": "..XX.|.X...|X....|XXXX.|X...X|X...X|.XXX.", "7": "XXXXX|....X|...X.|..X..|.X...|.X...|.X...",
    "8": ".XXX.|X...X|X...X|.XXX.|X...X|X...X|.XXX.", "9": ".XXX.|X...X|X...X|.XXXX|....X|...X.|.XX..",
    A: ".XXX.|X...X|X...X|XXXXX|X...X|X...X|X...X", B: "XXXX.|X...X|X...X|XXXX.|X...X|X...X|XXXX.",
    C: ".XXX.|X...X|X....|X....|X....|X...X|.XXX.", D: "XXXX.|X...X|X...X|X...X|X...X|X...X|XXXX.",
    E: "XXXXX|X....|X....|XXXX.|X....|X....|XXXXX", F: "XXXXX|X....|X....|XXXX.|X....|X....|X....",
    G: ".XXX.|X...X|X....|X.XXX|X...X|X...X|.XXXX", H: "X...X|X...X|X...X|XXXXX|X...X|X...X|X...X",
    I: ".XXX.|..X..|..X..|..X..|..X..|..X..|.XXX.", K: "X...X|X..X.|X.X..|XX...|X.X..|X..X.|X...X",
    L: "X....|X....|X....|X....|X....|X....|XXXXX", M: "X...X|XX.XX|X.X.X|X.X.X|X...X|X...X|X...X",
    N: "X...X|XX..X|X.X.X|X.X.X|X..XX|X...X|X...X", O: ".XXX.|X...X|X...X|X...X|X...X|X...X|.XXX.",
    P: "XXXX.|X...X|X...X|XXXX.|X....|X....|X....", R: "XXXX.|X...X|X...X|XXXX.|X.X..|X..X.|X...X",
    S: ".XXXX|X....|X....|.XXX.|....X|....X|XXXX.", T: "XXXXX|..X..|..X..|..X..|..X..|..X..|..X..",
    U: "X...X|X...X|X...X|X...X|X...X|X...X|.XXX.", W: "X...X|X...X|X...X|X.X.X|X.X.X|XX.XX|X...X",
    Y: "X...X|X...X|.X.X.|..X..|..X..|..X..|..X..", J: "..XXX|...X.|...X.|...X.|...X.|X..X.|.XX..", Q: ".XXX.|X...X|X...X|X...X|X.X.X|X..X.|.XX.X",
    V: "X...X|X...X|X...X|X...X|X...X|.X.X.|..X..", X: "X...X|X...X|.X.X.|..X..|.X.X.|X...X|X...X", Z: "XXXXX|....X|...X.|..X..|.X...|X....|XXXXX", ".": ".....|.....|.....|.....|.....|.....|..X..",
    "-": ".....|.....|.....|XXXXX|.....|.....|.....", " ": ".....|.....|.....|.....|.....|.....|....."
  };
  function rows(ch) { return (F[ch] || F[" "]).split("|"); }

  function circle(cx, cy, r, fill, op) { return '<circle cx="' + cx.toFixed(2) + '" cy="' + cy.toFixed(2) + '" r="' + r.toFixed(2) + '" fill="' + fill + '"' + (op != null && op < 1 ? ' fill-opacity="' + op + '"' : "") + "/>"; }

  /* A grid of dots: `lit(c, r)` says which ones are on. Every `cell` columns/rows there is an extra `gap` (the braille
     cell is 2 columns × 4 rows). Unlit dots stay visible, smaller and dim: the display is "off", not absent. */
  function grid(o) {
    var cols = o.cols, rws = o.rows, p = o.pitch || 10, r = o.r || p * 0.32, gx = o.gapX == null ? 0 : o.gapX, gy = o.gapY == null ? 0 : o.gapY;
    var cx = o.cellX || 0, cy = o.cellY || 0, out = [], xs = [], ys = [];
    for (var c = 0; c < cols; c++) xs.push(c * p + (cx ? Math.floor(c / cx) * gx : 0));
    for (var q = 0; q < rws; q++) ys.push(q * p + (cy ? Math.floor(q / cy) * gy : 0));
    var w = xs[cols - 1] + p, h = ys[rws - 1] + p;
    for (var y = 0; y < rws; y++) for (var x = 0; x < cols; x++) {
      var on = o.lit(x, y);
      if (on) out.push(circle(xs[x] + p / 2, ys[y] + p / 2, r, o.on, 1));
      else if (o.off) out.push(circle(xs[x] + p / 2, ys[y] + p / 2, r * (o.offScale || 0.42), o.off, o.offOpacity == null ? 0.55 : o.offOpacity));
    }
    return { w: w, h: h, body: out.join("") };
  }
  function svg(g, o) {
    o = o || {};
    var pad = o.pad || 0, vb = [-pad, -pad, g.w + 2 * pad, g.h + 2 * pad];
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + vb.join(" ") + '"' + (o.width ? ' width="' + o.width + '"' : "") + (o.height ? ' height="' + o.height + '"' : "") + (o.cls ? ' class="' + o.cls + '"' : "") + ' role="img" aria-label="' + (o.label || "Leader") + '">' +
      (o.bg ? '<rect x="' + vb[0] + '" y="' + vb[1] + '" width="' + vb[2] + '" height="' + vb[3] + '" fill="' + o.bg + '"/>' : "") + g.body + "</svg>";
  }

  /* ── the mark: N ─────────────────────────────────────────────────────────────────────────────── */
  /* Patterns, one string per row. "brailleN" is 6×8 = 3×2 braille cells; "heavyN" is 8×12 = 4×3 cells with 2-dot stems. */
  var PAT = {
    brailleN: ["X....X", "XX...X", "XX...X", "X.X..X", "X..X.X", "X...XX", "X...XX", "X....X"],
    classicN: ["X...X", "XX..X", "X.X.X", "X.X.X", "X..XX", "X...X", "X...X"]
  };
  function heavyN() {
    var out = [];
    for (var r = 0; r < 12; r++) {
      var line = "", dx = 1.5 + (r * 5) / 11;
      for (var c = 0; c < 8; c++) line += c <= 1 || c >= 6 || Math.abs(c + 0.5 - dx - 0.5) < 0.95 ? "X" : ".";
      out.push(line);
    }
    return out;
  }
  PAT.heavyN = heavyN();

  /* mark({ pattern, on, off, ... }) → { w, h, body } (use svg() to wrap). Braille cell spacing unless `flat`. */
  function mark(o) {
    o = o || {};
    var pat = PAT[o.pattern || "brailleN"], rws = pat.length, cols = pat[0].length, braille = !o.flat && (o.pattern || "brailleN") !== "classicN";
    return grid({ cols: cols, rows: rws, pitch: o.pitch || 10, r: o.r, gapX: braille ? (o.gap == null ? 3 : o.gap) : 0, gapY: braille ? (o.gap == null ? 3 : o.gap) : 0, cellX: braille ? 2 : 0, cellY: braille ? 4 : 0,
      lit: function (c, r) { return pat[r][c] === "X"; }, on: o.on || "#b8bb26", off: o.off === undefined ? o.on || "#b8bb26" : o.off, offScale: o.offScale, offOpacity: o.offOpacity });
  }

  /* ── dot-matrix text ─────────────────────────────────────────────────────────────────────────── */
  function text(str, o) {
    o = o || {};
    str = String(str).toUpperCase();
    var p = o.pitch || 10, r = o.r || p * 0.34, spacing = o.spacing == null ? 1 : o.spacing, body = [], x0 = 0;
    for (var i = 0; i < str.length; i++) {
      var g = rows(str[i]);
      for (var y = 0; y < 7; y++) for (var x = 0; x < 5; x++) {
        var on = g[y][x] === "X";
        if (on) body.push(circle(x0 + x * p + p / 2, y * p + p / 2, r, o.on || "#b8bb26", 1));
        else if (o.off) body.push(circle(x0 + x * p + p / 2, y * p + p / 2, r * (o.offScale || 0.42), o.off, o.offOpacity == null ? 0.5 : o.offOpacity));
      }
      x0 += (5 + spacing) * p;
    }
    return { w: Math.max(p, x0 - spacing * p), h: 7 * p, body: body.join("") };
  }

  var API = { mark: mark, text: text, svg: svg, grid: grid, PATTERNS: PAT, GLYPHS: F };
  if (typeof module === "object" && module.exports) module.exports = API; else root.DOTS = API;
})(typeof self !== "undefined" ? self : this);
