-- RustcoreSelfFoundBuff: shows verified Self Found status as a real-looking
-- buff on the player's own buff bar (spell 431567, Blizzard's actual
-- Hardcore "Self-Found Adventurer" buff) instead of a custom stats-panel icon.
--
-- Two earlier approaches (shifting BuffFrame's own anchor, then reading and
-- reassigning Blizzard's real BuffButtonN positions) both fought Blizzard's
-- own layout code and lost - the real buttons kept snapping back to their
-- own computed slots, leaving our icon stranded on top of/beside them.
--
-- This version stops trying to cooperate with Blizzard's layout entirely:
-- the whole native BuffFrame is made invisible and mouse-transparent (alpha
-- 0, EnableMouse off - not :Hide(), so Blizzard's own bookkeeping is left
-- alone), and we draw our own row of icons from scratch by reading aura
-- data directly via UnitAura("player", i, "HELPFUL"). Debuffs are already
-- shown natively elsewhere on screen and are intentionally not duplicated
-- here. Our self-found icon is always slot 1; every real buff follows in
-- slot 2, 3, ... in the same top-right-anchored, left-growing, row-wrapping
-- grid BuffFrame itself uses (see MANUAL_OFFSET_X/Y below for fine-tuning
-- on clients where that default is a pixel or two off).
--
-- A second, independent display mirrors this same hide-and-redraw approach
-- on TargetFrame when you target yourself, since that frame's buff/debuff
-- row reflects real aura data and would never include our faked buff on
-- its own - see RefreshTargetIcon.

RustcoreSelfFoundBuff = RustcoreSelfFoundBuff or {}

local TOOLTIP_TEXT = "Verified Self Found Character"
-- Matches BuffButtonTemplate's native 30x30 size / 3px spacing.
local BUTTON_SIZE = 30
local GAP = 3
local REFRESH_INTERVAL = 0.2

-- Blizzard's own FrameXML anchors real slot 1 at BuffFrame's TOPRIGHT with
-- a 0,0 offset, but this client's Edit Mode buff frame renders about half
-- an icon further right than that - shifted left by half BUTTON_SIZE to
-- compensate. Nudge further and /reload if a given build is still off by a
-- few pixels - a live offset can't be derived from a screenshot alone.
local MANUAL_OFFSET_X, MANUAL_OFFSET_Y = -(BUTTON_SIZE / 2), 0

local iconFrame
local buttonPool = {}
local active = false
local sinceRefresh = 0
local RefreshAuraLayout -- forward-declared: OnUpdate (below) needs to call it before it's defined
local HideNativeBuffFrame -- forward-declared: OnUpdate (below) needs to call it before it's defined
local HideNativeTargetAurasIfSelfTargeted -- forward-declared: OnUpdate (below) needs to call it before it's defined

local function EnsureIconFrame()
    if iconFrame then return iconFrame end

    iconFrame = CreateFrame("Button", "RustcoreSelfFoundBuffIcon", UIParent)
    iconFrame:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    iconFrame:SetFrameStrata("MEDIUM")
    iconFrame:EnableMouse(true)
    iconFrame:Hide()

    iconFrame.texture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.texture:SetAllPoints(iconFrame)
    -- Real BuffButtonTemplate icons are shown uncropped (full 0-1 texcoords) -
    -- the thin border you see on a normal buff is baked into the icon art
    -- itself, not a separate frame texture.

    iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(TOOLTIP_TEXT, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Self-heal on a short throttle instead of depending on any one Blizzard
    -- event/function to fire reliably. OnUpdate only runs while the frame is
    -- shown, so this costs nothing while self-found is inactive. Hiding the
    -- native BuffFrame is reasserted every tick (cheap, single call) since
    -- Blizzard's own aura fade animations can fight a one-time SetAlpha.
    iconFrame:SetScript("OnUpdate", function(self, elapsed)
        HideNativeBuffFrame()
        HideNativeTargetAurasIfSelfTargeted()
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh < REFRESH_INTERVAL then return end
        sinceRefresh = 0
        pcall(RefreshAuraLayout)
    end)

    return iconFrame
end

local function CreateAuraButton()
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:EnableMouse(true)
    b:RegisterForClicks("RightButtonUp")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)

    b.duration = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.duration:SetPoint("TOP", b, "BOTTOM", 0, 0)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        if self.auraIndex and GameTooltip.SetUnitAura then
            GameTooltip:SetUnitAura("player", self.auraIndex, self.auraFilter)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        if self.auraIndex then
            pcall(CancelUnitBuff, "player", self.auraIndex, self.auraFilter)
        end
    end)

    return b
