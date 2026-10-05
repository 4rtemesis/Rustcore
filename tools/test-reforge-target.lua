-- Reuse the frame mocks, then exercise the real peer protocol and target renderer.
local root = (arg and arg[1]) or "dist/forever/Rustcore"
dofile("tools/test-reforge-buff-layout.lua")
local now, ownTarget, enabled, prestige, debugMode = 0, false, true, true, false
GetTime = function() return now end
UnitExists = function(unit) return unit == "target" or unit == "player" end
UnitIsPlayer = function() return true end
UnitIsUnit = function() return ownTarget end
UnitName = function(unit) return unit == "player" and "Local" or "Peer" end
Rustcore.GetSetting = function() return enabled end
RustcoreReforge = { RUSTBOUND_ICON = "helmet", HasRustbound = function() return prestige end,
    IsDebug = function() return debugMode end }
TargetFrame = CreateFrame("Frame")
TargetFrame.buffs, TargetFrame.debuffs, TargetFrame.AuraContainer = {}, {}, false
GameTooltip = CreateFrame("Frame")
local create, commFrame = CreateFrame
CreateFrame = function(...) local f = create(...); commFrame = f; return f end
strsplit = function(delimiter, text)
    local fields = {}; for field in (text .. delimiter):gmatch("(.-)" .. delimiter) do fields[#fields+1] = field end
    return unpack(fields)
end
local sent
C_ChatInfo = { SendAddonMessage = function(_,msg) sent = msg end }
dofile(root .. "/RustcoreSelfFoundComm.lua")
CreateFrame = create
C_Timer.After = function() end
commFrame.scripts.OnEvent(commFrame, "PLAYER_LOGIN")
RustcoreSelfFoundComm.RefreshOverlays = function() end
local function response(payload, sender)
    commFrame.scripts.OnEvent(commFrame,"CHAT_MSG_ADDON","RCSF",payload,"WHISPER",sender or "Peer")
    RustcoreSelfFoundBuff.RefreshTarget()
end
response("R~Peer~1~3~1")
assert(RustcoreSelfFoundComm.IsKnownRustbound("Peer"))
assert(RustcoreSelfFoundTargetIcon:IsShown() and RustcoreRustboundTargetIcon:IsShown(), "both prestige icons appear")
response("R~Peer~0~3~1")
assert(not RustcoreSelfFoundTargetIcon:IsShown() and RustcoreRustboundTargetIcon:IsShown(), "Rustbound works without Self-Found")
response("R~Peer~0~3~0")
assert(not RustcoreRustboundTargetIcon:IsShown(), "lost prestige clears target icon")
response("R~Peer~0~3~1", "Other")
assert(not RustcoreSelfFoundComm.IsKnownRustbound("Peer"), "sender mismatch cannot claim prestige")
response("R~Peer~0~3~1")
response("R~Peer~1~3")
assert(not RustcoreRustboundTargetIcon:IsShown(), "older responses clear missing prestige")
response("R~Peer~0~3~1")
now = 121; RustcoreSelfFoundBuff.RefreshTarget()
assert(not RustcoreRustboundTargetIcon:IsShown(), "expired status disappears")
ownTarget = true; RustcoreSelfFoundBuff.RefreshTarget()
assert(RustcoreRustboundTargetIcon:IsShown(), "self target uses live prestige")
enabled = false; RustcoreSelfFoundBuff.RefreshTarget()
assert(not RustcoreRustboundTargetIcon:IsShown(), "target verification setting hides prestige")
commFrame.scripts.OnEvent(commFrame,"CHAT_MSG_ADDON","RCSF","Q~Local","WHISPER","Peer")
assert(sent:sub(-2) == "~1", "live prestige is shared")
debugMode = true
commFrame.scripts.OnEvent(commFrame,"CHAT_MSG_ADDON","RCSF","Q~Local","WHISPER","Peer")
assert(sent:sub(-2) == "~0", "test prestige is not shared")
print("Rustbound target: peer status, layout visibility, expiry, legacy peers and debug isolation passed (" .. root .. ")")
