local H = dofile("tests/helper.lua")
local F = require("flora.flower")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local Frames = require("flora.frames")
local Settings = require("flora.settings")

local W = 595.28

-- Reservations are page boxes. Each plant closes only the inverse-mapped
-- portion in its own frame, including mirrors, rotations and ovals.
do
  local Layout = require("flora.layout")
  local Tune = require("flora.tune")
  local Serial = require("flora.serial")
  for _, name in ipairs(Frames.order) do
    local s = { width = 400, height = 300, layout = name, page = 1,
      text = { x0 = 80, y0 = 60, x1 = 320, y1 = 240 },
      reserve = { { 0, 80, 50, 160 }, { 390, 0, 410, 20 } } }
    local original = Serial.encode(s.reserve)
    Tune._with({ gesture = { top_inset = 70 } }, function()
      for _, f in ipairs(Frames.of(s)) do
        H.check(f.spec.top_inset ~= nil or not f.fn, name .. ': inherited a page inset')
        if f.map then
          local inv = Frames.invert(f.map)
          local expected = {}
          for _, r in ipairs(s.reserve) do
            local a,b = Frames.apply(inv,r[1],r[2])
            local c,d = Frames.apply(inv,r[3],r[4])
            local q = { math.max(0,math.min(a,c)), math.max(0,math.min(b,d)),
              math.min(f.spec.width,math.max(a,c)), math.min(f.spec.height,math.max(b,d)) }
            if q[1]<q[3] and q[2]<q[4] then expected[#expected+1]=q end
          end
          H.check(Serial.encode(f.spec.reserve)==Serial.encode(expected), name .. ': reservation not mapped/clipped')
          if f.map[4] ~= 1 then
            local _,m = Layout.region(f.spec)
            H.check(f.spec.top_inset==0 and m.y1==f.spec.height-(f.spec.edge or 16)-6,
              name .. ': page inset leaked into a turned frame')
          end
        elseif f.inv then
          for _, r in ipairs(f.spec.reserve) do
            H.check(r[1]>=0 and r[2]>=0 and r[3]<=f.spec.width and r[4]<=f.spec.height,
              name .. ': curved reservation escaped frame')
          end
        end
      end
    end)
    H.check(Serial.encode(s.reserve)==original,name .. ': mutated page reservations')
  end
  local s = {width=400,height=300,layout='centered',text={x0=80,y0=60,x1=320,y1=240},reserve={{0,80,50,160}}}
  local fs = Frames.of(s)
  H.check(#fs[1].spec.reserve==1 and #fs[2].spec.reserve==0,'left reservation closes right margin')
end

-- The helper's page with its text block (and lines) mirrored, so the wide
-- margin is on the right.
local function mirrored(seed)
  local s = H.page(seed)
  s.text = { x0 = W - s.text.x1, x1 = W - s.text.x0, y0 = s.text.y0, y1 = s.text.y1 }
  for _, l in ipairs(s.lines) do l.x0, l.x1 = W - l.x1, W - l.x0 end
  s.header_y = nil
  return s
end

-- A page with a centred text block and margins of 120pt on both sides.
local function centred(seed)
  local s = H.page(seed)
  s.text = { x0 = 120, y0 = 140, x1 = 475, y1 = 700 }
  local ls = {}
  for _, l in ipairs(s.lines) do
    if l.y0 > 140 and l.y1 < 700 then
      ls[#ls + 1] = { x0 = 120, x1 = math.min(475, l.x1 - 53), y0 = l.y0, y1 = l.y1 }
    end
  end
  s.lines, s.header_y = ls, nil
  return s
end

-- Every painted point of a page, in order.
local function points(spec)
  local pts = {}
  spec.probe = function(x, y, r) pts[#pts + 1] = { x, y, r } end
  Paint.reset_resources()
  Compose.page(spec)
  return pts
end

local function on_text(spec, pts)
  for _, p in ipairs(pts) do
    local x, y, r = p[1], p[2], p[3]
    for _, l in ipairs(spec.lines) do
      if x + r > l.x0 + 1 and x - r < l.x1 - 1 and y + r > l.y0 + 1 and y - r < l.y1 - 1 then
        return string.format("(%.1f, %.1f)", x, y)
      end
    end
  end
end

-- The default layout is the plain page: naming it changes nothing.
do
  Paint.reset_resources()
  local a = Compose.page(H.page(2)):code()
  local s = H.page(2)
  s.layout = "left"
  Paint.reset_resources()
  H.check(Compose.page(s):code() == a, "layout=left differs from the default")
end

-- layout=right on a mirrored page is the left layout mirrored: same seed,
-- same plant. Each layer's extents (paint.lua's boxes) match its mirror.
-- (Points themselves differ in number: a circle under a frame map is
-- painted as four curves rather than one centre and radius.)
do
  local base = H.page(4)
  base.header_y = nil
  Paint.reset_resources()
  local l = Compose.page(base).boxes
  local s = mirrored(4)
  s.layout = "right"
  Paint.reset_resources()
  local r = Compose.page(s).boxes
  H.check(#l == #r and #l >= 5, string.format("right has %d layers, left %d", #r, #l))
  local worst = 0
  for i = 1, math.min(#l, #r) do
    local a, b = l[i], r[i]
    H.check(a.tag == b.tag, "layers out of order: " .. a.tag .. " / " .. b.tag)
    worst = math.max(worst, math.abs(W - a.x1 - b.x0), math.abs(W - a.x0 - b.x1),
      math.abs(a.y0 - b.y0), math.abs(a.y1 - b.y1))
  end
  H.check(worst < 1e-6, string.format("right is not left mirrored (off by %.3g pt)", worst))
end

-- No layout paints over text, with and without the top inset.
for _, inset in ipairs({ 0, 48 }) do
  for _, lay in ipairs({ "right", "centered", "surround", "title", "split" }) do
    for seed = 1, 1 do
      local spec = (lay == "right" or lay == "split") and mirrored(seed) or centred(seed)
      if lay == "title" then
        spec.lines = { { x0 = 170, x1 = 425, y0 = 560, y1 = 600 }, { x0 = 230, x1 = 365, y0 = 530, y1 = 545 } }
      end
      spec.layout, spec.page = lay, 1
      if inset > 0 then spec.tune = { gesture = { top_inset = inset } } end
      local where = on_text(spec, points(spec))
      H.check(not where, string.format("%s seed %d inset %d paints on text at %s",
        lay, seed, inset, tostring(where)))
    end
  end
end

-- A reservation on the oval's seam closes only the arc near it.
do
  local s = {width=400,height=300,layout='wreath',text={x0=160,y0=110,x1=240,y1=190},reserve={{350,0,400,300}}}
  local fs, n = Frames.of(s), 0
  for _, f in ipairs(fs) do
    for _, r in ipairs(f.spec.reserve) do
      n = n + 1
      local x = f.fn((r[1] + r[3]) / 2, (r[2] + r[4]) / 2)
      H.check(x > 300, string.format('seam reservation closed the far arc at page x=%.0f', x))
    end
  end
  H.check(n > 0, 'seam reservation closed nothing')
end

-- A reserved rectangle stays empty.
do
  local spec = H.page(7)
  local r = { 200, 400, 350, 500 }
  spec.reserve = { r }
  local inside = 0
  spec.probe = function(x, y)
    if x > r[1] and x < r[3] and y > r[2] and y < r[4] then inside = inside + 1 end
  end
  Paint.reset_resources()
  Compose.page(spec)
  H.check(inside == 0, string.format("flora paints %d points inside a reserved rectangle", inside))
end

-- Surround: each plant keeps to its own side. The first never enters the
-- right margin beside the text, the second never the left one.
do
  local spec = centred(5)
  spec.layout = "surround"
  local t, label = spec.text, nil
  local stray = {}
  spec.on_frame = function(f) label = f.label end
  spec.probe = function(x, y)
    local in_right = x > t.x1 + 12 and y > t.y0 + 12 and y < t.y1 - 12
    local in_left = x < t.x0 - 12 and y > t.y0 + 12 and y < t.y1 - 12
    if (label == "left" and in_right) or (label == "right" and in_left) then
      stray[label] = (stray[label] or 0) + 1
    end
  end
  Paint.reset_resources()
  Compose.page(spec)
  H.check(not stray.left, string.format("left plant strays into the right margin %d times", stray.left or 0))
  H.check(not stray.right, string.format("right plant strays into the left margin %d times", stray.right or 0))
end

-- A wreath frames a short page's text; it does not grow into the empty
-- part of the text block, as the left layout's excursion does.
do
  local spec = centred(3)
  local short = {}
  for _, l in ipairs(spec.lines) do if l.y0 > 560 then short[#short + 1] = l end end
  spec.lines, spec.layout = short, "surround"
  local t, inside = spec.text, 0
  spec.probe = function(x, y)
    if x > t.x0 + 12 and x < t.x1 - 12 and y > t.y0 + 12 and y < 540 then inside = inside + 1 end
  end
  Paint.reset_resources()
  Compose.page(spec)
  H.check(inside == 0, string.format("surround grows %d points into the empty text block", inside))
end

-- A clearing between paragraphs (a gap of more than Layout.CLEARING) is
-- grown into across the text's width; ordinary paragraph breaks are not.
do
  local spec = H.page(3)
  local keep = {}
  for _, l in ipairs(spec.lines) do if l.y1 > 520 or l.y0 < 370 then keep[#keep + 1] = l end end
  spec.lines = keep
  local deep, bad = 0, nil
  spec.probe = function(x, y, r)
    if x > spec.text.x0 + 120 and y > 380 and y < 510 then deep = deep + 1 end
    for _, l in ipairs(spec.lines) do
      if x + r > l.x0 + 1 and x - r < l.x1 - 1 and y + r > l.y0 + 1 and y - r < l.y1 - 1 then bad = bad or string.format("(%.1f, %.1f)", x, y) end
    end
  end
  Paint.reset_resources()
  Compose.page(spec)
  H.check(deep > 500, string.format("only %d points grow into the clearing", deep))
  H.check(not bad, "flora in the clearing lands on text at " .. tostring(bad))
end

-- The upper crown stops below gesture.top_inset; the inset lowers its
-- topmost painted point by the same amount.
do
  local top = H.page(6).height
  local function upper_top(inset)
    local spec = centred(6)
    spec.layout, spec.tune = "surround", { gesture = { top_inset = inset } }
    local label, highest = nil, 0
    spec.on_frame = function(f) label = f.label end
    spec.probe = function(_, y)
      if label == "right" then highest = math.max(highest, y) end
    end
    Paint.reset_resources()
    Compose.page(spec)
    return highest
  end
  local plain, lowered = upper_top(0), upper_top(48)
  H.check(plain > top - 40, string.format("upper crown starts too low without an inset: %.1f", plain))
  H.check(lowered < top - 47.5, string.format("upper crown ignores the inset: %.1f", lowered))
  H.check(math.abs((plain - lowered) - 48) < 2,
    string.format("inset moves the crown by %.1f pt, not 48", plain - lowered))
end

-- gesture.header_clip clips margin-mode plants at the running head, and
-- title furniture follows the clip.
do
  local spec = H.page(11)
  spec.backend, spec.header, spec.frametitle = "pdf", "margin", true
  spec.tune = { gesture = { header_clip = 1 } }
  Paint.reset_resources()
  local pt = Compose.page(spec)
  H.check(pt.header_clip == spec.header_y, "header_clip did not record the boundary")
  H.check(pt:body():match("^q 0%.00 0%.00 m") ~= nil,
    "the header clip is not the first paint operation")

  spec.layout = "title"
  spec.title = { x0 = 170, x1 = 425, y0 = 530, y1 = 600 }
  spec.tune.gesture.top_inset = 48
  spec.reserve = {{0,0,10,10},{5,5,15,15}}
  local Title = require("flora.orn_title")
  local paint, depth = Title.paint
  Title.paint = function(p, ...)
    depth = p.clips
    return paint(p, ...)
  end
  Paint.reset_resources()
  local st = Compose.page(spec)
  Title.paint = paint
  H.check(st.header_clip == spec.header_y and st.title ~= nil,
    "the title-furniture path did not run under the header clip")
  H.check(depth == 3 and st.clips == 0,
    "title furniture lost page/reserve protection or retained the margin header clip")

  spec.tune = { gesture = { header_clip = 0 } }
  Paint.reset_resources()
  H.check(Compose.page(spec).header_clip == nil,
    "header_clip clipped without the setting")
end

-- Split follows page parity: odd pages are mirrored, even ones are not.
do
  local s = H.page(1)
  s.layout = "split"
  s.page = 3
  H.check(Frames.of(s)[1].map ~= nil, "split on an odd page is not mirrored")
  s.page = 4
  H.check(Frames.of(s)[1].map == nil, "split on an even page is mirrored")
end

-- Frame maps invert exactly, and boxes keep their size through a frame.
do
  for _, m in ipairs({ { -1, 0, 0, 1, W, 0 }, { 0, -1, 1, 0, 0, 841.89 }, { -1, 0, 0, -1, W, 841.89 } }) do
    local inv = Frames.invert(m)
    local x, y = Frames.apply(inv, Frames.apply(m, 123.4, 567.8))
    H.check(math.abs(x - 123.4) < 1e-9 and math.abs(y - 567.8) < 1e-9, "frame map does not round-trip")
  end
  local s = centred(1)
  s.layout = "title"
  s.title = { x0 = 170, x1 = 425, y0 = 530, y1 = 600 }
  local f = Frames.of(s)[1]
  local tx = f.spec.text
  H.check(math.abs((tx.x1 - tx.x0) - 70) < 1e-6, "title block's height is not the frame's text width")
  H.check(f.spec.text.y1 <= f.spec.height, "title frame's text runs past the frame")
end

-- The title block: lines between two marks, or the top block by default.
do
  local lines = {
    { x0 = 200, x1 = 400, y0 = 600, y1 = 630 },
    { x0 = 250, x1 = 350, y0 = 570, y1 = 585 },
    { x0 = 120, x1 = 470, y0 = 400, y1 = 410 },
  }
  local B = Frames.between(lines, 640, 560)
  H.check(B and B.x0 == 200 and B.x1 == 400 and B.y0 == 570 and B.y1 == 630, "between misses the title lines")
  H.check(Frames.between(lines, 300, 200) == nil, "between found lines outside its range")
  local top = Frames.top_block({ text = { x0 = 120, y0 = 100, x1 = 470, y1 = 700 }, lines = lines })
  H.check(top.y0 == 570 and top.x0 == 200, "top block runs past the gap below the title")
end

-- Settings: keys are checked, nested values keep their braces' contents.
do
  local t = Settings.parse("layout=surround, seed = 12")
  H.check(t.layout == "surround" and t.seed == "12", "settings did not parse")
  local list = Settings.parse_list("a=1, mix={b=2, c=3}, d")
  H.check(#list == 3 and list[2][2] == "b=2, c=3" and list[3][2] == nil, "nested list split wrongly")
  for _, bad in ipairs({ "layout=diagonal", "colour=blue", "seed=", "layout", "mix={a=1" }) do
    H.check(not pcall(Settings.parse, bad), "accepted bad settings \"" .. bad .. "\"")
  end
  local m = Settings.merge({ layout = "left", mix = { a = 1, b = 2 } }, { mix = { b = 5 } })
  H.check(m.layout == "left" and m.mix.a == 1 and m.mix.b == 5, "merge lost or kept the wrong values")
end

H.done("layout")
