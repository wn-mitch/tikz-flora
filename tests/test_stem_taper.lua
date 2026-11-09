-- With plant.end_taper, the final shadow-edge ink follows the narrowing stem.
local H = dofile("tests/helper.lua")
local B = require("flora.brush")
local Rng = require("flora.rng")
local cfg = { stem_l = 0.5, stem_brush = 1, end_taper = 0.25 }
local near = 0
for seed = 1, 20 do
  local last
  local pt = { fill = function(_, cmds) last = cmds end, clip_begin = function() end, clip_end = function() end }
  B.stem(pt, Rng.new(seed), { { 0, 0 }, { 300, 0 } }, function() return 10 end, cfg)
  for _, poly in ipairs(last or {}) do
    for _, c in ipairs(poly) do
      if c[2] and (c[2] < 6 or c[2] > 294) then
        near = near + 1
        H.check(math.abs(c[3]) < 2, "stem ink stayed at full width at a tapered end")
      end
    end
  end
end
H.check(near > 0, "no ink reached a tapered end to check")
H.done("stem_taper")
