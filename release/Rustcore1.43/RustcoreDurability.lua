-- Rustcore: Custom durability HUD
-- Per-slot artwork replaces WoW's native DurabilityFrame when enabled.
-- Normal mode: only shows slots at or below 20% durability.
-- Show-all mode: shows every equipped slot with a durability value.

RustcoreDurability = {}

local BODY_FONT_PATH    -- resolved in Init

-- Frame sizing
local FRAME_W           = 110
local FRAME_H           = 38
local SLOT_GAP          = -2

-- Counter frame overlay art is 1890x558 (native); stretched to FRAME_W at full
-- height it squashes the icon cutout into a tall rectangle, so the overlay is
-- sized to this shorter height (and vertically centered) to keep the cutout square.
local COUNTER_FRAME_H   = 32

-- Counter digit layout — positions as fractions of FRAME_W, all relative to "LEFT"
-- Counter area sits in the right portion of the counter overlay texture.
local COUNTER_CENTER_X  = 0.62    -- center of counter area as fraction of FRAME_W
local DIGIT_SPACING     = 0.148   -- distance between adjacent digit centers (fraction of FRAME_W)
local DIGIT_SLOT_W      = 16      -- pixel width of each clipping digit slot
local DIGIT_FONT_SIZE   = 13
-- Clipping window for animation — only one character tall so the roll looks like
-- a physical counter drum, not a digit flying across the whole frame.
local DIGIT_SLOT_H      = DIGIT_FONT_SIZE + 4

-- Per-digit pixel nudge: { hundreds, tens, ones }
-- Positive = right, negative = left.  Applied on top of the spacing formula.
local DIGIT_NUDGE = { -5, -2, 1 }

local COUNTER_ROLL_DURATION = 0.18  -- seconds per digit roll

