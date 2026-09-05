-- Rustcore Verification: Self-Found money monitoring
-- (plan sections 23, 24 and 25).
--
-- Section 23 sets the ambition deliberately low: do not try to explain every
-- copper. Only two things matter here.
--
--   direction  a gain can be an acquisition; spending never is. Money going
--              down is not tracked beyond keeping the running figure honest.
--   magnitude  an unexplained gain is judged against what is normal for the
--              character's level, not against a ledger of where it came from.
--
-- Everything that legitimately produces money -- looting, quest rewards, selling
-- to a vendor, NPC mail -- is filtered out by Economy.lua's context window
-- before magnitude is ever consulted, so in ordinary play this module reaches
-- its thresholds essentially never.

RustcoreVerification = RustcoreVerification or {}
local V = RustcoreVerification
V.Money = V.Money or {}
local Mo = V.Money

local function E()
    return V.Economy
end

local function CurrentMoney()
    return (GetMoney and GetMoney()) or 0
end

-- State ----------------------------------------------------------------------

-- Persisted, because the comparison has to survive a logout: money earned while
-- Rustcore was not watching should still be noticed next login.
local function GetState()
    local economy = E() and E().GetState()
    if not economy then return nil end
    economy.money = economy.money or {}
    local state = economy.money
    if state.unexplained == nil then state.unexplained = 0 end
    if state.anomalies == nil then state.anomalies = 0 end
    return state
end

Mo.GetState = GetState

-- Evaluation ------------------------------------------------------------------

-- An unexplained gain, in copper, judged against the level-scaled thresholds.
local function Judge(amount)
    local economy = E()
    local level = V.GetPlayerLevel() or 1
    local warn = economy.GetGoldWarningThreshold(level)
    local fail = economy.GetGoldFailureThreshold(level)

    if amount < warn then return nil end
    return (amount >= fail) and "fail" or "warn"
end

-- Set once the world is loaded. Until then GetMoney() can still answer 0, and
-- comparing a real balance against that phantom zero would read as the player
-- suddenly acquiring everything they own.
local ready = false

-- Called on every money change.
function Mo.Evaluate()
    local state = GetState()
    if not state then return end

    local current = CurrentMoney()
    local previous = state.last

    -- First reading on this character, or the figure is not trustworthy yet:
    -- adopt it and judge nothing.
    if previous == nil or not ready then
        state.last = current
        return
    end

    state.last = current

    local delta = current - previous
    if delta <= 0 then return end          -- spending is never a violation
    if not E().ShouldJudge() then return end

    -- Quest rewards state their amount outright, so that much is settled
    -- exactly rather than merely excused.
    local remaining = E().ConsumeExpectedMoney(delta)
    if remaining <= 0 then return end

    -- Anything the player was plainly in the middle of doing.
    if E().IsExplained() then return end

    state.unexplained = (state.unexplained or 0) + remaining

    local band = Judge(remaining)
    if not band then return end

    state.anomalies = (state.anomalies or 0) + 1
    state.lastAnomaly = remaining
    state.lastAnomalyAt = time and time() or 0

    E().Escalate(band, "goldDiscrepancy", string.format(
        "%s unexplained at level %d",
        E().FormatMoney(remaining), V.GetPlayerLevel() or 0))

    if V.Integrity and V.Integrity.Seal then V.Integrity.Seal() end
end

-- Take the current figure as the new baseline without judging it. Used when
-- Rustcore has no business comparing -- at login, and when a claim begins.
function Mo.Rebase()
    local state = GetState()
    if not state then return end
    state.last = CurrentMoney()
end

-- Events -----------------------------------------------------------------------

function Mo.OnEvent(event)
    if event == "PLAYER_MONEY" then
        Mo.Evaluate()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The figure is not always readable the instant this fires, and a login
        -- is not a moment Rustcore can reason about anyway: it did not watch
        -- whatever happened between sessions. Judging only begins once this
        -- settled reading has been taken.
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                pcall(Mo.Rebase)
                ready = true
            end)
        else
            Mo.Rebase()
            ready = true
        end
    end
end

function Mo.Init()
    if Mo.initialized then return end
    Mo.initialized = true

    Mo.Rebase()

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_MONEY")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event)
        -- A fault in verification must never break the game session.
        local ok, err = pcall(Mo.OnEvent, event)
        if not ok then
            print("|cffff4444Rustcore ERROR:|r money verification: " .. tostring(err))
        end
    end)
    Mo.frame = frame
end
