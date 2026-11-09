set export

PATH := env("HOME") / "Library/TinyTeX/bin/universal-darwin" + ":" + env("PATH")
TEXINPUTS := "./tex//:"
# Values saved from the tuner override lua/flora/tune.lua when present.
# An interpreter with numpy and Pillow for tuner/; Homebrew's newest
# python3 may not have them yet.
PYTHON := env("FLORA_PYTHON", "python3.14")
FLORA_TUNE := if path_exists(justfile_directory() / "tune-local.lua") == "true" { justfile_directory() / "tune-local.lua" } else { "" }

# Compile a document in tex/ to build/<name>.pdf and a PNG preview.
build name="lorem" seed="1" dpi="200":
    mkdir -p build
    lualatex -interaction=nonstopmode -halt-on-error -output-directory=build \
        -jobname={{name}} "\def\florseed{ {{seed}} }\input{tex/{{name}}.tex}" > build/{{name}}.out || (tail -30 build/{{name}}.log; exit 1)
    pdftocairo -png -singlefile -r {{dpi}} build/{{name}}.pdf build/{{name}}
    grep -h 'flora:' build/{{name}}.log || true

# Time a compile of tex/manuscript.tex, a 51-page book with flora on every
# page, to build/manuscript.pdf; prints the seconds taken and the file size.
bench:
    mkdir -p build
    /usr/bin/time -p lualatex -interaction=nonstopmode -halt-on-error -output-directory=build \
        manuscript > build/manuscript.out 2> build/bench.txt || (tail -30 build/manuscript.log; exit 1)
    grep real build/bench.txt
    pdfinfo build/manuscript.pdf | grep -E 'Pages|File size'

# Run the Lua unit tests under texlua, and the tune.lua writer's test.
test:
    for f in tests/test_*.lua; do texlua "$f" || exit 1; done
    {{PYTHON}} -I tests/test_bake.py

# The ornament gallery: every ornament kind, labelled, for three seeds
# (tex/gallery.tex), to build/gallery.pdf and .png. ONLY limits it to some
# slots or kinds (comma-separated), e.g. `just gallery flourish,fan 6`.
gallery only="" seeds="3" dpi="100":
    FLORA_GALLERY={{only}} FLORA_GALLERY_SEEDS={{seeds}} just build gallery 1 {{dpi}}

# "Watch it grow": page PAGE of tex/NAME.tex as its flora grows, written to
# build/grow-NAME-PAGE.mp4 and .gif (tools/grow.sh; needs ffmpeg).
grow name="lorem" seed="1" page="1" fps="20" secs="8":
    tools/grow.sh {{name}} {{seed}} {{page}} {{fps}} {{secs}}

# The drop-in package: build/tikzflora.zip with the package, its Lua, the
# worked example, the title pages and a latexmkrc that selects LuaLaTeX
# (also on Overleaf).
dist:
    rm -rf build/dist && mkdir -p build/dist/tikzflora/lua
    cp tex/tikzflora.sty tex/tikzflora-boot.lua tex/latexmkrc README.md LICENSE build/dist/tikzflora/
    cp tex/lorem.tex build/dist/tikzflora/example.tex
    cp tex/titles.tex build/dist/tikzflora/titles.tex
    cp -R lua/flora build/dist/tikzflora/lua/flora
    rm -f build/tikzflora.zip
    # The files sit at the zip's root: Overleaf keeps a top-level folder on
    # Upload Project, and a main document inside one does not compile.
    cd build/dist/tikzflora && zip -qrX ../../tikzflora.zip .
    @echo "dist: build/tikzflora.zip"

