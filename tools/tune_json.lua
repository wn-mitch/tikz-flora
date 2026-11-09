-- Prints lua/flora/tune.lua (with any FLORA_TUNE overrides applied) as JSON,
-- for the tuner page. Run with texlua from the repository root.
package.path = "./lua/?.lua;" .. package.path
local Tune = require("flora.tune")
local Inks = require("flora.inks")

local function encode(v)
  local t = type(v)
  if t == "number" then return string.format("%.6g", v) end
  if t == "boolean" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if #v > 0 then
    local out = {}
    for i, x in ipairs(v) do out[i] = encode(x) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = string.format("%q:%s", k, encode(v[k])) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- Choice lists for settings that name something, keyed by the setting's
-- parent path: every color.palette part takes "look", a group or an ink.
local palette = { "look" }
for _, g in ipairs(Inks.group_order) do palette[#palette + 1] = g end
for _, n in ipairs(Inks.order) do palette[#palette + 1] = n end
local out = {}
-- _with is a helper, not a setting (tune.lua reserves underscore names).
for k, v in pairs(Tune) do if type(v) ~= "function" then out[k] = v end end
-- The ornament registry labels the ornament weights (tests check that
-- tune.lua lists every kind); a bare table read by bake_tune.py has none.
if Tune.ornaments then require("flora.ornaments") end
out._choices = { ["color.palette"] = palette }
-- Slider bounds for the gilt looks' keys, from their checked ranges.
out._bounds = {}
for name, look in pairs(Tune.gilt_looks or {}) do
  for k, r in pairs(require("flora.gilt_look").keys) do
    if look[k] ~= nil then out._bounds["gilt_looks." .. name .. "." .. k] = { r[1], r[2], r[3] } end
  end
end
io.write(encode(out), "\n")
