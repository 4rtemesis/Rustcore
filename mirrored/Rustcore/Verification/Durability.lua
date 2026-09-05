-- Rustcore Verification: durability tracking and repair detection
-- (plan sections 12, 13 and 14).
--
-- Durability only ever goes up when something repaired it, so an increase is
-- the observable footprint of a repair. Two things are being separated here:
--
--   an increase we can tie to a repair action we watched happen
--       -> an observed repair. Rustcore blocks repair at every preset, so this
--          is a broken rule, not a suspicion (section 12).
--   an increase we cannot explain
--       -> evidence only. First one warns, second one fails (section 14).
--
-- Clicking a repair button is deliberately NOT enough on its own: the click may
-- fail for lack of money, or repair nothing but bag items. Certification only
-- moves when durability actually went up. That direction of error is the one
-- section 51 asks for -- miss a repair rather than punish an innocent player.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.Durability = V.Durability or {}
local U = V.Durability

-- Slots that carry durability, matching SLOT_DATA in RustcoreDurability.lua and
-- DURABLE_SLOTS in Migration.lua. Slot 15 (back) has none.
local DURABLE_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

-- How long a repair action keeps explaining durability increases. The client
-- sends the durability update a moment after the repair, and
-- UPDATE_INVENTORY_DURABILITY arrives in bursts, so this is generous.
local REPAIR_WINDOW = 30

-- UPDATE_INVENTORY_DURABILITY fires several times for one repair; coalesce.
local SCAN_DEBOUNCE = 1

-- The event is documented as unreliable in edge cases, so a slow sweep backs it
-- up. Nothing here is expensive: eleven slot reads.
local PERIODIC_SCAN = 120

-- Slots whose equipped item changed since the last scan. An item swap can raise
-- a slot's durability without anything being repaired, and this is the signal
-- that says so. Treating a slot as swapped only ever makes Rustcore more
-- lenient, so it is safe to trust even where the event's exact semantics are
-- murky.
local replacedSlots = {}

local repairArmedAt, repairArmedKind
local scanPending = false

local function Now()
    return GetTime and GetTime() or (time and time() or 0)
end

-- ── Reading the current state ────────────────────────────────────────────────

-- C_Item.GetItemGUID distinguishes two copies of the same item, which is the
-- only fully reliable answer to "is this the same item as last time"
-- (section 14). It exists in Classic Era, but it is feature-detected anyway;
-- without it the code falls back to item id plus the swap hint above.
local function ItemGuidForSlot(slot)
    if not (C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromEquipmentSlot) then
        return nil
    end
    local ok, guid = pcall(function()
        local loc = ItemLocation:CreateFromEquipmentSlot(slot)
        if not loc or not loc:IsValid() then return nil end
        return C_Item.GetItemGUID(loc)
    end)
    if ok then return guid end
    return nil
end

-- One slot's identity and wear, or nil when the slot is empty, and a second
-- return saying whether the slot is genuinely empty as opposed to unreadable.
local function ReadSlot(slot)
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    if not link then return nil, true end

    local current, maximum = GetInventoryItemDurability(slot)
    if not current or not maximum or maximum <= 0 then
        -- Equipped but no durability figures yet (or an item without any).
        return nil, false
    end

    return {
        id   = GetInventoryItemID and GetInventoryItemID("player", slot) or nil,
        guid = ItemGuidForSlot(slot),
        cur  = current,
        max  = maximum,
    }, false
end

function U.GetState()
    local record = V.GetRecord()
    if not record then return nil end
    record.durabilityState = record.durabilityState or { slots = {} }
    record.durabilityState.slots = record.durabilityState.slots or {}
    return record.durabilityState
end

function U.GetSnapshot()
    local state = U.GetState()
    return state and state.slots or nil
end

-- ── Repair actions we can watch ──────────────────────────────────────────────

