local H=dofile('tests/helper.lua')
local Paint=require('flora.paint')
local saved_node,saved_font,saved_fonts=node,font,fonts
local SP=65536
local ids={glyph=1,kern=2,glue=3,hlist=4,disc=5}
node={
 id=function(name) return ids[name] end,
 traverse=function(head)
  local next_node=head
  return function() local current=next_node; next_node=current and current.next; return current end
 end,
 effective_glue=function(n,b) return n.width+(n.stretch or 0)*(b.glue_set or 0) end,
 dimensions=function(head)
  local total=0
  for n in node.traverse(head) do total=total+(n.width or n.kern or 0) end
  return total
 end,
}
local outlines={units=1000,glyphs={}}
local chars={}
for i=65,67 do
 chars[i]={index=i}
 local w=(i-60)*50
 outlines.glyphs[i]={segments={{0,0,'m'},{w,0,'l'},{w,700,'l'},{0,700,'l'},{0,0,'l'}}}
end
font={getfont=function() return {filename='test.otf',size=10*SP,characters=chars} end}
fonts={handlers={otf={readers={loadshapes=function() return outlines end}}}}
local Letters=require('flora.letters')
local function glyph(c) return {id=ids.glyph,font=1,char=string.byte(c),width=5*SP} end
local function link(...)
 local list={...}
 for i=1,#list-1 do list[i].next=list[i+1] end
 return list[1]
end
local function paint(head,stretch)
 local p=Paint.new({backend='pdf'})
 local ext=Letters.paint(p,{head=head,width=30*SP,glue_set=stretch or 0},assert(Letters.options('style=outline')))
 H.check(ext~=nil,'test glyph outlines were unavailable')
 return p:body()
end
local expected=paint(link(glyph('A'),glyph('B'),glyph('C')))
local disc={id=ids.disc,replace=glyph('B'),pre=glyph('C'),post=glyph('C')}
H.check(paint(link(glyph('A'),disc,glyph('C')))==expected,'discretionary replacement glyph was skipped or alternatives painted')
local nested={id=ids.disc,replace={id=ids.disc,replace=glyph('B')}}
H.check(paint(link(glyph('A'),nested,glyph('C')))==expected,'nested replacement was skipped')
H.check(paint(link(glyph('A'),{id=ids.disc,pre=glyph('B'),post=glyph('B')},glyph('C')))==paint(link(glyph('A'),glyph('C'))),'empty replacement painted a break alternative')
-- The child must inherit effective glue, and its real advance must place C
-- where it appears in the same ordinary unbroken node list.
expected=paint(link(glyph('A'),{id=ids.glue,width=SP,stretch=2*SP},glyph('B'),{id=ids.kern,kern=SP},glyph('C')),1)
disc={id=ids.disc,replace=link({id=ids.glue,width=SP,stretch=2*SP},glyph('B'),{id=ids.kern,kern=SP})}
H.check(paint(link(glyph('A'),disc,glyph('C')),1)==expected,'replacement lost effective glue or following glyph advance')
node,font,fonts=saved_node,saved_font,saved_fonts
H.done('letters')
