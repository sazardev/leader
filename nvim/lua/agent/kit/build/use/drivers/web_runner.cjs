// Build with agent · use: one scenario in a browser (or an Electron window), driven by Playwright.
// stdin: {"mode":"web"|"electron","url":"http://…","root":"…","viewport":"1280x800","steps":[…],"shots":"dir"}
// stdout: one JSON array of frames: {"step":n,"did":"…","screen":"…","image":"…png","error":"…"}
// A frame's screen is what a screen reader would announce (Playwright's ARIA snapshot), then the layout problems a user
// would see (sideways scroll, elements out of the window, overlapping controls, tiny targets, cut text) and the
// JavaScript errors the page threw: a button wired to nothing usually shows up there.
"use strict";

const fs = require("fs");
const path = require("path");
const pw = require(process.env.PLAYWRIGHT_MODULE || "playwright");

const STEP_TIMEOUT = 3000;

function size(text, fallback) {
  const m = /^(\d+)x(\d+)$/.exec(text || "");
  return m ? { width: +m[1], height: +m[2] } : fallback;
}

function locate(page, t) {
  if (!t || typeof t !== "object") throw new Error("no target");
  if (t.role) return page.getByRole(t.role, t.name ? { name: t.name } : {}).first();
  if (t.label) return page.getByLabel(t.label).first();
  if (t.placeholder) return page.getByPlaceholder(t.placeholder).first();
  if (t.testid) return page.getByTestId(t.testid).first();
  if (t.text) return page.getByText(t.text).first();
  if (t.css) return page.locator(t.css).first();
  throw new Error("unknown target " + JSON.stringify(t));
}

// Layout problems, measured in the page (no model needed to see them)
function layout() {
  const out = [];
  const vw = window.innerWidth;
  const doc = document.documentElement;
  if (doc.scrollWidth > vw + 1) out.push(`the page scrolls sideways: it is ${doc.scrollWidth}px wide in a ${vw}px window`);
  const label = (el) => {
    const name = (el.getAttribute("aria-label") || el.innerText || el.value || el.placeholder || "").trim().slice(0, 40);
    return `${el.tagName.toLowerCase()}${name ? ` "${name}"` : ""}`;
  };
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== "hidden" && s.display !== "none" && +s.opacity !== 0;
  };
  const controls = [...document.querySelectorAll("button, a[href], input, select, textarea, [role=button], [tabindex]")].filter(visible);
  let n = 0;
  for (const el of controls) {
    const r = el.getBoundingClientRect();
    if ((r.right > vw + 1 || r.left < -1) && n < 5) {
      out.push(`${label(el)} is partly outside the window (x ${Math.round(r.left)}–${Math.round(r.right)}, window ${vw}px)`);
      n++;
    }
  }
  n = 0;
  for (const el of controls) {
    const r = el.getBoundingClientRect();
    if ((r.width < 24 || r.height < 24) && el.tagName !== "A" && n < 5) {
      out.push(`${label(el)} is a small target (${Math.round(r.width)}×${Math.round(r.height)}px, under 24px)`);
      n++;
    }
  }
  n = 0;
  for (let i = 0; i < controls.length && n < 5; i++) {
    for (let j = i + 1; j < controls.length && n < 5; j++) {
      const a = controls[i].getBoundingClientRect();
      const b = controls[j].getBoundingClientRect();
      if (controls[i].contains(controls[j]) || controls[j].contains(controls[i])) continue;
      const w = Math.min(a.right, b.right) - Math.max(a.left, b.left);
      const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
      if (w > 0 && h > 0 && w * h > 0.3 * Math.min(a.width * a.height, b.width * b.height)) {
        out.push(`${label(controls[i])} overlaps ${label(controls[j])}`);
        n++;
      }
    }
  }
  n = 0;
  for (const el of document.querySelectorAll("body *")) {
    if (n >= 5) break;
    if (!el.childElementCount && el.innerText && el.innerText.trim() && visible(el)) {
      const s = getComputedStyle(el);
      if (el.scrollWidth > el.clientWidth + 1 && (s.overflow === "hidden" || s.textOverflow === "ellipsis" || s.overflowX === "hidden")) {
        out.push(`the text "${el.innerText.trim().slice(0, 40)}" is cut off`);
        n++;
      }
    }
  }
  const focused = document.activeElement && document.activeElement !== document.body ? label(document.activeElement) : null;
  if (focused) out.push(`focus: ${focused}`);
  return out;
}