-- Called when the player does something that could repair. This only arms the
-- explanation; it never changes a certification by itself.
function U.NoteRepairAction(kind)
    repairArmedAt = Now()
    repairArmedKind = kind or "repair"
end

local function RepairArmed()
    if InRepairMode and InRepairMode() then
        -- The repair cursor is up, so an individual item repair is in progress.
        -- Classic has no event for one, which makes this the only handle on it.
        return "repairCursor"
    end
    if not repairArmedAt then return nil end
    if (Now() - repairArmedAt) > REPAIR_WINDOW then return nil end
    return repairArmedKind
end

-- ── Comparison (plan section 14) ─────────────────────────────────────────────

-- Did the same physical item stay in this slot? Returns one of:
--   "same"        we can show it is the same item
--   "different"   we can show it is not
--   "unreadable"  our own read failed, so nothing can be concluded
--   "unconfirmed" the client offers no item GUID, so a repair and a second
--                 copy of the same item look alike (section 14 names this case)
local function CompareIdentity(previous, current, slot)
    if replacedSlots[slot] then return "different" end
    if previous.guid and current.guid then
        return previous.guid == current.guid and "same" or "different"
    end
    if previous.id and current.id and previous.id ~= current.id then
        return "different"
    end
    if previous.max ~= current.max then
        -- Same item id, different maximum: a different item after all.
        return "different"
    end
    if previous.guid or current.guid then
        -- One side has a GUID and the other does not, so the comparison the
        -- GUID exists for cannot be made. That is our own read failing rather
        -- than the player doing anything, so it must never cost them.
        return "unreadable"
    end
    -- Same id, same maximum, no GUIDs anywhere. Classic Era does expose
    -- C_Item.GetItemGUID, so this is a client that does not; the swap hint
    -- above is then all that separates a repair from an identical copy, which
    -- is enough to suspect but not enough to conclude.
    return "unconfirmed"
end

