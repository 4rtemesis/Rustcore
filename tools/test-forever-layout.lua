local function read(name)
 local f=assert(io.open('dist/Forever/Rustcore/'..name));local s=f:read('*a'):gsub('\r\n','\n');f:close();return s
end
local source=read('RustcoreStats.lua')
local a=assert(source:find('local function ComputeLayout()',1,true))
local b=assert(source:find('-- Natural size',a,true))
local horizontal,long,count=true,true,3
Rustcore={GetSetting=function() return horizontal end}
local layout=assert(loadstring([[
local COLUMN_GAP, ROW_GAP, TITLE_BAND_H = 5,4,10
local function ActiveVariant() return {width=80} end
local function TileHeight() return 40 end
local function TitlesShown() return true end
local function LongItemShown() return testLong end
local function LongItemSize() return 165,35 end
local function VisibleCounters()
 local t={}; for i=1,testCount do t[#t+1]={key=i} end
 t[#t+1]={key='best',isBestItem=true};return t
end
]]..source:sub(a,b-1)..'\nreturn ComputeLayout'))()
for n=0,3 do
 testCount,testLong=n,true
 horizontal=true;local l=layout()
 assert(l.long.y==0 and l.long.x==(n>0 and n*85 or 0))
 for _,cell in ipairs(l.cells) do assert(cell.y==0 and cell.x+80<=l.long.x) end
 assert(l.width>=l.long.x+l.long.w)
 horizontal=false;l=layout();if n>0 then assert(l.long.y>0) end
end
source=read('RustcoreDurability.lua')
a=assert(source:find('local function ClampEdgeOffset',1,true));b=assert(source:find('\nend',a,true))
local clamp=assert(loadstring('local function Clamp(v,a,b) return math.max(a, math.min(b,v)) end\n'..source:sub(a,b+3)..'\nreturn ClampEdgeOffset'))()
for _,size in ipairs({20,200,1000}) do
 for _,offset in ipairs({-1000,-1,0,400,3000}) do
  local x=clamp(offset,size,1000); assert(x>=0 and x+size<=1000)
 end
end
assert(clamp(100,1200,1000)==0)
print('Horizontal long-name row, vertical fallback and full-panel screen boundaries passed')
