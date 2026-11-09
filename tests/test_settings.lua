local H = dofile("tests/helper.lua")
local Settings = require("flora.settings")
local Tune = require("flora.tune")

local a = Settings.parse("header=body, tune={compose={hero=0.3}, gesture.bow_amp={0.1,0.2}}")
local b = Settings.parse("tune={compose={hero_shift=12}}")
local c = Settings.merge(a, b)
H.check(c.header == "body" and c.tune.compose.hero == 0.3
  and c.tune.compose.hero_shift == 12, "nested overrides lost sibling settings")
H.check(a.tune.compose.hero_shift == nil, "merge changed its input")
local d = Settings.merge(c, Settings.parse("tune={gesture.bow_amp={0.3,0.4}}"))
H.check(d.tune.gesture.bow_amp[1] == 0.3 and c.tune.gesture.bow_amp[1] == 0.1,
  "list replacement changed the previous settings")
for _, bad in ipairs({
  "header=unknown", "tune={unknown=1}", "tune={compose={hero=word}}",
  "tune={gesture={bow_amp={1}}}", "tune={_with=1}",
}) do
  H.check(not pcall(Settings.parse, bad), "accepted invalid settings: " .. bad)
end
local before = Tune.compose.hero
local over = { compose = { hero = 0.3 }, gesture = { bow_amp = { 0.1, 0.2 } } }
local result = Tune._with(over, function()
  H.check(Tune.compose.hero == 0.3, "override was not applied")
  return 17
end)
H.check(result == 17 and Tune.compose.hero == before, "successful render leaked tuning")
H.check(over.gesture.bow_amp[1] == 0.1, "restoration changed caller's list")
H.check(not pcall(Tune._with, over, function() error("render failure") end),
  "render failure was swallowed")
H.check(Tune.compose.hero == before, "failed render leaked tuning")
-- A cached raster ramp must remain immutable after leaving its scope,
-- including nested scopes and failure restoration.
local Serial = require("flora.serial")
local original = Serial.encode(Tune.gilt_looks.studio.gold)
local ramp = { { 0, { 1, 0, 0 } }, { 1, { 1, 0, 0 } } }
local outer, inner
Tune._with({ gilt_looks = { studio = { gold = ramp } } }, function()
  outer = Tune.gilt_looks.studio.gold
  pcall(Tune._with, { gilt_looks = { studio = { gold = { { 0, { 0, 1, 0 } }, { 1, { 0, 1, 0 } } } } } }, function()
    inner = Tune.gilt_looks.studio.gold
    error("restore nested ramp")
  end)
  H.check(Serial.encode(Tune.gilt_looks.studio.gold) == Serial.encode(ramp), "nested ramp not restored")
end)
H.check(Serial.encode(Tune.gilt_looks.studio.gold) == original, "default ramp not restored")
H.check(Serial.encode(outer) == Serial.encode(ramp), "restoration mutated memoized ramp")
H.check(inner[1][2][2] == 1, "nested restoration mutated memoized ramp")
H.done("settings")
