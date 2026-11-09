// The margin garden (src/lib/margins.js) on the built site in headless
// Chrome: plants grow either side of each page's content and never behind
// it, a reader who jumps down a long page finds the margins grown where
// they look within seconds, tools and phones get none, and reduced motion
// shows each plant whole. Also the layout helpers, without a browser.
//
//   just test-site      (builds first; needs Google Chrome)
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";
import { rowGrowth, targetRow, tilesOf, MIN_MARGIN, TILE, FIRST_TILE } from "../src/lib/margins-layout.js";

// A run is drawn in windows that cover it exactly, each a whole number of
// birth cells from its top.
for (const h of [320, 1200, 1201, 15567]) {
  const ws = tilesOf(h);
  assert.equal(ws[0].y, 0);
  for (let i = 1; i < ws.length; i++) assert.equal(ws[i].y, ws[i - 1].y + ws[i - 1].h);
  assert.equal(ws[ws.length - 1].y + ws[ws.length - 1].h, h);
  for (const w of ws) assert.ok(w.y % 3 === 0 && w.h <= TILE && w.h > 0, `window ${JSON.stringify(w)} of ${h}`);
  assert.ok(ws[0].h <= FIRST_TILE, `the first window of ${h} is ${ws[0].h} tall`);
}
// The front's growth by row never falls, and carries on past the foot
// without a jump.
{
  const rows = Float32Array.from([0, 5, 5, 12, 30]);
  let prev = -1;
  for (let r = -3; r < 40; r += 0.5) {
    const g = rowGrowth(rows, 3, r);
    assert.ok(g >= prev, `rowGrowth falls at row ${r}`);
    prev = g;
  }
  assert.equal(rowGrowth(rows, 3, 15), 30);
  assert.equal(rowGrowth(rows, 3, 25), 40);
}
// The front leads the reader, and takes in the whole page at its foot or
// on a page that does not scroll.
assert.ok(targetRow(0, 800, 5000, 0.9) > 600 && targetRow(0, 800, 5000, 0.9) < 800);
assert.equal(targetRow(0, 800, 5000, 1), 800);
assert.equal(targetRow(4200, 800, 5000), 5000);
assert.equal(targetRow(0, 800, 700), 700);
for (let y = 0; y <= 4200; y += 300) assert.ok(targetRow(y, 800, 5000) >= y + 600, `the front trails the reader at ${y}`);

