local H = dofile("tests/helper.lua")
local Inline = require("flora.inline")
local Orn = require("flora.ornaments")
local Serial = require("flora.serial")
local Flora = require("flora.init")
local Paint = require("flora.paint")
Flora.settings = { seed = "7", layout = "surround" }
Flora.once = { density = 2 }
local settings, once, palette = Serial.encode(Flora.settings), Flora.once, Serial.encode(Paint.palette)
for _, name in ipairs(Orn.order) do
  local p, b = Inline.draw(name, 24, 24, 2, 3, "inlineink")
  H.check(p.count > 0 and b.x0 <= 0 and b.x1 >= 24 and b.y0 <= 0 and b.y1 >= 24,
    "missing painting/bounds for " .. name)
  H.check(not table.concat(p.out):find("pgfsetfillcolor{fl%d"), "unmapped pigment: " .. name)
  H.check(not table.concat(p.defs):find("rgb(", 1, true), "unmapped gradient: " .. name)
  H.check(not p.gilt_pending, "inline ornament generated raster gilt: " .. name)
end
local a = Inline.draw("gilt_star", 12, 12, 0, 3, "inlineink")
local b = Inline.draw("gilt_star", 12, 12, 0, 3, "inlineink")
H.check(table.concat(a.out) == table.concat(b.out), "inline render is not deterministic")
H.check(Serial.encode(Flora.settings) == settings and Flora.once == once
  and Serial.encode(Paint.palette) == palette, "inline render changed global state")
for _, args in ipairs({ {"unknown",12,12,0,1}, {"gilt_star",0,12,0,1},
  {"gilt_star",12,12,0,1.5}, {"gilt_star",12,12,0,"random"} }) do
  H.check(not pcall(Inline.draw, table.unpack(args)), "accepted invalid inline arguments")
end
H.done("inline")
