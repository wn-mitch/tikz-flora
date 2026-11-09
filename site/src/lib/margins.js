// The site's margin garden: a plant hangs from the top of each side margin
// and grows down the page as the reader scrolls, painted in by a soft wet
// front. margins.worker.js grows each plant and draws it a window (tile) at
// a time; this module lays the plants out, asks for tiles a little ahead
// of the reader and reveals them by their birth times.
//
//   const garden = startMargins();   // later: garden.stop()
//
// Each side's margin is what the page's content leaves between itself and
// that edge; a side narrower than MIN_MARGIN grows nothing. One plant runs
// the length of each margin. Elements marked data-flora-avoid keep its
// leaves, blooms and sprays out, but not its stems: past one that spans
// the margin, such as the strip of pages, only stems run on, behind it.
// What the reader has scrolled past is shown grown. Under
// prefers-reduced-motion each plant appears whole once drawn.
import { gardenAt } from "./garden.js";
import { client, rgbOf } from "./margins-client.js";
import engine from "@alpaca-software/web-flora/package.json";

// The engine release the tiles are drawn with, for the tile cache.
const ENGINE = engine.version;
import { LEAD, MIN_MARGIN, MIN_RUN, tilesOf, rowGrowth, targetRow, jitter } from "./margins-layout.js";

export { MIN_MARGIN };
// How far a plant reaches into the column, px: the column's edge band,
// which the engine keeps clear.
const INTO = 30;
// How the garden grows, as startMargins starts it; garden.tune(...)
// changes it (the dials, dials.js):
//   lead      the share of the viewport the front heads for (LEAD)
//   soft      the width of the wet front, px of growth
//   slow      the least growth speed, px of growth per second
//   catch     the share of the growth still to go grown each second, so
//             the front eases in behind a quick scroll
//   top       the most growth speed, px of growth per second
//   ease      seconds a plant takes to come up to speed from rest, so it
//             starts as a sprout rather than appearing in a burst
//   colourway tikz-flora's colourway
//   inks      { part: ink name } over the colourway's (inks.ts parts)
export const TUNE = { lead: LEAD, soft: 90, slow: 200, catch: 2, top: 900, ease: 1.2, colourway: "spring" };
// Tiles are asked for this many viewports ahead of the front.
const AHEAD = 1.5;
// The plants at the page's top start growing together, once each has its
// first window drawn, so neither margin starts alone; but a margin drawn
// this much later than the first (ms) is not waited for.
const TOGETHER_MS = 1200;
// How far above the viewport's top the front may still be growing, px.
const UNSEEN = 40;