# Compiles the example and the title pages from the unpacked zip alone,
# outside the repository and without its TEXINPUTS, as a user would.
test-dist: dist
    rm -rf build/test-dist && mkdir -p build/test-dist
    unzip -q build/tikzflora.zip -d build/test-dist/tikzflora
    # As Overleaf sees it: the package and the example at the root.
    for f in tikzflora.sty tikzflora-boot.lua latexmkrc example.tex titles.tex lua/flora/init.lua; do \
      unzip -l build/tikzflora.zip "$f" > /dev/null || { echo "dist: $f is not at the zip's root"; exit 1; }; \
    done
    cd build/test-dist/tikzflora && env -u TEXINPUTS -u FLORA_TUNE latexmk -quiet example > latexmk.out 2>&1 || (tail -30 example.log; exit 1)
    test "$(pdfinfo build/test-dist/tikzflora/example.pdf | awk '/^Pages/ {print $2}')" = 7
    grep -q 'painted objects' build/test-dist/tikzflora/example.log
    # An edit, as a user makes one: latexmk must settle again (the page
    # cache's index must stop changing once the pages do).
    cd build/test-dist/tikzflora && sed -i.orig "s/a hen's egg/a goose's egg/" example.tex && ! cmp -s example.tex example.tex.orig
    cd build/test-dist/tikzflora && env -u TEXINPUTS -u FLORA_TUNE latexmk -quiet example > latexmk-edit.out 2>&1 || (tail -30 latexmk-edit.out; echo "dist: latexmk did not settle after an edit"; exit 1)
    cd build/test-dist/tikzflora && env -u TEXINPUTS -u FLORA_TUNE latexmk -quiet titles > latexmk-titles.out 2>&1 || (tail -30 titles.log; exit 1)
    test "$(pdfinfo build/test-dist/tikzflora/titles.pdf | awk '/^Pages/ {print $2}')" = 4
    ! grep -q 'floraletters needs' build/test-dist/tikzflora/titles.log
    @echo "dist: example and title pages compile from the zip"

# The browser mixer runs the generator under Lua 5.4 (wasmoon); LuaLaTeX
# runs Lua 5.3. Runs the Lua tests under 5.4 and checks both draw the same
# pages byte for byte. Needs Homebrew's lua@5.4.
LUA54 := env("FLORA_LUA54", "/opt/homebrew/opt/lua@5.4/bin/lua5.4")
test-lua54:
    for f in tests/test_*.lua; do {{LUA54}} "$f" || exit 1; done
    mkdir -p build
    texlua tests/parity.lua build/parity-53.txt
    {{LUA54}} tests/parity.lua build/parity-54.txt
    cmp build/parity-53.txt build/parity-54.txt && echo "lua54: identical to texlua"

