local H=dofile('tests/helper.lua')
local outputs={}
tex={sprint=function(s) outputs[#outputs+1]=s end}
texio={write_nl=function() end}
local calls=0
local pt={defs={},out={'CUSTOM'}}
package.loaded['flora.compose']={page=function() calls=calls+1; return pt end}
local Flora=require('flora.init')
local function args()
  return {width='400pt',height='300pt',text_x0='40pt',text_x1='360pt',text_y0='30pt',text_y1='270pt',seed='3',page=7}
end
H.check(Flora.render_page_version==1 and type(Flora.typeset_page)=='function','missing render capability')
local a=args(); a.prepare_spec=function(s) s.seed=42 end
local seen
local other={defs={},out={'CACHED'}}
a.render_page=function(s,actual) seen=s; H.check(s.seed==42 and actual==a,'callback ordering/args'); return other end
Flora.page(a)
H.check(calls==0 and table.concat(outputs):find('CACHED',1,true),'cached painter recomposed or omitted')
outputs={}; a.render_page=function() tex.sprint('ANIMATION'); return true end
Flora.page(a)
H.check(calls==0 and table.concat(outputs)=='ANIMATION','self-emitting callback received extra wrapper')
a.render_page=function() return nil end; Flora.page(a)
H.check(calls==1,'nil callback did not fall back to normal composition')
outputs={}; Flora.typeset_page(other,seen,{background_height='20pt',background_color='blue'})
H.check(table.concat(outputs):find('blue',1,true),'helper lost background')
outputs={}; seen.reserve={{10,20,30,40},{20,30,40,50}}
Flora.typeset_page(other,seen,{})
local _,n=table.concat(outputs):gsub('pgfseteorule','')
H.check(n==2,'helper lost overlapping reservation exclusion clips')
outputs={}; Flora._pdf_defs=nil
local cached={backend='pdf',defs={'RESOURCE'},body=function() return 'BODY' end}
Flora.typeset(cached); Flora.typeset(cached)
local registrations=0
for _,s in ipairs(outputs) do if s=='RESOURCE' then registrations=registrations+1 end end
H.check(registrations==1,'cached PDF definitions registered repeatedly')
outputs={}; Flora.typeset({backend='pgf',defs={'COLOUR'},out={}})
Flora.typeset({backend='pgf',defs={'COLOUR'},out={}})
H.check(#outputs==2,'scoped PGF definitions were suppressed')
H.done('render_page')