-- Everything that got more durable since the previous snapshot, split by how
-- sure we are of the item's identity.
function U.Compare(previous, current)
    local findings = { slots = {}, unconfirmed = {}, gained = 0, unreadable = 0 }

    for _, slot in ipairs(DURABLE_SLOTS) do
        local was, now = previous[slot], current[slot]
        if was and now and now.cur > was.cur then
            local verdict = CompareIdentity(was, now, slot)
            if verdict == "same" then
                findings.slots[#findings.slots + 1] = slot
                findings.gained = findings.gained + (now.cur - was.cur)
            elseif verdict == "unconfirmed" then
                findings.unconfirmed[#findings.unconfirmed + 1] = slot
            elseif verdict == "unreadable" then
                findings.unreadable = findings.unreadable + 1
            end
            -- "different": the item was replaced, which is not a repair.
        end
    end

    return findings
end

-- ── Scanning ─────────────────────────────────────────────────────────────────

-- opts.baselineOnly records the current state without judging it, for the first
-- scan of a character and after anything that makes comparison meaningless.
function U.Scan(opts)
    opts = opts or {}
    local state = U.GetState()
    if not state then return end

    local previous = state.slots
    local current = {}
    for _, slot in ipairs(DURABLE_SLOTS) do
        local entry, empty = ReadSlot(slot)
        if entry then
            current[slot] = entry
        elseif not empty and previous[slot] then
            -- Equipped but unreadable this instant. Keeping the old figures
            -- beats discarding the only baseline we have.
            current[slot] = previous[slot]
        end
    end

    local findings
    if state.established and not opts.baselineOnly then
        findings = U.Compare(previous, current)
    end

    state.slots = current
    state.takenAt = time and time() or 0
    state.established = true
    wipe(replacedSlots)

    -- The snapshot is covered by the state seal, so it is restamped whether or
    -- not anything was found.
    if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end

    if not findings or not V.Difficulty then return findings end

    -- One repair repairs everything at once, so the whole scan is a single
    -- event. Reporting it per slot would turn one repair into an instant
    -- failure by way of the second-warning rule.
    if #findings.slots > 0 then
        local kind = RepairArmed()
        local detail = string.format("%d slot%s, +%d durability%s",
            #findings.slots,
            #findings.slots == 1 and "" or "s",
            findings.gained,
            kind and (" via " .. kind) or "")
        if kind then
            V.Difficulty.OnRepairPerformed(detail)
        else
            V.Difficulty.OnUnexplainedRepairEvidence(detail)
        end

    elseif #findings.unconfirmed > 0 then
        -- Identity could not be established, so this is evidence at most --
        -- never an observed repair, however plainly a repair was armed.
        V.Difficulty.OnUnexplainedRepairEvidence(string.format(
            "%d slot%s, item identity unconfirmed",
            #findings.unconfirmed,
            #findings.unconfirmed == 1 and "" or "s"))
    end

    return findings
end

local function RequestScan()
    if scanPending then return end
    scanPending = true
    local function run()
        scanPending = false
        U.Scan()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(SCAN_DEBOUNCE, run)
    else
        run()
    end
end

-- ── Hooks ────────────────────────────────────────────────────────────────────

-- Rustcore.lua already replaces RepairAllItems and ShowRepairCursor to block
-- repair, and the TOC loads it first, so these wrap the blocking versions.
-- Wrapping outside the block is deliberate: an attempt is worth arming for even
-- when Rustcore refuses it, and the durability comparison decides whether
-- anything actually happened.
local function HookGlobals()
    if U.globalsHooked then return end
    U.globalsHooked = true

    if type(RepairAllItems) == "function" then
        local original = RepairAllItems
        RepairAllItems = function(...)
            U.NoteRepairAction("repair all")
            return original(...)
        end
    end

    if type(ShowRepairCursor) == "function" then
        local original = ShowRepairCursor
        ShowRepairCursor = function(...)
            U.NoteRepairAction("repair cursor")
            return original(...)
        end
    end
end

-- The merchant buttons exist in the base UI, but only hook them once a merchant
-- window has actually been opened -- HookScript stacks, so a guard is required.
local function HookMerchantButtons()
    if U.buttonsHooked then return end
    U.buttonsHooked = true

    if MerchantRepairAllButton and MerchantRepairAllButton.HookScript then
        MerchantRepairAllButton:HookScript("OnClick", function()
            U.NoteRepairAction("repair all button")
        end)
    end
    if MerchantRepairItemButton and MerchantRepairItemButton.HookScript then
        MerchantRepairItemButton:HookScript("OnClick", function()
            U.NoteRepairAction("repair item button")
        end)
    end
end

function U.OnEvent(event, ...)
    if event == "UPDATE_INVENTORY_DURABILITY" then
        RequestScan()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        local slot = ...
        if slot then replacedSlots[slot] = true end
        RequestScan()

    elseif event == "MERCHANT_SHOW" then
        HookMerchantButtons()

    elseif event == "MERCHANT_CLOSED" then
        -- Backstop for the durability event going missing, which it is known
        -- to do; the merchant window is where repairs happen.
        U.Scan()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Durability figures are not always readable the instant this fires.
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function() U.Scan() end)
        else
            U.Scan()
        end
    end
end

function U.Init()
    if U.initialized then return end
    U.initialized = true

    HookGlobals()

    -- A character whose record has no snapshot yet gets one without judgment;
    -- there is nothing to compare a first reading against.
    local state = U.GetState()
    if state and not state.established then
        U.Scan({ baselineOnly = true })
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event, ...)
        -- A fault in verification must never break the game session.
        local ok, err = pcall(U.OnEvent, event, ...)
        if not ok then
            print("|cffff4444Rustcore ERROR:|r durability verification: " .. tostring(err))
        end
    end)
    U.frame = frame

    if C_Timer and C_Timer.NewTicker then
        U.ticker = C_Timer.NewTicker(PERIODIC_SCAN, function()
            pcall(U.Scan)
        end)
    end
end
