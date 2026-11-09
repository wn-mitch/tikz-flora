local H=dofile('tests/helper.lua')
md5=md5 or select(2,pcall(require,'md5'))
lfs=lfs or select(2,pcall(require,'lfs'))
-- LuaTeX bundles both; the standalone Lua 5.4 target has neither.
if type(md5)~='table' or type(lfs)~='table' then
  print('cache_key: skipped, needs LuaTeX md5 and lfs')
  return
end
local Cache=assert(loadfile('lua/flora/cache.lua'))('flora.cache','./lua/flora/cache.lua')
local Tune=require('flora.tune')
local spec={width=400,height=300,seed=7,text={x0=40,y0=30,x1=360,y1=270}}
local key=Cache.key(spec,{})
H.check(type(key)=='string' and #key==32,'cache cannot hash tuning with private helpers')
H.check(Cache.key(spec,{})==key,'cache key is unstable')
local other=Tune._with({compose={leaves=Tune.compose.leaves+1}},function() return Cache.key(spec,{}) end)
H.check(other~=key and Cache.key(spec,{})==key,'cache ignored or retained temporary tuning')
H.done('cache_key')
