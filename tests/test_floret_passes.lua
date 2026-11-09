-- Painting florets pass by pass must match the canonical order, and a pass
-- must be empty exactly when floret_paints says so.
local H = dofile("tests/helper.lua")
local F = require("flora.flower")
local function record()
  local log = {}
  local function add(kind) return function(_, cmds, _, a, b) log[#log + 1] = kind .. ":" .. #cmds .. ":" .. tostring(a) .. ":" .. (type(b)=="table" and tostring(b.blend) or tostring(b)) end end
  return { fill = add("fill"), stroke = add("stroke"), log = log }
end
local items = {}
for _, r in ipairs({ 0.5, 1, 1.5 }) do
  for _, airy in ipairs({ false, true }) do items[#items + 1] = { 10, 10, r, 0, 2, airy } end
end
local whole = record()
F.florets(whole, items)
local parts = record()
for _, pass in ipairs(F.FLORET_PASSES) do F.florets(parts, items, pass) end
H.check(table.concat(whole.log, "\n") == table.concat(parts.log, "\n"), "passes differ from the canonical order")
for i, f in ipairs(items) do
  for _, pass in ipairs(F.FLORET_PASSES) do
    local one = record()
    F.florets(one, { f }, pass)
    H.check((#one.log > 0) == F.floret_paints(f, pass), string.format("floret %d disagrees in pass %s", i, pass))
  end
end
H.done("floret_passes")
