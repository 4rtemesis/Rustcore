local root = (arg and arg[1]) or "dist/forever/Rustcore"
local frames, postCall, popup, repaired = {}, nil, nil, nil
local skinCount, buttonSkinCount, timers, canRepair = 0, 0, {}, true
local function frame(name)
    local f = { scripts = {}, shown = true, lines = {}, name = name }
    setmetatable(f, { __index = function(_, key)
        if key:match("^%u") then return function() end end
    end })
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:SetShown(value) self.shown = value end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetText(text) self.text = text end
    function f:GetFrameLevel() return 1 end
    function f:GetFontString() self.fontString = self.fontString or frame(); return self.fontString end
    function f:SetAllPoints(target) self.allPoints = target end
    function f:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = {...} end
    function f:AddLine(text) self.lines[#self.lines + 1] = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    function f:CreateTexture() return frame() end
    function f:CreateFontString() return frame() end
    function f:SetEnabled(value) self.enabled = value end
    return f
end
CreateFrame = function(_, name, parent)
    local f = frame(name); f.parent = parent; frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
UIParent = frame()
GameTooltip = frame()
StaticPopupDialogs = {}
StaticPopup_Show = function(key, text, _, data) popup = { key = key, text = text, data = data } end
StaticPopup_Hide = function() popup = nil end
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
Enum = { TooltipDataType = { Item = 1 } }
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function FlushTimers()
    local queued = timers; timers = {}
    for _, fn in ipairs(queued) do fn() end
end
RustcoreTheme = {
    ApplyFrameSkin = function() skinCount = skinCount + 1 end,
    SkinButton = function() buttonSkinCount = buttonSkinCount + 1 end,
    SetDifficultyBackground = function() end,
}
C_Item = { GetItemNameByID = function() return "Test sword" end, GetItemInfoInstant = function() return nil,nil,nil,"INVTYPE_WEAPON" end }
GetTime = function() return 0 end
GetMoney = function() return 10000 end
local record = { difficulty = { status = "VERIFIED" } }
local glowEnabled = true
Rustcore = { GetAssetPath = function(path) return path end, GetSetting = function(key)
    if key == "reforgeGlow" then return glowEnabled end
    return key == "reforgeThreshold" and 50 or false
end }
RustcoreVerification = { GetRecord = function() return record end, GetTrack = function() return record.difficulty end,
    GetPlayerLevel = function() return 60 end, IsCertified = function() return true end }
local a = { id = 18816, guid = "A", slot = 16, cur = 49, max = 100 }
local b = { id = 18816, guid = "B", bag = 0, slot = 1, cur = 95, max = 100 }
RustcoreReforgeAPI = { Scan = function() return {a,b} end, Read = function(bag) return bag == nil and a or b end,
    AtMerchant = function() return MerchantFrame and MerchantFrame:IsShown() and canRepair end,
    Public = function() return true end, Cost = function() return 100 end }
dofile(root .. "/Reforge/Sources.lua")
dofile(root .. "/Reforge/Core.lua")
local R = RustcoreReforge
dofile(root .. "/Reforge/UI.lua")
local events = frames[1]
events.scripts.OnEvent(events, "PLAYER_LOGIN")
assert(RustcoreRustboundBuff:IsShown(), "Rustbound appears after real eligibility check")
-- MerchantFrame can be load-on-demand; initialization must be retryable.
MerchantFrame = frame(); MerchantFrame:Hide()
events.scripts.OnEvent(events, "MERCHANT_SHOW")
assert(not RustcoreReforgeMerchant, "merchant event can precede the native window showing")
MerchantFrame:Show(); FlushTimers()
assert(RustcoreReforgeMerchant:IsShown(), "deferred merchant refresh opens panel automatically")
assert(skinCount == 1 and buttonSkinCount == 7, "panel and repair buttons use the options theme")
canRepair = false; events.scripts.OnEvent(events, "MERCHANT_UPDATE")
assert(not RustcoreReforgeMerchant:IsShown(), "non-repair shop cannot open reforge panel")
canRepair = true; events.scripts.OnEvent(events, "MERCHANT_UPDATE")
assert(RustcoreReforgeMerchant:IsShown(), "repair-capable merchant update restores panel")
events.scripts.OnEvent(events, "BOSS_KILL", 672)
assert(R.HasShard(a) and R.HasShard(b), "actual event invokes central award")
GameTooltip.lines = {}; postCall(GameTooltip, { id = a.id, guid = a.guid })
assert(#GameTooltip.lines == 2 and GameTooltip.lines[2] == "Reforge Shard: Ready", "charged tooltip has exactly two lines")
R.State().items.B.charged = false
GameTooltip.lines = {}; postCall(GameTooltip, { id = b.id, guid = b.guid })
assert(not table.concat(GameTooltip.lines, " "):find("Reforge Shard: Ready",1,true), "duplicate ID tooltip uses exact GUID")
GameTooltip.lines = {}; postCall(GameTooltip, { id = a.id })
assert(not table.concat(GameTooltip.lines, " "):find("Reforge Shard: Ready",1,true), "hyperlink cannot borrow Shard")
assert(#GameTooltip.lines == 2 and GameTooltip.lines[2] == "Reforge Shard: Missing", "unknown physical item has no Shard")
local originalLevel = RustcoreVerification.GetPlayerLevel
RustcoreVerification.GetPlayerLevel = function() return 59 end
GameTooltip.lines = {}; postCall(GameTooltip, { id = a.id, guid = a.guid })
assert(#GameTooltip.lines == 0, "locked reforging adds no tooltip lines")
RustcoreVerification.GetPlayerLevel = originalLevel
local hud = frame(); hud.iconTex = frame()
assert(R.UpdateHUDIndicator(hud,16) and hud.reforgeReady == nil, "charged counter no longer adds an anvil icon")
assert(hud.reforgeGlow.points[1][2] == hud.iconTex and hud.reforgeGlow.points[2][2] == hud.iconTex,
    "expanded glow remains anchored to the item icon, not the full counter")
assert(hud.reforgeGlow:IsShown(), "charged counter glows by default")
glowEnabled = false; R.UpdateHUDIndicator(hud,16)
assert(not hud.reforgeGlow:IsShown() and R.HasShard(a), "disabling glow preserves the Shard")
glowEnabled = true; R.State().items.A.charged = false; R.UpdateHUDIndicator(hud,16)
assert(not hud.reforgeGlow:IsShown(), "spending a Shard removes the glow")
R.AwardBoss(672); R.Refresh()
local all, manual
for _, f in ipairs(frames) do
    if f.text == "Reforge All" then all = f end
    if f.text == "Reforge" and f.parent.item == b then manual = f end
end
assert(all and manual)
local calls = 0
R.Execute = function(plan) calls = calls + 1; assert(#plan.items == 1 and plan.items[1].guid == "A"); return true end
all.scripts.OnClick()
assert(calls == 0 and popup.text:find("1 Reforge Shards",1,true), "confirmation precedes spending")
assert(popup.text:find("1 additional items",1,true), "confirmation explains threshold skip")
StaticPopupDialogs[popup.key].OnAccept(nil,popup.data)
assert(calls == 1, "confirmation executes snapshot")
R.Repair = function(guid) repaired = guid; return true end
manual.scripts.OnClick()
assert(repaired == "B", "manual button permits above-threshold item")
events.scripts.OnEvent(events,"MERCHANT_CLOSED")
assert(popup == nil and not RustcoreReforgeMerchant:IsShown(), "closing vendor cancels confirmation and immediately hides panel")
events.scripts.OnEvent(events, "MERCHANT_SHOW")
events.scripts.OnEvent(events, "MERCHANT_CLOSED")
FlushTimers()
assert(not RustcoreReforgeMerchant:IsShown(), "deferred opening cannot reopen a closed merchant")
events.scripts.OnEvent(events, "MERCHANT_SHOW"); FlushTimers()
assert(RustcoreReforgeMerchant:IsShown(), "subsequent merchant visits open automatically")
print("Boss Reforging UI: event routing, lazy load, GUID tooltips, HUD, confirmation and manual actions passed")
