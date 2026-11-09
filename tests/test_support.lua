local H=dofile('tests/helper.lua')
local P=require('flora.progression')
local Paint=require('flora.paint')
local G=require('flora.geom')
local S=require('flora.sprig')
local Rng=require('flora.rng')
local Compose=require('flora.compose')
local original=Compose.page
local root={pts={{10,10},{10,90}}}
local branch={pts={{10,70},{40,70}}}
local crossing={pts={{0,70},{80,70}}}
Compose.page=function(spec)
  local pt=Paint.new({backend='pdf'}); P.attach(pt,spec)
  local function stem(token,birth,duration,support)
    P.part(pt,'stem',token.pts[1],birth,duration,function()
      pt:stroke(G.polyline(token.pts),{0,0,0},1)
    end,token.pts,{token=token,parent=support and support.parent,t=support and support.t})
  end
  -- The true parent is painted last and its provisional birth is later
  -- than the child. An unrelated crossing touches the same attachment.
  P.part(pt,'florets',{40,70},0,.1,function()
    pt:fill({{'o',40,70,3}},{0,0,1})
  end,nil,{parent=branch,t=1})
  stem(branch,.1,.2,{parent=root,t=.75})
  stem(crossing,0,.05)
  stem(root,.2,1)
  return pt
end
local plan=P.plan({width=100,height=100,text={x0=90,y0=0,x1=100,y1=100},lines={}})
Compose.page=original
local flower,child,noise,parent=table.unpack(plan.parts)
H.check(child.support==parent,'branch selected a nearby crossing instead of its actual parent')
H.check(math.abs(child.birth-.95)<1e-9,'child did not wait for the later painted parent')
H.check(flower.support==child and flower.birth>=child.birth+child.duration,'floret ignored transitive support')
H.check(math.abs(child.support_fraction-.75)<1e-9,'wrong support arc fraction')
H.check(flower.birth<parent.birth+parent.duration,'dependencies became a global stems-first phase')
local loop={{0,0},{10,10},{0,10},{10,0},{0,0},{10,10}}
local mapped={{0,0},{10,40},{0,40},{10,0},{0,0},{10,40}}
local late=G.fraction(loop,5)+.5*G.dist(loop[5],loop[6])/G.length(loop)
local expected=G.fraction(mapped,5)+.5*G.dist(mapped[5],mapped[6])/G.length(mapped)
H.check(math.abs(G.mapped_fraction(loop,loop,late)-late)<1e-9,'self-crossing attachment moved to an earlier visit')
H.check(math.abs(G.mapped_fraction(loop,mapped,late)-expected)<1e-9,'mapped attachment lost its sampled segment')
-- Actual spray builders: every ray, pedicel, recursive branch and floret
-- retains its construction parent despite width-bucket paint order/merge.
for _,kind in ipairs({'umbel','cyme','gyps'}) do
  Compose.page=function(spec)
    local pt=Paint.new({backend='pdf'}); P.attach(pt,spec)
    pt.growth_clock={reach=100,birth=function(_,x,y) return y end}
    local b=S.batch(); local support={parent=root,t=.75}; local r=Rng.new(7)
    if kind=='umbel' then S.umbel(b,r,{10,70},0,18,support)
    elseif kind=='cyme' then S.cyme(b,r,{10,70},0,18,1,support)
    else S.gypsophila(b,r,{10,70},0,18,3,support) end
    local merged=S.batch(); merged:merge(b); merged:paint(pt)
    P.part(pt,'stem',root.pts[1],.2,1,function()
      pt:stroke(G.polyline(root.pts),{0,0,0},1)
    end,root.pts,{token=root})
    return pt
  end
  local p=P.plan({width=100,height=100,text={x0=90,y0=0,x1=100,y1=100},lines={}})
  Compose.page=original
  local support_count=0
  for _,part in ipairs(p.parts) do if part.token~=root then
    H.check(part.support~=nil,kind..': missing support on '..part.kind)
    if part.support then
      support_count=support_count+1
      H.check(part.birth+1e-9>=part.support.birth+part.support.duration*part.support_fraction,
        kind..': child appears before parent reaches attachment')
      local seen={}; local top=part
      while top.support do
        H.check(not seen[top],kind..': support cycle'); if seen[top] then break end
        seen[top]=true; top=top.support
      end
      H.check(top.token==root,kind..': spray disconnected from root')
    end
  end end
  H.check(support_count>5,kind..': fixture did not build a compound spray')
end
-- Regression from Beamer's seed=3 logical frame 2, stage 2/4. Every
-- foreground plant part must trace through explicit parents to a main stem.
local file=assert(io.open('tests/fixtures/support-seed3.lua'))
local fixture=require('flora.serial').decode(file:read('a')); file:close()
Paint.reset_resources()
local actual=P.plan(fixture)
local attached=0
for _,part in ipairs(actual.parts) do
  local botanical=part.stem or ({leaves=true,blooms=true,hero=true,leaflet=true,florets=true,buds=true,stars=true})[part.kind]
  if botanical and not (part.token and part.token.main) then
    H.check(part.support~=nil,'seed3: unsupported '..part.kind)
  end
  if part.support then
    attached=attached+1
    H.check(part.birth+1e-9>=part.support.birth+part.support.duration*part.support_fraction,
      'seed3: parent has not reached attachment')
    local top=part
    while top.support do top=top.support end
    H.check(top.token and top.token.main,'seed3: support chain does not reach a main stem')
  end
end
H.check(attached>1000,'seed3: regression no longer exercises dense sprays')
-- Turned frames no longer inherit the page's top inset as a local limit.
H.check(math.abs(actual.area-6157.48)<.01,'support metadata changed measured painted area')
H.check(#P.stages(actual,4)==4,'seed3 overlay stages rejected')
Paint.reset_resources()
local ordinary=Compose.page(fixture)
H.check(ordinary:body()==actual.final:body(),'support metadata changed canonical endpoint')
-- Disabled runners retain ordinary composition's decorations, but cannot
-- require a painted runner. Exercise ordinary and curved/bare layouts.
for _,frame in ipairs({'left','wreath'}) do
  for _,rf in ipairs({0,1}) do
    local spec=H.page(3); spec.layout=frame; spec.tune={compose={runners=rf}}
    Paint.reset_resources()
    local grown=P.plan(spec)
    Paint.reset_resources()
    H.check(grown.final:body()==Compose.page(spec):body(),frame..': runners changed endpoint')
    H.check(#P.stages(grown,4)==4,frame..': runners rejected growth stages')
    for _,p in ipairs(grown.parts) do if p.support then
      H.check(p.birth+1e-9>=p.support.birth+p.support.duration*p.support_fraction,
        frame..': omitted runner bypassed ancestor timing')
    end end
  end
end
H.done('support')