const SITE = join(dirname(fileURLToPath(import.meta.url)), "..");
const PORT = process.env.SITE_TEST_PORT_MARGINS || "4318";
const URL = `http://127.0.0.1:${PORT}/`;
let failures = 0;
const check = (ok, msg) => { if (!ok) { failures++; console.error("FAIL: " + msg); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const server = spawn("npx", ["vite", "preview", "--port", PORT, "--strictPort", "--host", "127.0.0.1"], { cwd: SITE, stdio: "ignore" });
let browser;
try {
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(URL)).ok) break; } catch { /* not up yet */ }
    await sleep(150);
  }
  browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
  const errors = [];
  const open = async (path, o = {}) => {
    const p = await browser.newPage({ viewport: { width: 1280, height: 800 }, ...o });
    p.on("pageerror", (e) => errors.push(`${path}: ${e}`));
    p.on("console", (m) => { if (m.type() === "error") errors.push(`${path}: ${m.text()}`); });
    await p.goto(URL + path);
    return p;
  };
  const state = (p) => p.evaluate(() => window.__floraMargins?.state ?? null);
  // The share of inked samples in the margins' canvases over page rows
  // y0..y1, per side.
  const inked = (p, y0, y1) => p.evaluate(([y0, y1]) => {
    const out = { left: [0, 0], right: [0, 0] };
    for (const c of document.querySelectorAll(".flora-margins canvas")) {
      const top = parseFloat(c.style.top), h = parseFloat(c.style.height), k = c.height / h;
      const a = Math.max(y0, top), b = Math.min(y1, top + h);
      if (b <= a) continue;
      const d = c.getContext("2d").getImageData(0, Math.floor((a - top) * k), c.width, Math.ceil((b - a) * k)).data;
      const side = parseFloat(c.style.left) === 0 ? out.left : out.right;
      for (let i = 3; i < d.length; i += 4 * 5) { side[1]++; if (d[i] > 40) side[0]++; }
    }
    return { left: out.left[0] / Math.max(1, out.left[1]), right: out.right[0] / Math.max(1, out.right[1]) };
  }, [y0, y1]);

  // Both margins grow on the home page, from the top corners.
  {
    const p = await open("");
    await sleep(4000);
    const s = await state(p);
    check(s && s.sides.length === 2, `home: margins ${JSON.stringify(s?.sides)}`);
    // One plant down each side, through the strip of pages.
    for (const mirror of [false, true]) {
      const n = s?.runs.filter((r) => r.mirror === mirror).length;
      check(n === 1, `home: the ${mirror ? "right" : "left"} margin grows ${n} plants, not 1`);
    }
    const top = await inked(p, 0, 400);
    check(top.left > 0.08 && top.right > 0.08, `home: the top corners are bare after 4 s (${JSON.stringify(top)})`);
    // Beside the strip only stems run on: some ink, but far less than in
    // the margin just above it, where leaves and blooms grow.
    const [b0, b1] = await p.evaluate(() => { const r = document.querySelector("[data-flora-avoid]").getBoundingClientRect(); return [r.top + scrollY, r.bottom + scrollY]; });
    for (let y = 0; y <= b1; y += 400) { await p.evaluate((y) => scrollTo(0, y), y); await sleep(500); }
    await p.evaluate((y) => scrollTo(0, y), b1);
    await p.waitForFunction(([b0, b1]) => window.__floraMargins.state.tiles.filter((t) => t.y < b1 && t.y + t.h > b0 - 400).every((t) => t.state === "done"), [b0, b1], { timeout: 60000 }).catch(() => {});
    const beside = await inked(p, b0, b1), above = await inked(p, b0 - 400, b0);
    for (const k of ["left", "right"]) {
      check(beside[k] > 0.003, `home: no stems run behind the strip on the ${k} (${beside[k].toFixed(4)})`);
      check(beside[k] < above[k] / 3, `home: the ${k} margin beside the strip is as full as above it (${beside[k].toFixed(3)} vs ${above[k].toFixed(3)})`);
    }
    await p.close();
  }

  // The two margins start growing together, even when one is drawn
  // later: here the second margin worker's replies are held back 700 ms.
  {
    const p = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await p.addInitScript(() => {
      let made = 0;
      const W = window.Worker;
      window.Worker = class extends W {
        constructor(url, o) {
          super(url, o);
          this.margin = String(url).includes("margins.worker");
          this.tiles = new Set();
        }
        postMessage(msg, ...args) {
          if (this.margin && msg.kind === "tile") {
            if (this.slow === undefined) this.slow = ++made === 2;
            this.tiles.add(msg.id);
          }
          return super.postMessage(msg, ...args);
        }
        // The delay counts from the first reply, so that how long the
        // slow worker took on its own doesn't add to it.
        set onmessage(f) {
          super.onmessage = !this.margin ? f : (e) => {
            if (!this.tiles.delete(e.data.id)) { f(e); return; }
            window.__firstReply ??= performance.now();
            const wait = this.slow ? window.__firstReply + 700 - performance.now() : 0;
            if (wait > 0) setTimeout(() => f(e), wait); else f(e);
          };
        }
      };
      window.__start = {};
      const t0 = performance.now();
      const tick = () => {
        for (const r of window.__floraMargins?.state?.runs ?? []) {
          const k = r.mirror ? "R" : "L";
          if (r.u > 0 && !(k in window.__start)) window.__start[k] = performance.now() - t0;
        }
        if (!("L" in window.__start && "R" in window.__start)) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
    await p.goto(URL);
    await p.waitForFunction(() => "L" in window.__start && "R" in window.__start, null, { timeout: 30000 }).catch(() => {});
    const st = await p.evaluate(() => window.__start);
    check(st.L !== undefined && st.R !== undefined && Math.abs(st.L - st.R) < 150,
      `home: the margins start growing ${Math.round(Math.abs((st.L ?? 0) - (st.R ?? 0)))} ms apart (${JSON.stringify(st)})`);
    await p.close();
  }

  // A hidden 1 px iframe in the page's corner (the analytics beacon the
  // live site gets) is not content, so both margins still grow.
  {
    const p = await browser.newPage({ viewport: { width: 1280, height: 800 } });
    await p.addInitScript(() => document.addEventListener("DOMContentLoaded", () => {
      const f = document.createElement("iframe");
      f.width = f.height = "1";
      f.style.cssText = "position:absolute;top:0;left:0;border:none;visibility:hidden";
      document.body.append(f);
    }));
    await p.goto(URL);
    await sleep(2000);
    const s = await state(p);
    check(s?.sides.length === 2, `home with a hidden corner iframe: margins ${JSON.stringify(s?.sides)}`);
    await p.close();
  }

  // On the guide the plants stay out of the sticky plate and the contents
  // column, which sit outside the running head; and a reader who jumps
  // halfway down finds the margins grown in view within seconds (the
  // plant above the viewport is not regrown out of sight first).
  {
    const p = await open("guide/");
    await p.locator(".flora-margins canvas").first().waitFor({ state: "attached" });
    const edges = await p.evaluate(() => {
      const cs = [...document.querySelectorAll(".flora-margins canvas")];
      const reach = (left) => cs.filter((c) => (parseFloat(c.style.left) === 0) === left).map((c) => c.getBoundingClientRect());
      const content = [...document.querySelectorAll("main *, header *, aside *, nav *")].filter((e) => !e.closest("[data-flora-avoid]"))
        .map((e) => e.getBoundingClientRect()).filter((r) => r.width > 0 && r.height > 0 && r.width < document.documentElement.clientWidth - 1);
      return {
        leftEnd: Math.max(...reach(true).map((r) => r.right)), rightStart: Math.min(...reach(false).map((r) => r.left)),
        contentL: Math.min(...content.map((r) => r.left)), contentR: Math.max(...content.map((r) => r.right)),
      };
    });
    // A tile reaches INTO (30 px) into the column's clear edge band, no more.
    check(edges.leftEnd <= edges.contentL + 31, `guide: the left garden reaches ${edges.leftEnd}, content starts at ${edges.contentL}`);
    check(edges.rightStart >= edges.contentR - 31, `guide: the right garden starts at ${edges.rightStart}, content ends at ${edges.contentR}`);
    // The guide's 15,000 px margin is one plant a side, not a stack.
    const runs = (await state(p))?.runs ?? [];
    check(runs.length === 2 && runs.every((r) => r.y === 0), `guide: plants ${JSON.stringify(runs.map((r) => [r.mirror, r.y, r.h]))}`);
    await sleep(1000);
    // A slow catch-up, so only the rule under test (what lies above the
    // viewport is shown grown) can fill the view in time.
    await p.evaluate(() => window.__floraMargins.tune({ catch: 0.3 }));
    const y = await p.evaluate(() => {
      const y = Math.round((document.documentElement.scrollHeight - innerHeight) * 0.5);
      window.scrollTo(0, y);
      return y;
    });
    // Once the tiles in view are drawn (how long that takes is the
    // machine's business), 2 s takes the view most of the way to grown;
    // regrowing the part above the viewport first leaves it nearly bare
    // that long.
    await p.waitForFunction(() => window.__floraMargins.state.tiles
      .filter((t) => t.y < scrollY + innerHeight && t.y + t.h > scrollY)
      .every((t) => t.state === "ready" || t.state === "done"), null, { timeout: 60000 });
    await sleep(2000);
    const soon = await inked(p, y, y + 480);
    await sleep(4000);
    const grown = await inked(p, y, y + 480);
    for (const k of ["left", "right"]) {
      check(grown[k] > 0.04, `guide: the ${k} margin in view is bare once grown (${grown[k]})`);
      check(soon[k] >= grown[k] * 0.6, `guide: the ${k} margin in view is ${soon[k]} inked 2 s after a jump, ${grown[k]} grown`);
    }
    await p.close();
  }

  // Normal motion also finishes the last plant at the page's foot,
  // including a viewport tall enough that the page does not scroll.
  for (const vh of [800, 6000]) {
    const p = await open("", { viewport: { width: 1280, height: vh } });
    await p.waitForFunction(() => window.__floraMargins?.state.runs.length > 0);
    await p.evaluate(() => {
      window.__floraMargins.tune({ slow: 90000, top: 90000, ease: 0.05 });
      window.scrollTo(0, document.documentElement.scrollHeight);
    });
    await p.waitForFunction(() => {
      const s = window.__floraMargins.state;
      return s.runs.length > 0 && s.runs.every((r) => r.full > 0 && r.u >= r.full)
        && s.tiles.every((t) => t.state === "done");
    }, null, { timeout: 60000 }).catch(() => check(false, `normal motion: plants never finish at foot (viewport ${vh})`));
    await p.close();
  }

  // Under reduced motion each plant in view appears whole.
  {
    const p = await open("", { reducedMotion: "reduce" });
    await p.waitForFunction(() => {
      const s = window.__floraMargins?.state;
      return s && s.tiles.filter((t) => t.y < innerHeight).every((t) => t.state === "done");
    }, null, { timeout: 15000 }).catch(() => check(false, "reduced motion: the plants in view never finish"));
    await p.close();
  }

  // A tool page is inset on wide screens to grow a plant each side, and
  // given the whole width (so no garden) on narrower ones; a phone has no
  // margin to give.
  {
    const p = await open("mixer/", { viewport: { width: 1440, height: 900 } });
    await p.waitForFunction(() => window.__floraMargins?.state?.tiles?.some((t) => t.state === "ready" || t.state === "done"), null, { timeout: 60000 }).catch(() => {});
    const ms = await state(p);
    check(ms?.sides.length === 2 && ms.sides.every((sd) => sd.m >= MIN_MARGIN), `mixer: wide screen sides ${JSON.stringify(ms?.sides ?? "no garden")}`);
    // The garden stays outside the tool: its head and panes start past each side's plant.
    const box = await p.evaluate(() => [...document.querySelectorAll("header.head, main")].map((e) => { const b = e.getBoundingClientRect(); return [b.left, innerWidth - b.right]; }));
    check(box.every(([l, r]) => l >= MIN_MARGIN && r >= MIN_MARGIN), `mixer: tool reaches into the margins ${JSON.stringify(box)}`);
    await p.close();
    const narrow = await open("mixer/", { viewport: { width: 1100, height: 800 } });
    await sleep(1500);
    check(await narrow.locator(".flora-margins").count() === 0, "mixer: a garden grows on a screen too narrow to inset the tool");
    await narrow.close();
    const phone = await open("", { viewport: { width: 390, height: 844 } });
    await sleep(1500);
    const s = await state(phone);
    check(s && s.sides.length === 0 && (await phone.locator(".flora-margins").count()) === 0,
      `phone: margins under ${MIN_MARGIN} px grow ${JSON.stringify(s?.sides)}`);
    await phone.close();
  }

  // The gear opens the dials without the panel or the gear counting as
  // content (both margins still grow); the dials' tuning moves the front,
  // and new inks grow the garden afresh.
  {
    const p = await open("");
    await p.locator("button.gear").click();
    await p.locator(".dialkit-root").waitFor({ state: "attached", timeout: 10000 });
    await sleep(1500);
    const s = await state(p);
    check(s?.sides.length === 2, `dials: the margins with the panel open are ${JSON.stringify(s?.sides)}`);
    const moved = await p.evaluate(() => {
      const g = window.__floraMargins, a = g.state.target;
      g.tune({ lead: 0.4 });
      return [a, g.state.target];
    });
    check(moved[1] < moved[0] - 100, `dials: a shorter lead leaves the front at ${moved[1]} (was ${moved[0]})`);
    const regrown = await p.evaluate(async () => {
      const g = window.__floraMargins;
      g.tune({ inks: { leaves: "ku-jaku" } });
      return g.state.tiles.every((t) => t.state === "idle" || t.state === "pending") && g.tuning.inks.leaves === "ku-jaku";
    });
    check(regrown, "dials: new inks do not grow the garden afresh");
    await p.close();
  }

  // The package's ornaments set between the plates draw, each a kind of
  // its slot, and gild in once seen.
  {
    const p = await open("");
    const n = await p.locator(".ornament").count();
    check(n >= 5, `home: ${n} ornaments`);
    await p.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
    await p.waitForFunction(() => document.querySelector("footer .ornament.gilt"), null, { timeout: 15000 })
      .catch(() => check(false, "the colophon's tailpiece never gilds in"));
    const kinds = await p.evaluate(() => [...document.querySelectorAll(".ornament")].map((o) => [o.dataset.slot, o.dataset.kind]));
    const drawn = kinds.filter(([, k]) => k);
    check(drawn.length >= 2, `ornaments drawn: ${JSON.stringify(kinds)}`);
    await p.close();
  }

  // A tile once drawn is kept: in the same browser the page's second visit
  // reads its first tiles from the cache, without growing the plant, and
  // they look as they did when drawn.
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const firstTile = (p) => p.evaluate(() => {
      const c = document.querySelector(".flora-margins canvas");
      return [...c.getContext("2d").getImageData(0, 0, c.width, c.height).data];
    });
    const visit = async () => {
      const p = await ctx.newPage();
      p.on("pageerror", (e) => errors.push(`cache: ${e}`));
      await p.goto(URL);
      await p.waitForFunction(() => window.__floraMargins?.state.tiles[0]?.state === "done", null, { timeout: 60000 });
      const t = await p.evaluate(() => window.__floraMargins.state.tiles[0].timing);
      const px = await firstTile(p);
      await sleep(1500); // the cache is written after the reply
      await p.close();
      return { t, px };
    };
    const a = await visit(), b = await visit();
    check(!a.t?.cached && a.t?.compose > 0, `cache: the first visit did not grow its plant (${JSON.stringify(a.t)})`);
    check(b.t?.cached === 1, `cache: the second visit grew its plant again (${JSON.stringify(b.t)})`);
    let worst = 0;
    for (let i = 0; i < Math.min(a.px.length, b.px.length); i++) worst = Math.max(worst, Math.abs(a.px[i] - b.px[i]));
    check(a.px.length === b.px.length && worst <= 2, `cache: the cached tile differs from the drawn one by ${worst}/255`);
    await ctx.close();
  }

  // Stopping removes the garden and its hook.
  {
    const p = await open("");
    await sleep(800);
    const gone = await p.evaluate(() => {
      window.__floraMargins.stop();
      return !document.querySelector(".flora-margins") && !window.__floraMargins;
    });
    check(gone, "stop() leaves the garden behind");
    await p.close();
  }
  check(errors.length === 0, "page errors: " + errors.join("; "));
} finally {
  if (browser) await browser.close();
  server.kill();
}
if (failures) {
  console.error(`margins: ${failures} failure(s)`);
  process.exit(1);
}
console.log("margins: ok");
