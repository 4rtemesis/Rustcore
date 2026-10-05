RustcoreReforge = {}
local R, A, V = RustcoreReforge, RustcoreReforgeAPI, RustcoreVerification
R.REFORGE_UNLOCK_LEVEL = 60
R.RUSTBOUND_ICON = "Interface\\Icons\\INV_Helmet_01"
R.READY_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local pending, receipts, observed = {}, {}, {}
local debugState, debugLevel

local function NewState(everRepaired)
    return { version = 1, everRepaired = everRepaired == true, rustboundEarned = false,
        rustboundLost = false, items = {} }
end

function R.State()
    if debugState then return debugState end
    local record = V.GetRecord()
    if not record then return nil end
    if not record.reforge then
        local track = record.difficulty or {}
        record.reforge = NewState((track.repairViolations or 0) > 0)
        if V.Integrity and V.Integrity.Seal then V.Integrity.Seal(record) end
    end
    return record.reforge
end

function R.IsDebug() return debugState ~= nil end
function R.UnlockLevel() return debugLevel or R.REFORGE_UNLOCK_LEVEL end
function R.LiveVerified()
    local track = V.GetTrack("difficulty")
    return track and V.IsCertified(track.status) == true or false
end
function R.Verified()
    -- Developer eligibility is a session-only fixture, never a change to the
    -- character's real difficulty certification or its missing playtime.
    return not Rustcore.GetSetting("allowRepair") and (R.IsDebug() or R.LiveVerified())
end
function R.AtUnlockLevel()
    return (V.GetPlayerLevel() or 0) >= R.UnlockLevel()
end
function R.UnlockReason()
    if not R.AtUnlockLevel() then
        return "Requires level " .. R.UnlockLevel() .. "; current level is " .. (V.GetPlayerLevel() or 0) .. "."
    end
    if Rustcore.GetSetting("allowRepair") then return "Turn off Allow Item Repair to use Boss Reforging." end
    if not R.Verified() then
        local track = V.GetTrack("difficulty")
        return "Difficulty verification is " .. tostring(track and track.status or "unavailable")
            .. ". Developer mode can test eligibility without changing this record."
    end
end
function R.Unlocked()
    return R.UnlockReason() == nil
end
function R.Changed()
    if not debugState and V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end
    if R.Refresh then R.Refresh() end
end

function R.CheckRustbound()
    local reason = R.UnlockReason()
    if reason then return false, reason end
    local state = R.State()
    if not state then return false, "No character verification record is available." end
    if state.rustboundLost then return false, "Rustbound was permanently lost through Boss Reforging." end
    if state.everRepaired then return false, "This character has already repaired an item." end
    if not state.rustboundEarned then
        state.rustboundEarned = true
        R.Changed()
    end
    return true
end
function R.HasRustbound()
    local state = R.State()
    return state and state.rustboundEarned and not state.rustboundLost
        and not state.everRepaired and R.Unlocked()
end
function R.NoteRepair()
    local state = R.State()
    if state then state.everRepaired = true end
    if debugState then
        local record = V.GetRecord()
        if record then
            record.reforge = record.reforge or NewState(true)
            record.reforge.everRepaired = true
            if V.Integrity and V.Integrity.Seal then V.Integrity.Seal(record) end
        end
    end
    R.Changed()
end
function R.Source(item)
    if debugState and debugState.sources and debugState.sources[item.guid] then
        return debugState.sources[item.guid]
    end
    return RustcoreReforgeSources.items[item.id]
end
function R.SourceName(id)
    return RustcoreReforgeSources.bosses[id] or (debugState and id and "Test boss " .. id) or "Unknown"
end
function R.HasShard(item)
    local state = R.State()
    local entry = state and item and state.items[item.guid]
    return entry and entry.id == item.id and entry.source == R.Source(item) and entry.charged == true or false
end
function R.AwardBoss(id)
    local reason = R.UnlockReason()
    if reason then return 0, reason end
    if type(id) ~= "number" or (not RustcoreReforgeSources.bosses[id] and not debugState) then
        return 0, "Unknown encounter ID."
    end
    local state, count, matching, waiting = R.State(), 0, 0, 0
    if not state then return 0, "No character verification record is available." end
    for _, item in ipairs(A.Scan()) do
        if R.Source(item) == id then
            matching = matching + 1
            if pending[item.guid] then waiting = waiting + 1 end
        end
        if R.Source(item) == id and not pending[item.guid] then
            if not R.HasShard(item) then count = count + 1 end
            state.items[item.guid] = { id = item.id, source = id, charged = true }
        end
    end
    R.Changed()
    if matching == 0 then return 0, "No readable carried items match that Reforge Source. Inspect the item or run /rcreforge api." end
    if count == 0 and waiting > 0 then return 0, "Matching items are awaiting repair confirmation or already have a Reforge Shard." end
    if count == 0 then return 0, "All matching carried items already have a Reforge Shard." end
    return count
