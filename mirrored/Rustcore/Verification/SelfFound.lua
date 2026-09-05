-- Rustcore Verification: Self-Found certification (plan sections 6 and 19-28).
--
-- Phase 4 scope is only the start of the claim: when it begins, what baseline
-- it begins from, and whether a late start can still earn verification. The
-- direct restrictions -- trade, auction house, mail -- land in Phase 5 and hang
-- off this same track.
--
-- The track exists on every character but only carries a claim once Self-Found
-- is actually switched on. Until then it sits unclaimed at UNCERTAIN, which is
-- the one status Core will ever promote; starting it at UNVERIFIED would
-- permanently lock out a player who enables Self-Found at level 1 tomorrow.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.SelfFound = V.SelfFound or {}
local SF = V.SelfFound

local function Setting(key)
    if Rustcore and Rustcore.GetSetting then return Rustcore.GetSetting(key) end
    return nil
end

local function Append(eventType, payload)
    if V.Integrity and V.Integrity.Append then V.Integrity.Append(eventType, payload) end
end

local function Seal()
    if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end
end

local function RefreshBuff()
    if RustcoreSelfFoundBuff and RustcoreSelfFoundBuff.Refresh then
        RustcoreSelfFoundBuff.Refresh()
    end
end

-- Baseline (plan section 6) --------------------------------------------------
--
-- "Existing items and gold at activation become the baseline unless they are
-- sufficiently abnormal to trigger suspicion." Phase 4 records that baseline.
-- Judging it against the level-scaled thresholds in sections 23-27 is Phase 7's
-- job, and it needs this snapshot to have been taken at the right moment.

-- Slots 1-19: the whole paper doll in Classic, ammo and tabard included.
local EQUIPMENT_SLOTS = 19

-- Mirrors CaptureBagSnapshot in Rustcore.lua: C_Container is the current API
-- and the loose globals are the pre-10.0 spelling still present on older
-- clients, so both are tried rather than assumed.
local function BagItemCounts()
    local counts, total = {}, 0
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local slots = 0
        if C_Container and C_Container.GetContainerNumSlots then
            slots = C_Container.GetContainerNumSlots(bag) or 0
        elseif GetContainerNumSlots then
            slots = GetContainerNumSlots(bag) or 0
        end
        for slot = 1, slots do
            local link, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then link, count = info.hyperlink, info.stackCount or 1 end
            elseif GetContainerItemInfo then
                local _, stack, _, _, _, _, hyperlink = GetContainerItemInfo(bag, slot)
                link, count = hyperlink, stack or 1
            end
            local id = link and link:match("item:(%d+)")
            if id then
                counts[id] = (counts[id] or 0) + (count or 1)
                total = total + (count or 1)
            end
        end
    end
    return counts, total
end

function SF.CaptureBaseline()
    local equipped = {}
    for slot = 1, EQUIPMENT_SLOTS do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        if id then equipped[slot] = id end
    end

    local bags, bagTotal = BagItemCounts()
    return {
        takenAt  = time and time() or 0,
        level    = V.GetPlayerLevel(),
        money    = GetMoney and GetMoney() or 0,
        played   = V.Time and V.Time.GetLastServerPlayed and V.Time.GetLastServerPlayed() or 0,
        bags     = bags,
        bagCount = bagTotal,
        equipped = equipped,
    }
end

-- Claiming Self-Found --------------------------------------------------------

-- Plan section 6: Self-Found ideally begins at level 1, and enabling it at
-- level 8 or below is a late start that can still qualify. Later than that,
-- Rustcore never watched the early game and has no way to tell where the
-- character's gear and gold came from.
local function StatusForClaimLevel(level)
    if not level or level <= 1 then return V.STATUS.VERIFIED end
    if level <= V.LATE_START_MAX_LEVEL then return V.STATUS.UNCERTAIN end
    return V.STATUS.UNVERIFIED
end

