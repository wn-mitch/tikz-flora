local H=dofile('tests/helper.lua')
local cache_calls,compose_calls,nodes=0,0,0
tex={sprint=function() end}
texio={write_nl=function() end}
pdf={getcompresslevel=function() return 6 end}
img={scan=function(a) return a end,node=function(a) return a end}
node={write=function() nodes=nodes+1 end}
local painter={defs={},out={}}
package.loaded['flora.cache']={page=function(spec)
  cache_calls=cache_calls+1
  H.check(spec.width==400,'cache missed prepared spec')
  return 'cached.pdf',{coverage=.3},true
end}
package.loaded['flora.compose']={page=function() compose_calls=compose_calls+1; return painter end}
local Flora=require('flora.init')
local function args()
 return {width='400pt',height='300pt',text_x0='40pt',text_x1='360pt',text_y0='30pt',text_y1='270pt',seed='3',page=1}
end
Flora.page(args())
H.check(cache_calls==1 and compose_calls==0 and nodes==1,'normal page did not reuse upstream cache')
local a=args(); a.background_height='20pt'; Flora.page(a)
H.check(cache_calls==1 and compose_calls==1,'cache bypassed background wrapper')
Flora.add_reserve('10pt','20pt','30pt','40pt'); Flora.page(args()); Flora.clear_reserve()
H.check(cache_calls==1 and compose_calls==2,'cache bypassed reservation wrapper')
a=args(); local called=0; a.render_page=function() called=called+1; return painter end
Flora.page(a)
H.check(called==1 and cache_calls==1 and compose_calls==2,'cache bypassed adapter painter')
a.render_page=function() called=called+1; return nil end; Flora.page(a)
H.check(called==2 and cache_calls==1 and compose_calls==3,'adapter nil fallback used physical-page cache')
Flora.settings.cache=false; Flora.page(args())
H.check(cache_calls==1 and compose_calls==4,'cache=false ignored')
H.done('page_cache')
