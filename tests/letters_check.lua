-- Checks run by tests/letters.tex: box 0 holds a word set plainly, box 2
-- the same word as \floraletters, box 4 arched, box 6 a paragraph holding
-- it.
local SP = 65536
local function fail(msg) error("letters test: " .. msg) end
local plain, straight, arched = tex.box[0], tex.box[2], tex.box[4]

-- The lettering keeps the word's advance width (to the 0.001pt it is
-- written with), so it sets like text.
if math.abs(straight.width - plain.width) > 0.01 * SP then
  fail(string.format("lettering is %.2fpt wide, the word %.2fpt", straight.width / SP, plain.width / SP))
end
-- It drew the outlines: the picture's literal holds curves (c) and fills.
local literal
for n in node.traverse(straight.head) do
  local function find(h)
    for m in node.traverse(h) do
      if m.id == node.id("whatsit") and m.data and m.data:find(" c ", 1, true) then literal = m.data end
      if m.head then find(m.head) end
    end
  end
  if n.head then find(n.head) end
end
if not literal then fail("no outline curves were drawn") end
-- The shaded shadow falls below the baseline's descent-free capitals.
if straight.depth <= plain.depth then fail("the shadow did not deepen the box") end
-- An arch raises the middle above the straight word.
if arched.height <= straight.height + 2 * SP then
  fail(string.format("arched height %.2fpt is no taller than straight %.2fpt", arched.height / SP, straight.height / SP))
end
-- The measurer sees the lettering as ink.
local boxes = require("flora.measure").boxes(6, 800)
if #boxes ~= 1 or boxes[1].x1 - boxes[1].x0 < plain.width / SP - 2 then
  fail("the lettering was not measured as ink (" .. #boxes .. " boxes)")
end
-- A real LuaTeX discretionary must paint its no-break replacement and
-- advance subsequent glyphs just like the identical ordinary node list.
local first
for n in node.traverse(plain.head) do if n.id==node.id("glyph") then first=n; break end end
local function box(head)
  local b=node.new("hlist"); b.dir="TLT"; b.head=head
  b.width=plain.width+first.width; b.height=plain.height; b.depth=plain.depth
  return b
end
local ordinary_head=node.copy_list(plain.head)
local tail=node.tail(ordinary_head); tail.next=node.copy(first); tail.next.prev=tail
local ordinary_box=box(ordinary_head)
local disc=node.new("disc"); disc.replace=node.copy_list(plain.head)
disc.next=node.copy(first); disc.next.prev=disc
local replacement_box=box(disc)
local Letters,Paint=require("flora.letters"),require("flora.paint")
local opts=assert(Letters.options("style=outline"))
local a,b=Paint.new({backend="pdf"}),Paint.new({backend="pdf"})
Letters.paint(a,ordinary_box,opts); Letters.paint(b,replacement_box,opts)
if a:body()~=b:body() then fail("discretionary replacement glyphs or following advance changed") end
node.flush_list(ordinary_box); node.flush_list(replacement_box)
texio.write_nl("term and log", "letters: ok")