async function capture(page, i, shots, errors) {
  let tree;
  try {
    tree = await page.locator("body").ariaSnapshot({ timeout: STEP_TIMEOUT });
  } catch (e) {
    tree = await page.evaluate(() => document.body.innerText).catch(() => "");
  }
  const facts = await page.evaluate(layout).catch(() => []);
  let screen = tree.trim();
  if (facts.length) screen += "\n[layout]\n- " + facts.join("\n- ");
  if (errors.length) screen += "\n[javascript errors]\n- " + errors.splice(0).slice(0, 5).join("\n- ");
  const image = path.join(shots, `step-${String(i).padStart(2, "0")}.png`);
  await page.screenshot({ path: image }).catch(() => {});
  return { screen, image };
}

async function act(page, s) {
  const d = s.do;
  if (d === "goto") return page.goto(new URL(s.path || "/", page.__base).href, { timeout: 15000 });
  if (d === "click") return locate(page, s.target).click({ timeout: STEP_TIMEOUT });
  if (d === "fill") return locate(page, s.target).fill(String(s.value), { timeout: STEP_TIMEOUT });
  if (d === "press") return page.keyboard.press(s.key);
  if (d === "select") return locate(page, s.target).selectOption({ label: String(s.value) }, { timeout: STEP_TIMEOUT }).catch(() => locate(page, s.target).selectOption(String(s.value), { timeout: STEP_TIMEOUT }));
  if (d === "check") return locate(page, s.target).check({ timeout: STEP_TIMEOUT });
  if (d === "hover") return locate(page, s.target).hover({ timeout: STEP_TIMEOUT });
  if (d === "viewport") return page.setViewportSize(size(s.size, { width: 1280, height: 800 }));
  if (d === "wait") return page.waitForTimeout(Math.min(5000, s.ms || 300));
  throw new Error("unknown action " + d);
}

function describe(s) {
  const t = (x) => (x ? (x.role ? `${x.role} "${x.name || ""}"` : Object.entries(x).map(([k, v]) => `${k} "${v}"`)[0]) : "?");
  switch (s.do) {
    case "goto": return "open " + (s.path || "/");
    case "fill": return `fill ${t(s.target)} with ${JSON.stringify(s.value)}`;
    case "press": return "key " + s.key;
    case "viewport": return "resize to " + s.size;
    case "wait": return `wait ${s.ms || 300} ms`;
    case "select": return `choose ${JSON.stringify(s.value)} in ${t(s.target)}`;
    default: return `${s.do} ${t(s.target)}`;
  }
}

async function main() {
  const input = JSON.parse(fs.readFileSync(0, "utf8"));
  fs.mkdirSync(input.shots, { recursive: true });
  const errors = [];
  let browser, app, page;
  if (input.mode === "electron") {
    app = await pw._electron.launch({ args: [input.root], cwd: input.root });
    page = await app.firstWindow();
  } else {
    browser = await pw.chromium.launch();
    const context = await browser.newContext({ viewport: size(input.viewport, { width: 1280, height: 800 }) });
    page = await context.newPage();
    page.__base = input.url;
  }
  page.on("console", (m) => m.type() === "error" && errors.push(m.text().slice(0, 300)));
  page.on("pageerror", (e) => errors.push(String(e.message || e).slice(0, 300)));
  const frames = [];
  const steps = input.steps || [];
  if (input.mode !== "electron" && (!steps.length || steps[0].do !== "goto")) {
    await page.goto(input.url, { timeout: 15000 }).catch((e) => errors.push(String(e.message).split("\n")[0]));
  }
  await page.waitForLoadState("networkidle", { timeout: 3000 }).catch(() => {});
  frames.push({ step: 0, did: "start", ...(await capture(page, 0, input.shots, errors)) });
  for (let i = 0; i < steps.length; i++) {
    let error;
    try {
      await act(page, steps[i]);
    } catch (e) {
      error = String(e.message || e).split("\n")[0].slice(0, 300);
    }
    await page.waitForLoadState("networkidle", { timeout: 2000 }).catch(() => {});
    await page.waitForTimeout(150);
    frames.push({ step: i + 1, did: describe(steps[i]), error, ...(await capture(page, i + 1, input.shots, errors)) });
  }
  if (app) await app.close();
  if (browser) await browser.close();
  process.stdout.write(JSON.stringify(frames));
}

main().catch((e) => {
  process.stderr.write(String(e && e.stack ? e.stack : e));
  process.exit(1);
});
