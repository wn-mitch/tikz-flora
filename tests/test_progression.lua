local H=dofile('tests/helper.lua')
local P=require('flora.progression')
local Paint=require('flora.paint')
local Compose=require('flora.compose')
local Serial=require('flora.serial')
local function spec(layout)
  return {width=360,height=270,text={x0=65,y0=35,x1=295,y1=235},seed=7,
    layout=layout or 'left', mix={gyps=0,cyme=0,umbel=0,ghost=0},
    tune={compose={sprays=0,leaves=2,small_blooms=1,curls=0,no_leaflets=true}}}
end
for _,layout in ipairs({'left','centered','surround','title','flank','wreath','bouquet','scrollwork'}) do
  local s=spec(layout); local saved=Serial.encode(s)
  Paint.reset_resources(); local ordinary=Compose.page(s):body()
  s=spec(layout)
  Paint.reset_resources(); local plan=P.plan(s,{resolution=1})
  H.check(P.api_version==1 and plan.api_version==1,'version marker')
  H.check(Serial.encode(s)==saved,'planning mutated input spec')
  H.check(plan.final:body()==ordinary,layout..': final painting changed')
  H.check(plan.area>0 and #plan.parts>4,layout..': missing parts/area')
  local seen={}; for _,part in ipairs(plan.parts) do seen[part.kind]=true end
  H.check(seen.stem and seen.hero,layout..': missing semantic categories')
  H.check(layout~='title' or seen.title,'title furniture missing')
  local stemEnds={}
  for _,part in ipairs(plan.parts) do if part.stem then
    local tip=part.stem[#part.stem]
    stemEnds[#stemEnds+1]={tip=tip,finish=part.birth+part.duration}
  end end
  for _,part in ipairs(plan.parts) do if part.kind=='hero' then
    local attached=false
    for _,ending in ipairs(stemEnds) do
      if require('flora.geom').dist(part.anchor,ending.tip)<1e-7 then
        attached=true
        H.check(part.birth+1e-9>=ending.finish,'hero opens before its supporting stem finishes')
      end
    end
    H.check(attached,'hero does not grow from a stem attachment')
  end end
  H.check(#plan.forms>0 and P.render(plan,.5):body():find(' Do',1,true),'parts are not reused as Forms')
  H.check(P.render(plan,1).xobjects==plan.forms,'endpoint changed frame transport')
  H.check(P.render(plan,1).pdf_resources:find('/ExtGState',1,true) and
    P.render(plan,1).pdf_resources:find('/Pattern',1,true),'canonical frame lacks painting resources')
  local before=plan.final:body()
  local real=Compose.page; Compose.page=function() error('render replanned composition') end
  for _,n in ipairs({1,2,4,16,64}) do
    local stages=P.stages(plan,n); H.check(#stages==n and stages[n]==1,'stage count/end')
    local previous=P.render(plan,0):body()
    for _,t in ipairs(stages) do
      local body=P.render(plan,t):body()
      H.check(body~=previous,layout..': duplicate consecutive stage')
      previous=body
    end
  end
  H.check(P.render(plan,.37):body()==P.render(plan,.37):body(),'repeat render differs')
  Compose.page=real
  H.check(plan.final:body()==before,'render mutated stored final')
  H.check(not pcall(P.stages,plan,1e9),'insufficient resolution accepted')
  for _,t in ipairs({-1,1.1,math.huge,0/0}) do H.check(not pcall(P.render,plan,t),'invalid progression accepted') end
end
-- Protection remains in page coordinates outside individual motif transforms.
local s=spec(); s.reserve={{15,80,55,100},{30,90,70,110}}
local plan=P.plan(s)
local body=P.render(plan,.5):body()
H.check(body:find('W* n',1,true)~=nil,'missing fixed exclusion clips')
H.check(not pcall(P.stages,plan,0) and not pcall(P.stages,plan,1.5),'invalid stage counts accepted')
local grown=spec(); grown.grow=.25
local plain=spec()
Paint.reset_resources(); local a=P.plan(grown).final:body()
Paint.reset_resources(); local b=P.plan(plain).final:body()
H.check(a==b,'spec.grow leaked into progression planning')
H.check(grown.grow==.25,'spec.grow not preserved')
H.done('progression')
