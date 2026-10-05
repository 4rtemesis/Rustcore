-- Exercises each build's real player-buff layout without target-frame behavior.
local root = (arg and arg[1]) or "dist/forever/Rustcore"
local assertions, frames, combat, state = 0, {}, false, "off"
local function check(value, message) assert(value, message); assertions = assertions + 1 end
local function region(name)
    local obj = { name = name, shown = true, points = {}, scripts = {}, scale = 1, width = 240 }
    setmetatable(obj, { __index = function(_, key)
        if key:match("^%u") then return function() end end
    end })
    function obj:SetPoint(...) self.points[#self.points + 1] = {...} end
    function obj:ClearAllPoints() self.points = {} end
    function obj:GetPoint(index) return unpack(self.points[index or 1]) end
    function obj:GetNumPoints() return #self.points end
    function obj:SetScale(value) self.scale = value end
    function obj:GetEffectiveScale() return self.scale end
    function obj:GetRight() return self.right end
    function obj:GetWidth() return self.width end
    function obj:SetSize(width,height) self.width, self.height = width,height end
    function obj:Show() self.shown = true end
    function obj:Hide() self.shown = false end
    function obj:IsShown() return self.shown end
    function obj:SetScript(event,fn) self.scripts[event] = fn end
    function obj:CreateTexture() return region() end
    function obj:CreateFontString() return region() end
    function obj:SetNormalTexture() self.normal = region() end
    function obj:GetNormalTexture() return self.normal end
    return obj
end
CreateFrame = function(_,name)
    local obj = region(name); frames[#frames + 1] = obj
    if name then _G[name] = obj end
    return obj
end
UIParent, BuffFrame, BuffButton1 = region(), region(), region()
BuffFrame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-200,-20)
BuffFrame.AuraContainer = region()
BuffButton1.right = 1000
BuffFrame.auraFrames = {BuffButton1}
GetTime = function() return 0 end
InCombatLockdown = function() return combat end
C_Timer = { After = function(_,fn) fn() end }
Rustcore = {
    GetAssetPath = function(path) return path end,
    GetSelfFoundIconState = function() return state end,
    GetSelfFoundIconTexture = function() return "self-found" end,
    GetSetting = function() return true end,
}
local nativeHidden = false
RustcoreCompat = {
    HideNativeBuffFrame = function() nativeHidden = true end,
    ShowNativeBuffFrame = function() nativeHidden = false end,
    GetAura = function(_,index) if index == 1 then return "Native buff", "native-icon", 0, nil, 0, 0 end end,
    GetWeaponEnchantInfo = function() return false,0,0,0,false,0,0 end,
}
dofile(root .. "/RustcoreSelfFoundBuff.lua")
local S = RustcoreSelfFoundBuff
local rustbound = region("Rustbound"); rustbound:SetNormalTexture(); rustbound:Hide()
S.SetRustboundIcon(rustbound); S.Refresh()
local selfFound = RustcoreSelfFoundBuffIcon
check(selfFound and not selfFound:IsShown(), "Self-Found remains hidden when inactive")
state = "verified"; S.Refresh()
check(selfFound:IsShown(), "Self-Found can display alone")
rustbound:Show(); S.RefreshPlayerLayout()
local file = assert(io.open(root .. "/RustcoreSelfFoundBuff.lua","rb"))
local source = file:read("*a"); file:close()
if source:find("local function ReserveBuffSlots",1,true) then
    check(BuffFrame.points[1][4] == -270, "two prestige buffs reserve exactly two native slots")
    check(rustbound.points[1][2] == BuffButton1 and selfFound.points[1][2] == rustbound,
        "Self-Found and Rustbound precede the native buffs in one chain")
    for _ = 1,20 do S.RefreshPlayerLayout() end
    check(BuffFrame.points[1][4] == -270, "repeated layout refreshes cannot accumulate offset")
    state = "off"; S.Refresh()
    check(not selfFound:IsShown() and BuffFrame.points[1][4] == -235 and rustbound.points[1][2] == BuffButton1,
        "Rustbound alone keeps one slot and follows the native bar")
    rustbound:Hide(); S.RefreshPlayerLayout()
    check(BuffFrame.points[1][4] == -200, "removing both icons restores the original anchor")
    state = "verified"; S.Refresh(); combat = true
    rustbound:Show(); S.RefreshPlayerLayout()
    check(BuffFrame.points[1][4] == -235, "new buff cannot move protected native anchor during combat")
    combat = false; S.RefreshPlayerLayout()
    check(BuffFrame.points[1][4] == -270, "reservation catches up after combat")
    BuffFrame:ClearAllPoints(); BuffFrame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-320,-80)
    S.RefreshPlayerLayout(); state = "off"; rustbound:Hide(); S.Refresh()
    check(BuffFrame.points[1][4] == -320 and BuffFrame.points[1][5] == -80,
        "Edit Mode's new baseline survives disabling the custom buffs")
    BuffFrame.auraFrames = {}; BuffButton1 = nil
    rustbound:Show(); S.RefreshPlayerLayout()
    check(rustbound.points[1][2] == BuffFrame.AuraContainer, "empty native bar uses its aura container")
else
    local native
    for _, f in ipairs(frames) do if f.auraIndex == 1 then native = f end end
    check(nativeHidden and native, "legacy layout retains its existing native-aura presentation")
    check(selfFound.points[1][4] == -15 and rustbound.points[1][4] == -50 and native.points[1][4] == -85,
        "legacy order is Self-Found, Rustbound, then native buffs")
    state = "off"; S.Refresh()
    check(not selfFound:IsShown() and rustbound.points[1][4] == -15 and native.points[1][4] == -50,
        "legacy Rustbound-only layout reclaims Self-Found's slot")
    rustbound:Hide(); S.RefreshPlayerLayout()
    check(not nativeHidden and not native:IsShown(), "legacy layout restores native buffs after both prestige icons disappear")
end
print("Reforge buff layout: " .. assertions .. " assertions passed (" .. root .. ")")
