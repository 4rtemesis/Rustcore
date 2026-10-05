-- Run from repository root with Lua 5.1.
local function read(path)
    local f = assert(io.open('dist/Forever/Rustcore/' .. path, 'rb'))
    local s = f:read('*a'):gsub('\r\n', '\n'); f:close(); return s
end
local source = read('Rustcore.lua')
local finish = assert(source:find('-- The difficulty palette', 1, true))
local init = source:sub(1, finish-1) .. '\nRustcore.GetCharacterKey=GetCurrentCharacterKey; return EnsureProfile'
SlashCmdList = {}
local name, guid, now = 'Alice', 'Player-A', 0
function UnitName() return name end
function UnitGUID() return guid end
function UnitFullName() return name, 'Realm' end
function GetRealmName() return 'Realm' end
function UnitClass() return 'Warrior', 'WARRIOR' end
function UnitLevel() return 10 end
function GetTime() return now end
local function login()
    local ensure = assert(loadstring(init))()
    RustcoreVerification = nil
    assert(loadstring(read('Verification/Core.lua')))()
    return ensure
end
local ensure = login()
ensure().difficulty = 4
local saved = {identity={guid='Player-A'}, time={anchorPlayed=100, trackedSinceAnchor=120}, difficulty={status='VERIFIED'}}
RustcoreDB.verification = {['Player-A']=saved}
name, guid = 'Bob', 'Player-B'
ensure = login(); ensure().difficulty = 2
assert(RustcoreDB.profiles['Player-A'].difficulty == 4)
assert(RustcoreDB.profiles['Player-B'].difficulty == 2)
name, guid = 'Alice', nil
ensure = login()
assert(ensure().difficulty == 4)
assert(Rustcore.GetCharacterKey() == 'Player-A')
assert(RustcoreVerification.GetRecord() == saved)
guid = 'Player-A'
assert(ensure().difficulty == 4 and RustcoreVerification.GetRecord() == saved)
-- Settings created under a pre-GUID key follow the same character.
RustcoreDB.profiles['Player-A'] = nil
RustcoreDB.profiles['Alice-Realm'] = {characterLabel='Alice-Realm', difficulty=3}
assert(ensure().difficulty == 3 and RustcoreDB.profiles['Alice-Realm'] == nil)
-- Core's realm lookup works independently of the profile alias.
RustcoreDB.verification = {['Alice-Realm']=saved}
assert(RustcoreVerification.GetRecord() == saved)
-- A recreated character must not inherit the old GUID's profile or certificate.
guid = 'Player-New'
assert(ensure().difficulty == nil)
assert(RustcoreVerification.GetRecord() == nil)
-- Exercise the real accrual code across two fresh session-local clocks.
guid = 'Player-A'
local timeSource = read('Verification/Time.lua')
local function session()
    return assert(loadstring(timeSource .. '\nreturn Accrue, T.GetSessionTracked'))()
end
local accrue, total = session()
now=10; accrue(); now=40; accrue()
assert(saved.time.trackedSinceAnchor == 150 and total() == 30)
accrue, total = session()
assert(total() == 0 and saved.time.trackedSinceAnchor == 150)
now=1; accrue(); now=21; accrue()
assert(total() == 20 and saved.time.trackedSinceAnchor == 170 and saved.time.anchorPlayed == 100)
print('Profiles and verification survive character switches/late GUIDs; new GUID isolated; accumulated time survives fresh session clocks')
