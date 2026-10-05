local root='dist/Forever/Rustcore/'
local function read(path)
 local f=assert(io.open(root..path,'rb')); local s=f:read('*a'):gsub('\r\n','\n'); f:close(); return s
end
local record, now, level, xp, maxXP = nil, 0, 20, 0, 1000
local queued={}
function GetTime() return now end
function time() return now end
function UnitLevel() return level end
function UnitXP() return xp end
function UnitXPMax() return maxXP end
C_Timer={After=function(_,fn) queued[#queued+1]=fn end}
local function flush() local q=queued; queued={}; for _,fn in ipairs(q) do fn() end end
RustcoreVerification={STATUS={VERIFIED='VERIFIED',WARNING='WARNING',UNCERTAIN='UNCERTAIN',UNVERIFIED='UNVERIFIED'}}
local V=RustcoreVerification
V.GetRecord=function() return record end
V.GetPlayerLevel=function() return level end
V.Integrity={Seal=function() end}
local accrue,reconcile,event,sample=assert(loadstring(read('Verification/Time.lua')..'\nreturn Accrue,Reconcile,OnEvent,SampleXP'))()
local T=V.Time
local function setup()
 record={time={anchorPlayed=0,lastServerPlayed=10000,trackedSinceAnchor=7000,untrackedSeconds=3000}}
end
setup(); accrue()
assert(T.GetRequiredTracked()==5000)
-- At an efficient XP pace each watched second earns one extra recovery second.
for i=1,25 do
 now=now+100; accrue(); record.time.lastServerPlayed=record.time.lastServerPlayed+100
 T.CreditXP(level,100/T.XPSecondsPerLevel(level))
end
assert(T.GetRequiredTracked()<0.001 and T.GetXPRecoveryCredit()==2500)
assert(record.time.untrackedSeconds==3000, 'XP erased missing evidence')
assert(record.time.recoveredGapSeconds==3000)
level=60
assert(T.ComponentStatus()=='VERIFIED' and T.GetRequiredTracked()==0,
 'level change reopened a recovered gap')
record.time.untrackedSeconds=3001
assert(T.ComponentStatus()~='VERIFIED' and T.GetRequiredTracked()>0,
 'checkpoint concealed additional missing time')
level=20
-- A large XP burst cannot earn more bonus than real watched recovery time.
setup(); now=now+60; accrue(); T.CreditXP(level,1)
assert(T.GetXPRecoveryCredit()==60)
-- Same fraction is worth more at later levels; same absolute XP is scaled by XPMax.
assert(T.XPSecondsPerLevel(10)<T.XPSecondsPerLevel(40))
setup(); xp=900; maxXP=1000; level=20; T.ResetXPBaseline()
now=now+10; level=21; xp=100; maxXP=2000
sample()
local expected=.1*T.XPSecondsPerLevel(20)+.05*T.XPSecondsPerLevel(21)
assert(math.abs(record.time.xpRecoverySeconds-expected)<0.0001)
sample(); assert(math.abs(record.time.xpRecoverySeconds-expected)<0.0001, 'XP counted twice')
-- Both event orderings coalesce into one stable snapshot after a level-up.
for _,events in ipairs({{'PLAYER_LEVEL_UP','PLAYER_XP_UPDATE'},{'PLAYER_XP_UPDATE','PLAYER_LEVEL_UP'}}) do
 setup(); level=20; xp=900; maxXP=1000; T.ResetXPBaseline()
 for _,e in ipairs(events) do event(nil,e,e=='PLAYER_XP_UPDATE' and 'player' or 21) end
 level=21; xp=100; maxXP=2000; flush()
 assert(math.abs(record.time.xpRecoverySeconds-expected)<0.0001)
end
-- No credit for XP already present at login/import, or earned without a gap.
setup(); T.ResetXPBaseline(); sample(); assert(not record.time.xpRecoverySeconds)
record.time.untrackedSeconds=0; T.CreditXP(level,1); assert(not record.time.xpRecoverySeconds)
-- Unused recovery potential is discarded once verification is restored.
record.time.xpRecoverySeconds=1000; record.time.xpRecoveryWatched=100
now=now+10; accrue(); assert(record.time.xpRecoverySeconds==100 and record.time.xpRecoveryWatched==100)
-- Missing history on Forever is measured from birth, not grandfathered away.
RustcoreCompat={interfaceVersion=16001}; record={time={trackedSinceAnchor=120}}
reconcile(1000,1000); assert(record.time.anchorPlayed==0 and record.time.untrackedSeconds==880)
RustcoreCompat.interfaceVersion=11509; record={time={trackedSinceAnchor=120}}
reconcile(1000,1000); assert(record.time.anchorPlayed==1000 and record.time.untrackedSeconds==0)
local migration=read('Verification/Migration.lua')
local a=assert(migration:find('local function IsLegacyCharacter()',1,true))
local b=assert(migration:find('-- ── Baselines',a,true))
local legacy=assert(loadstring('local evidence={statsHistory=true}\n'..migration:sub(a,b-1)..'\nreturn IsLegacyCharacter'))()
RustcoreCompat.interfaceVersion=16001; assert(not legacy())
RustcoreCompat.interfaceVersion=11509; assert(legacy())
print('XP recovery: half-time target, watched cap, level scaling/rollover, no banking, and Forever anchor passed')