-- Low-durability state triggers at 5 points remaining or 20% remaining,
-- whichever the item reaches first (mirrors WoW Classic's own durability frame).
local MIN_DURABILITY_POINTS = 5
local LOW_THRESHOLD_PCT     = 0.20

-- Threshold (as a fraction of max durability) at which the low-durability
-- state triggers for a given item: whichever of "5 points remaining" or
-- "20% remaining" is reached first, i.e. whichever is the larger fraction.
-- Capped below 1.0 to avoid a divide-by-zero in GetDurabilityColor for
-- items with very low max durability.
local function GetLowThresholdPct(maximum)
    if not maximum or maximum <= 0 then return LOW_THRESHOLD_PCT end
    return math.min(0.999, math.max(LOW_THRESHOLD_PCT, MIN_DURABILITY_POINTS / maximum))
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Equipped slots with durability. Slot 15 (Back/Cloak) omitted — no durability.
local SLOT_DATA = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

-- Icon layout constants (sized to fit the new counter frame's icon cutout, ~22px square)
local ICON_IMAGE_SIZE  = 24                       -- item icon image
local ICON_BORDER_SIZE = 40                       -- sizing basis for the rust overlay host
local RUSTED_SIZE      = 27                       -- rustedframe.tga overlay
local RUSTED_INSET     = (ICON_BORDER_SIZE - RUSTED_SIZE) / 2  -- inset from border edges
local ICON_CENTER_X    = 16                       -- icon center from frame LEFT
local ICON_Y_OFFSET    = 0                        -- icon elements vertically centered
local RUSTED_X_OFFSET  = -1                       -- rust overlay x offset
local ICON_INSET       = 0.08                     -- texcoord crop (removes border artifact)

-- Colors are blended toward gray by this much to soften the raw neon RGB mix below.
local COLOR_SATURATION = 0.85

local function Desaturate(r, g, b)
    local gray = (r + g + b) / 3
    return gray + (r - gray) * COLOR_SATURATION,
           gray + (g - gray) * COLOR_SATURATION,
           gray + (b - gray) * COLOR_SATURATION
end

-- Green (100%) → Yellow (at the low-durability threshold) → Red (0%)
local function GetDurabilityColor(current, maximum)
    if maximum == 0 or current == 0 then return Desaturate(1, 0, 0) end
    local pct = math.min(1, current / maximum)
    local threshold = GetLowThresholdPct(maximum)
    if pct >= threshold then
        local t = (pct - threshold) / (1 - threshold)  -- 0 at threshold (yellow) → 1 at full (green)
        return Desaturate(1 - t, 1, 0)
    else
        local t = pct / threshold  -- 1 at threshold (yellow) → 0 at empty (red)
        return Desaturate(1, t, 0)
    end
end

-- ── Rolling digit animation (mirrors RustcoreStats pattern) ───────────────────

-- Animate a single digit slot to a new character with the given colour.
-- slot must have: .oldText, .newText (FontStrings), .currentValue (string|nil)
local function SetCounterDigit(slot, char, r, g, b)
    slot.oldText:SetTextColor(r, g, b)
    slot.newText:SetTextColor(r, g, b)

    if slot.currentValue == nil then
        -- First display: snap immediately, no animation
        slot.currentValue = char
        slot.oldText:SetText(char)
        slot.oldText:ClearAllPoints()
        slot.oldText:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slot.oldText:Show()
        slot.newText:Hide()
        slot:SetScript("OnUpdate", nil)
        return
    end

    if slot.currentValue == char then
        -- Value unchanged, just update colour on the visible text
        return
    end

    -- Roll new digit in from above, old digit out through the bottom
    slot:SetScript("OnUpdate", nil)
    slot.elapsed = 0
    slot.oldText:SetText(slot.currentValue)
    slot.oldText:ClearAllPoints()
    slot.oldText:SetPoint("CENTER", slot, "CENTER", 0, 0)
    slot.newText:SetText(char)
    slot.newText:ClearAllPoints()
    slot.newText:SetPoint("CENTER", slot, "CENTER", 0, slot:GetHeight())
    slot.oldText:Show()
    slot.newText:Show()
    slot.currentValue = char

    slot:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        local progress = Clamp(self.elapsed / COUNTER_ROLL_DURATION, 0, 1)
        local eased = progress * progress * (3 - 2 * progress)  -- smoothstep
        local travel = self:GetHeight()

        self.oldText:ClearAllPoints()
        self.oldText:SetPoint("CENTER", self, "CENTER", 0, -travel * eased)
        self.newText:ClearAllPoints()
        self.newText:SetPoint("CENTER", self, "CENTER", 0, travel * (1 - eased))

        if progress >= 1 then
            self.oldText:SetText(self.currentValue)
            self.oldText:ClearAllPoints()
            self.oldText:SetPoint("CENTER", self, "CENTER", 0, 0)
            self.oldText:Show()
            self.newText:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Set all three counter digit slots to display 'value' (0–100) in the given colour.
-- digits[1]=hundreds, digits[2]=tens, digits[3]=ones.
local function SetCounterDigits(digits, value, r, g, b)
    local str = tostring(math.max(0, math.floor(value)))
    local len = #str
    local chars = {
        len >= 3 and str:sub(-3, -3) or "0",   -- hundreds (always present, pads with 0)
        len >= 2 and str:sub(-2, -2) or "0",   -- tens (always present, pads with 0)
        str:sub(-1),                            -- ones (always present)
    }

    for i = 1, 3 do
        local slot = digits[i]
        if chars[i] then
            slot:Show()
            SetCounterDigit(slot, chars[i], r, g, b)
        else
            -- Digit not needed; hide immediately and reset so next show is clean
            slot:Hide()
            slot:SetScript("OnUpdate", nil)
            slot.currentValue = nil
        end
    end
end

-- ── Frame construction ────────────────────────────────────────────────────────

local hudContainer = nil
local slotEntries  = {}

local function BuildDigitSlot(parent, idx)
    -- idx 1=hundreds, 2=tens, 3=ones
    -- Center X of each slot, measured from frame's LEFT anchor
    local centerX = math.floor(FRAME_W * COUNTER_CENTER_X
                                + (idx - 2) * (FRAME_W * DIGIT_SPACING) + 0.5)
                    + DIGIT_NUDGE[idx]

    local slot = CreateFrame("Frame", nil, parent)
    -- Explicit level keeps digits above the counter frame overlay (set below).
    slot:SetFrameLevel(parent:GetFrameLevel() + 5)
    -- Height = one digit character; SetClipsChildren keeps the roll inside this window.
    slot:SetSize(DIGIT_SLOT_W, DIGIT_SLOT_H)
    slot:SetPoint("CENTER", parent, "LEFT", centerX, 0)
    if slot.SetClipsChildren then slot:SetClipsChildren(true) end
    slot:EnableMouse(false)   -- let drag events fall through to the parent slot frame

    local function MakeText()
        local fs = slot:CreateFontString(nil, "OVERLAY")
        fs:SetFont(BODY_FONT_PATH, DIGIT_FONT_SIZE, "")
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH("CENTER")
        fs:SetJustifyV("MIDDLE")
        fs:SetSize(DIGIT_SLOT_W, DIGIT_SLOT_H)
        fs:SetPoint("CENTER", slot, "CENTER", 0, 0)
        return fs
    end

    slot.oldText = MakeText()
    slot.newText = MakeText()
    slot.newText:Hide()
    slot.currentValue = nil

    slot:Hide()
    return slot
end

local function BuildSlotFrame(parent, slotId)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(FRAME_W, FRAME_H)
    f.slotId = slotId

    -- Black fill behind icon
    local iconBg = f:CreateTexture(nil, "BACKGROUND")
    iconBg:SetSize(ICON_IMAGE_SIZE, ICON_IMAGE_SIZE)
    iconBg:SetPoint("CENTER", f, "LEFT", ICON_CENTER_X, ICON_Y_OFFSET)
    iconBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    iconBg:SetVertexColor(0, 0, 0, 1)

    -- Full-colour item icon (shown at 100% durability, fades to sepia as durability drops)
    local iconTex = f:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(ICON_IMAGE_SIZE, ICON_IMAGE_SIZE)
    iconTex:SetPoint("CENTER", f, "LEFT", ICON_CENTER_X, ICON_Y_OFFSET)
    iconTex:SetTexCoord(ICON_INSET, 1 - ICON_INSET, ICON_INSET, 1 - ICON_INSET)

    -- Sepia overlay (snaps to full alpha once the low-durability threshold is reached)
    local sepiaTex = f:CreateTexture(nil, "OVERLAY")
    sepiaTex:SetSize(ICON_IMAGE_SIZE, ICON_IMAGE_SIZE)
    sepiaTex:SetPoint("CENTER", f, "LEFT", ICON_CENTER_X, ICON_Y_OFFSET)
    sepiaTex:SetTexCoord(ICON_INSET, 1 - ICON_INSET, ICON_INSET, 1 - ICON_INSET)
    sepiaTex:SetDesaturation(1)
    sepiaTex:SetVertexColor(1.0, 0.5, 0.2, 0)   -- starts invisible

    -- Slight shadow over the icon so it reads as sitting in the frame, not pasted on top
    local shadowTex = f:CreateTexture(nil, "OVERLAY")
    shadowTex:SetSize(ICON_IMAGE_SIZE, ICON_IMAGE_SIZE)
    shadowTex:SetPoint("CENTER", f, "LEFT", ICON_CENTER_X, ICON_Y_OFFSET)
    shadowTex:SetColorTexture(0, 0, 0, 0.20)

    -- Rusted frame overlay: wipes top-down from the low-durability threshold to 0% durability
    local rustedHost = CreateFrame("Frame", nil, f)
    rustedHost:SetSize(ICON_BORDER_SIZE, ICON_BORDER_SIZE)
    rustedHost:SetPoint("CENTER", f, "LEFT", ICON_CENTER_X, ICON_Y_OFFSET)
    rustedHost:SetFrameLevel(f:GetFrameLevel() + 3)
    rustedHost:EnableMouse(false)
    local rustedTex = rustedHost:CreateTexture(nil, "OVERLAY")
    rustedTex:SetWidth(RUSTED_SIZE)
    rustedTex:SetHeight(0)
    rustedTex:SetPoint("TOPLEFT", rustedHost, "TOPLEFT", RUSTED_INSET + RUSTED_X_OFFSET, -RUSTED_INSET)
    rustedTex:SetTexture(Rustcore.GetAssetPath("UI/rustedframe.tga"))
    rustedTex:SetTexCoord(0, 1, 0, 0)

    -- Counter frame overlay: has a cutout window over the icon, so it must draw
    -- above the icon/border/rust layers (not just above the icon's own textures).
    local overlayHost = CreateFrame("Frame", nil, f)
    overlayHost:SetSize(FRAME_W, COUNTER_FRAME_H)
    overlayHost:SetPoint("CENTER", f, "CENTER", 0, 0)
    overlayHost:SetFrameLevel(f:GetFrameLevel() + 4)
    overlayHost:EnableMouse(false)
    local overlayTex = overlayHost:CreateTexture(nil, "OVERLAY")
    overlayTex:SetAllPoints(overlayHost)
    overlayTex:SetTexture(Rustcore.GetAssetPath("UI/durability counter frame copy.tga"))

    -- Digit slots (child frames, draw above all textures automatically)
    local digits = {}
    for i = 1, 3 do
        digits[i] = BuildDigitSlot(f, i)
    end

    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() hudContainer:StartMoving() end)
    f:SetScript("OnDragStop", function()
        hudContainer:StopMovingOrSizing()
        local point, _, relPoint, x, y = hudContainer:GetPoint()
        Rustcore.SetProfileValue("durHUDPos", { point = point, relPoint = relPoint, x = x, y = y })
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetInventoryItem("player", self.slotId)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.iconTex   = iconTex
    f.sepiaTex  = sepiaTex
    f.rustedTex = rustedTex
    f.digits    = digits
    f:Hide()
    return f
end

local function BuildHUD()
    if hudContainer then return end

    BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")

    local f = CreateFrame("Frame", "RustcoreDurabilityHUD", UIParent)
    f:SetSize(FRAME_W, 10)
    f:SetFrameStrata("LOW")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        Rustcore.SetProfileValue("durHUDPos", { point = point, relPoint = relPoint, x = x, y = y })
    end)

    local p = Rustcore.GetProfileValue("durHUDPos")
    if p then
        f:SetPoint(p.point or "TOPRIGHT", UIParent, p.relPoint or "TOPRIGHT", p.x or -180, p.y or -120)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -180, -120)
    end

    f:Hide()

    slotEntries = {}
    for _, slot in ipairs(SLOT_DATA) do
        local sf = BuildSlotFrame(f, slot)
        slotEntries[#slotEntries + 1] = { slot = slot, frame = sf }
    end

    hudContainer = f
end

-- ── HUD update ────────────────────────────────────────────────────────────────

local function UpdateHUD()
    if not hudContainer then return end

    local showHUD = Rustcore.GetSetting("showDurabilityHUD")
    if not showHUD then
        hudContainer:Hide()
        return
    end

    local showAll      = Rustcore.GetSetting("showAllDurability")
    local visibleSlots = {}

    for _, entry in ipairs(slotEntries) do
        local slot    = entry.slot
        local link    = GetInventoryItemLink("player", slot)
        local visible = false
        local pct     = 1  -- default for sort; overwritten when durability is read

        if link then
            local current, maximum = GetInventoryItemDurability(slot)
            if current ~= nil and maximum ~= nil and maximum > 0 then
                pct = current / maximum
                local threshold = GetLowThresholdPct(maximum)
                if showAll or pct <= threshold then
                    local itemTex = GetInventoryItemTexture("player", slot)
                    local fallback = "Interface\\Icons\\INV_Misc_QuestionMark"
                    entry.frame.iconTex:SetTexture(itemTex or fallback)
                    entry.frame.sepiaTex:SetTexture(itemTex or fallback)

                    -- Sepia snaps fully desaturated the instant the item enters the
                    -- low-durability zone; rust is what ramps from there to 0.
                    local sepiaAlpha = (pct <= threshold) and 1.0 or 0.0
                    entry.frame.sepiaTex:SetVertexColor(1.0, 0.5, 0.2, sepiaAlpha)

                    -- Rusted wipe: 0 coverage at the threshold → full at 0%
                    local rustedFrac = Clamp(
                        (threshold - pct) / threshold, 0, 1)
                    entry.frame.rustedTex:SetHeight(RUSTED_SIZE * rustedFrac)
                    entry.frame.rustedTex:SetTexCoord(0, 1, 0, rustedFrac)

                    local r, g, b = GetDurabilityColor(current, maximum)
                    SetCounterDigits(entry.frame.digits, current, r, g, b)
                    visible = true
                end
            end
        end

        if not visible then
            for _, d in ipairs(entry.frame.digits) do
                d:Hide()
                d:SetScript("OnUpdate", nil)
                d.currentValue = nil
            end
            entry.frame.sepiaTex:SetVertexColor(1.0, 0.5, 0.2, 0)
            entry.frame.rustedTex:SetHeight(0)
            entry.frame.rustedTex:SetTexCoord(0, 1, 0, 0)
        end

        entry.frame:SetShown(visible)
        if visible then
            visibleSlots[#visibleSlots + 1] = { frame = entry.frame, pct = pct }
        end
    end

    if #visibleSlots > 0 then
        -- Sort least durable first (top) → most durable last (bottom)
        table.sort(visibleSlots, function(a, b) return a.pct < b.pct end)

        local totalH = #visibleSlots * FRAME_H + (#visibleSlots - 1) * SLOT_GAP
        hudContainer:SetHeight(totalH)
        local yOff = 0
        for _, entry in ipairs(visibleSlots) do
            local sf = entry.frame
            sf:ClearAllPoints()
            sf:SetPoint("TOPLEFT", hudContainer, "TOPLEFT", 0, yOff)
            yOff = yOff - FRAME_H - SLOT_GAP
        end
        hudContainer:Show()
        if DurabilityFrame then DurabilityFrame:Hide() end
    else
        hudContainer:Hide()
    end
end

-- ── Native DurabilityFrame suppression ───────────────────────────────────────

local function HookNativeDurabilityFrame()
    if not DurabilityFrame then return end
    DurabilityFrame:HookScript("OnShow", function(self)
        if Rustcore.GetSetting("showDurabilityHUD") then
            self:Hide()
        end
    end)
end

-- ── Event handling ────────────────────────────────────────────────────────────

local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
evFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    -- Deferred one frame: GetInventoryItemDurability can still report the
    -- previous item's value in the same tick the inventory-changed event
    -- fires, before the client's local item cache has caught up.
    if hudContainer then C_Timer.After(0, UpdateHUD) end
end)

-- ── Public API ────────────────────────────────────────────────────────────────

function RustcoreDurability.Init()
    BuildHUD()
    HookNativeDurabilityFrame()
    UpdateHUD()
end

function RustcoreDurability.Refresh()
    UpdateHUD()
end

function RustcoreDurability.RefreshPosition()
    if not hudContainer then return end
    hudContainer:ClearAllPoints()
    local p = Rustcore.GetProfileValue("durHUDPos")
    if p then
        hudContainer:SetPoint(p.point or "TOPRIGHT", UIParent, p.relPoint or "TOPRIGHT", p.x or -180, p.y or -120)
    else
        hudContainer:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -180, -120)
    end
end