# Assets for the site (site/) made from the example, tex/lorem.tex: the
# zip, each layout's measured layout and text page for the mixer, page
# renders, the grow animation and the link-preview image.
site-bake seed="3" CW="site/src/lib/colourways.json":
    just dist
    rm -rf site/public/bake site/public/img site/public/media build/site-bake
    mkdir -p site/public/bake site/public/img/large site/public/media build/site-bake
    cp build/tikzflora.zip site/public/
    for _ in 1 2; do FLORA_SPEC_DIR=build/site-bake lualatex -interaction=nonstopmode -halt-on-error -output-directory=build/site-bake -jobname=base "\def\florseed{ {{seed}} }\def\florapages{0}\input{tex/lorem.tex}" > build/site-bake/base.out || (tail -20 build/site-bake/base.log; exit 1); done
    for p in 1 2 3 4 6; do cp build/site-bake/spec-$p.lua site/public/bake/; pdftocairo -png -singlefile -r 110 -f $p -l $p build/site-bake/base.pdf site/public/bake/text-$p; done
    # The mixer's title pages (11 to 14), one for each lettering style and
    # arch (site/bake-titles.mjs): each one's layout, its text without the
    # lettering, and the lettering alone as a mask the mixer fills with ink.
    mkdir -p build/site-bake/titles
    node site/bake-titles.mjs build/site-bake/titles > build/site-bake/titles/list.txt
    while read -r page v f; do \
        d=build/site-bake/titles/$v; mkdir -p $d; \
        FLORA_SPEC_DIR=$d lualatex -interaction=nonstopmode -halt-on-error -output-directory=$d -jobname=full "\def\florapages{0}\input{$f}" > $d/full.out || { tail -20 $d/full.log; exit 1; }; \
        FLORA_LETTERS=hide lualatex -interaction=nonstopmode -halt-on-error -output-directory=$d -jobname=text "\def\florapages{0}\input{$f}" > $d/text.out || { tail -20 $d/text.log; exit 1; }; \
        cp $d/spec-1.lua site/public/bake/spec-$v.lua; \
        pdftocairo -png -singlefile -r 110 -f 1 -l 1 $d/full.pdf $d/full; \
        pdftocairo -png -singlefile -r 110 -f 1 -l 1 $d/text.pdf site/public/bake/text-$v; \
        magick $d/full.png \( site/public/bake/text-$v.png -colorspace gray -threshold 99.5% -negate \) -compose lighten -composite -colorspace gray -negate -background black -alpha shape site/public/bake/letters-$v.png || exit 1; \
    done < build/site-bake/titles/list.txt
    printf '%s\n' '[{"layout":"left","page":4,"label":"Left"},{"layout":"right","page":3,"label":"Right"},{"layout":"centered","page":6,"label":"Centred"},{"layout":"title","page":1,"label":"Title"},{"layout":"surround","page":2,"label":"Surround"},{"layout":"flank","page":11,"label":"Flank"},{"layout":"wreath","page":12,"label":"Wreath"},{"layout":"bouquet","page":13,"label":"Bouquet"},{"layout":"scrollwork","page":14,"label":"Scrollwork"}]' > site/public/bake/manifest.json
    texlua tools/catalog.lua > site/public/bake/catalog.json
    just build lorem {{seed}} >/dev/null; just build lorem {{seed}} 110 >/dev/null
    pdftocairo -jpeg -jpegopt quality=86 -r 110 build/lorem.pdf site/public/img/page
    just build titles {{seed}} 110 >/dev/null
    pdftocairo -jpeg -jpegopt quality=86 -r 110 build/titles.pdf site/public/img/title
    # Each page twice as fine again, for the home page's viewer (Lightbox.svelte).
    pdftocairo -jpeg -jpegopt quality=86 -r 220 build/lorem.pdf site/public/img/large/page
    pdftocairo -jpeg -jpegopt quality=86 -r 220 build/titles.pdf site/public/img/large/title
    pdftocairo -png -singlefile -r 220 -f 4 -l 4 build/site-bake/base.pdf build/site-bake/text-4-large
    # Page 4 in each colourway of site/src/lib/colourways.json, grown as the
    # mixer grows it, and the first colourway's flora alone beside the guide.
    for i in $(seq 0 $(($(jq length $CW) - 1))); do s=$(jq -r ".[$i].seed" $CW) && w=$(jq -r ".[$i].key" $CW) && texlua tools/preview.lua build/site-bake/spec-4.lua $s 4 build/site-bake/cw-$i.pdf - "fresh, visitors=1, colourway=$w" && pdftocairo -png -singlefile -r 110 build/site-bake/cw-$i.pdf build/site-bake/cw-$i && magick build/site-bake/cw-$i.png site/public/bake/text-4.png -compose multiply -composite -quality 86 site/public/img/colourway-$i.jpg && pdftocairo -png -singlefile -r 220 build/site-bake/cw-$i.pdf build/site-bake/cw-$i-large && magick build/site-bake/cw-$i-large.png build/site-bake/text-4-large.png -compose multiply -composite -quality 86 site/public/img/large/colourway-$i.jpg || exit 1; done
    texlua tools/preview.lua build/site-bake/spec-4.lua $(jq -r ".[0].seed" $CW) 4 build/site-bake/flora-4.pdf - "fresh, noheader, visitors=1, colourway=$(jq -r ".[0].key" $CW)"
    pdftocairo -png -transp -singlefile -r 90 build/site-bake/flora-4.pdf build/site-bake/flora-4
    magick build/site-bake/flora-4.png -gravity west -crop 36%x100%+0+0 +repage site/public/img/flora-margin.png
    just grow lorem {{seed}} 3 20 8
    cp build/grow-lorem-3.mp4 site/public/media/grow.mp4
    cp build/grow-lorem-3.gif site/public/media/grow.gif
    magick -size 1200x630 xc:'#f5f2eb' \( site/public/img/colourway-0.jpg -resize x560 \) -geometry +12+35 -composite \( site/public/img/colourway-1.jpg -resize x560 \) -geometry +402+35 -composite \( site/public/img/colourway-2.jpg -resize x560 \) -geometry +792+35 -composite -quality 86 site/public/img/og.jpg

# The site with hot reload at http://127.0.0.1:5174/ (run site-bake first).
site-dev:
    cd site && npm ci --no-audit --no-fund --silent && npx vite --port 5174 --host 127.0.0.1

# Compares flora's WebGL2 and 2D canvas renderers on one garden at
# http://127.0.0.1:5175/tools/renderers.html (site/tools/renderers.js):
# grow time, each renderer's median draw time and a map of where their
# pictures differ. The form sets the garden; its URL reproduces a run.
renderers:
    cd site && npm ci --no-audit --no-fund --silent && npx vite --port 5175 --host 127.0.0.1

