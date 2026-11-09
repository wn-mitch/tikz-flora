local H = dofile("tests/helper.lua")
local emitted = {}
tex = { sprint = function(s) emitted[#emitted + 1] = s end }
texio = { write_nl = function() end }
package.loaded["flora.compose"] = { page = function()
  return { defs = {}, out = { "FLORA" } }
end }
local Flora = require("flora.init")
Flora.add_reserve("0pt", "220pt", "60pt", "250pt")
Flora.add_reserve("20pt", "230pt", "80pt", "260pt")
local function render()
  emitted = {}
  Flora.page { width = "400pt", height = "300pt", text_x0 = "40pt",
    text_x1 = "360pt", text_y0 = "30pt", text_y1 = "270pt",
    seed = "3", page = 1, background_height = "60pt", background_color = "orange" }
  return table.concat(emitted, "\n")
end
local s = render()
local _, clips = s:gsub("pgfusepath{clip}", "")
H.check(clips == 2, "overlapping reserves must intersect separate exclusion clips")
H.check(not s:find("pgfsetfillcolor{white}", 1, true), "reserve repaints background white")
H.check(s:find("orange", 1, true) < s:find("pgfusepath{clip}", 1, true)
  and s:find("pgfusepath{clip}", 1, true) < s:find("FLORA", 1, true),
  "reservation clips the background or misses the flora")
Flora.clear_reserve()
H.check(not render():find("pgfusepath{clip}", 1, true), "clear leaves a reservation clip")
H.done("reserve")
