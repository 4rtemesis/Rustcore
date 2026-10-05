-- Loaded before Rustcore.lua wraps repair functions. Native calls stay private.
-- Forever source audit and remaining in-client checks: docs/BOSS-REFORGING.md.
RustcoreReforgeAPI = {}
local A = RustcoreReforgeAPI
local showRepair, hideRepair = ShowRepairCursor, HideRepairCursor
local pickupEquipment = PickupInventoryItem
local pickupBag = C_Container and C_Container.PickupContainerItem
local costTip

function A.Public(value)
    return not (issecretvalue and issecretvalue(value))
end

function A.Read(bag, slot)
    local ok, item = pcall(function()
        if not (C_Item and C_Item.GetItemGUID and ItemLocation) then return end
        local loc = bag == nil and ItemLocation:CreateFromEquipmentSlot(slot)
            or ItemLocation:CreateFromBagAndSlot(bag, slot)
        if not loc:IsValid() then return end
        local guid = C_Item.GetItemGUID(loc)
        local id = C_Item.GetItemID(loc)
        if not A.Public(guid) or not A.Public(id) or type(guid) ~= "string" or guid == "" then return end
        local cur, max
        if bag == nil then cur, max = GetInventoryItemDurability(slot)
        else cur, max = C_Container.GetContainerItemDurability(bag, slot) end
        if not A.Public(cur) or not A.Public(max) or not cur or not max or max <= 0 then return end
        return { guid = guid, id = id, bag = bag, slot = slot, cur = cur, max = max }
    end)
    return ok and item or nil
end

function A.Scan()
    local items, seen = {}, {}
    local function add(bag, slot)
        local item = A.Read(bag, slot)
        if item and not seen[item.guid] then
            seen[item.guid] = true
            items[#items + 1] = item
        end
    end
    for slot = 1, 19 do add(nil, slot) end
    -- Only backpack and normal carried bags. Never query bank containers.
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local ok, count = pcall(C_Container.GetContainerNumSlots, bag)
            if ok and A.Public(count) and type(count) == "number" then
                for slot = 1, count do add(bag, slot) end
            end
        end
    end
    return items
end

function A.AtMerchant()
    return MerchantFrame and MerchantFrame:IsShown() and CanMerchantRepair and CanMerchantRepair()
end

function A.Cost(item)
    if not A.AtMerchant() then return nil end
    local ok, cost = pcall(function()
        if C_TooltipInfo then
            local data
            if item.bag == nil and C_TooltipInfo.GetInventoryItem then
                data = C_TooltipInfo.GetInventoryItem("player", item.slot)
            elseif item.bag ~= nil and C_TooltipInfo.GetBagItem then
                data = C_TooltipInfo.GetBagItem(item.bag, item.slot)
            end
            local value = data and data.repairCost
            if A.Public(value) and type(value) == "number" and value >= 0 then return value end
        end
        costTip = costTip or CreateFrame("GameTooltip", "RustcoreReforgeCostTooltip", UIParent, "GameTooltipTemplate")
        costTip:SetOwner(UIParent, "ANCHOR_NONE")
        costTip:ClearLines()
        local amount
        if item.bag == nil then
            local _, _, value = costTip:SetInventoryItem("player", item.slot)
            amount = value
        else
            local _, value = costTip:SetBagItem(item.bag, item.slot)
            amount = value
        end
        -- Some modern tooltip implementations return a data object instead.
        if amount == nil and costTip.GetPrimaryTooltipData then
            local data = costTip:GetPrimaryTooltipData()
            amount = data and data.repairCost
        end
        costTip:Hide()
        if A.Public(amount) and type(amount) == "number" and amount >= 0 then return amount end
    end)
    return ok and cost or nil -- Unknown cost must never be guessed.
end

function A.Repair(item)
    if not A.AtMerchant() or (InCombatLockdown and InCombatLockdown()) then return false end
    if not (showRepair and hideRepair and InRepairMode) then return false end
    if GetCursorInfo and GetCursorInfo() then return false end
    local pickup = item.bag == nil and pickupEquipment or pickupBag
    if not pickup then return false end
    local ok, result = pcall(function()
        showRepair()
        if not InRepairMode() then return false end
        if item.bag == nil then pickup(item.slot) else pickup(item.bag, item.slot) end
        return true
    end)
    -- Never leave an unrestricted native repair cursor available to the player.
    pcall(hideRepair)
    return ok and result == true
end

function A.Diagnose()
    local _, build, _, interface = GetBuildInfo()
    print("Rustcore Reforge API: build=" .. tostring(build) .. " interface=" .. tostring(interface))
    print("GUID=" .. tostring(C_Item and type(C_Item.GetItemGUID) == "function")
        .. " bag pickup=" .. tostring(type(pickupBag) == "function")
        .. " native repair=" .. tostring(type(showRepair) == "function"))
    local items = A.Scan()
    print("Readable physical durable items: " .. #items)
    for _, item in ipairs(items) do
        print(item.guid, item.id, item.bag == nil and "equipped" or ("bag " .. item.bag), item.slot,
            item.cur .. "/" .. item.max, "repair cost:", tostring(A.Cost(item)))
    end
end
