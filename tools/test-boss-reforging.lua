-- Lua 5.1: lua tools/test-boss-reforging.lua [addon directory]
local root = (arg and arg[1]) or "dist/forever/Rustcore"
local tests = 0
local function check(value, message) assert(value, message); tests = tests + 1 end
local clock, level, gold, merchant, mode = 0, 14, 10000, true, "success"
local record = { difficulty = { status = "VERIFIED", repairViolations = 0 } }
local settings = { allowRepair = false, reforgeThreshold = 50 }
local inventory, bank, actions, violations = {}, {}, 0, 0
GetTime = function() return clock end
GetMoney = function() return gold end
Rustcore = { GetSetting = function(key) return settings[key] end }
RustcoreVerification = {
    GetRecord = function() return record end,
    GetTrack = function() return record.difficulty end,
    GetPlayerLevel = function() return level end,
    IsCertified = function(status) return status == "VERIFIED" end,
    Integrity = { Seal = function() end },
    Durability = { NoteRepairAction = function() end },
    Difficulty = { OnRepairPerformed = function() violations = violations + 1 end },
}
local function copy(item)
    local result = {}; for key, value in pairs(item) do result[key] = value end; return result
end
RustcoreReforgeAPI = {
    Scan = function()
        local result = {}; for _, item in ipairs(inventory) do result[#result + 1] = copy(item) end; return result
    end,
    AtMerchant = function() return merchant end,
    Cost = function(item) return item.cost end,
    Repair = function(item)
        actions = actions + 1
        if mode == "fail" then return false end
        if mode == "defer" then return true end
        for _, actual in ipairs(inventory) do
            if actual.guid == item.guid then actual.cur = actual.max; gold = gold - actual.cost end
        end
        return true
    end,
}
local function item(guid, durability, bag)
    return { guid = guid, id = 18816, cur = durability, max = 100, bag = bag, slot = 16, cost = 125 }
end
dofile(root .. "/Reforge/Sources.lua")
dofile(root .. "/Reforge/Core.lua")
local R = RustcoreReforge
inventory = { item("A", 49), item("B", 50, 0), item("C", 51, 1) }
bank = { item("BANK", 10, -1) }
check(not R.CheckRustbound(), "level 14 production must not earn Rustbound")
check(R.AwardBoss(672) == 0, "level 14 production must not earn Shards")
level = 60
check(R.CheckRustbound() and R.HasRustbound(), "verified unlock earns Rustbound")
check(R.AwardBoss(672) == 3, "all three carried copies earn independent Shards")
check(not R.State().items.BANK, "bank excluded")
check(R.AwardBoss(672) == 0 and R.HasRustbound(), "no stacking and award preserves Rustbound")
inventory[1].bag, inventory[1].slot = 3, 2
check(R.HasShard(inventory[1]), "moving a physical item preserves its Shard")
local plan = R.Plan()
check(#plan.items == 2 and plan.skipped == 1 and plan.cost == 250, "inclusive 50 percent threshold")
local before = gold
inventory[1].cur = 48
check(not R.Execute(plan) and gold == before, "changed confirmation cannot spend")
inventory[1].cur = 49
check(R.Execute(R.Plan()), "bulk succeeds")
check(gold == before - 250 and not R.HasShard(inventory[1]) and not R.HasShard(inventory[2]), "only successful items spend gold and Shards")
check(R.HasShard(inventory[3]) and inventory[3].cur == 51, "above threshold remains untouched")
check(not R.HasRustbound() and R.State().rustboundLost and R.State().everRepaired, "first success permanently loses prestige")
check(not R.CheckRustbound(), "cannot re-earn prestige")
inventory[3].cur = 95
check(R.Repair("C") and inventory[3].cur == 100, "manual ignores threshold")
check(record.difficulty.status == "VERIFIED" and violations == 0, "legitimate reforges preserve verification")
check(not R.Repair("C"), "no second repair without Shard")
R.AwardBoss(672); inventory[1].cur = 30; mode = "fail"
check(not R.Repair("A") and R.HasShard(inventory[1]), "API failure retains Shard")
mode = "defer"
check(R.Repair("A") and R.HasShard(inventory[1]), "do not consume before success")
check(not R.Repair("A"), "pending repair cannot be submitted twice")
clock = 9; R.Observe()
check(R.HasShard(inventory[1]), "timeout retains Shard")
mode = "success"; gold = 0
check(not R.Repair("A"), "insufficient funds blocked")
gold = 10000; merchant = false
check(not R.Repair("A"), "merchant required")
merchant = true; inventory[1].cost = nil
check(not R.Repair("A") and R.Plan().error, "unknown cost fails closed")
inventory[1].cost = 125
inventory[1].bag = nil
mode = "defer"
check(R.Repair("A"), "start equipped deferred repair")
local was = { guid = "A", id = 18816, cur = 30, max = 100 }
local now = { guid = "A", id = 18816, cur = 100, max = 100 }
check(R.AcceptVerifiedRepair(was, now), "verification may observe success first")
check(not R.AcceptVerifiedRepair(was, now), "verification receipt is single use")
check(not R.AcceptVerifiedRepair(was, { guid = "OTHER", id = 18816, cur = 100, max = 100 }), "same item ID never grants exemption to another copy")
inventory[1].cur = 100
R.Observe()
R.AwardBoss(672); inventory[1].cur = 20
check(R.Repair("A"), "start persistent request")
inventory[1].cur = 100
dofile(root .. "/Reforge/Core.lua"); R = RustcoreReforge
R.LoadPending(); R.Observe()
check(not R.HasShard(inventory[1]), "reload reconciles saved pending success")
level = 14
check(R.DebugMode(true), "enable developer mode")
R.DebugLevel(14)
check(R.CheckRustbound() and R.HasRustbound(), "debug runs actual eligibility")
inventory[1].id = 999; inventory[1].cur = 40
R.DebugSource(inventory[1], 672)
check(R.AwardBoss(672) > 0 and R.HasShard(inventory[1]), "test mapping uses real award")
mode = "success"
check(R.Repair("A") and not R.HasRustbound(), "debug uses real repair and prestige lifecycle")
check(record.reforge.everRepaired and record.reforge.rustboundLost, "real test repair cannot preserve production prestige")
check(R.DebugRestoreRustbound() and R.HasRustbound(), "restore re-earns test Rustbound after a successful real Reforge")
check(R.Source(inventory[1]) == 672 and not R.HasShard(inventory[1]), "restore preserves test source and spent Shard state")
check(record.reforge.everRepaired and record.reforge.rustboundLost, "test restore cannot rewrite production repair history")
check(R.DebugMode(false) and R.UnlockLevel() == 60 and not R.Unlocked(), "disable restores production level and data")
check(R.Source(inventory[1]) == nil, "debug source never leaks into production")
check(not R.DebugRestoreRustbound(), "production Rustbound cannot be restored by developer reset")
settings.allowRepair = true; level = 60
check(not R.Unlocked(), "unrestricted repair option excludes verified reforging")
settings.allowRepair = false; record.difficulty.status = "FAILED"
check(not R.Unlocked(), "failed verification blocks feature")

-- A reload during an asynchronous real developer repair must still remember it.
record.difficulty.status = "VERIFIED"; record.reforge = nil; level = 14
R.DebugMode(true); R.DebugLevel(14); R.DebugSource(inventory[1],672)
inventory[1].cur = 25; mode = "defer"; R.AwardBoss(672)
check(R.Repair("A"), "deferred developer repair starts")
check(record.reforge.pending.A.test, "developer request persists only real transaction evidence")
check(not R.DebugRestoreRustbound(), "restore waits for in-flight repairs instead of erasing their history")
inventory[1].cur = 100
dofile(root .. "/Reforge/Core.lua"); R = RustcoreReforge
R.LoadPending(); R.Observe()
check(record.reforge.everRepaired and record.reforge.rustboundLost and not R.IsDebug(), "reload confirms developer repair without retaining test mode")
level = 60

-- Exercise the actual verification comparison, including an unrelated repair
-- in the same scan as an authorized Boss Reforge.
record.difficulty.status = "VERIFIED"
inventory[1].id = 18816; inventory[1].cur = 20; inventory[1].bag = nil
R.AwardBoss(672); mode = "defer"
check(R.Repair("A"), "start receipt integration test")
dofile(root .. "/Verification/Durability.lua")
local findings = RustcoreVerification.Durability.Compare(
    { [16] = { guid = "A", id = 18816, cur = 20, max = 100 }, [1] = { guid = "H", id = 5, cur = 10, max = 100 } },
    { [16] = { guid = "A", id = 18816, cur = 100, max = 100 }, [1] = { guid = "H", id = 5, cur = 100, max = 100 } })
check(#findings.slots == 1 and findings.slots[1] == 1, "only authorized GUID is exempt from verification")

-- Actual adapter: physical GUID scans, normal repair dispatch, and safe refusal.
local slots = { [16] = item("EQ", 30) }
local bags = { [0] = { item("BAG", 40, 0) } }
local repairCursor, locked = false, false
ItemLocation = {
    CreateFromEquipmentSlot = function(_, slot) return { slot = slot, IsValid = function() return slots[slot] ~= nil end } end,
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot, IsValid = function() return bags[bag] and bags[bag][slot] ~= nil end } end,
}
local function location(loc) return loc.bag == nil and slots[loc.slot] or bags[loc.bag][loc.slot] end
C_Item = { GetItemGUID = function(loc) return location(loc).guid end, GetItemID = function(loc) return location(loc).id end }
C_Container = {
    GetContainerNumSlots = function(bag) assert(bag >= 0 and bag <= 4, "bank queried"); return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemDurability = function(bag, slot) local i = bags[bag][slot]; return i.cur, i.max end,
    PickupContainerItem = function(bag, slot) assert(repairCursor); bags[bag][slot].cur = 100 end,
}
GetInventoryItemDurability = function(slot) return slots[slot].cur, slots[slot].max end
PickupInventoryItem = function(slot) assert(repairCursor); slots[slot].cur = 100 end
ShowRepairCursor = function() repairCursor = true end
HideRepairCursor = function() repairCursor = false end
InRepairMode = function() return repairCursor end
InCombatLockdown = function() return locked end
GetCursorInfo = function() return nil end
MerchantFrame = { IsShown = function() return true end }
CanMerchantRepair = function() return true end
dofile(root .. "/Reforge/API.lua")
local A = RustcoreReforgeAPI
check(#A.Scan() == 2, "adapter scans carried equipment and bags")
check(A.Repair(A.Read(nil, 16)) and slots[16].cur == 100 and not repairCursor, "native equipment repair closes cursor")
check(A.Repair(A.Read(0, 1)) and bags[0][1].cur == 100 and not repairCursor, "native bag repair closes cursor")
-- Modern cost field is taken verbatim; unavailable/secret data fails closed.
C_TooltipInfo = { GetInventoryItem = function() return { repairCost = 321 } end,
    GetBagItem = function() return { repairCost = 654 } end }
check(A.Cost(A.Read(nil,16)) == 321 and A.Cost(A.Read(0,1)) == 654, "modern normal repair costs")
C_TooltipInfo.GetInventoryItem = function() return {} end
CreateFrame = function() error("tooltip fallback unavailable") end
check(A.Cost(A.Read(nil,16)) == nil, "unavailable cost is not estimated")
local secretGuid = slots[16].guid
issecretvalue = function(value) return value == secretGuid end
check(A.Read(nil,16) == nil, "secret GUID cannot become a state key")
issecretvalue = nil
locked = true
check(not A.Repair(A.Read(nil, 16)), "combat action rejected")
locked = false; C_Item.GetItemGUID = nil
check(#A.Scan() == 0, "no GUID means no item-ID fallback")
print("Boss Reforging: " .. tests .. " assertions passed")