end

local function AcquireButton(i)
    local b = buttonPool[i]
    if not b then
        b = CreateAuraButton()
        buttonPool[i] = b
    end
    return b
end

local function FormatDuration(seconds)
    if seconds >= 3600 then
        return math.ceil(seconds / 3600) .. "h"
    elseif seconds >= 60 then
        return math.ceil(seconds / 60) .. "m"
    else
        return math.max(math.ceil(seconds), 0) .. "s"
    end
end

local function ComputePerRow()
    local frame = _G.BuffFrame
    local width = frame and frame.GetWidth and frame:GetWidth()
    if not width or width <= 0 then return 6 end
    return math.max(math.floor((width + GAP) / (BUTTON_SIZE + GAP)), 1)
end

-- 1-based grid slot -> anchored position, matching BuffFrame's own
-- top-right-anchored, left-growing, row-wrapping layout. baseX/baseY apply
-- MANUAL_OFFSET_X/Y on top of the verified (0,0)-at-TOPRIGHT default.
local function PositionSlot(button, slotIndex, perRow, baseX, baseY)
    local col = (slotIndex - 1) % perRow
    local row = math.floor((slotIndex - 1) / perRow)
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", _G.BuffFrame, "TOPRIGHT",
        baseX - (col * (BUTTON_SIZE + GAP)), baseY - (row * (BUTTON_SIZE + GAP)))
end

function HideNativeBuffFrame()
    local frame = _G.BuffFrame
    if not frame then return end
    frame:SetAlpha(0)
    frame:EnableMouse(false)
end

local function ShowNativeBuffFrame()
    local frame = _G.BuffFrame
    if not frame then return end
    frame:SetAlpha(1)
    frame:EnableMouse(true)
end

function RefreshAuraLayout()
    if not active or not iconFrame or not _G.BuffFrame then return end

    HideNativeBuffFrame()

    local perRow = ComputePerRow()
    local baseX, baseY = MANUAL_OFFSET_X, MANUAL_OFFSET_Y
    PositionSlot(iconFrame, 1, perRow, baseX, baseY)

    local slotIndex = 2
    local usedCount = 0
    local now = GetTime()

    local auraIndex = 1
    while true do
        local name, icon, count, _, duration, expirationTime = UnitAura("player", auraIndex, "HELPFUL")
        if not name then break end

        usedCount = usedCount + 1
        local b = AcquireButton(usedCount)
        b.auraIndex = auraIndex
        b.auraFilter = "HELPFUL"
        b.icon:SetTexture(icon)
        b.count:SetText((count and count > 1) and tostring(count) or "")
        if duration and duration > 0 and expirationTime then
            b.expirationTime = expirationTime
        else
            b.expirationTime = nil
            b.duration:SetText("")
        end
        PositionSlot(b, slotIndex, perRow, baseX, baseY)
        b:Show()

        slotIndex = slotIndex + 1
        auraIndex = auraIndex + 1
    end

    for i = 1, usedCount do
        local b = buttonPool[i]
        if b.expirationTime then
            b.duration:SetText(FormatDuration(b.expirationTime - now))
        end
    end

    for i = usedCount + 1, #buttonPool do
        buttonPool[i]:Hide()
    end
end

