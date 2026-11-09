local H = dofile("tests/helper.lua")
local Orn = require("flora.ornaments")
local Paint = require("flora.paint")
local Rng = require("flora.rng")
local Roundel = require("flora.orn_roundel")
for _, size in ipairs({ {280,46}, {120,20}, {40,20}, {20,20}, {10,20} }) do
  for seed = 1, 5 do
    local w, h = size[1], size[2]
    local pt = Paint.new({backend="pgf"})
    local rosette = Roundel.rosette
    local parts = {}
    pt:begin_group("band")
    Roundel.rosette = function(p, ...)
      p:end_group()
      p:begin_group("rosette")
      rosette(p, ...)
      p:end_group()
    end
    local ok, err = pcall(Orn.draw, "headpiece", pt, Rng.new(seed), {0,0,w,h})
    Roundel.rosette = rosette
    assert(ok, err)
    for _, b in ipairs(pt.boxes) do parts[#parts+1]=b end
    local band, left, right = parts[1], parts[2], parts[3]
    H.check(band and left and right, "missing headpiece components")
    H.check(left.x1 + 0.02 < band.x0 and band.x1 + 0.02 < right.x0,
      string.format("headpiece components overlap at %gx%g seed %d",w,h,seed))
    for _, b in ipairs(parts) do
      H.check(b.x0 >= -0.5 and b.x1 <= w+0.5 and b.y0 >= -0.5 and b.y1 <= h+0.5,
        "headpiece escapes its box")
    end
  end
end
H.done("headpiece")
