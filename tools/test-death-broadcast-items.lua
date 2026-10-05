local f=assert(io.open(arg[1] or 'dist/Forever/Rustcore/RustcoreBroadcast.lua','rb'))
local source=f:read('*a'):gsub('\r\n','\n');f:close()
local function section(a,b)
 local start=assert(source:find(a,1,true));local stop=assert(source:find(b,start,true));return source:sub(start,stop-1)
end
function strsplit(delim,text)
 local fields={};for s in (text..delim):gmatch('(.-)'..delim) do fields[#fields+1]=s end
 return unpack(fields)
end
local serialize,parse=assert(loadstring('local DELIM="~"; local CHANNEL_MARKER="RCD1~"; local MAX_CHANNEL_MESSAGE_BYTES=255\n'
 ..section('local function SanitizeField','local function EnsureRealmChannel')
 ..section('local function SerializeDeathData','local function QueueRealmMessage')
 ..section('local function Parse(msgStr)','-- Old clients')
 ..'\nreturn SerializeDeathData,Parse'))()
-- Verify the selected highest-ilvl item survives sender-to-receiver serialization.
local low='|cff0070dd|Hitem:11111:0:0:0|h[Lower Item]|h|r'
local high='|cffa335ee|Hitem:22222:'..string.rep('12345:',50)..'|h[Highest Item]|h|r'
RustcoreCompat={GetItemInfo=function(link)
 return 'Item',link,4,link==high and 650 or 100
end}
function UnitName() return 'Player' end
function UnitClass() return 'Warrior','WARRIOR' end
function UnitLevel() return 70 end
function GetZoneText() return 'Zone' end
function UnitRace() return 'Human' end
function UnitSex() return 2 end
function time() return 1790000000 end
local build=assert(loadstring(section('local function FindHighestIlvlItem',
 'local function SerializeDeathData')..'\nreturn BuildDeathData'))()
local selected=build({{link=low},{link=high},{link=low}},'Attacker')
local received=parse(serialize(selected))
assert(received.link:find('|Hitem:22222:',1,true))
assert(received.link:find('[Highest Item]',1,true))
assert(received.ilvl==650 and received.count==3 and received.source=='Attacker')
-- A valid link must survive zero or uncached ilvl results (e.g. starter gear).
local itemInfo=RustcoreCompat.GetItemInfo
RustcoreCompat.GetItemInfo=function() return 'Starter',low,1,0 end
received=parse(serialize(build({{link=low}},'Mana Wyrm')))
assert(received.link==low and received.count==1 and received.ilvl==0,
 'zero-ilvl item was dropped before serialization')
RustcoreCompat.GetItemInfo=function() return nil end
received=parse(serialize(build({{link=low}},'Mana Wyrm')))
assert(received.link==low, 'uncached item was dropped before serialization')
received=parse(serialize(build({{link=low,ilvl=10},{link=high,ilvl=80}},'Attacker')))
assert(received.link:find('|Hitem:22222:',1,true) and received.ilvl==80,
 'cached snapshot ilvl should select the highest lost item')
RustcoreCompat.GetItemInfo=itemInfo
local d={name='Example Character',class='WARRIOR',level=70,zone='Zone',source='Attacker',ilvl=650,count=3,race='Human',gender='Female',timestamp=1790000000}
local short='|cffa335ee|Hitem:12345:0:0:0|h[Lost Sword]|h|r'
d.link=short
local msg=serialize(d);assert(parse(msg).link==short)
-- Named item-quality colors must survive both updated senders and older peers.
local named='|cnIQ4:|Hitem:12345:0:0:0|h[Lost Sword]|h|r'
d.link=named
assert(parse(serialize(d)).link==short, 'named quality color was rejected')
local oldPacket=msg:gsub('|cffa335ee','|cnIQ4:')
assert(parse(oldPacket).link==short, 'incoming named quality color was rejected')
d.link='|cnIQ1:|Hitem:2092::::::::1:1:::::::::|h[Worn Dagger]|h|r'
assert(parse(serialize(d)).link:find('[Worn Dagger]',1,true))
d.link='|cnIQ4:|Hitem:12345:'..string.rep('12345:',50)..'|h[Lost Sword]|h|r'
local namedMsg=serialize(d)
assert(#namedMsg+5<=255 and parse(namedMsg).link:find('[Lost Sword]',1,true))
-- Large retail bonus payload: preserve a real item link instead of erasing it.
d.link='|cffa335ee|Hitem:12345:'..string.rep('12345:',50)..'|h[Lost Sword]|h|r'
msg=serialize(d);local result=parse(msg)
assert(#msg+5<=255 and result.link:find('|Hitem:12345:',1,true))
assert(result.link:find('[Lost Sword]',1,true) and result.count==3 and result.ilvl==650)
-- A payload that leaves room for only PART of the name must use a base link.
local label=string.rep('Long Item ',8)
d.link='|cffa335ee|Hitem:12345:'..string.rep('12345:',20)..'|h['..label..']|h|r'
msg=serialize(d);result=parse(msg)
assert(#msg+5<=255 and result.link:find('['..label..']',1,true))
assert(result.link:find('|Hitem:12345:|h',1,true))
assert(result.source==d.source and result.name==d.name and result.zone==d.zone)
assert(result.count==d.count and result.ilvl==d.ilvl and result.timestamp==d.timestamp)
-- Long labels and other metadata remain within the transport budget.
d.name=string.rep('N',100);d.zone=string.rep('Z',100);d.source=string.rep('S',100)
d.link='|cffa335ee|Hitem:54321:1:2:3|h['..string.rep('É',200)..']|h|r'
msg=serialize(d);result=parse(msg)
assert(#msg+5<=255 and result.link~='' and result.link:find('|Hitem:54321:',1,true))
local visible=assert(result.link:match('|h%[(.-)%]|h'))
assert(#visible>0 and #visible%2==0 and visible==string.rep('É',#visible/2))
-- Existing full-link packets still parse; non-item payloads are not displayed.
d.link='|Hspell:123|h[Spell]|h';assert(parse(serialize(d)).link=='')
d.link='';assert(parse(serialize(d)).link=='')
print((arg[1] or 'Forever')..': Death broadcasts preserve short links, oversized retail item identity, count and ilvl; stay within 255 bytes; reject non-item links')