-- ── Self-targeted display (TargetFrame) ─────────────────────────────────
-- TargetFrame draws its own buff/debuff icons reflecting the targeted
-- unit's real aura data, in two dedicated sub-containers (TargetFrame.buffs
-- / .debuffs) separate from the player's own BuffFrame above. Since our
-- self-found icon isn't a real aura it never shows up there on its own -
-- when you target yourself we mirror the main bar's approach exactly: hide
-- both native containers and redraw everything ourselves from UnitAura data
-- with our icon in slot 1, so real auras start at slot 2. Untouched (native,
-- unhidden) for every target other than yourself.
--
-- Blizzard's own target/focus aura buttons render at 21x21 (smaller than
-- the 30x30 main buff bar) - matched here so ours doesn't stand out.
local TARGET_BUTTON_SIZE = 21
local TARGET_GAP = 3
local TARGET_ROW_WIDTH = 122 -- Blizzard's own max row width for these auras
local TARGET_PER_ROW = math.max(math.floor((TARGET_ROW_WIDTH + TARGET_GAP) / (TARGET_BUTTON_SIZE + TARGET_GAP)), 1)
-- Fallback anchor only, used if TargetFrameBuff1 doesn't exist yet - normal
-- positioning instead anchors directly off that real button (see
-- PositionTargetSlot), since it's still live-positioned by Blizzard's own
-- layout code even while we've alpha-hidden it.
local TARGET_OFFSET_X, TARGET_OFFSET_Y = 21, -28

local targetIcon
local targetButtonPool = {}

local function EnsureTargetIcon()
    if targetIcon then return targetIcon end

    targetIcon = CreateFrame("Button", "RustcoreSelfFoundTargetIcon", UIParent)
    targetIcon:SetSize(TARGET_BUTTON_SIZE, TARGET_BUTTON_SIZE)
    targetIcon:SetFrameStrata("MEDIUM")
    targetIcon:EnableMouse(true)
    targetIcon:Hide()

    targetIcon.texture = targetIcon:CreateTexture(nil, "ARTWORK")
    targetIcon.texture:SetAllPoints(targetIcon)

    targetIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(TOOLTIP_TEXT, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    targetIcon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return targetIcon
end

local function CreateTargetAuraButton()
    local b = CreateFrame("Button", nil, UIParent)
    b:SetSize(TARGET_BUTTON_SIZE, TARGET_BUTTON_SIZE)
    b:SetFrameStrata("MEDIUM")
    b:EnableMouse(true)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)

    -- Matches the radial "wipe" every real buff/debuff button shows for
    -- time remaining, including the faint glow along the swipe edge. The
    -- countdown-number overlay is a separate opt-in Blizzard adds on top of
    -- the swipe itself - real buff/debuff buttons don't show it, so it's
    -- explicitly hidden here to match.
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b)
    b.cooldown:SetDrawEdge(true)
    b.cooldown:SetReverse(true)
    if b.cooldown.SetHideCountdownNumbers then
        b.cooldown:SetHideCountdownNumbers(true)
    end

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        if self.auraIndex and GameTooltip.SetUnitAura then
            GameTooltip:SetUnitAura("target", self.auraIndex, self.auraFilter)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return b
end

local function AcquireTargetButton(i)
    local b = targetButtonPool[i]
    if not b then
        b = CreateTargetAuraButton()
        targetButtonPool[i] = b
    end
    return b
end

local function PositionTargetSlot(button, slotIndex)
    local col = (slotIndex - 1) % TARGET_PER_ROW
    local row = math.floor((slotIndex - 1) / TARGET_PER_ROW)
    button:ClearAllPoints()

    -- TargetFrameBuff1 is only alpha-hidden, never :Hide()'d, so Blizzard
    -- keeps repositioning it every layout pass exactly like the real,
    -- visible buff icon it would otherwise be. Anchoring slot 1 directly to
    -- it (instead of guessing a fixed offset from TargetFrame) means our
    -- grid always lands wherever the native row actually renders, on any
    -- client build, scale, or Edit Mode layout.
    local nativeSlot1 = _G.TargetFrameBuff1
    if nativeSlot1 then
        button:SetPoint("TOPLEFT", nativeSlot1, "TOPLEFT",
            col * (TARGET_BUTTON_SIZE + TARGET_GAP),
            -(row * (TARGET_BUTTON_SIZE + TARGET_GAP)))
    else
        button:SetPoint("TOPLEFT", _G.TargetFrame, "BOTTOMLEFT",
            TARGET_OFFSET_X + (col * (TARGET_BUTTON_SIZE + TARGET_GAP)),
            TARGET_OFFSET_Y - (row * (TARGET_BUTTON_SIZE + TARGET_GAP)))
    end