# The same bench in headless Chrome, printed as a table; ARGS as the page's
# form, e.g. `just renderers-bench dpr=1 settings=backdrop=dark`.
renderers-bench *ARGS:
    cd site && npm ci --no-audit --no-fund --silent
    node site/tests/renderers-bench.mjs {{ARGS}}

# Drives the built site in headless Chrome (site/tests/e2e.mjs).
# The garden for other web pages: build/garden/ holds garden.js, its
# worker and the Lua WebAssembly, to serve together (site/src/lib/garden.js).
garden:
    cd site && npm ci --no-audit --no-fund --silent && npx vite build --config vite.garden.config.js --logLevel warn
    @ls -1 build/garden build/garden/assets

# The garden's clock, and its bundle grown in headless Chrome.
test-garden: garden
    node site/tests/garden.mjs
    cd site && node tests/garden-e2e.mjs

test-site:
    cd site && npm ci --no-audit --no-fund --silent && npm run build --silent
    node site/tests/e2e.mjs
    node site/tests/margins-e2e.mjs

# Builds and publishes the site at https://flora.alpacasoft.dev (Cloudflare
# Workers; wrangler creates the DNS record for the custom domain).
site-deploy: site-bake
    cd site && npm ci --no-audit --no-fund --silent && npm run build --silent && npx wrangler deploy

