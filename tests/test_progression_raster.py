"""Optional integration test: texlua, pdftoppm and Pillow required.

Run python3 tests/test_progression_raster.py from the repository root.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image, ImageChops, ImageFilter

LUA = r"""
package.path='./lua/?.lua;'..package.path
local P=require('flora.progression')
local PDF=require('flora.pdfout')
local prefix=arg[1]
local s={width=360,height=270,text={x0=65,y0=35,x1=295,y1=235},seed=7,
  layout='centered',header='margin',mix={gyps=0,cyme=0,umbel=0,ghost=0},
  tune={compose={sprays=0,leaves=2,small_blooms=1,curls=0,no_leaflets=true}}}
local p=P.plan(s)
assert(#P.stages(p,64)==64)
for i=0,64 do
  PDF.write(string.format('%s-%02d.pdf',prefix,i),P.render(p,i/64),s.width,s.height)
end
PDF.write(prefix..'-ordinary.pdf',p.final,s.width,s.height)
local names={}
for i,part in ipairs(p.parts) do names[i]=part.form; part.form=nil end
-- Batch transparency groups remain Forms even when their children use
-- raw paths; discard only the semantic part indirection above.
local unfactored=P.render(p,.5)
PDF.write(prefix..'-unfactored.pdf',unfactored,s.width,s.height)
for i,part in ipairs(p.parts) do part.form=names[i] end
s.reserve={{15,80,55,100},{30,90,70,110}}
local protected=P.plan(s)
PDF.write(prefix..'-protected.pdf',P.render(protected,.5),s.width,s.height)
print(string.format('%d parts; %.1f pt2; Lua memory %.1f MiB',#p.parts,p.area,collectgarbage('count')/1024))
-- A red header line is wholly clipped in the endpoint; a blue rectangle
-- crosses that clip. Compare growth against geometry clipped in advance.
local Paint=require('flora.paint')
local Compose=require('flora.compose')
local original=Compose.page
-- Standalone composition must honor the same exclusions as the TeX
-- wrapper, including a full-page reserve and overlapping boxes.
local ordinary_spec={width=120,height=100,text={x0=40,y0=20,x1=100,y1=80},seed=7,
  reserve={{0,0,120,100}},gilt_dpi=72}
PDF.write(prefix..'-reserved-ordinary.pdf',Compose.page(ordinary_spec),120,100)
local S=require('flora.sprig')
local G=require('flora.geom')
Compose.page=function(spec)
  local pt=Paint.new({backend='pdf'}); P.attach(pt,spec)
  pt:fill({{'m',0,0},{'l',100,0},{'l',100,100},{'l',0,100},{'z'}},{.8,.6,.4})
  pt.growth_clock={reach=100,birth=function() return 0 end}
  local b=S.batch()
  for class=1,3 do
    b:line({{10,20+class*15},{90,20+class*15}},class)
    b:line({{10,20+class*15},{90,20+class*15}},class)
    b:line({{50,5},{50,95}},class)
  end
  b:stem({{10,10},{90,90}},5,5)
  b:stem({{10,90},{90,10}},5,5)
  local merged=S.batch(); merged:merge(b); merged:paint(pt)
  -- Keep growth running after the spray batches mature, to compare their
  -- ordinary compositing before the canonical endpoint is selected.
  P.part(pt,'late-marker',{95,95},2,1,function()
    pt:fill({{'o',95,95,1}},{1,0,0})
  end)
  return pt
end
Paint.reset_resources()
local crossing=P.plan({width=100,height=100,text={x0=100,y0=0,x1=100,y1=100},lines={}})
PDF.write(prefix..'-batch-grown.pdf',P.render(crossing,1-1e-10),100,100)
PDF.write(prefix..'-batch-final.pdf',P.render(crossing,1),100,100)
Compose.page=original
local function fixture(cut)
  Compose.page=function(spec)
    local pt=Paint.new({backend='pdf'}); P.attach(pt,spec)
    pt:clip_begin({{'m',0,0},{'l',100,0},{'l',100,60},{'l',0,60},{'z'}})
    P.part(pt,'marker',{70,10},0,1,function()
      pt:fill({{'m',70,10},{'l',80,10},{'l',80,20},{'l',70,20},{'z'}},{0,0.6,0})
    end)
    if not cut then
      P.part(pt,'hidden-header',nil,0.4,0.6,function()
        pt:stroke({{'m',10,80},{'l',90,80}},{1,0,0},2)
      end)
    end
    P.part(pt,'partial-header',{20,50},0,1,function()
      local top=cut and 60 or 90
      pt:fill({{'m',20,50},{'l',40,50},{'l',40,top},{'l',20,top},{'z'}},{0,0,1})
    end)
    pt:clip_end(); return pt
  end
  local plan=P.plan({width=100,height=100,text={x0=90,y0=0,x1=100,y1=100},lines={}})
  Compose.page=original
  return plan
end
local clipped,reference=fixture(false),fixture(true)
assert(clipped.parts[2].area==0,'fixture header was not fully clipped')
for _,n in ipairs({16,64}) do
  local stages=P.stages(clipped,n)
  for i,t in ipairs(stages) do
    PDF.write(string.format('%s-clip-%d-%02d.pdf',prefix,n,i),P.render(clipped,t),100,100)
    PDF.write(string.format('%s-reference-%d-%02d.pdf',prefix,n,i),P.render(reference,t),100,100)
  end
end

"""


def raster(path):
    subprocess.run(
        ['pdftoppm', '-r', '72', '-singlefile', '-png', str(path), str(path.with_suffix(''))],
        check=True, capture_output=True,
    )
    with Image.open(path.with_suffix('.png')) as image:
        return image.convert('RGB')


def pixels(image):
    # Pillow 13 deprecates getdata; Ubuntu's packaged Pillow predates its
    # replacement. Support both for the optional test and CI.
    return image.get_flattened_data() if hasattr(image, 'get_flattened_data') else image.getdata()


def painted(image):
    return sum(min(pixel) < 245 for pixel in pixels(image))


def main():
    start = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='flora-growth-') as directory:
        root = Path(directory)
        script = root / 'stages.lua'
        script.write_text(LUA)
        prefix = root / 'stage'
        subprocess.run(['texlua', str(script), str(prefix)], check=True)
        paths = [root / f'stage-{i:02d}.pdf' for i in range(65)]
        with ThreadPoolExecutor(max_workers=4) as pool:
            images = list(pool.map(raster, paths))
        changes = [sum(max(pixel) > 3 for pixel in pixels(ImageChops.difference(a, b)))
                   for a, b in zip(images, images[1:])]
        assert min(changes) > 0, 'a stage failed to change visible pixels'
        areas = list(map(painted, images))
        assert areas[0] == 0, 'zero progression paints visible content'
        errors = [abs(area / areas[-1] - i / 64) for i, area in enumerate(areas)]
        assert max(errors) < .10, f'painted area deviates by {max(errors):.3f}'
        unfactored = raster(root / 'stage-unfactored.pdf')
        difference = ImageChops.difference(unfactored, images[32])
        differences = list(pixels(difference))
        # Poppler can antialias a Form's clip differently from a page path.
        # Bound both the peak change and the total pixel error.
        assert max(map(max, differences)) <= 32, 'XObject factoring changed painting'
        assert sum(sum(pixel) for pixel in differences) / (3 * len(differences)) < .05, 'XObject raster error too large'
        ordinary = raster(root / 'stage-ordinary.pdf')
        assert ImageChops.difference(ordinary, images[-1]).getbbox() is None, 'final composition changed'
        protected = raster(root / 'stage-protected.pdf')
        reserved = raster(root / 'stage-reserved-ordinary.pdf')
        assert painted(reserved.crop((2, 2, reserved.width-2, reserved.height-2))) == 0, 'standalone reserve ignored'
        grown = raster(root / 'stage-batch-grown.pdf')
        final = raster(root / 'stage-batch-final.pdf')
        delta = list(pixels(ImageChops.difference(grown, final)))
        # Forms and transparency-group edges can antialias differently;
        # interiors (especially the crossings) must retain batch opacity.
        assert max(map(max, delta)) <= 32, 'batch overlap changed opacity'
        assert sum(map(sum, delta)) / (3 * len(delta)) < .05, 'batch endpoint jump'
        # The interior of each exclusion is white, including their overlap.
        bp = 72 / 72.27
        for x0, y0, x1, y1 in [(15, 80, 55, 100), (30, 90, 70, 110), (65, 35, 295, 235)]:
            region = protected.crop((int(x0 * bp) + 2, int((270 - y1) * bp) + 2,
                                     int(x1 * bp) - 2, int((270 - y0) * bp) - 2))
            assert painted(region) == 0, 'intermediate growth crossed fixed protection'
        for count in (16, 64):
            actual_paths = [root / f'stage-clip-{count}-{i:02d}.pdf' for i in range(1, count + 1)]
            reference_paths = [root / f'stage-reference-{count}-{i:02d}.pdf' for i in range(1, count + 1)]
            with ThreadPoolExecutor(max_workers=4) as pool:
                actual = list(pool.map(raster, actual_paths))
                expected = list(pool.map(raster, reference_paths))
            for stage, (image, target) in enumerate(zip(actual, expected), 1):
                assert not any(r > 150 and g < 100 and b < 100 for r, g, b in pixels(image)), (
                    f'fully clipped header appeared at {stage}/{count}')
                # A clipping edge and a filled polygon edge have different
                # antialias coverage. Allow one edge pixel, but no source
                # geometry outside the pre-clipped silhouette's neighborhood.
                expected_blue = Image.new('L', target.size)
                expected_blue.putdata([255 if b > 180 and r < 120 and g < 120 else 0
                                       for r, g, b in pixels(target)])
                allowed = list(pixels(expected_blue.filter(ImageFilter.MaxFilter(3))))
                assert all(allowed[i] or not (b > 180 and r < 120 and g < 120)
                           for i, (r, g, b) in enumerate(pixels(image))), (
                    f'partially clipped geometry scaled into view at {stage}/{count}')
        size = sum(path.stat().st_size for path in paths)
        print(f'progression raster: 64 distinct transitions; minimum {min(changes)} changed pixels; '
              f'max area error {max(errors):.3f}; clipped silhouettes 16/64 pass; PDFs {size / 1024**2:.1f} MiB; '
              f'{time.monotonic() - start:.1f}s')


if __name__ == '__main__':
    main()
