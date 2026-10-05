-- Regression coverage for the level-14 beta report, Reforge tab and HUD tooltip.
local root = (arg and arg[1]) or "dist/forever/Rustcore"
local count = 0
local function check(value, message) assert(value, message); count = count + 1 end
local output, level, settings = {}, 14, { allowRepair = false, reforgeThreshold = 50, reforgeGlow = true }
local originalPrint = print
print = function(message) output[#output + 1] = tostring(message) end
GetTime = function() return 0 end
local record = { difficulty = { status = "UNCERTAIN", repairViolations = 0 } }
local item = { id = 999, guid = "test-item", slot = 16, cur = 40, max = 100 }
Rustcore = { GetSetting = function(key) return settings[key] end }
RustcoreVerification = {
    GetRecord = function() return record end,
    GetTrack = function() return record.difficulty end,
    GetPlayerLevel = function() return level end,
    IsCertified = function(status) return status == "VERIFIED" end,
    Integrity = { Seal = function() end },
}
RustcoreReforgeAPI = {
    Scan = function() return {item} end,
    Read = function(bag, slot) if bag == nil and slot == 16 then return item end end,
}
SlashCmdList = {}
dofile(root .. "/Reforge/Sources.lua")
dofile(root .. "/Reforge/Core.lua")
local R = RustcoreReforge
R.Refresh = function() end
dofile(root .. "/Reforge/Debug.lua")
local command = SlashCmdList.RUSTCOREREFORGE
command("dev on")
check(not R.HasRustbound(), "developer mode alone must not lower unlock level")
command("level 14")
check(R.HasRustbound(), "level override immediately grants test Rustbound with missing live playtime")
check(record.difficulty.status == "UNCERTAIN" and not R.LiveVerified(), "test eligibility cannot certify the real character")
command("source equip 16 672")
command("boss 672")
check(R.HasShard(item), "reported developer command sequence awards the physical item's Shard")
command("rustbound restore")
check(R.HasRustbound() and R.HasShard(item) and R.Source(item) == 672, "restore command preserves the test source and earned Shard")
command("status")
local joined = table.concat(output,"\n")
check(joined:find("test eligibility=true",1,true) and joined:find("live verified=false",1,true), "status distinguishes test eligibility from live verification")
local awarded, reason = R.AwardBoss(672)
check(awarded == 0 and reason:find("already have",1,true), "saturated award explains zero new Shards")
R.DebugRemoveShard(item)
awarded, reason = R.AwardBoss(nil)
check(awarded == 0 and reason == "Unknown encounter ID." and not R.HasShard(item), "missing boss ID cannot award unsupported items")
awarded, reason = R.AwardBoss(9999)
check(awarded == 0 and reason:find("No readable carried items",1,true), "unmatched source is diagnosed")
settings.allowRepair = true
command("boss 672")
check(not R.HasShard(item) and output[#output]:find("Turn off Allow Item Repair",1,true), "developer test still requires repair blocking")
settings.allowRepair = false
command("level production")
check(not R.HasRustbound() and not R.AtUnlockLevel(), "restoring production level hides test prestige below unlock")
command("dev off")
check(not R.Unlocked() and not R.HasShard(item) and R.Source(item) == nil, "test state and source cannot leak into production")
level = 60
check(not R.Unlocked() and not R.CheckRustbound(), "real missing-playtime verification still blocks production at 60")
record.difficulty.status = "VERIFIED"
check(R.CheckRustbound(), "production still grants prestige through real certification")

local function read(name)
    local file = assert(io.open(root .. "/" .. name,"rb"))
    local text = file:read("*a"):gsub("\r\n","\n"); file:close(); return text
end
local objects = {}
local function object(parent)
    local value = { parent = parent, shown = true, scripts = {} }
    function value:SetShown(shown) self.shown = shown end
    function value:IsShown() return self.shown end
    function value:SetText(text) self.text = text end
    function value:SetPoint() end
    function value:SetWidth() end
    function value:SetJustifyH() end
    function value:SetAllPoints() end
    function value:SetScript(event, fn) self.scripts[event] = fn end
    function value:CreateFontString() return object(self) end
    objects[#objects + 1] = value
    return value
end
CreateFrame = function(_, _, parent) return object(parent) end
local page, options = object(), {}
local function slider(parent) return object(parent) end
local function checkbox(parent)
    local cb = object(parent)
    function cb:Refresh() self.checked = settings.reforgeGlow end
    return cb
end
local source = read("RustcoreOptions.lua")
local start = assert(source:find("    -- The locked page contains only the explanation;",1,true))
local finish = assert(source:find("    -- About",start,true))
local build = assert(loadstring("local reforgePage,f,MakeHeader,MakeSettingSlider,MakeCheckbox,ApplyBodyFont=...\n" .. source:sub(start,finish-1)))
level = 14
build(page, options, function() end, slider, checkbox, function() end)
local explanation
for _, value in ipairs(objects) do if value.text and value.text:find("unlocked at max level",1,true) then explanation = value end end
check(explanation and explanation:IsShown() and not options.reforgeSlider.parent:IsShown(), "pre-60 Reforge page contains explanation without controls")
R.Refresh = function() options.refreshReforgePage() end
command("dev on"); command("level 14")
check(not explanation:IsShown() and options.reforgeSlider.parent:IsShown(), "test unlock updates already-open Reforge page")
check(options.cbReforgeGlow.parent == options.reforgeSlider.parent and options.cbReforgeGlow.checked, "glow toggle shares the unlocked controls group")
command("dev off")
check(explanation:IsShown() and not options.reforgeSlider.parent:IsShown(), "disabling developer mode immediately relocks page")
level = 60; page.scripts.OnShow()
check(options.reforgeSlider.parent:IsShown() and not explanation:IsShown(), "production level unlock reveals controls on opening tab")

-- Run the actual tooltip helper, checking flags when the item is populated,
-- including an already-open shopping comparison and repeated counter hovers.
local hooks, hookCount, populated = {}, 0, false
local shop1, shop2 = {shown=true}, {shown=true}
function shop1:Hide() self.shown = false end
function shop2:Hide() self.shown = false end
GameTooltip = { supportsItemComparison = true, suppressAutomaticCompareItem = false,
    shoppingTooltips = {shop1,shop2} }
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:HookScript(event, fn) hooks[event] = fn; hookCount = hookCount + 1 end
function GameTooltip:SetInventoryItem(unit,slot)
    populated = unit == "player" and slot == 16 and not self.supportsItemComparison and self.suppressAutomaticCompareItem
end
function GameTooltip:Show() end
function GameTooltip:Hide() if hooks.OnHide then hooks.OnHide(self) end end
local clears = 0
TooltipComparisonManager = { Clear = function(_,tip) assert(tip == GameTooltip); clears = clears + 1 end }
RustcoreDurability = {}
source = read("RustcoreDurability.lua")
start = assert(source:find("local function RestoreCounterTooltipComparison",1,true))
finish = assert(source:find("local function BuildSlotFrame",start,true))
assert(loadstring(source:sub(start,finish-1)))()
RustcoreDurability.ShowItemTooltip({slotId=16})
check(populated and not shop1.shown and not shop2.shown and clears == 1, "counter hover suppresses comparison before populating tooltip and clears old shopping tooltips")
GameTooltip:Hide()
check(GameTooltip.supportsItemComparison and not GameTooltip.suppressAutomaticCompareItem, "leaving counter restores normal item comparisons")
GameTooltip.supportsItemComparison, GameTooltip.suppressAutomaticCompareItem = nil, true
RustcoreDurability.ShowItemTooltip({slotId=16}); GameTooltip:Hide()
check(GameTooltip.supportsItemComparison == nil and GameTooltip.suppressAutomaticCompareItem == true and hookCount == 1, "restore preserves original nil/true flags without accumulating hooks")
print = originalPrint
print("Reforge follow-up: " .. count .. " assertions passed")