# Integration tests for the shipout measurer and \floraletters (need
# lualatex).
test-tex:
    mkdir -p build
    lualatex -interaction=nonstopmode -halt-on-error -output-directory=build tests/measure.tex > build/measure.out || (grep -A3 '^!' build/measure.log; exit 1)
    grep -q 'measure: ok' build/measure.log && echo "measure: ok"
    lualatex -interaction=nonstopmode -halt-on-error -output-directory=build tests/letters.tex > build/letters.out || (grep -A3 '^!' build/letters.log; exit 1)
    grep -q 'letters: ok' build/letters.log && echo "letters: ok"
    lualatex -interaction=nonstopmode -halt-on-error -output-directory=build tests/reserve-dimensions.tex > build/reserve-dimensions.out || (grep -A3 '^!' build/reserve-dimensions.log; exit 1)
    echo "reserve-dimensions: ok"
    # The package lowers LaTeX's compression level 9 to 4, and keeps a
    # lower one a document set before loading it.
    for pre in 9:4 1:1; do \
        lualatex -interaction=nonstopmode -halt-on-error -output-directory=build -jobname=compress \
            "\pdfvariable compresslevel=${pre%:*} \documentclass{article}\usepackage{tikzflora}\typeout{compresslevel=\the\pdfvariable compresslevel}\stop" > build/compress.out || exit 1; \
        grep -q "^compresslevel=${pre#*:}$" build/compress.log || { echo "compresslevel ${pre%:*} became $(grep -o 'compresslevel=[0-9]*' build/compress.log), not ${pre#*:}"; exit 1; }; \
    done; echo "compresslevel: ok"
    # The page cache: grown on the first run, reused on the second, only
    # the edited page grown again, its index untouched by a run that uses
    # the same pages (latexmk reruns while it changes), a page dropped once
    # three newer layouts have not used it, and nothing cached with
    # cache=false, whose pages match the cached ones pixel for pixel.
    rm -rf build/cache build/cache-off && mkdir -p build/cache build/cache-off
    c() { lualatex -interaction=nonstopmode -halt-on-error -output-directory=build/cache -jobname=cache "$1\input{tests/cache.tex}" > build/cache/out.txt || exit 1; \
        test "$(grep -c 'grown and cached' build/cache/cache.log)/$(grep -c 'from the cache' build/cache/cache.log)" = "$2" || { echo "cache run $3: grown/found $(grep -c 'grown and cached' build/cache/cache.log)/$(grep -c 'from the cache' build/cache/cache.log), not $2"; exit 1; }; }; \
    c "" 2/0 1; pdftocairo -png -r 72 build/cache/cache.pdf build/cache/first; \
    c "" 0/2 2; pdftocairo -png -r 72 build/cache/cache.pdf build/cache/second; \
    cmp build/cache/first-1.png build/cache/second-1.png && cmp build/cache/first-2.png build/cache/second-2.png || { echo "cached pages differ from grown ones"; exit 1; }; \
    n() { ls build/cache/cache-flora/*.pdf | wc -l | tr -d ' '; }; \
    c "\def\cacheedit{9}" 1/1 3; test "$(n)" = 3 || { echo "edit run left $(n) files, not 3"; exit 1; }; \
    cp build/cache/cache-flora/index.lua build/cache/index-before.lua; \
    c "\def\cacheedit{9}" 0/2 4; \
    cmp -s build/cache/index-before.lua build/cache/cache-flora/index.lua || { echo "a run using the same pages rewrote the cache index"; exit 1; }; \
    c "\def\cacheedit{10}" 1/1 5; test "$(n)" = 4 || { echo "a page used two layouts ago was dropped"; exit 1; }; \
    c "\def\cacheedit{11}" 1/1 6; test "$(n)" = 4 || { echo "a page unused for three layouts was kept ($(n) files)"; exit 1; }; \
    c "\def\cacheedit{9}" 0/2 7; \
    lualatex -interaction=nonstopmode -halt-on-error -output-directory=build/cache-off -jobname=cache "\def\cacheoff{}\input{tests/cache.tex}" > build/cache-off/out.txt || exit 1; \
    test ! -e build/cache-off/cache-flora || { echo "cache=false still cached"; exit 1; }; \
    pdftocairo -png -r 72 build/cache-off/cache.pdf build/cache-off/off; \
    cmp build/cache/first-1.png build/cache-off/off-1.png || { echo "cached page differs from cache=false"; exit 1; }; \
    rm -rf build/cache && mkdir -p build/cache; \
    ! lualatex -interaction=nonstopmode -halt-on-error -output-directory=build/cache -jobname=cache "\def\cachecrash{}\input{tests/cache.tex}" > build/cache/out.txt || { echo "the stopped compile did not stop"; exit 1; }; \
    c "" 1/1 "after a stopped compile"; \
    echo "cache: ok"
    # A --draftmode run writes no PDF, so it grows no flora at all.
    rm -rf build/draft && mkdir -p build/draft
    lualatex --draftmode -interaction=nonstopmode -halt-on-error -output-directory=build/draft -jobname=cache tests/cache.tex > build/draft/out.txt
    ! grep -q 'flora: page' build/draft/cache.log && test ! -e build/draft/cache-flora && echo "draftmode: ok"

# The component tuner for lua/flora/tune.lua at http://127.0.0.1:8766/:
# builds the Svelte app in tuner/ and serves it with the render API.
tuner:
    cd tuner && npm ci --no-audit --no-fund --silent && npm run build --silent
    {{PYTHON}} -I tuner/server.py

# The tuner app with hot reload at http://127.0.0.1:5173/tuner/dist/; it
# forwards renders to a running `just tuner`.
tuner-dev:
    cd tuner && npm run dev

# Drives the built tuner in headless Chrome (tuner/tests/e2e.mjs).
test-tuner:
    cd tuner && npm ci --no-audit --no-fund --silent && npm run build --silent
    FLORA_PYTHON={{PYTHON}} node tuner/tests/e2e.mjs

# The TeX-free preview (tools/preview.lua) must match a real compile pixel
# for pixel once laid under the same page's text.
test-preview seed="3" page="2":
    mkdir -p build/test-preview
    FLORA_SPEC_DIR=build/test-preview lualatex -interaction=nonstopmode -halt-on-error -output-directory=build/test-preview -jobname=base "\def\florapages{0}\input{tex/reference.tex}" > /dev/null
    lualatex -interaction=nonstopmode -halt-on-error -output-directory=build/test-preview -jobname=real "\def\florseed{ {{seed}} }\def\florapages{ {{page}} }\input{tex/reference.tex}" > /dev/null
    texlua tools/preview.lua build/test-preview/spec-{{page}}.lua {{seed}} {{page}} build/test-preview/flora.pdf
    cd build/test-preview && pdftocairo -png -singlefile -r 110 flora.pdf flora && pdftocairo -png -singlefile -r 110 -f {{page}} -l {{page}} base.pdf text && pdftocairo -png -singlefile -r 110 -f {{page}} -l {{page}} real.pdf real
    cd build/test-preview && magick flora.png text.png -compose multiply -composite combo.png && magick compare -metric AE -fuzz 1% combo.png real.png null: 2>diff.txt; d=$(cut -d' ' -f1 diff.txt); echo "preview: $d pixels differ"; test "$d" = "0"