-- tools/preview.lua must grow a saved page as it was compiled: the document
-- seed, an adapter's prepared seed, and the page's tuning under overrides.
local H = dofile("tests/helper.lua")
tex = tex or { sprint = function() end }
texio = texio or { write_nl = function() end }
local seen
package.loaded["flora.compose"] = { page = function(s) seen = s; return { defs = {}, out = {} } end }
package.loaded["flora.pdfout"] = { write = function() end }
local Init = require("flora.init")
local Serial = require("flora.serial")
local path = os.tmpname()

local function preview(spec, seed, extra)
  local f = assert(io.open(path, "w"))
  f:write(Serial.encode(spec), "\n")
  f:close()
  arg = { path, seed, "7", "out.pdf", nil, extra }
  dofile("tools/preview.lua")
  return seen
end

local base = { width = 400, height = 300, text = { x0 = 40, y0 = 30, x1 = 360, y1 = 270 }, doc_seed = "3" }
local function with(extra)
  local s = {}
  for k, v in pairs(base) do s[k] = v end
  for k, v in pairs(extra) do s[k] = v end
  return s
end

H.check(preview(with({}), "doc").seed == Init.seed("3", 7), "doc seed is not the compiled seed")
H.check(preview(with({ prepared_seed = 42 }), "doc").seed == 42, "doc preview lost the prepared seed")
H.check(preview(with({ prepared_seed = 42 }), "9").seed == Init.seed("9", 7), "explicit seed did not reseed")

local tuned = { compose = { leaves = 2 } }
H.check(preview(with({ tune = tuned }), "doc").tune.compose.leaves == 2, "page tuning lost without settings")
local s = preview(with({ tune = tuned }), "doc", "tune={compose={hero=0.3}}")
H.check(s.tune.compose.hero == 0.3 and s.tune.compose.leaves == 2, "settings did not merge over the page's tuning")
H.check(preview(with({ tune = tuned }), "doc", "fresh").tune == nil, "fresh kept the page's tuning")

-- The standalone progression tool shares the same seed rule.
local planned
package.loaded["flora.progression"] = {
  plan = function(s) planned = s; return { api_version = 1, parts = {}, area = 0 } end,
  stages = function() return {} end,
}
local f = assert(io.open(path, "w"))
f:write(Serial.encode(with({ prepared_seed = 42 })), "\n")
f:close()
arg = { path, "doc", "7", "out", "1" }
dofile("tools/progression.lua")
H.check(planned.seed == 42, "progression doc mode lost the prepared seed")

os.remove(path)
H.done("preview")
