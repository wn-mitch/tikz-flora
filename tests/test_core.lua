local H = dofile("tests/helper.lua")
local Rng = require("flora.rng")
local G = require("flora.geom")
local Space = require("flora.space")
local Paint = require("flora.paint")

-- RNG: reproducible, in range, and forks independent of parent consumption.
do
  local a, b = Rng.new(42), Rng.new(42)
  for _ = 1, 100 do
    local x = a:next()
    H.check(x == b:next(), "same seed diverged")
    H.check(x >= 0 and x < 1, "next() out of [0,1)")
  end
  local p, q = Rng.new(5), Rng.new(5)
  q:next(); q:next()
  H.check(p:fork("leaf"):next() == q:fork("leaf"):next(), "fork depends on parent state")
  H.check(p:fork("leaf"):next() ~= p:fork("bloom"):next(), "forks with different labels collide")
  local seen = {}
  local r = Rng.new(9)
  for _ = 1, 400 do seen[r:weighted({ a = 1, b = 1, c = 2 })] = true end
  H.check(seen.a and seen.b and seen.c, "weighted never picked some key")
  H.check(Rng.new(1):weighted({ a = 0 }) == nil, "weighted picked a zero-weight key")
end

-- Geometry: closed splines end where they start; ribbons enclose their line.
do
  local sq = { { 0, 0 }, { 10, 0 }, { 10, 10 }, { 0, 10 } }
  local cmds = G.smooth(sq, true)
  local last = cmds[#cmds - 1]
  H.check(last[6] == 0 and last[7] == 0, "closed spline does not return to start")
  H.check(cmds[#cmds][1] == "z", "closed spline not closed")
  H.check(G.inside(sq, 5, 5) and not G.inside(sq, 15, 5), "inside() wrong")
  local line = { { 0, 0 }, { 50, 0 } }
  local rib = G.ribbon(line, function() return 2 end)
  H.check(G.inside(rib, 25, 1) and not G.inside(rib, 25, 3), "ribbon width wrong")
  H.check(math.abs(G.length(G.resample(line, 11)) - 50) < 1e-6, "resample changed length")
end

-- Resampling gives exactly the points G.at does, bit for bit, so pages
-- drawn before and after it measured segments once are identical; also
-- over a repeated point (a zero-length segment) and very short lines.
do
  local r = Rng.new(3)
  local wiggle = {}
  for i = 1, 40 do wiggle[i] = { i * r:range(0.5, 3), r:range(-9, 9) } end
  wiggle[20] = { wiggle[19][1], wiggle[19][2] }
  for _, pts in ipairs({ wiggle, { { 1, 2 } }, { { 0, 0 }, { 3, 4 } }, { { 0, 0 }, { 0, 0 }, { 5, 0 } } }) do
    for _, n in ipairs({ 2, 7, 64 }) do
      local got = G.resample(pts, n)
      for i = 0, n - 1 do
        local want = G.at(pts, i / (n - 1))
        H.check(got[i + 1][1] == want[1] and got[i + 1][2] == want[2],
          string.format("resample point %d of %d differs from G.at on a %d-point line", i, n, #pts))
      end
    end
  end
end

-- Circles: under 2 pt in radius, two Bezier halves; from 2 pt, four
-- quarters. Either way every point of the outline lies within 1.4% of
-- the radius of the true circle, and a frame moves the circle whole.
do
  local function curves(body)
    local out, cur = {}, nil
    for x, y in body:gmatch("(%-?[%d.]+) (%-?[%d.]+) m") do cur = { tonumber(x), tonumber(y) } break end
    for a, b, c, d, e, f in body:gmatch("(%-?[%d.]+) (%-?[%d.]+) (%-?[%d.]+) (%-?[%d.]+) (%-?[%d.]+) (%-?[%d.]+) c") do
      out[#out + 1] = { cur[1], cur[2], tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e), tonumber(f) }
      cur = { tonumber(e), tonumber(f) }
    end
    return out
  end
  local BP = 72 / 72.27
  for _, case in ipairs({ { 0.5, 2 }, { 1.99, 2 }, { 2, 4 }, { 40, 4 } }) do
    local r, want = case[1], case[2]
    for _, framed in ipairs({ false, true }) do
      local pt = Paint.new()
      if framed then pt:frame(function(x, y) return x + 100, y - 50 end) end
      pt:fill({ { "o", 300, 200, r } }, Paint.palette.blue, 1)
      local cs = curves(pt:body())
      H.check(#cs == want, string.format("circle of radius %g drawn with %d curves, not %d", r, #cs, want))
      local cx, cy = (framed and 400 or 300) * BP, (framed and 150 or 200) * BP
      local worst = 0
      for _, q in ipairs(cs) do
        for k = 0, 20 do
          local t = k / 20
          local u = 1 - t
          local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
          local x = a * q[1] + b * q[3] + c * q[5] + d * q[7]
          local y = a * q[2] + b * q[4] + c * q[6] + d * q[8]
          worst = math.max(worst, math.abs(math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) - r * BP))
        end
      end
      -- The written coordinates are rounded to 0.01 bp.
      H.check(worst <= 0.014 * r * BP + 0.008,
        string.format("circle of radius %g strays %.4f bp from round", r, worst))
    end
  end
end

-- Brush marks: a broken stroke leaves real gaps along its line, an
-- unbroken one covers nearly all of it, and no piece strays further from
-- the line than its width allows.
do
  local Brush = require("flora.brush")
  local line = { { 0, 0 }, { 100, 0 } }
  local function coverage(gap, seed)
    local hit = {}
    for _, p in ipairs(Brush.broken(Rng.new(seed), line, 2, gap, 0)) do
      for _, q in ipairs(p) do
        H.check(math.abs(q[2]) <= 2.6, string.format("brush piece strays %.2f pt from its line", q[2]))
      end
      local x0, _, x1 = G.bbox(p)
      for x = math.floor(x0), math.floor(x1) do hit[x] = true end
    end
    local n = 0
    for x = 0, 99 do if hit[x] then n = n + 1 end end
    return n / 100
  end
  local broken, solid = 0, 0
  for seed = 1, 20 do broken, solid = broken + coverage(0.8, seed), solid + coverage(0, seed) end
  H.check(broken / 20 < 0.8, string.format("broken strokes cover %.2f of their line", broken / 20))
  H.check(solid / 20 > 0.85, string.format("unbroken strokes cover only %.2f of their line", solid / 20))
end

-- Span sampler: points land inside the polygon (within half a row) and
-- spread by area, so the wide arm of an L gets proportionally more.
do
  local L = { { 0, 0 }, { 30, 0 }, { 30, 10 }, { 10, 10 }, { 10, 40 }, { 0, 40 } }
  local sample = G.span_sampler(L, 0.5)
  local rng = Rng.new(4)
  local foot, outside = 0, 0
  for _ = 1, 6000 do
    local x, y = sample(rng)
    if not (G.inside(L, x, y) or G.inside(L, x, y + 0.25) or G.inside(L, x, y - 0.25)) then outside = outside + 1 end
    if y < 10 then foot = foot + 1 end
  end
  H.check(outside == 0, string.format("%d sampled points outside the polygon", outside))
  -- The foot (y < 10) is 300 of the L's 600 square pt.
  H.check(math.abs(foot / 6000 - 0.5) < 0.03, string.format("foot got %.2f of samples, expected 0.50", foot / 6000))
  H.check(G.span_sampler({ { 0, 0 }, { 1, 0 }, { 2, 0 } }, 0.5) == nil, "degenerate polygon gave a sampler")
end

-- Space: clearance stops at blocked cells and at reservations.
do
  local g = Space.new(120, 120, 2)
  g:open(0, 0, 120, 120)
  g:block_text(60, 0, 120, 120)
  local c = g:clearance(30, 60, 50)
  H.check(c > 26 and c <= 30, string.format("clearance %.1f, expected about 30", c))
  H.check(g:clearance(70, 60, 50) == 0, "clearance inside text is not zero")
  g:reserve(30, 60, 10)
  H.check(not g:free(30, 60), "reserved cell still free")
  H.check(g:open_at(30, 60), "reserved cell no longer open for stems")
  H.check(g:clearance(30, 80, 50) <= 10.5, "clearance ignores a reservation")
end

-- Paint (pgf backend): coordinates carry units; colors are defined once and
-- reused.
do
  local pt = Paint.new({ backend = "pgf" })
  pt:fill({ { "m", 1, 2 }, { "l", 3, 4 }, { "z" } }, Paint.palette.blue, 0.5)
  pt:fill({ { "o", 0, 0, 1 } }, Paint.palette.blue, 1)
  local code = pt:code()
  H.check(code:find("\\pgfpathqmoveto{1.00pt}{2.00pt}", 1, true), "moveto lacks pt units")
  H.check(select(2, code:gsub("\\definecolor", "")) == 1, "color defined more than once")
  H.check(code:find("\\pgfsetfillopacity{0.50}", 1, true), "opacity not set")
  H.check(not code:find("nan", 1, true) and not code:find("inf", 1, true), "non-finite number emitted")
end

-- Paint (pdf backend): coordinates are converted to bp; each opacity and
-- blend combination is registered with PGF once per run, however many
-- pages use it; a gradient becomes a pattern registered as a resource.
do
  local a, b = Paint.new(), Paint.new()
  a:fill({ { "m", 72.27, 0 }, { "l", 0, 72.27 }, { "z" } }, Paint.palette.blue, 0.5, { blend = "multiply" })
  a:fill({ { "o", 0, 0, 1 } }, Paint.palette.blue, 0.5, { blend = "multiply" })
  b:fill({ { "o", 0, 0, 1 } }, Paint.palette.blue, 0.5, { blend = "multiply" })
  local body = a:body()
  H.check(body:find("72.00 0.00 m", 1, true), "pdf backend did not convert pt to bp")
  H.check(body:find(" 0.080 0.280 0.780 rg", 1, true), "fill colour missing")
  local regs = select(2, a:tex_defs():gsub("addpdfresource@extgs", ""))
  H.check(regs == 1, string.format("one gstate registered %d times on a page", regs))
  H.check(b:tex_defs() == "", "gstate registered again on a later page")
  H.check(a:tex_defs():find("/ca 0.50 /CA 1.00 /BM /Multiply", 1, true), "gstate has wrong opacity or blend")
  H.check(not body:find("\\", 1, true), "pdf body contains TeX code")
  local c = Paint.new()
  c:shading("g", { { 0, { 1, 1, 1 } }, { 0.5, { 0.5, 0.5, 1 } }, { 1, { 0, 0, 1 } } })
  c:shade("g", { 0, 0 }, { 10, 0 }, 4)
  H.check(c:tex_defs():find("addpdfresource@patterns", 1, true), "gradient pattern not registered")
  H.check(c:body():find("/Pattern cs /flpat%d+ scn"), "gradient not painted with its pattern")
  local q = select(2, (a:body() .. c:body()):gsub("%f[%w]q%f[%W]", ""))
  local Q = select(2, (a:body() .. c:body()):gsub("%f[%w]Q%f[%W]", ""))
  H.check(q == Q, string.format("unbalanced q/Q: %d vs %d", q, Q))
end

-- Probe: paint inside a clip is bounded by the clip path, which is probed;
-- paint after the clip ends is probed again.
do
  local pt = Paint.new()
  local seen = {}
  pt.probe = function(x, y, r) seen[#seen + 1] = { x, y, r } end
  pt:clip_begin({ { "m", 0, 0 }, { "l", 10, 0 }, { "l", 10, 10 }, { "z" } })
  local after_clip = #seen
  pt:fill({ { "o", 500, 500, 300 } }, Paint.palette.blue, 1)
  H.check(#seen == after_clip, "paint inside a clip was probed")
  pt:clip_end()
  H.check(after_clip == 3, "clip path not probed")
  pt:fill({ { "o", 500, 500, 300 } }, Paint.palette.blue, 1)
  H.check(#seen == after_clip + 1 and seen[#seen][3] == 300, "paint after a clip not probed")
end

-- Colour: OKLCH conversion keeps lightness when chroma is clipped into
-- gamut, ramps run light to dark within their look's range, and two shapes
-- of one look get visibly different ramps.
do
  local Color = require("flora.color")
  local Tune = require("flora.tune")
  for _, L in ipairs({ 0.3, 0.5, 0.7, 0.95 }) do
    local rgb = Color.oklch(L, 0.5, 266)   -- far outside gamut
    for k = 1, 3 do H.check(rgb[k] >= 0 and rgb[k] <= 1, "oklch channel out of range") end
    H.check(math.abs(Color.lightness(rgb) - L) < 0.01,
      string.format("clipping chroma moved lightness %.2f to %.3f", L, Color.lightness(rgb)))
  end
  H.check(Color.max_chroma(0.45, 266) > 0.2, "max chroma for ultramarine implausibly low")
  local rng = Rng.new(11)
  local tips = {}
  for i = 1, 40 do
    local stops = Color.ramp(rng, "vivid")
    local lb, lt = Color.lightness(stops[1][2]), Color.lightness(stops[#stops][2])
    local range = Tune.color.looks.vivid
    H.check(lb > lt + 0.3, string.format("ramp %d too flat: base %.2f tip %.2f", i, lb, lt))
    H.check(lt > range.tip_l[1] - 0.02 and lt < range.tip_l[2] + 0.02, string.format("ramp %d tip %.2f outside look", i, lt))
    tips[i] = stops[#stops][2]
  end
  local spread = 0
  for i = 2, #tips do
    spread = math.max(spread, math.abs(tips[i][1] - tips[1][1]) + math.abs(tips[i][3] - tips[1][3]))
  end
  H.check(spread > 0.15, "vivid ramps barely vary from shape to shape")
end

-- Every tuner setting has a label and description, by dotted path or, for
-- settings repeated in each look, by key; labels within a folder differ.
do
  local Tune = require("flora.tune")
  require("flora.ornaments")  -- labels the ornament weights
  local doc = Tune._doc
  local function walk(tbl, path)
    local seen = {}
    for k, v in pairs(tbl) do
      if k:sub(1, 1) ~= "_" then  -- _doc, _with: not settings (tune.lua)
        local p = path == "" and k or path .. "." .. k
        local d = doc[p] or doc[k]
        H.check(d and #d == 2 and #d[1] > 0 and #d[2] > 0, "tuner setting " .. p .. " has no label")
        if d then
          H.check(not seen[d[1]], "two settings in " .. path .. " share the label " .. d[1])
          seen[d[1]] = true
        end
        if type(v) == "table" and #v == 0 then walk(v, p) end
      end
    end
  end
  walk(Tune, "")
end

-- Lost edges: the runs alternate found/lost and join end to end around the
-- whole contour, the lost share is close to the request, and lost edges sit
-- mostly at the pale end: on a circle pale on its left half, most lost
-- points over many shapes are on the left (noise places the rest).
do
  local W = require("flora.wash")
  local circle = {}
  for k = 0, 47 do
    local a = k * math.pi / 24
    circle[#circle + 1] = { 10 * math.cos(a), 10 * math.sin(a) }
  end
  local pale = function(p) return p[1] < 0 and 1 or 0 end
  H.check(W.edge_runs(Rng.new(1), circle, pale, 0) == nil, "no lost edges at share 0")
  local left, total = 0, 0
  for seed = 1, 20 do
    local found, lost = W.edge_runs(Rng.new(seed), circle, pale, 0.3)
    H.check(found and lost and #found == #lost and #lost >= 1, "runs alternate")
    local len, lost_len = 0, 0
    for _, r in ipairs(found) do len = len + G.length(r) end
    for _, r in ipairs(lost) do
      local l = G.length(r)
      len, lost_len = len + l, lost_len + l
      for i = 2, #r - 1 do
        total = total + 1
        if r[i][1] < 0.5 then left = left + 1 end
      end
    end
    H.check(math.abs(len - G.length(circle) - 10 * math.sin(math.pi / 48) * 2) < 1.5,
      "runs cover the contour once: " .. len)
    H.check(math.abs(lost_len / len - 0.3) < 0.06, "lost share near 0.3: " .. lost_len / len)
    local all = {}
    for i = 1, #lost do all[#all + 1] = lost[i]; all[#all + 1] = found[i] end
    for i = 1, #all do
      local a, b = all[i], all[i % #all + 1]
      H.check(G.dist(a[#a], b[1]) < 1e-9, "runs join end to end")
    end
  end
  H.check(left >= 0.7 * total, "lost edges mostly on the pale side: " .. left .. "/" .. total)
end

-- Size curves: samples follow the curve's shape. A peak in the middle
-- rarely yields the ends; a falling ramp averages a third of the way along; weight
-- only on the last point keeps every sample in the last segment, averaging
-- two thirds of the way through it.
do
  local Dist = require("flora.dist")
  local function stats(c, n)
    local r = Rng.new(5)
    local sum, lo, ends = 0, math.huge, 0
    for _ = 1, n do
      local v = Dist.sample(r, c)
      sum, lo = sum + v, math.min(lo, v)
      if v < c.range[1] + 0.05 * (c.range[2] - c.range[1]) or v > c.range[2] - 0.05 * (c.range[2] - c.range[1]) then
        ends = ends + 1
      end
    end
    return sum / n, lo, ends / n
  end
  -- A triangle puts (0.1)^2 = 1% of its mass in the outer 5% at both ends;
  -- uniform sampling within each segment would put 5% there.
  local mean, _, ends = stats({ range = { 0, 1 }, weights = { 0, 1, 0 } }, 4000)
  H.check(math.abs(mean - 0.5) < 0.02 and ends < 0.02, string.format("peaked curve: mean %.3f, %.3f at the ends", mean, ends))
  mean = stats({ range = { 2, 5 }, weights = { 1, 0 } }, 4000)
  H.check(math.abs(mean - 3) < 0.05, string.format("falling ramp mean %.3f, want 3", mean))
  mean, lo = stats({ range = { 0, 1 }, weights = { 0, 0, 1 } }, 4000)
  H.check(lo >= 0.5 and math.abs(mean - 5 / 6) < 0.02, string.format("last-point curve: mean %.3f, min %.3f", mean, lo))
  mean = stats({ range = { 0, 1 }, weights = { 0, 0 } }, 2000)
  H.check(math.abs(mean - 0.5) < 0.03, "a flat zero curve falls back to uniform")
end

-- Spline curves: the curve passes through its points, never overshoots a
-- peak or dips below zero between points, rises steadily between rising
-- points, and sampling follows its shape.
do
  local Dist = require("flora.dist")
  local peak = { { 0, 0 }, { 0.3, 1 }, { 0.6, 0.1 }, { 1, 0 } }
  local f = Dist.spline(peak)
  for _, p in ipairs(peak) do
    H.check(math.abs(f(p[1]) - p[2]) < 1e-9, string.format("spline misses its point at %.2f", p[1]))
  end
  local lo, hi = math.huge, -math.huge
  for i = 0, 200 do
    local v = f(i / 200)
    lo, hi = math.min(lo, v), math.max(hi, v)
  end
  H.check(hi <= 1 + 1e-9 and lo >= -1e-9, string.format("spline overshoots: %.3f..%.3f", lo, hi))
  local rise = Dist.spline({ { 0, 0.2 }, { 0.4, 0.3 }, { 1, 0.9 } })
  local prev, steady = -1, true
  for i = 0, 100 do
    local v = rise(i / 100)
    if v < prev - 1e-12 then steady = false end
    prev = v
  end
  H.check(steady, "spline dips between rising points")
  local r, sum = Rng.new(3), 0
  for _ = 1, 4000 do sum = sum + Dist.sample(r, { range = { 0, 10 }, points = { { 0, 0 }, { 0.5, 1 }, { 1, 0 } } }) end
  H.check(math.abs(sum / 4000 - 5) < 0.15, string.format("spline curve mean %.2f, want 5", sum / 4000))
end

-- Bloom styles: picks follow the weights, and a style of weight 0 is never
-- picked.
do
  local F = require("flora.flower")
  local Tune = require("flora.tune")
  local saved = { Tune.blooms.fan.weight, Tune.blooms.round.weight, Tune.blooms.soft.weight }
  Tune.blooms.fan.weight, Tune.blooms.round.weight, Tune.blooms.soft.weight = 3, 1, 0
  local r, n = Rng.new(9), { fan = 0, round = 0, soft = 0 }
  for _ = 1, 4000 do
    local st = F.pick_style(r, { "fan", "round", "soft" })
    n[st] = n[st] + 1
  end
  H.check(n.soft == 0, "a style of weight 0 was picked")
  H.check(math.abs(n.fan / 4000 - 0.75) < 0.03, string.format("fan picked %.3f of the time, want 0.75", n.fan / 4000))
  Tune.blooms.fan.weight, Tune.blooms.round.weight, Tune.blooms.soft.weight = saved[1], saved[2], saved[3]
end

-- Granulation: clumping gathers the same number of specks closer together,
-- and mottling adds patches only when asked for.
do
  local W = require("flora.wash")
  local square = { { 0, 0 }, { 60, 0 }, { 60, 60 }, { 0, 60 } }
  local function run(clump, mottle)
    local dots, patches = {}, 0
    local pt = { fill = function(_, paths, _, _, o)
      for _, p in ipairs(paths) do
        if p[1] and p[1][1] == "o" then dots[#dots + 1] = { p[1][2], p[1][3] } elseif o and o.many then patches = patches + 1 end
      end
    end }
    W.grain(pt, Rng.new(3), square, 0.25, { clump = clump, mottle = mottle })
    return dots, patches
  end
  local function mean_nn(dots)
    local sum = 0
    for i, a in ipairs(dots) do
      local best = math.huge
      for j, b in ipairs(dots) do
        if i ~= j then best = math.min(best, G.dist(a, b)) end
      end
      sum = sum + best
    end
    return sum / #dots
  end
  local even, p0 = run(0, 0)
  local clumped = run(1, 0)
  local half = run(0.5, 0)
  H.check(p0 == 0, "patches drawn with mottle 0")
  H.check(math.abs(#clumped - #even) <= 0.05 * #even, string.format("clumping changed the speck count: %d vs %d", #clumped, #even))
  H.check(math.abs(#half - #even) <= 0.05 * #even, string.format("half clumping changed the speck count: %d vs %d", #half, #even))
  local e, h, c = mean_nn(even), mean_nn(half), mean_nn(clumped)
  H.check(c < 0.5 * e, string.format("clumped specks not closer: %.2f vs %.2f", c, e))
  H.check(h < e and h > c, string.format("half clumping not in between: %.2f (%.2f to %.2f)", h, c, e))
  local _, patches = run(0, 1)
  H.check(patches > 20, "mottle 1 drew " .. patches .. " patches on a 60 pt square")
end

-- Wedge petals: with a gap, petals around one eye never overlap, even at
-- the style's largest spacing jitter, and each is narrow at its base.
do
  local F = require("flora.flower")
  local Tune = require("flora.tune")
  local st = Tune.blooms.wedge
  for _, n in ipairs({ 5, 6 }) do
    for seed = 1, 20 do
      local rng = Rng.new(seed)
      local slot = F.slot(n, st.gap, st.spacing)
      local polys = {}
      for i = 1, n do
        -- Neighbours jittered toward each other as far as the style allows.
        local a = (i - 1) * 2 * math.pi / n + (i % 2 == 0 and -1 or 1) * st.spacing
        local pts = F.petal(rng, "wedge", 60, 60 * st.width[2] * 1.08, rng:jit(0.04), st.rim, slot)
        polys[i] = G.transform(pts, 0, 0, a - math.pi / 2)
      end
      for i = 1, n do
        local j = i % n + 1
        for _, p in ipairs(polys[i]) do
          if math.sqrt(p[1] ^ 2 + p[2] ^ 2) > 3 and G.inside(polys[j], p[1], p[2]) then
            H.check(false, string.format("%d wedge petals overlap (seed %d)", n, seed))
            break
          end
        end
      end
    end
  end
  local pts = F.petal(Rng.new(1), "wedge", 60, 24, 0, 0)
  local function half_width(y0)
    local w = 0
    for _, p in ipairs(pts) do if math.abs(p[2] - y0) < 2.4 then w = math.max(w, math.abs(p[1])) end end
    return w
  end
  H.check(half_width(6) < 0.35 * half_width(36), string.format("wedge base not narrow: %.1f vs %.1f", half_width(6), half_width(36)))
end

-- Leaf blade: a stalk at the base, widest about two fifths of the way up,
-- and a tapering tip, not a teardrop with a blunt base.
do
  local L = require("flora.leaf")
  local best, at = 0, 0
  for i = 0, 200 do
    local w = L.blade(i / 200, 0.68, 0.85)
    if w > best then best, at = w, i / 200 end
  end
  H.check(at > 0.3 and at < 0.5, string.format("leaf widest at %.2f of its length", at))
  H.check(L.blade(0.05, 0.68, 0.85) < 0.06 * best, "leaf has no stalk at its base")
  H.check(L.blade(0.15, 0.68, 0.85) < 0.45 * best, string.format("leaf base blunt: %.2f of widest at 0.15", L.blade(0.15, 0.68, 0.85) / best))
  H.check(L.blade(0.95, 0.68, 0.85) < 0.35 * best, "leaf tip not tapering")
end

-- Ink palettes: an ink's colour at a measured stop is that stop's; a leaf
-- painted from an ink takes the ink's hue; "look" ignores inks entirely.
do
  local Color = require("flora.color")
  local Inks = require("flora.inks")
  local Tune = require("flora.tune")
  for _, name in ipairs(Inks.order) do
    local r = Inks.ramps[name]
    local s = r[#r - 1]
    local ch, h = Color.ink_at(name, s[1])
    H.check(math.abs(ch - math.sqrt(s[2] ^ 2 + s[3] ^ 2)) < 1e-6, name .. " chroma at a stop")
    H.check(math.abs(math.cos(math.rad(h)) * ch - s[2]) < 1e-6, name .. " hue at a stop")
    for i = 1, #r - 1 do H.check(r[i][1] < r[i + 1][1], name .. " ramp not dense to pale") end
  end
  for g, names in pairs(Inks.groups) do
    for _, n in ipairs(names) do H.check(Inks.ramps[n] ~= nil, "group " .. g .. " names unknown ink " .. n) end
  end
  local saved = Tune.color.palette
  Tune.color.palette = { leaves = "chiku-rin" }
  local stops, info = Color.ramp(Rng.new(4), "leaf")
  local _, want = Color.ink_at("chiku-rin", info.L)
  H.check(math.abs(info.h - want) < 1e-6, "ink ramp info hue is not the ink's")
  local tip = stops[#stops][2]
  H.check(tip[2] > tip[3], string.format("chiku-rin leaf tip not green: %.2f %.2f %.2f", tip[1], tip[2], tip[3]))
  Tune.color.palette = { leaves = "look" }
  local a = Color.ramp(Rng.new(4), "leaf")
  Tune.color.palette = nil
  local b = Color.ramp(Rng.new(4), "leaf")
  Tune.color.palette = saved
  for i = 1, #a do
    for c = 1, 3 do H.check(a[i][2][c] == b[i][2][c], "look palette differs from no palette") end
  end
  H.check(Color.ink_for(Rng.new(1), "look") == nil and Color.ink_for(Rng.new(1), "nonsense") == nil, "look or unknown chose an ink")
end

-- Stem corridors: other placements avoid them, leaves may grow over them,
-- and they still count as covered; placed elements block both.
do
  local g = Space.new(60, 60, 3)
  g:open(0, 0, 60, 60)
  g:reserve(30, 30, 4, 4)
  H.check(not g:free(30, 30), "stem corridor counted as free")
  H.check(g:free(30, 30, true), "leaf may not grow over a stem corridor")
  H.check(g:clearance(30, 22, 6) < g:clearance(30, 22, 6, true), "clearance over stems not larger")
  H.check(g:open_at(30, 30), "stem corridor not open for painting")
  H.check(g:coverage() > 0, "stem corridor not counted as covered")
  g:reserve(10, 10, 4)
  H.check(not g:free(10, 10, true), "leaf may grow over a placed element")
end

H.done("core")