function SF.Claim()
    local record = V.GetRecord()
    local track = record and record.selfFound
    if not track or track.claimed then return false end

    local level = V.GetPlayerLevel()
    track.claimed = true
    track.claimedAtLevel = level
    -- The qualification window is measured from the claim, not from when the
    -- record was created: enabling Self-Found at level 30 on a character
    -- Rustcore has watched since level 1 is still a level-30 start.
    track.qualifyFromLevel = level
    track.claimedAt = time and time() or 0
    record.selfFoundBaseline = SF.CaptureBaseline()

    Append("SF_CLAIM", {
        level = level or 0,
        money = record.selfFoundBaseline.money or 0,
        items = record.selfFoundBaseline.bagCount or 0,
    })

    local wanted = StatusForClaimLevel(level)
    if wanted == V.STATUS.VERIFIED then
        V.Promote("selfFound", "Self-Found from level 1")
    elseif wanted == V.STATUS.UNVERIFIED then
        V.SetStatus("selfFound", V.STATUS.UNVERIFIED,
            "Self-Found started at level " .. tostring(level or "?"))
    end
    -- A late start inside the window needs no transition at all: UNCERTAIN is
    -- where an unclaimed track already sits. It simply starts qualifying.

    Seal()
    RefreshBuff()
    return true
end

-- Called from Rustcore.SetSetting the moment the option is toggled, so the
-- baseline is taken then rather than at the next login.
function SF.OnSettingChanged(enabled)
    local track = V.GetTrack("selfFound")
    if not track then return end

    if enabled then
        if not track.claimed then
            SF.Claim()
            return
        end
        -- Re-enabling never restores anything. If Rustcore saw the option go
        -- off, or saw it already off at a login, that gap is unwatched time in
        -- which nothing stopped the character trading, so the claim cannot be
        -- vouched for any more.
        Append("SF_ENABLE", { level = V.GetPlayerLevel() or 0 })
        if track.claimLapsed then
            V.SetStatus("selfFound", V.STATUS.UNVERIFIED, "Self-Found was switched off")
            track.claimLapsed = nil
        end
        Seal()
        RefreshBuff()
        return
    end

    if not track.claimed then return end
    -- While Self-Found is off none of the section 19 restrictions are in force.
    -- UNVERIFIED rather than FAILED: this is missing evidence, not proof of
    -- anything (section 47).
    track.disabledAt = time and time() or 0
    Append("SF_DISABLE", { level = V.GetPlayerLevel() or 0 })
    V.SetStatus("selfFound", V.STATUS.UNVERIFIED, "Self-Found switched off")
    Seal()
    RefreshBuff()
end

-- Qualification (plan section 6) ---------------------------------------------

-- UNCERTAIN -> VERIFIED once a late start has been watched cleanly for about
-- two levels. Refuses unless Self-Found is actually on right now, so a claim
-- that is currently switched off can never mature into a certification while
-- nobody is enforcing it.
function SF.CheckQualification()
    local track = V.GetTrack("selfFound")
    if not track or not track.claimed or track.claimLapsed then return false end
    if not Setting("selfFound") then return false end

    local ok, reason = V.EvaluateQualification("selfFound")
    if not ok then return false end
    if not V.Promote("selfFound", reason) then return false end

    Seal()
    RefreshBuff()
    return true
end

function SF.Init()
    if SF.initialized then return end
    SF.initialized = true

    local track = V.GetTrack("selfFound")
    if not track then return end

    local enabled = Setting("selfFound") and true or false

    if enabled and not track.claimed then
        -- Switched on in a session Rustcore was not watching, or a record that
        -- predates claim tracking. Either way the claim starts now, at the
        -- level the character is actually at.
        SF.Claim()
        return
    end

    if track.claimed then
        -- Records written before this phase have no qualifyFromLevel; the level
        -- the record was created at is the best available answer, and it is
        -- exact whenever Self-Found was already on at creation.
        if track.qualifyFromLevel == nil then
            track.qualifyFromLevel = track.claimedAtLevel or track.startedAtLevel
        end

        -- Migration marks the claim without taking a baseline, so the first
        -- login after a claim is where one gets captured. When the claim was
        -- made as the record was created that is still the claim moment; on an
        -- older record it is not, and Phase 7 needs to know the difference
        -- before it reads anything into the numbers.
        local record = V.GetRecord()
        if record and not record.selfFoundBaseline then
            record.selfFoundBaseline = SF.CaptureBaseline()
            if track.claimedAt == nil or track.claimedAt ~= record.createdAt then
                record.selfFoundBaseline.backfilled = true
            end
        end

        if not enabled then
            -- Off at login with a claim on file. Rustcore did not see it happen
            -- and will not degrade a status over an unobserved toggle -- that
            -- would make a grandfathered character worse off for doing nothing
            -- (section 4). The lapse is recorded instead, and it blocks
            -- promotion and bites if the player claims Self-Found again.
            track.claimLapsed = true
            Seal()
            return
        end

        SF.CheckQualification()
    end
end