end

function R.Find(guid)
    for _, item in ipairs(A.Scan()) do if item.guid == guid then return item end end
end
function R.Threshold()
    return math.max(10, math.min(90, tonumber(Rustcore.GetSetting("reforgeThreshold")) or 50))
end
function R.Plan()
    local plan = { items = {}, cost = 0, skipped = 0, threshold = R.Threshold() }
    if not R.Unlocked() or not A.AtMerchant() then return plan end
    for _, item in ipairs(A.Scan()) do
        if R.HasShard(item) and item.cur < item.max and not pending[item.guid] then
            if item.cur * 100 <= item.max * plan.threshold then
                local cost = A.Cost(item)
                if cost == nil then plan.error = "Repair cost unavailable; run /rcreforge api at this vendor."; return plan end
                plan.items[#plan.items + 1] = { guid = item.guid, id = item.id, cur = item.cur, max = item.max, cost = cost }
                plan.cost = plan.cost + cost
            else plan.skipped = plan.skipped + 1 end
        end
    end
    return plan
end

-- Receipts describe an exact GUID and durability transition, never a blanket
-- exemption for repairs during a time window. Verification consumes each once.
local function Complete(item, request)
    if item.id ~= request.id or item.cur ~= item.max or item.max ~= request.max or item.cur <= request.cur then return false end
    local state = request.state
    local entry = state.items[item.guid]
    if not request.test and (not entry or not entry.charged) then return false end
    if entry and not request.test then entry.charged = false end
    state.everRepaired, state.rustboundLost = true, true
    if state.pending then state.pending[item.guid] = nil end
    if request.persistedState and request.persistedState.pending then
        request.persistedState.pending[item.guid] = nil
    end
    if debugState then
        local record = V.GetRecord()
        if record then
            record.reforge = record.reforge or NewState(true)
            record.reforge.everRepaired, record.reforge.rustboundLost = true, true
            if V.Integrity and V.Integrity.Seal then V.Integrity.Seal(record) end
        end
    end
    pending[item.guid] = nil
    observed[item.guid] = item
    receipts[item.guid] = { cur = request.cur, max = item.max, at = GetTime() }
    R.Changed()
    return true
end

function R.AcceptVerifiedRepair(was, now)
    if not now.guid or was.guid ~= now.guid then return false end
    local request = pending[now.guid]
    if request then
        local item = { guid = now.guid, id = now.id, cur = now.cur, max = now.max }
        Complete(item, request)
    end
    local receipt = receipts[now.guid]
    if receipt and GetTime() - receipt.at <= 10 and was.cur == receipt.cur and now.cur == receipt.max then
        receipts[now.guid] = nil
        return true
    end
    return false
end

function R.Repair(guid, expectedCost)
    -- Bring the existing verifier to the exact pre-repair durability. Otherwise
    -- damage since its last debounced scan could make a legitimate receipt miss.
    if V.Durability and V.Durability.Scan then V.Durability.Scan() end
    local item = R.Find(guid)
    if not item or not R.Unlocked() or not A.AtMerchant() or not R.HasShard(item)
        or item.cur >= item.max or pending[guid] then return false, "Item cannot be reforged." end
    local cost = A.Cost(item)
    if cost == nil or (expectedCost and cost ~= expectedCost) then return false, "Repair cost unavailable or changed." end
    if GetMoney() < cost then return false, "Not enough gold." end
    local request = { id = item.id, cur = item.cur, max = item.max, state = R.State(), at = GetTime() }
    pending[guid] = request
    local record = V.GetRecord()
    if record then
        record.reforge = record.reforge or NewState(false)
        request.persistedState = record.reforge
        record.reforge.pending = record.reforge.pending or {}
        record.reforge.pending[guid] = { id = item.id, cur = item.cur, max = item.max, test = debugState ~= nil }
        if V.Integrity and V.Integrity.Seal then V.Integrity.Seal(record) end
    end
    if V.Durability then V.Durability.NoteRepairAction("Boss Reforge") end
    local ok = A.Repair(item)
    -- Also observe after a rejected call: a client may execute before reporting
    -- an error. Only an observed full repair spends the Shard.
    R.Observe()
    if not ok and pending[guid] then
        pending[guid] = nil
        if request.persistedState and request.persistedState.pending then request.persistedState.pending[guid] = nil end
        if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end
        R.Changed()
    end
    return ok, ok and nil or "Repair API refused the action; try a single Reforge."
end

function R.Execute(plan)
    if plan.error or not R.Unlocked() or not A.AtMerchant() then return false end
    -- Revalidate the entire confirmation snapshot before spending anything.
    if plan.threshold ~= R.Threshold() or GetMoney() < plan.cost then return false end
    for _, expected in ipairs(plan.items) do
        local item = R.Find(expected.guid)
        if not item or item.id ~= expected.id or item.cur ~= expected.cur or item.max ~= expected.max
            or not R.HasShard(item) or pending[item.guid] or A.Cost(item) ~= expected.cost then return false end
    end
    for _, expected in ipairs(plan.items) do
        local ok, reason = R.Repair(expected.guid, expected.cost)
        if not ok then print("Rustcore: " .. reason); return false end
    end
    return true
end

function R.Observe()
    local current = {}
    for _, item in ipairs(A.Scan()) do
        current[item.guid] = item
        local request, was = pending[item.guid], observed[item.guid]
        if request then
            Complete(item, request)
        elseif was and was.id == item.id and item.max == was.max and item.cur > was.cur then
            -- Includes bags and unrestricted repairs; never infer "never repaired"
            -- from whether the Rustbound icon happens to be showing.
            R.NoteRepair()
            if item.bag ~= nil and not receipts[item.guid] and V.Difficulty then
                local armed = V.Durability and V.Durability.GetRepairAction and V.Durability.GetRepairAction()
                if armed then V.Difficulty.OnRepairPerformed("carried item durability increased")
                elseif V.Difficulty.OnUnexplainedRepairEvidence then
                    V.Difficulty.OnUnexplainedRepairEvidence("carried item durability increased")
                end
            end
        end
    end
    for guid, request in pairs(pending) do
        if GetTime() - request.at > 8 then
            pending[guid] = nil
            if request.persistedState and request.persistedState.pending then request.persistedState.pending[guid] = nil end
            if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end
            R.Changed()
        end
    end
    for guid, receipt in pairs(receipts) do
        if GetTime() - receipt.at > 10 then receipts[guid] = nil end
    end
    observed = current
end

function R.LoadPending()
    local state = R.State()
    if not state then return end
    for guid, entry in pairs(state.pending or {}) do
        pending[guid] = { id = entry.id, cur = entry.cur, max = entry.max, state = state,
            persistedState = state, test = entry.test, at = GetTime() }
    end
end

-- Debug uses the production functions with a session-only state. Actual repairs
-- still modify real gear, so production prestige records that repair permanently.
function R.DebugMode(enabled)
    if next(pending) then return false, "Wait for pending repairs to finish." end
    debugState = enabled and NewState(false) or nil
    debugLevel, receipts, observed = nil, {}, {}
    R.Changed()
    return true
end
function R.DebugLevel(level)
    if not debugState then return false, "Enable developer mode first." end
    if level ~= nil and (type(level) ~= "number" or level < 1 or level > R.REFORGE_UNLOCK_LEVEL or level % 1 ~= 0) then
        return false, "Invalid test unlock level."
    end
    debugLevel = level
    local earned, reason = R.CheckRustbound()
    R.Changed()
    return earned, reason
end
function R.DebugSource(item, boss)
    if not debugState or not item then return false end
    debugState.sources = debugState.sources or {}
    debugState.sources[item.guid] = boss
    debugState.items[item.guid] = nil
    R.Changed()
    return true
end
function R.DebugResetRustbound()
    if not debugState then return false, "Enable developer mode first." end
    if next(pending) then return false, "Wait for pending repairs to finish." end
    debugState.everRepaired, debugState.rustboundEarned, debugState.rustboundLost = false, false, false
    R.Changed()
    return true
end
function R.DebugRestoreRustbound()
    local ok, reason = R.DebugResetRustbound()
    if not ok then return false, reason end
    return R.CheckRustbound()
end
function R.DebugRemoveShard(item)
    if debugState and item and not pending[item.guid] then debugState.items[item.guid] = nil; R.Changed() end
end
