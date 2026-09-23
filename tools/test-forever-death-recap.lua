-- Run from the repository root with Lua 5.1 or later.
local root = "dist/Forever/Rustcore/"
local timers, recap, apiThrows
local function resetRecap()
    timers, recap, apiThrows = {}, nil, false
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    C_DeathRecap = { GetRecapEvents = function()
        if apiThrows then error("restricted") end
        return recap
    end }
    UnitGUID = function() return "Player-self" end
    UnitIsDeadOrGhost = function() return false end
    issecretvalue = function(value) return type(value) == "table" and value.secret end
    CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
    dofile(root .. "RustcoreDeathRecap.lua")
    RustcoreDeathRecap.CaptureBaseline()
end
local function flush()
    local count = 0
    while #timers > 0 do
        count = count + 1
        assert(count < 100, "timer loop")
        table.remove(timers, 1)()
    end
end
local function hit(guid, flags, event, amount, timestamp)
    return { sourceGUID = guid, sourceFlags = flags, destGUID = "Player-self",
        event = event or "SWING_DAMAGE", amount = amount or 10, timestamp = timestamp or 100 }
end
resetRecap()
local classify = RustcoreDeathRecap.Classify
assert(classify({hit("Player-enemy")}, "Player-self") == "pvp")
assert(classify({hit("Creature-mob", 0x200)}, "Player-self") == "pve")
assert(classify({hit(nil,nil,"ENVIRONMENTAL_DAMAGE")}, "Player-self") == "pve")
assert(classify({hit("Player-self")}, "Player-self") == "pve")
assert(classify({hit("Pet-enemy", 0x100)}, "Player-self") == "pvp")
assert(classify({hit(nil, 0x400)}, "Player-self") == "pvp")
assert(classify({hit(nil,nil)}, "Player-self") == "unknown")
assert(classify({}, "Player-self") == "unknown")
assert(classify({hit("Player-healer",nil,"SPELL_HEAL")}, "Player-self") == "unknown")
local missing = hit("Creature-mob"); missing.amount = nil
assert(classify({hit("Creature-mob"),missing}, "Player-self") == "unknown")
local secret = hit("Player-enemy"); secret.sourceGUID = {secret=true}
assert(classify({secret}, "Player-self") == "unknown")
secret.amount = {secret=true}
assert(classify({secret}, "Player-self") == "unknown")
assert(classify({hit(nil,nil),hit("Player-enemy")}, "Player-self") == "pvp")
local foreign = hit("Player-enemy"); foreign.destGUID = "Player-other"
assert(classify({foreign}, "Player-self") == "unknown")
print("Recap classification: players, NPCs, pets, self, environment, missing/secret data passed")

local verdict, calls
resetRecap(); calls = 0
RustcoreDeathRecap.Check(function(v) verdict=v; calls=calls+1 end)
table.remove(timers,1)() -- first read has not arrived
recap = { hit("Creature-mob") }; flush()
assert(verdict=="pve" and calls==1)
resetRecap(); recap={hit("Player-enemy")}; RustcoreDeathRecap.CaptureBaseline()
RustcoreDeathRecap.Check(function(v) verdict=v end); flush()
assert(verdict=="unknown", "stale recap accepted")
resetRecap(); apiThrows=true; RustcoreDeathRecap.CaptureBaseline(); apiThrows=false
recap={hit("Creature-mob")}
RustcoreDeathRecap.Check(function(v) verdict=v end); flush()
assert(verdict=="unknown", "failed baseline accepted")
resetRecap(); apiThrows=true
RustcoreDeathRecap.Check(function(v) verdict=v end); flush()
assert(verdict=="unknown")
print("Recap timing: delayed arrival, stale data, failed baseline, API error passed")

