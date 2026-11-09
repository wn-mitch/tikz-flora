local H = dofile("tests/helper.lua")
local Garden = require("flora.garden")
local Compose = require("flora.compose")
local Paint = require("flora.paint")

-- Settings shared by both garden modes must survive spec construction.
for _,mode in ipairs({'margins','band'}) do
  local settings='tune={compose={leaves=0,runners=0}},density=2,visitors=0,colourway=autumn,gilt=vector,giltdpi=120'
  local parsed=require('flora.settings').parse(settings)
  local spec=Garden.spec({mode=mode,width=1000,height=300,x0=180,x1=820,seed=3,settings=settings})
  for _,key in ipairs({'tune','mix','palette','gilt'}) do
    H.check(require('flora.serial').encode(spec[key])==require('flora.serial').encode(parsed[key]),
      mode..': dropped '..key..' settings')
  end
  H.check(spec.gilt_dpi==parsed.giltdpi,mode..': dropped gilt DPI')
end

-- Bad gardens stop with a message naming what is wrong.
do
  local base = { mode = "margins", width = 1440, height = 900, x0 = 208, x1 = 1232, seed = 20261102 }
  local function with(k, v)
    local o = {}
    for a, b in pairs(base) do o[a] = b end
    o[k] = v
    return o
  end
  for _, case in ipairs({
    { with("mode", "sideways"), "mode" }, { with("width", 0), "width" }, { with("seed", 1.5), "seed" },
    { with("grow", 1.2), "grow" }, { with("x1", 100), "x0 < x1" }, { with("x0", 30), "margins under" },
    { with("settings", "backdrop=#ffffff"), "backdrop" },
    { { mode = "band", width = 390, height = 40, seed = 1 }, "band under" },
  }) do
    local ok, err = pcall(Garden.spec, case[1])
    H.check(not ok and tostring(err):find(case[2], 1, true), "accepted a garden with bad " .. case[2] .. ": " .. tostring(err))
  end
end

-- Margins: the column is centred on the page, the narrower margin setting
-- both; nothing grows over it but the foot's runners, which meet under it
-- within 16 px of the foot, and both plants grow.
do
  local spec, view = Garden.spec({ mode = "margins", width = 1000, height = 700, x0 = 180, x1 = 760, seed = 3, settings = "backdrop=dark" })
  H.check(spec.layout == "centered" and spec.text.x0 == 180 and spec.text.x1 == 820, "margins not centred on the narrower one")
  H.check(view.width == 1000 and view.height == 700 and view.y == 0, "margins view is not the whole viewport")
  H.check(spec.backdrop == "dark" and spec.seed and spec.grow == nil, "settings or seed not carried")
  local over, left, right = 0, 0, 0
  spec.probe = function(x, y, r)
    if x + r > spec.text.x0 + 1 and x - r < spec.text.x1 - 1 and y - r > spec.text.y0 + 16 then over = over + 1 end
    if x < spec.text.x0 then left = left + 1 elseif x > spec.text.x1 then right = right + 1 end
  end
  Paint.reset_resources()
  Compose.page(spec)
  H.check(over == 0, string.format("%d points grow over the content column", over))
  H.check(left > 1000 and right > 1000, string.format("a margin is bare (%d left, %d right)", left, right))
end

-- Band: a crown in the strip, none of it below the strip's foot, where
-- the hidden block is cut off.
do
  local spec, view = Garden.spec({ mode = "band", width = 390, height = 110, seed = 5, grow = 0.6 })
  H.check(spec.layout == "title" and spec.height == 110 + view.y and view.height == 110, "band page and view disagree")
  H.check(spec.grow == 0.6, "band growth not carried")
  local below, inside = 0, 0
  spec.probe = function(x, y, r)
    if y + r < view.y - 2 then below = below + 1 elseif y - r < view.y + view.height then inside = inside + 1 end
  end
  Paint.reset_resources()
  Compose.page(spec)
  H.check(below == 0, string.format("%d points of the band fall under its foot", below))
  H.check(inside > 500, "the band is bare")
end

-- One seed is one garden: the same spec paints the same page; another
-- day's seed another.
do
  local function code(seed)
    Paint.reset_resources()
    return Compose.page((Garden.spec({ mode = "band", width = 300, height = 90, seed = seed }))):code()
  end
  local a = code(20261102)
  H.check(a == code(20261102), "one day's garden differs between renders")
  H.check(a ~= code(20261103), "two days grow the same garden")
end

H.done("garden")
