-- Draws one page's flora without TeX, for fast previews.
--
--   texlua tools/preview.lua SPEC SEED PAGE OUT.pdf [T] [SETTINGS]
--
-- SPEC is a layout written during a real compile with FLORA_SPEC_DIR set
-- (page size, text block and measured lines). The flora is grown exactly as
-- in that compile, for document seed SEED on page PAGE, and written as a
-- one-page PDF holding the flora alone; the text comes from that compile's
-- own pages. SEED "doc" takes the seed the document itself set. With T
-- (0-1) the flora is drawn as grown at that time (clock.lua), for "watch it
-- grow" frames; "-" or 1 draws the finished page. SETTINGS is a
-- \florasetup key list (mix, palette, spin, density, visitors, layout,
-- gilt, giltdpi, giltenv, giltlook, backdrop),
-- applied over the page's own. Two words in it are not settings: "fresh"
-- drops the page's own mix and palette first, as the site's mixer does, and
-- "noheader" drops the running-head rule, for a picture of the flora alone. FLORA_TUNE applies as usual. Run
-- from the repository root.

package.path = "./lua/?.lua;" .. package.path
local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")

local spec_path, seed, page, out, T, extra = arg[1], arg[2], tonumber(arg[3]), arg[4], tonumber(arg[5]), arg[6]
assert(spec_path and seed and page and out, "usage: preview.lua SPEC SEED PAGE OUT.pdf")
local f = assert(io.open(spec_path))
local spec = Serial.decode(f:read("a"))
f:close()
-- "doc" means this page as compiled, including a seed set by an adapter.
if seed == "doc" then
  spec.seed = spec.prepared_seed or Init.seed(spec.doc_seed or "1", page)
else
  spec.seed = Init.seed(seed, page)
end
spec.grow = T
if extra then
  local flags = {}
  for _, word in ipairs({ "noheader", "fresh" }) do
    extra = extra:gsub("%f[%w]" .. word .. "%f[%W],?%s*", function() flags[word] = true return "" end)
  end
  local own = flags.fresh and { layout = spec.layout, header = spec.header, gilt = spec.gilt, giltdpi = spec.gilt_dpi, giltenv = spec.gilt_env, giltlook = spec.gilt_look,
      backdrop = spec.backdrop }
    or { layout = spec.layout, header = spec.header, tune = spec.tune, mix = spec.mix, palette = spec.palette, spin = spec.spin, gilt = spec.gilt, giltdpi = spec.gilt_dpi, giltenv = spec.gilt_env,
      giltlook = spec.gilt_look, backdrop = spec.backdrop }
  local set = Settings.merge(own, Settings.parse(extra))
  local noheader = flags.noheader
  spec.layout, spec.mix, spec.palette, spec.spin = set.layout, set.mix, set.palette, set.spin
  spec.gilt, spec.gilt_dpi, spec.gilt_env, spec.gilt_look = set.gilt, set.giltdpi, set.giltenv, set.giltlook
  spec.backdrop = set.backdrop
  spec.tune = set.tune
  spec.header = set.header or spec.header
  if noheader then spec.header_y = nil end
end

Paint.reset_resources()
local pt = Compose.page(spec)
Pdf.write(out, pt, spec.width, spec.height)
