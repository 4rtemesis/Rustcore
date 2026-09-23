local f=assert(io.open('dist/Forever/Rustcore/RustcoreBroadcast.lua','rb'))
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
local d={name='Example Character',class='WARRIOR',level=70,zone='Zone',source='Attacker',ilvl=650,count=3,race='Human',gender='Female',timestamp=1790000000}
local short='|cffa335ee|Hitem:12345:0:0:0|h[Lost Sword]|h|r'
d.link=short
local msg=serialize(d);assert(parse(msg).link==short)
-- Large retail bonus payload: preserve a real item link instead of erasing it.
d.link='|cffa335ee|Hitem:12345:'..string.rep('12345:',50)..'|h[Lost Sword]|h|r'
msg=serialize(d);local result=parse(msg)
assert(#msg+5<=255 and result.link:find('|Hitem:12345:',1,true))
assert(result.link:find('[Lost Sword]',1,true) and result.count==3 and result.ilvl==650)
-- Long labels and other metadata remain within the transport budget.
d.name=string.rep('N',100);d.zone=string.rep('Z',100);d.source=string.rep('S',100)
d.link='|cffa335ee|Hitem:54321:1:2:3|h['..string.rep('É',200)..']|h|r'
msg=serialize(d);result=parse(msg)
assert(#msg+5<=255 and result.link~='' and result.link:find('|Hitem:54321:',1,true))
-- Existing full-link packets still parse; non-item payloads are not displayed.
d.link='|Hspell:123|h[Spell]|h';assert(parse(serialize(d)).link=='')
d.link='';assert(parse(serialize(d)).link=='')
print('Death broadcasts preserve short links, oversized retail item identity, count and ilvl; stay within 255 bytes; reject non-item links')
