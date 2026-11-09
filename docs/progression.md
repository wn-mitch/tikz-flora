# Reusable page growth (Lua API v1)

`flora.progression` plans a complete page once. It records projected painting
and semantic parts: stems, complete leaves and flowers, spray stalks and
florets, visitors, the hero, ornaments and title furniture. It retains layer
order, palette, random choices, final batched drawing and PDF resources.
`spec.grow` continues to select the older distance-clock effect in
`flora.compose`; the new planner ignores it without changing the input spec.

```lua
local Growth = require('flora.progression')
assert(Growth.api_version == 1)
local plan = Growth.plan(spec) -- spec uses ordinary compose.page fields
local stages = Growth.stages(plan, 16) -- array [1..16], k/16, last = 1
local pt = Growth.render(plan, stages[3])
local frame = Growth.render(plan, 2/16 + 0.4/16) -- arbitrary timed interval
```

`render` accepts finite progression in [0,1]. Zero is empty and one contains
the original finished painting. A plan is an in-memory, document-local object;
keep it for all overlays and animation frames. Do not serialize it, mutate its
parts, reset Paint resources while it is live, or reuse it in another PDF.
`pt.defs` shares the plan's resource definitions; emit them before the body.

Stems extend along their original curved paths. Complete forms scale from
their attachment points; ornaments without an attachment grow about their
painted centroid. Provisional birth times follow the plant's stem-distance field, normalized
across plants so growth occurs around the whole page. Actual dependencies come
from the construction graph: a shoot, stalk, spray ray or leaflet records its
supporting stem and attachment arc fraction; florets and buds record their own
pedicel. The planner resolves this graph recursively, independent of painting
layers, width buckets and provisional times. A child starts only after that
specific parent reaches its attachment. Basal foliage can therefore open while
higher stems are still extending; there are no global stem/leaf/flower phases.
Crossings never select a different supporting stem. A nonlinear frame preserves
the attachment's sampled path segment when converting its arc fraction. A monotone inverse of
summed painted part areas distributes requested progression over the page.
A part's repeated watercolor passes count once in its footprint. The default
measurement grid is 1 pt; `plan(spec, {resolution=0.5})` refines it. Curves are
flattened for measurement; thin strokes receive fractional cell coverage.
This is an approximation to projected painted area, not an opacity-weighted
pixel integral. Overlapping semantic parts contribute separately. Stem area
is approximated as proportional to visible arc length.

Measurement accounts for fixed frame/header clips, page edges, text rectangles
and reservations. Each part also retains its original header/frame/page/text/reservation clips
inside its Form before growth scaling. Thus material clipped out of the finished
part cannot be scaled back into view, even for fully invisible parts with no
measured anchor. During rendering text and reservation exclusions additionally
remain in page coordinates outside every scaling transform, including overlapping
reservations. At the final endpoint the original drawing and reservation clips
are used; its existing text avoidance is preserved exactly. This prevents intermediate shapes crossing protected text.
`stages` requires a positive integer and rejects insufficient sampled area
(less than one measurement cell per stage) or identical quantized part progress.
The check concerns the plan's geometric resolution; visibility still depends on
the viewer's raster resolution and display size.

The plan exposes `api_version`, `width`, `height`, `resolution`, `area`, `parts`
and `final` for diagnostics. Treat other fields as implementation details.
`plan` stores the semantic parts as PDF Form XObjects with a shared resource
dictionary. `render` emits transforms, curved stem clips and references to these
forms; it allocates no new gradients, opacity states, motifs or layouts. Mature
parts reuse the same form at the same scale. Spray ribbons and each stroke-width
bucket additionally use a small isolated transparency Form per rendered frame:
their parts grow independently inside it, while opacity and blending apply once
to the combined batch. This preserves the original compositing at intersections.
The original final batched stream
is retained for exact endpoint painting. `flora.typeset` registers PDF definitions
once per document; PGF definitions retain their normal scope behavior.
`flora.flush` uses a native LuaTeX frame Form for every stage, including the
canonical endpoint, so Beamer and animate manage the current resource scope.
The endpoint retains its original raw batched commands inside that Form. The planner requires the PDF backend. Actual playback
speed depends on the viewer; XObject reuse does not guarantee a frame rate.

## TeX adapters

`flora.init.render_page_version == 1` advertises:

```lua
flora.page {
  -- normal page arguments ...
  prepare_spec = function(spec) -- adjust measured geometry/seed here
  end,
  render_page = function(spec, args)
    return Growth.render(cached_plan, t)
  end,
}
```

`render_page` runs after measurement, `prepare_spec` and diagnostic export.
Return a painter for the normal picture wrapper; return nil to compose normally;
return true after emitting a custom picture or animation. Filtered physical pages
do not invoke rendering. `flora.typeset_page(pt,spec,args)` emits the shared
picture wrapper, optional background band, reservations and painted content.
For animations invoke it one frame at a time so the pending PDF literal is
flushed before constructing the next frame.

## Standalone example

Use a measured layout saved by `FLORA_SPEC_DIR`, or a Lua table file with the
ordinary width, height, text and seed fields:

```sh
texlua tools/progression.lua build/spec-1.lua doc 1 build/stage 16
```

This builds one plan and writes `build/stage-001.pdf` through
`build/stage-016.pdf`. `tex/progression.tex` demonstrates four overlay-like
stages using the same in-memory plan. `tools/test.sh progression render_page`
checks the API, all stage counts 1/2/4/16/64, sparse compositions, multiple page
layouts, final-stream equality, input immutability and rendering without
composition. The progression suite runs in CI alongside composition tests, and a separate
CI job runs the raster integration test.

Optional raster integration: `python3 tests/test_progression_raster.py` requires
Pillow and Poppler (`pdftoppm`). It verifies all 64 transitions at 72 dpi,
approximate painted area (maximum absolute deviation below 0.10), empty start,
pixel-identical canonical endpoint, bounded XObject/raw antialias differences and fixed
text/overlapping reservation protection. Standalone stage PDFs each contain their
own resources; shared forms reduce a multi-frame document, not a directory of
independent PDFs.

A measurement with a dense 8-second, 20-fps presentation frame
(161 samples) reduced the PDF from 122.9 MB to 5.1 MB and build time from
349.7 s to 14.1 s with shared Forms; peak RSS was about 437 MB. Acrobat Reader
26.00222031 still advanced at roughly 4 fps in the initial playback test.
These measurements establish resource/build improvements, not smooth real-time
playback. Viewer behavior remains an integration validation item.

The clip regression uses both 16 and 64 stages: a wholly clipped header line must
never appear, and a partially clipped shape must follow the silhouette of geometry
clipped before scaling (allowing a one-pixel antialias edge). The Lua/TeX growth
API requires no external Python or Poppler process. Those tools are dependencies
of the explicitly invoked raster integration test; raster animation workflows in
adapters must document their additional external tooling separately.

The support regression includes adversarial paint order and a misleading nearby
crossing, actual umbel/cyme/gypsophila builders after batch merge, self-crossing
paths and nonlinear arc mapping. `tests/fixtures/support-seed3.lua` records the
measured seed-3 Beamer frame that formerly showed floating sprays at stage 2/4;
every foreground botanical part must trace its support chain to a main stem.
Its painted area and canonical endpoint are checked unchanged.