export function startMargins({ doc = document, win = window } = {}) {
  const reduce = win.matchMedia("(prefers-reduced-motion: reduce)");
  const at = gardenAt();
  const T = { ...TUNE, inks: {} };
  const SOFT = () => T.soft;
  const targetAt = () => targetRow(win.scrollY, win.innerHeight, parseFloat(layer.style.height), T.lead);
  // Two workers, so the two margins grow side by side. A plant is kept by
  // the worker that grew it, so all its tiles go to that worker.
  const workers = [client(), client()];
  const idle = new Set([0, 1]);
  let layer = null, runs = [], tiles = [], raf = 0, stopped = false, layoutKey = "", nextRun = 0;
  // When the first of the top plants could start, and whether they have.
  let firstAt = 0, together = false, held = 0;
  let sides = [], ground = [1, 1, 1], dpr = 1;

  // The viewport width, each side's margin (what the page's content leaves
  // between itself and the edge) and the page's height. Content is every
  // visible element narrower than the viewport, other than what the plants
  // keep out of (data-flora-avoid), the site's own controls (data-flora-ui)
  // and the garden itself. Invisible ones, such as the 1 px hidden iframe
  // an analytics beacon puts in the page's corner, are not content.
  function measure() {
    const vw = doc.documentElement.clientWidth;
    let x0 = vw, x1 = 0;
    for (const el of doc.body.querySelectorAll("*")) {
      if (el.tagName === "SCRIPT" || el.tagName === "STYLE" || el.closest("[data-flora-avoid], [data-flora-ui], .flora-margins")) continue;
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0 || r.width >= vw - 1 || r.right <= 0 || r.left >= vw) continue;
      // Only what would widen the content is checked, as checking is slow.
      if ((r.left < x0 || r.right > x1) && !shown(el)) continue;
      x0 = Math.min(x0, r.left);
      x1 = Math.max(x1, r.right);
    }
    if (x1 <= x0) return null;
    // The old absolute garden must not keep a now shorter page tall.
    const display = layer?.style.display;
    let docH;
    try {
      if (layer) layer.style.display = "none";
      docH = Math.ceil(doc.documentElement.scrollHeight);
    } finally {
      if (layer) layer.style.display = display;
    }
    return { vw, ml: Math.floor(x0), mr: Math.floor(vw - x1), docH };
  }

  // Rects of [data-flora-avoid] elements that reach into run r, run px.
  // Whether `el` is seen: not hidden by visibility or opacity.
  function shown(el) {
    if (el.checkVisibility) return el.checkVisibility({ visibilityProperty: true, opacityProperty: true });
    const cs = win.getComputedStyle(el);
    return cs.visibility !== "hidden" && cs.opacity !== "0";
  }

  function avoidIn(r) {
    const out = [];
    for (const el of doc.querySelectorAll("[data-flora-avoid]")) {
      const b = el.getBoundingClientRect();
      const y0 = b.top + win.scrollY - r.y, y1 = b.bottom + win.scrollY - r.y;
      const x0 = b.left - r.side.x, x1 = b.right - r.side.x;
      if (y1 <= 0 || y0 >= r.h || x1 <= 0 || x0 >= r.side.fw) continue;
      out.push([x0 - 6, y0 - 6, x1 + 6, y1 + 6]);
    }
    return out;
  }

  // The page rows of the full-width bands in a side's margin: the layout
  // is laid afresh when they move, as the plants' stems-only stretches do.
  function bandsOf(side) {
    const out = [];
    for (const el of doc.querySelectorAll("[data-flora-avoid]")) {
      const r = el.getBoundingClientRect();
      if (r.height <= 0 || r.left > side.x + 1 || r.right < side.x + side.fw - 1) continue;
      out.push([Math.floor(r.top + win.scrollY), Math.ceil(r.bottom + win.scrollY)]);
    }
    return out;
  }

  // Add a plant to side over page rows y..y+h, with its tiles.
  function addRun(side, y, h) {
    const k = runs.filter((r) => r.side === side).length;
    const r = {
      key: `r${nextRun++}`, side, k, y, h, tiles: [], rows: null, born: 0, u: -1, cell: 3,
      seed: at.seed * 4 + k * 2 + (side.mirror ? 1 : 0),
      wi: sides.length === 2 ? (side.mirror ? 1 : 0) : k % 2,
    };
    for (const w of tilesOf(h)) {
      const canvas = doc.createElement("canvas");
      canvas.width = Math.round(side.fw * dpr);
      canvas.height = Math.round(w.h * dpr);
      Object.assign(canvas.style, { position: "absolute", left: `${side.x}px`, top: `${y + w.y}px`, width: `${side.fw}px`, height: `${w.h}px` });
      layer.append(canvas);
      const t = { run: r, ly: w.y, y: y + w.y, h: w.h, canvas, state: "idle", data: null, shown: -1, blo: 0, bhi: 0 };
      r.tiles.push(t);
      tiles.push(t);
    }
    runs.push(r);
  }

  function dropRun(r) {
    for (const t of r.tiles) { t.canvas.remove(); t.data?.bitmap?.close?.(); }
    runs = runs.filter((x) => x !== r);
    tiles = tiles.filter((t) => t.run !== r);
  }

  // Lay side's plant down to docH, past any it has. A last plant nothing
  // has been drawn of yet is laid again, so a page that settles taller
  // just after loading keeps one plant to its foot.
  function addRuns(side, docH) {
    let mine = runs.filter((r) => r.side === side);
    const last = mine[mine.length - 1];
    if (last && last.tiles.every((t) => t.state === "idle")) { dropRun(last); mine = mine.slice(0, -1); }
    const tail = mine[mine.length - 1];
    const from = tail ? tail.y + tail.h : 0;
    if (docH - from >= MIN_RUN) addRun(side, from, docH - from);
  }

  // What the layout depends on, other than the page's height.
  const keyOf = (g) => (g ? `${g.vw}:${g.ml}:${g.mr}:${JSON.stringify(sidesOf(g).map((sd) => sd.bands))}` : "");

  function sidesOf(g) {
    const out = [];
    for (const [mirror, m] of [[false, g.ml], [true, g.mr]]) {
      if (m < MIN_MARGIN) continue;
      const fw = m + INTO;
      const side = { mirror, m, fw, x: mirror ? g.vw - fw : 0 };
      side.bands = bandsOf(side);
      out.push(side);
    }
    return out;
  }

  function build() {
    const g = measure();
    teardown();
    firstAt = 0;
    together = false;
    win.clearTimeout(held);
    if (!g) return;
    sides = sidesOf(g);
    layoutKey = keyOf(g);
    if (sides.length === 0) return;
    layer = doc.createElement("div");
    layer.className = "flora-margins";
    layer.setAttribute("aria-hidden", "true");
    Object.assign(layer.style, {
      position: "absolute", left: "0", top: "0", width: `${g.vw}px`, height: `${g.docH}px`,
      overflow: "hidden", pointerEvents: "none", zIndex: "-1",
    });
    doc.body.append(layer);
    ground = rgbOf(win.getComputedStyle(doc.body).backgroundColor);
    dpr = Math.min(2, Math.max(1, win.devicePixelRatio || 1));
    for (const side of sides) addRuns(side, g.docH);
    kick();
  }

  function teardown() {
    layer?.remove();
    layer = null;
    for (const t of tiles) t.data?.bitmap?.close?.();
    runs = [];
    tiles = [];
  }

  const bottom = (t) => t.y + t.h;

  // Ask each free worker for the tile of its plants most needed: those in
  // view first, then those ahead of the front, then those passed.
  function request() {
    if (stopped || !layer) return;
    for (const wi of [...idle]) {
      const top = win.scrollY, vh = win.innerHeight, foot = top + vh;
      const horizon = targetAt() + vh * AHEAD;
      let best = null, bestScore = Infinity;
      for (const t of tiles) {
        if (t.state !== "idle" || t.run.wi !== wi) continue;
        let score;
        if (bottom(t) > top && t.y < foot) score = t.y - top;
        else if (t.y >= foot) score = t.y < horizon ? 1e5 + t.y : Infinity;
        else score = 1e7 - t.y;
        if (score < bestScore) { bestScore = score; best = t; }
      }
      if (!best) continue;
      const t = best, r = t.run;
      idle.delete(wi);
      t.state = "pending";
      workers[wi].post({
        kind: "tile", run: r.key, fw: r.side.fw, h: r.h, m: r.side.m, seed: r.seed, mirror: r.side.mirror, dpr,
        colourway: T.colourway, inks: T.inks, avoid: avoidIn(r), paper: ground, y0: t.ly, th: t.h, rows: !r.rows, engine: ENGINE,
      }).then((data) => {
        if (!tiles.includes(t)) { data.bitmap.close?.(); return; }
        if (data.rows && !r.rows) {
          r.rows = data.rows; r.cell = data.cell; r.born = data.full;
          if (r.y === 0 && !firstAt) firstAt = performance.now();
        }
        let lo = Infinity, hi = 0;
        for (let i = 0; i < data.birth.length; i++) { lo = Math.min(lo, data.birth[i]); hi = Math.max(hi, data.birth[i]); }
        t.data = { ...data, jitter: jitter(data.nx, data.ny, r.seed * 31 + t.ly) };
        t.blo = lo;
        t.bhi = hi;
        t.state = "ready";
      }, (err) => {
        t.state = "failed";
        console.error(err);
      }).finally(() => {
        idle.add(wi);
        kick();
      });
    }
  }

  // Paint tile t revealed to growth u.
  function paint(t, u) {
    const d = t.data, ctx = t.canvas.getContext("2d");
    const W = t.canvas.width, H = t.canvas.height;
    ctx.clearRect(0, 0, W, H);
    if (u <= 0) return;
    ctx.globalCompositeOperation = "source-over";
    ctx.drawImage(d.bitmap, 0, 0, W, H);
    if (u >= hiOf(t)) return;
    d.mask ??= new OffscreenCanvas(d.nx, d.ny);
    const mc = d.mask.getContext("2d");
    d.pixels ??= mc.createImageData(d.nx, d.ny);
    const px = d.pixels.data, b = d.birth, jit = d.jitter;
    for (let i = 0; i < b.length; i++) {
      let a = (u - b[i] - jit[i] * 16) / SOFT();
      a = a <= 0 ? 0 : a >= 1 ? 1 : a * a * (3 - 2 * a);
      px[i * 4 + 3] = a * 255;
    }
    mc.putImageData(d.pixels, 0, 0);
    ctx.globalCompositeOperation = "destination-in";
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(d.mask, 0, 0, W, H);
    ctx.globalCompositeOperation = "source-over";
  }

  // The growth before which tile t shows nothing, and by which it is whole;
  // and by which run r is whole.
  const loOf = (t) => t.blo - SOFT() - 16;
  const hiOf = (t) => t.bhi + SOFT() * 1.3;
  const fullOf = (r) => r.born + SOFT() * 1.3;

  function finish(t) {
    paint(t, hiOf(t));
    t.shown = hiOf(t);
    t.state = "done";
    const d = t.data;
    d.birth = d.jitter = d.mask = d.pixels = null;
  }

  let last = 0;
  function frame(now) {
    raf = 0;
    if (stopped || !layer) return;
    const dt = last ? Math.min(0.1, (now - last) / 1000) : 0;
    last = now;
    const top = win.scrollY;
    const target = targetAt();
    // Hold the top plants, once one can start, until each can, or until
    // TOGETHER_MS has passed. (Before one can, there is nothing to grow.)
    if (!together && firstAt) {
      const wait = TOGETHER_MS - (performance.now() - firstAt);
      if (runs.some((r) => r.y === 0 && !r.rows) && wait > 0) {
        win.clearTimeout(held);
        held = win.setTimeout(() => kick(), wait);
        request();
        last = 0;
        return;
      }
      together = true;
    }
    let moving = false;
    for (const r of runs) {
      if (!r.rows) continue;
      const reach = target - r.y;
      const full = fullOf(r);
      const cap = reach >= r.h ? full : Math.min(full, rowGrowth(r.rows, r.cell, reach) + (reach > 0 ? SOFT() * 0.6 : 0));
      let u = r.u < 0 ? 0 : r.u;
      if (reduce.matches) u = reach > 0 ? full : u;
      else if (u < cap) {
        // The speed the front wants, reached from rest over T.ease seconds
        // and dropped at once when the front nears its cap.
        const want = Math.min(T.top, Math.max(T.slow, (cap - u) * T.catch));
        const accel = T.top / Math.max(0.05, T.ease);
        r.v = Math.min(want, (r.v ?? 0) + accel * dt);
        u = Math.min(cap, u + r.v * dt);
      } else r.v = 0;
      // What lies above the viewport is shown grown: nobody saw it grow,
      // and the front should be where the reader is looking.
      if (top > r.y) u = Math.max(u, Math.min(cap, rowGrowth(r.rows, r.cell, top - r.y - UNSEEN)));
      if (u > r.u) r.u = u;
      if (!reduce.matches && u < cap - 0.25) moving = true;
      for (const t of r.tiles) {
        if (t.state !== "ready") continue;
        if (bottom(t) <= top || r.u >= hiOf(t)) { finish(t); continue; }
        // Paint only what the front shows anew.
        if (r.u > loOf(t) && r.u > t.shown + 0.25) {
          paint(t, r.u);
          t.shown = r.u;
        }
      }
    }
    request();
    if (moving) kick(false);
    else last = 0;
  }

  function kick(reset = true) {
    if (reset) last = 0;
    if (!raf && !stopped) raf = win.requestAnimationFrame(frame);
  }

  // A new width, margin or band lays the garden out afresh; a taller page
  // (fonts and images arriving) adds plants below, keeping what has grown.
  let resizeTimer = 0;
  function onResize() {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      const g = measure();
      if (keyOf(g) !== layoutKey || !layer) return build();
      if (g.docH < parseFloat(layer.style.height) - 2) return build();
      if (g.docH > parseFloat(layer.style.height) + 2) {
        layer.style.height = `${g.docH}px`;
        for (const side of sides) addRuns(side, g.docH);
        kick();
      }
    }, 250);
  }

  const ro = new ResizeObserver(onResize);
  ro.observe(doc.documentElement);
  ro.observe(doc.body);
  const onScroll = () => kick();
  win.addEventListener("scroll", onScroll, { passive: true });
  // Laid out once the fonts have set the page's height.
  Promise.resolve(doc.fonts?.ready).then(() => { if (!stopped) build(); });

  const api = {
    // Change how the garden grows (TUNE's keys). New inks grow it afresh;
    // the rest takes effect as it grows on.
    tune(o) {
      const inks = { colourway: o.colourway ?? T.colourway, inks: o.inks ?? T.inks };
      const regrow = JSON.stringify(inks) !== JSON.stringify({ colourway: T.colourway, inks: T.inks });
      for (const k of Object.keys(TUNE)) if (typeof TUNE[k] === "number" && typeof o[k] === "number" && Number.isFinite(o[k])) T[k] = o[k];
      Object.assign(T, inks);
      if (regrow) build();
      else kick();
    },
    // Grow the garden again from nothing.
    regrow() {
      build();
    },
    get tuning() {
      return { ...T, inks: { ...T.inks } };
    },
    stop() {
      stopped = true;
      if (raf) win.cancelAnimationFrame(raf);
      win.clearTimeout(held);
      clearTimeout(resizeTimer);
      ro.disconnect();
      win.removeEventListener("scroll", onScroll);
      teardown();
      for (const w of workers) w.stop();
      if (win.__floraMargins === api) delete win.__floraMargins;
    },
    // For tests: where the front heads, each side's margin and plants, and
    // each tile.
    get state() {
      return {
        target: layer ? targetAt() : 0,
        sides: sides.map((s) => ({ mirror: s.mirror, m: s.m, bands: s.bands })),
        runs: runs.map((r) => ({ mirror: r.side.mirror, k: r.k, y: r.y, h: r.h, u: r.u, full: r.rows ? fullOf(r) : 0 })),
        tiles: tiles.map((t) => ({ mirror: t.run.side.mirror, run: t.run.k, state: t.state, y: t.y, h: t.h, ms: t.data?.ms ?? null, timing: t.data?.timing ?? null })),
      };
    },
  };
  // The e2e tests read the garden's state here.
  win.__floraMargins = api;
  return api;
}