local file=assert(io.open(root.."Rustcore.lua","rb")); local core=file:read("*a"); file:close()
local a=assert(core:find("local function NotifyVerificationDeath",1,true))
local b=assert(core:find("-- ── Merchant repair blocking",a,true))
local deathCode=core:sub(a,b-1)
local compile=loadstring or load
local settings, shown, deaths, verified, announced, notes
local function loadDeathEngine()
    return assert(compile([[
local markedItems={}
local combatSnapshot={{slot=1,link="item:original",name="Original"}}
local snapshotWeaponSkipped=false
local tookEnemyPlayerDamageThisCombat=false
local lastDeathSource=nil
local pendingGuildDeathMessage
local function TakeSnapshot() end
local function BuildMarkedItems(source) markedItems={source[1]} end
local function GetCurrentCharacterKey() return "Player-self" end
local function PendingDeletionBelongsToCurrentCharacter() return true end
local function QueueGuildDeathMessage() end
]] .. deathCode .. [[
return { Die=OnPlayerDead, Resurrect=function() combatSnapshot={}; markedItems={} end }
]]))()
end
local function resetDeath()
    resetRecap()
    settings={ignoreDeathAfterEnemyPlayerDamage=true,difficulty=2}
    shown,deaths,verified,announced,notes={},0,{},0,0
    RustcoreDB={}; RustcoreCharacterDB={}; SlashCmdList={}
    Rustcore={GetSetting=function(k) return settings[k] end}
    RustcoreCompat={CanUseCombatLog=function() return false end}
    RustcoreStats={RegisterDeath=function() deaths=deaths+1 end}
    RustcoreVerification={Difficulty={OnDeath=function(context) verified[#verified+1]=context end},
        DeathLoss={Note=function() notes=notes+1 end}}
    RustcoreBroadcast={Announce=function() announced=announced+1 end}
    RustcoreUI={ShowDeletionFrame=function(items,snapshot) shown[#shown+1]={items=items,snapshot=snapshot} end}
    RustcoreDragon=nil
    InCombatLockdown=function() return false end
    wipe=function(t) for k in pairs(t) do t[k]=nil end end
    return loadDeathEngine()
end
local engine=resetDeath()
engine.Die(); assert(#shown==0)
recap={hit("Player-enemy")}; flush()
assert(#shown==0 and not RustcoreDB.pendingDeletion and not Rustcore.HasPendingDeathReview())
assert(deaths==1 and verified[1].penaltyApplied==false and notes==0)

engine=resetDeath(); engine.Die(); engine.Resurrect(); settings.difficulty=5
recap={hit("Creature-mob")}; flush()
assert(#shown==1 and shown[1].items[1].link=="item:original")
assert(shown[1].snapshot[1].link=="item:original" and verified[1].tier==2)
assert(deaths==1 and notes==1 and not Rustcore.HasPendingDeathReview())

engine=resetDeath(); engine.Die(); flush()
assert(#shown==1 and deaths==1 and notes==1 and not Rustcore.HasPendingDeathReview(),
    "missing recap must apply normal penalty")

engine=resetDeath(); engine.Die(); recap={hit(nil,nil)}; flush()
assert(#shown==1 and verified[1].penaltyApplied==true, "unidentified source must apply normal penalty")

-- Reload before a decision, retaining SavedVariables and discarding old timers.
engine=resetDeath(); engine.Die(); resetRecap()
settings.difficulty=5; engine=loadDeathEngine()
Rustcore.ResumePendingDeathPenalties()
assert(#shown==1 and shown[1].items[1].link=="item:original" and verified[1].tier==2)
assert(not Rustcore.HasPendingDeathReview())

-- A v6 held review automatically follows the new binary rule on login.
engine=resetDeath(); engine.Die(); resetRecap()
RustcoreCharacterDB.pendingDeathReviews[1].status="review"
engine=loadDeathEngine(); Rustcore.ResumePendingDeathPenalties()
assert(#shown==1 and not Rustcore.HasPendingDeathReview())

engine=resetDeath(); engine.Die()
SlashCmdList.RUSTCOREDEATHREVIEW("apply")
recap={hit("Creature-mob")}; flush()
assert(#shown==1 and deaths==1 and notes==1, "late callback duplicated death")

engine=resetDeath(); RustcoreDB.pendingDeletion={{link="item:older"}}
engine.Die(); recap={hit("Player-enemy")}; flush()
assert(RustcoreDB.pendingDeletion[1].link=="item:older", "PvP cleared an earlier obligation")

engine=resetDeath(); RustcoreDB.pendingDeletion={{link="item:older"}}
engine.Die(); recap={hit("Creature-mob")}; flush()
assert(#shown==0 and Rustcore.HasPendingDeathReview())
assert(RustcoreDB.pendingDeletion[1].link=="item:older")

engine=resetDeath(); settings.ignoreDeathAfterEnemyPlayerDamage=false; engine.Die(); recap={hit("Player-enemy")}; flush()
assert(#shown==1 and #timers==0 and deaths==1)
print("Death flow: PvP/PvE, resurrection, binary unknown fallback, relog/legacy recovery, frozen rules/gear, duplicate callback, earlier obligations, opt-out passed")

engine=resetDeath()
RustcoreUI.ShowDeletionFrame=function() error("simulated window failure") end
engine.Die(); recap={hit("Creature-mob")}; flush()
assert(RustcoreDB.pendingDeletion[1].link=="item:original")
assert(not Rustcore.HasPendingDeathReview() and deaths==1 and notes==1)
print("Window failure preserves a single committed obligation without re-queueing death")

engine=resetDeath(); RustcoreDB.pendingDeletion={{link="item:older"}}
engine.Die(); recap={hit("Creature-mob")}; flush()
assert(#shown==0)
RustcoreDB.pendingDeletion=nil
Rustcore.ResumePendingDeathPenalties()
assert(#shown==1 and not Rustcore.HasPendingDeathReview())
print("Queued normal penalty resumes after the earlier obligation is finished")

resetRecap()
local a,b=hit("Creature-old",nil,nil,10,100),hit("Creature-last",nil,nil,10,101)
a.sourceName="Old mob"; b.sourceName="Last mob"
assert(RustcoreDeathRecap.Source({b,a},"Player-self")=="Last mob")
b.sourceName={secret=true}
assert(RustcoreDeathRecap.Source({a,b},"Player-self")==nil)
b.event="ENVIRONMENTAL_DAMAGE"; b.environmentalType="FALLING"
assert(RustcoreDeathRecap.Source({a,b},"Player-self")=="FALLING")
engine=resetDeath(); settings.ignoreDeathAfterEnemyPlayerDamage=false
local announcedSource
RustcoreBroadcast.Announce=function(_,source) announcedSource=source end
engine.Die(); recap={a}; flush()
assert(announcedSource=="Old mob" and deaths==1)
print("Latest readable recap source reaches broadcast even with PvP protection off")
