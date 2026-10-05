local root='dist/Forever/Rustcore/'
local function read(path)
 local f=assert(io.open(root..path,'rb')); local s=f:read('*a'):gsub('\r\n','\n'); f:close(); return s
end
function UnitGUID() return 'Player-test' end
function UnitName() return 'Tester' end
function UnitLevel() return 20 end
function time() return 12345 end
SlashCmdList={}
RustcoreVerification={}; assert(loadstring(read('Verification/Core.lua')))()
local V=RustcoreVerification
assert(loadstring(read('Verification/Integrity.lua')))()
local seal=V.Integrity.Seal
V.Integrity.Seal=function() end; V.Integrity.Append=function() end
local store,previous={},nil
V.FindRecordKey=function() return 'Player-test',previous end
V.GetStore=function() return store end
V.GetRecord=function() return store['Player-test'] end
V.GetAddonVersion=function() return 'test' end
V.BuildIdentity=function() return {guid=UnitGUID()} end
local combat=false
testProfile={difficulty=4,selfFound=true,showDeathWarning=false,theme='untouched'}
Rustcore={GetSetting=function(key) return testProfile[key] end,
 SettingsLocked=function() return combat end, GetCharacterKey=UnitGUID}
local source=read('Rustcore.lua')
local a=assert(source:find('function Rustcore.ApplyVerificationSettings',1,true))
local b=assert(source:find('function Rustcore.SetSetting',a,true))
assert(loadstring('local EnsureProfile=function() return testProfile end\n'..source:sub(a,b-1)))()
assert(loadstring(read('Verification/Transfer.lua')))()
local X=V.Transfer
store['Player-test']={createdAt=100,origin='NEW_CHARACTER',
 difficulty={status='VERIFIED',highestVerifiedTier=4,startedAtLevel=1,warnings={}},
 selfFound={status='VERIFIED',startedAtLevel=1,claimed=true,warnings={}},
 time={anchorPlayed=0,lastServerPlayed=10000,trackedSinceAnchor=7000,untrackedSeconds=3000,
 xpRecoverySeconds=500,xpRecoveryWatched=400,recoveredGapSeconds=3000}}
seal(V.GetRecord()); assert(V.Integrity.Check(V.GetRecord()))
V.GetRecord().time.xpRecoverySeconds=501
assert(not V.Integrity.Check(V.GetRecord()), 'XP recovery was not sealed')
V.GetRecord().time.xpRecoverySeconds=500
local exported=assert(X.BuildString(10000))
assert(exported:sub(1,4)=='RC4:')
local decoded=assert(X.Parse(exported))
assert(decoded.selectedTier==4 and decoded.selfFoundSetting==1)
assert(decoded.xpRecovery==500 and decoded.xpWatched==400 and decoded.recoveredGap==3000)
local function import(text)
 local ok,err
 X.BeginImport(text,function(success,msg) ok,err=success,msg end)
 X.OnTimePlayed(10000)
 return ok,err
end
-- Request is mocked but still completes through the real public import flow.
C_Timer={After=function() end}
V.Time={GetLastServerPlayed=function() return 10000 end,Request=function() end,
 GetSessionTracked=function() return 0 end,ResetXPBaseline=function() end}
testProfile.difficulty=2; testProfile.selfFound=false
assert(import(exported))
assert(testProfile.difficulty==4 and testProfile.selfFound==true)
assert(testProfile.theme=='untouched' and testProfile.showDeathWarning==false)
assert(V.GetRecord().time.xpRecoveryWatched==400 and V.GetRecord().difficulty.currentTier==4)
-- A false toggle must also overwrite a true destination toggle.
testProfile.selfFound=false; local disabled=assert(X.BuildString(10000)); testProfile.selfFound=true
assert(import(disabled)); assert(testProfile.selfFound==false)
-- No settings/record mutation when combat prevents the import.
local original=V.GetRecord(); testProfile.difficulty=2; combat=true
assert(not import(exported)); assert(V.GetRecord()==original and testProfile.difficulty==2)
combat=false
-- Legacy RC2 strings leave settings unchanged and start with no XP credit.
local body=exported:match('^RC4:%x+:(.*)$')
local fields={}; for value in (body..'~'):gmatch('(.-)~') do fields[#fields+1]=value end
fields[1]='2'; for i=#fields,41,-1 do fields[i]=nil end
local legacyBody=table.concat(fields,'~')
local legacy='RC2:'..V.Integrity.Hash(legacyBody)..':'..legacyBody
assert(X.Parse(legacy)); assert(import(legacy))
assert(testProfile.difficulty==2 and testProfile.selfFound==false)
assert(V.GetRecord().time.xpRecoveryWatched==0)
-- The immediately previous RC3 format remains readable, without a checkpoint.
local v3={}; for v in (body..'~'):gmatch('(.-)~') do v3[#v3+1]=v end
v3[1]='3'; v3[45]=nil
local v3body=table.concat(v3,'~')
local parsed3=assert(X.Parse('RC3:'..V.Integrity.Hash(v3body)..':'..v3body))
assert(parsed3.selectedTier==4 and parsed3.recoveredGap==0)
-- Derived uncertainty must never become permanent imported evidence.
local r=V.GetRecord()
r.difficulty.evidenceStatus='VERIFIED'; r.difficulty.status='UNCERTAIN'
r.selfFound.evidenceStatus='FAILED'; r.selfFound.status='FAILED'
local evidence=assert(X.Parse(assert(X.BuildString(10000))))
assert(evidence.dStatus=='VERIFIED' and evidence.sStatus=='FAILED')
-- Recovery earned at a lower level survives repeated real export/import flows.
local currentLevel=20
function UnitLevel() return currentLevel end
V.GetPlayerLevel=function() return currentLevel end
assert(loadstring(read('Verification/Time.lua')))()
V.RegisterComponent('time',function() return V.Time.ComponentStatus() end)
local recovered=V.GetRecord()
recovered.time.untrackedSeconds=2000
recovered.time.xpRecoverySeconds=500; recovered.time.xpRecoveryWatched=400
V.Time.CheckpointRecovery()
assert(recovered.time.recoveredGapSeconds==2000)
currentLevel=60
previous=recovered
for i=1,2 do
 local roundtrip=assert(X.BuildString(10000))
 assert(import(roundtrip))
 assert(V.Time.ComponentStatus()=='VERIFIED')
 assert(V.Time.GetRequiredTracked()==0)
 assert(V.GetRecord().difficulty.status=='VERIFIED')
 assert(V.GetRecord().selfFound.status=='FAILED', 'recovery cleared a rule violation')
 previous=V.GetRecord()
end
-- An older import of the same gap must not discard the earned checkpoint.
fields[26]=X.ToB36(2000)
local sameGapBody=table.concat(fields,'~')
assert(import('RC2:'..V.Integrity.Hash(sameGapBody)..':'..sameGapBody))
assert(V.GetRecord().time.recoveredGapSeconds==2000 and V.Time.GetRequiredTracked()==0)
-- Invalid settings and inflated watched credit are rejected even with a valid checksum.
local function invalid(index,value)
 local parts={}; for v in (body..'~'):gmatch('(.-)~') do parts[#parts+1]=v end
 parts[index]=value; local data=table.concat(parts,'~')
 assert(not X.Parse('RC4:'..V.Integrity.Hash(data)..':'..data))
end
invalid(45,X.ToB36(3001)); invalid(43,'6'); invalid(44,'2'); invalid(42,X.ToB36(7001))
print('Verification transfer: settings allowlist, XP persistence, RC2 compatibility, combat and validation passed')
