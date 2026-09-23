local function read(name)
 local f=assert(io.open('dist/Forever/Rustcore/Verification/'..name)); local s=f:read('*a'):gsub('\r\n','\n'); f:close(); return s
end
SlashCmdList={}
assert(loadstring(read('Core.lua')))()
local V=RustcoreVerification
local source=read('Transfer.lua')
local a=assert(source:find('local function WorseStatus',1,true))
local b=assert(source:find('local function ApplyFields',a,true))
local merge=assert(loadstring('local V=RustcoreVerification\n'..source:sub(a,b-1)..'\nreturn PessimiseAgainstLocal'))()
local function record(status,tier)
 return {difficulty={status=status,evidenceStatus=status,highestVerifiedTier=tier,warnings={}},selfFound={status='VERIFIED',warnings={}},time={},chain={},economy={money={},items={}}}
end
local previous=record('UNVERIFIED',0)
local imported=record('VERIFIED',3)
V.importBootstrapDifficulty=previous.difficulty
merge(imported,previous)
assert(imported.difficulty.status=='VERIFIED' and imported.difficulty.highestVerifiedTier==3)
-- Observed losses still survive the bootstrap exception.
previous.difficulty.deaths=1; previous.difficulty.permanentCapTier=1
imported=record('VERIFIED',3); merge(imported,previous)
assert(imported.difficulty.deaths==1 and imported.difficulty.permanentCapTier==1)
-- Even an attempted same-status violation invalidates the initial-state exception.
V.GetTrack=function() return previous.difficulty end
V.SetStatus('difficulty','UNVERIFIED','observed violation')
assert(V.importBootstrapDifficulty==nil)
imported=record('VERIFIED',3); merge(imported,previous)
assert(imported.difficulty.status=='UNVERIFIED')
-- Persisted unverified records are never automatically treated as blank history.
previous=record('UNVERIFIED',0); imported=record('VERIFIED',3)
merge(imported,previous); assert(imported.difficulty.status=='UNVERIFIED')
print('Import restores fresh missing-history certification; retains caps, deaths and actual unverified findings')