end

-- TargetFrame.buffs/.debuffs (used above only as an occasional anchor
-- reference by Blizzard's own code) are NOT the real parent of the actual
-- icon buttons - those are individually named and parented directly to
-- TargetFrame itself (TargetFrameBuff1, TargetFrameDebuff1, ...), so they
-- have to be hidden one at a time rather than via a single container alpha.
local function SetNativeTargetAurasHidden(hidden)
    for _, prefix in ipairs({ "TargetFrameBuff", "TargetFrameDebuff" }) do
        local i = 1
        while true do
            local b = _G[prefix .. i]
            if not b then break end
            b:SetAlpha(hidden and 0 or 1)
            b:EnableMouse(not hidden)
            i = i + 1
        end
    end
end

local function IsSelfTargeted()
    return active and UnitExists("target") and UnitIsUnit("target", "player") and _G.TargetFrame ~= nil
end

function HideNativeTargetAurasIfSelfTargeted()
    if IsSelfTargeted() then
        SetNativeTargetAurasHidden(true)
    end
end

local function RefreshTargetIcon()
    local icon = EnsureTargetIcon()

    if not IsSelfTargeted() then
        icon:Hide()
        SetNativeTargetAurasHidden(false)
        for _, b in ipairs(targetButtonPool) do
            b:Hide()
        end
        return
    end

    SetNativeTargetAurasHidden(true)

    icon.texture:SetTexture(Rustcore.GetSelfFoundIconTexture())
    PositionTargetSlot(icon, 1)
    icon:Show()

    local slotIndex = 2
    local usedCount = 0

    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local auraIndex = 1
        while true do
            local name, auraIcon, count, _, duration, expirationTime = UnitAura("target", auraIndex, filter)
            if not name then break end

            usedCount = usedCount + 1
            local b = AcquireTargetButton(usedCount)
            b.auraIndex = auraIndex
            b.auraFilter = filter
            b.icon:SetTexture(auraIcon)
            b.count:SetText((count and count > 1) and tostring(count) or "")
            if duration and duration > 0 and expirationTime then
                b.cooldown:SetCooldown(expirationTime - duration, duration)
                b.cooldown:Show()
            else
                b.cooldown:Hide()
            end
            PositionTargetSlot(b, slotIndex)
            b:Show()

            slotIndex = slotIndex + 1
            auraIndex = auraIndex + 1
        end
    end

    for i = usedCount + 1, #targetButtonPool do
        targetButtonPool[i]:Hide()
    end
end

function RustcoreSelfFoundBuff.Refresh()
    EnsureIconFrame()

    local state = Rustcore.GetSelfFoundIconState and Rustcore.GetSelfFoundIconState()
    active = state == "verified"

    if active then
        iconFrame.texture:SetTexture(Rustcore.GetSelfFoundIconTexture())
        iconFrame:Show()
        pcall(RefreshAuraLayout)
    else
        iconFrame:Hide()
        ShowNativeBuffFrame()
        for _, b in ipairs(buttonPool) do
            b:Hide()
        end
    end

    pcall(RefreshTargetIcon)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- BuffFrame may not have settled yet at this exact point; a short
        -- delay lets Blizzard finish its own first layout pass before we
        -- start reading/hiding it.
        C_Timer.After(0.5, function()
            pcall(RustcoreSelfFoundBuff.Refresh)
        end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(RefreshTargetIcon)
    else
        pcall(RefreshAuraLayout)
        pcall(RefreshTargetIcon)
    end
end)
