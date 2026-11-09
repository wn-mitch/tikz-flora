-- Standalone stage PDFs from one reusable plan, without TeX.
-- texlua tools/progression.lua SPEC SEED PAGE OUT_PREFIX N
package.path='./lua/?.lua;'..package.path
local Serial=require('flora.serial')
local Progression=require('flora.progression')
local Init=require('flora.init')
local Pdf=require('flora.pdfout')
local path,seed,page,prefix,n=arg[1],arg[2],tonumber(arg[3]),arg[4],tonumber(arg[5])
assert(path and seed and page and prefix and n,'usage: progression.lua SPEC SEED PAGE OUT_PREFIX N')
local f=assert(io.open(path)); local spec=Serial.decode(f:read('a')); f:close()
spec.seed=Init.spec_seed(spec,seed,page)
local start=os.clock()
local plan=Progression.plan(spec)
local stages=Progression.stages(plan,n)
for i,t in ipairs(stages) do
  Pdf.write(string.format('%s-%03d.pdf',prefix,i),Progression.render(plan,t),spec.width,spec.height)
end
print(string.format('progression v%d: %d parts, %.1f pt2, %d stages, %.2fs',
  plan.api_version,#plan.parts,plan.area,#stages,os.clock()-start))
