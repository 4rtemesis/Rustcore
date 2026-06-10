-- Rustcore: minimal item loss stats window

RustcoreStats = {}

local statsFrame
local eventFrame
local initialized = false
local scanning = false
local GetSlotStateKey

local GEAR_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18 }
local BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 390, 170
local MIN_WIDTH, MIN_HEIGHT = 200, 125
local MAX_WIDTH, MAX_HEIGHT = 680, 300
local BACKGROUND_REF_WIDTH, BACKGROUND_REF_HEIGHT = 544, 548
local BACKGROUND_ALPHA = 0.78
local CORNER_SIZE = 14
local TEXT_PAD = 10
local BEST_ITEM_SIDE_PAD = 16
local COLUMN_GAP = 4
local ROW_GAP = 2
local SELF_FOUND_CELL_RATIO = 0.60
local COUNTER_REF_WIDTH, COUNTER_REF_HEIGHT = 416, 210
local COUNTER_DIGIT_SPACING = 0.235
local COUNTER_MIDDLE_DIGIT_NUDGE = 1
local COUNTER_RIGHT_DIGIT_OFFSET = 0.012
local COUNTER_RIGHT_DIGIT_NUDGE = 1
local COUNTER_DIGIT_Y = -0.01
local COUNTER_ROLL_DURATION = 0.20
local ITEM_FRAME_REF_WIDTH, ITEM_FRAME_REF_HEIGHT = 846, 190
local ITEM_LINK_WIDTH_RATIO = 0.80
local LABEL_COLOR = { 1, 0.82, 0 }
local VALUE_COLOR = { 1, 1, 1 }
local COUNTER_VALUE_COLOR = { 0.035, 0.03, 0.025 }
local SELF_FOUND_TOOLTIP = "Verified Self Found Character"
local RESIZE_TOOLTIP = "Left click and drag to adjust. Right click to auto adjust."

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function FormatCounterValue(value)
    value = math.floor(Clamp(tonumber(value) or 0, 0, 999))
    return string.format("%03d", value)
end

local function SetCounterDigit(slot, value)
    if slot.currentValue == nil then
        slot.currentValue = value
        slot.oldText:SetText(value)
        slot.oldText:Show()
        slot.newText:Hide()
        return
    end
    if slot.currentValue == value then return end

    slot:SetScript("OnUpdate", nil)
    slot.oldText:SetText(slot.currentValue)
    slot.currentValue = value
    slot.elapsed = 0
    slot.oldText:ClearAllPoints()
    slot.oldText:SetPoint("CENTER", slot, "CENTER", 0, 0)
    slot.newText:SetText(value)
    slot.newText:ClearAllPoints()
    slot.newText:SetPoint("CENTER", slot, "CENTER", 0, slot:GetHeight())
    slot.oldText:Show()
    slot.newText:Show()
    slot:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        local progress = Clamp(self.elapsed / COUNTER_ROLL_DURATION, 0, 1)
        local eased = progress * progress * (3 - (2 * progress))
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

local function SetCounterDigits(digits, value)
    local text = FormatCounterValue(value)
    for i = 1, 3 do
        SetCounterDigit(digits[i], text:sub(i, i))
    end
end

local function EnsureStatsDB()
    RustcoreDB.characterStats = RustcoreDB.characterStats or {}
    local key = Rustcore.GetCharacterKey and Rustcore.GetCharacterKey() or UnitName("player") or "player"
    RustcoreDB.characterStats[key] = RustcoreDB.characterStats[key] or {}
    local stats = RustcoreDB.characterStats[key]
    stats.destroyedItems = stats.destroyedItems or 0
    stats.rustedItems = stats.rustedItems or 0
    stats.bestItemLostLink = stats.bestItemLostLink or nil
    stats.bestItemLostIlvl = stats.bestItemLostIlvl or 0
    stats.zeroDurabilitySlots = stats.zeroDurabilitySlots or {}
    stats.rustedItemKeys = stats.rustedItemKeys or {}
    return stats
end

local function GetCounterVisibility()
    local stats = EnsureStatsDB()
    local showRusted = (stats.rustedItems or 0) > 0 or not Rustcore.GetSetting("allowRepair")
    local showDestroyed = (stats.destroyedItems or 0) > 0 or Rustcore.GetSetting("difficulty") ~= 1
    return showRusted, showDestroyed
end

local function GetItemIlvl(item)
    if not item or not item.link then return 0 end
    return item.ilvl or select(4, GetItemInfo(item.link)) or 0
end

local function UpdateBestItem(item)
    if not item or not item.link then return end
    local stats = EnsureStatsDB()
    local ilvl = GetItemIlvl(item)
    if ilvl >= (stats.bestItemLostIlvl or 0) then
        stats.bestItemLostIlvl = ilvl
        stats.bestItemLostLink = item.link
    end
end

local function RefreshText()
    if not statsFrame then return end
    local stats = EnsureStatsDB()
    statsFrame.destroyedLabel:SetText("Broken")
    SetCounterDigits(statsFrame.destroyedDigits, stats.destroyedItems)
    statsFrame.rustedLabel:SetText("Rusted")
    SetCounterDigits(statsFrame.rustedDigits, stats.rustedItems)
    statsFrame.bestLabel:SetText("Best item lost")
    statsFrame.bestValue:SetText(stats.bestItemLostLink or "None")
    if stats.bestItemLostLink then
        statsFrame.bestHitbox:Show()
    else
        statsFrame.bestHitbox:Hide()
    end
    RustcoreStats.RefreshSelfFoundIcon()
    RustcoreStats.RefreshLayout()
end

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    RustcoreDB.statsWindowPoint = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function ApplySavedPosition(frame)
    frame:ClearAllPoints()
    local pos = RustcoreDB.statsWindowPoint
    if pos and pos.point and pos.relativePoint and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function SaveSize(frame)
    local width, height = frame:GetSize()
    RustcoreDB.statsWindowSize = {
        width = width,
        height = height,
    }
end

local function ApplySavedSize(frame)
    local size = RustcoreDB.statsWindowSize
    local width = size and tonumber(size.width) or DEFAULT_WIDTH
    local height = size and tonumber(size.height) or DEFAULT_HEIGHT
    frame:SetSize(
        Clamp(width, MIN_WIDTH, MAX_WIDTH),
        Clamp(height, MIN_HEIGHT, MAX_HEIGHT)
    )
end

local function ApplyBodyFont(fontString, size)
    if fontString then
        fontString:SetFont(BODY_FONT_PATH, size or 15, "")
    end
end

function RustcoreStats.RefreshLayout()
    if not statsFrame then return end
    local width, height = statsFrame:GetSize()
    local pad = TEXT_PAD
    local contentWidth = math.max(1, width - (pad * 2))
    local bestContentWidth = math.max(1, width - (BEST_ITEM_SIDE_PAD * 2))
    local contentHeight = math.max(1, height - (pad * 2))
    local rowHeight = (contentHeight - ROW_GAP) / 2
    local showRusted, showDestroyed = GetCounterVisibility()
    local showSelfFound = statsFrame.selfFoundIcon and statsFrame.selfFoundIcon:IsShown()
    local visibleCounterCount = (showRusted and 1 or 0) + (showDestroyed and 1 or 0)
    local counterCellWidth
    local selfFoundCellWidth
    if visibleCounterCount == 2 and showSelfFound then
        counterCellWidth = (contentWidth - (COLUMN_GAP * 2)) / (2 + SELF_FOUND_CELL_RATIO)
        selfFoundCellWidth = counterCellWidth * SELF_FOUND_CELL_RATIO
    elseif visibleCounterCount == 2 then
        counterCellWidth = (contentWidth - COLUMN_GAP) / 2
        selfFoundCellWidth = 0
    elseif visibleCounterCount == 1 then
        counterCellWidth = showSelfFound
            and math.min(
                (contentWidth - COLUMN_GAP) / (1 + SELF_FOUND_CELL_RATIO),
                rowHeight * 1.33
            )
            or contentWidth
        selfFoundCellWidth = showSelfFound
            and math.min(counterCellWidth * SELF_FOUND_CELL_RATIO, 72)
            or 0
    else
        counterCellWidth = contentWidth
        selfFoundCellWidth = showSelfFound and math.min(contentWidth, 72) or 0
    end
    local labelSize = Clamp(math.floor(rowHeight * 0.17), 11, 17)
    local counterWidth = math.min(counterCellWidth, rowHeight * 1.33)
    local counterHeight = counterWidth * (COUNTER_REF_HEIGHT / COUNTER_REF_WIDTH)
    local elementGap = 2
    local counterTopOffset = labelSize + elementGap
    local digitSize = Clamp(math.floor(counterHeight * 0.34), 12, 25)
    local bestLabelSize = Clamp(math.floor(rowHeight * 0.19), 11, 17)
    local bestFrameMaxHeight = math.max(1, rowHeight - bestLabelSize - elementGap)
    local bestFrameWidth = math.min(
        bestContentWidth,
        bestFrameMaxHeight * (ITEM_FRAME_REF_WIDTH / ITEM_FRAME_REF_HEIGHT)
    )
    local bestFrameHeight = bestFrameWidth * (ITEM_FRAME_REF_HEIGHT / ITEM_FRAME_REF_WIDTH)
    local bestValueSize = Clamp(math.floor(bestFrameHeight * 0.22) + 1, 11, 19)
    local iconSize = Clamp(math.floor(math.min(
        selfFoundCellWidth,
        rowHeight - labelSize - elementGap,
        counterHeight
    )), 1, 72)

    ApplyBodyFont(statsFrame.destroyedLabel, labelSize)
    ApplyBodyFont(statsFrame.rustedLabel, labelSize)
    ApplyBodyFont(statsFrame.selfFoundLabel, labelSize)
    ApplyBodyFont(statsFrame.bestLabel, bestLabelSize)
    ApplyBodyFont(statsFrame.bestValue, bestValueSize)
    for i = 1, 3 do
        ApplyBodyFont(statsFrame.rustedDigits[i].oldText, digitSize)
        ApplyBodyFont(statsFrame.rustedDigits[i].newText, digitSize)
        ApplyBodyFont(statsFrame.destroyedDigits[i].oldText, digitSize)
        ApplyBodyFont(statsFrame.destroyedDigits[i].newText, digitSize)
    end

    local topY = -pad
    local bottomY = -pad - rowHeight - ROW_GAP
    local rustedCenterX
    local destroyedCenterX
    local selfFoundCenterX = width * 0.5
    if visibleCounterCount == 2 then
        rustedCenterX = pad + (counterCellWidth * 0.5)
        destroyedCenterX = pad + counterCellWidth + COLUMN_GAP + (counterCellWidth * 0.5)
        if showSelfFound then
            selfFoundCenterX = pad + (counterCellWidth * 2) + (COLUMN_GAP * 2) + (selfFoundCellWidth * 0.5)
        end
    elseif visibleCounterCount == 1 then
        local groupWidth = counterCellWidth
        if showSelfFound then
            groupWidth = groupWidth + COLUMN_GAP + selfFoundCellWidth
        end
        local groupLeft = (width - groupWidth) * 0.5
        local counterCenterX = groupLeft + (counterCellWidth * 0.5)
        rustedCenterX = counterCenterX
        destroyedCenterX = counterCenterX
        if showSelfFound then
            selfFoundCenterX = groupLeft + counterCellWidth + COLUMN_GAP + (selfFoundCellWidth * 0.5)
        end
    elseif showSelfFound then
        selfFoundCenterX = width * 0.5
    end

    statsFrame.rustedLabel:ClearAllPoints()
    statsFrame.rustedLabel:SetPoint("TOP", statsFrame, "TOPLEFT", rustedCenterX or (width * 0.5), topY)
    statsFrame.rustedLabel:SetWidth(counterCellWidth)
    statsFrame.rustedLabel:SetShown(showRusted)
    statsFrame.rustedCounter:SetShown(showRusted)

    statsFrame.destroyedLabel:ClearAllPoints()
    statsFrame.destroyedLabel:SetPoint("TOP", statsFrame, "TOPLEFT", destroyedCenterX or (width * 0.5), topY)
    statsFrame.destroyedLabel:SetWidth(counterCellWidth)
    statsFrame.destroyedLabel:SetShown(showDestroyed)
    statsFrame.destroyedCounter:SetShown(showDestroyed)

    local function PositionCounter(counter, digits, centerX)
        counter:SetSize(counterWidth, counterHeight)
        counter:ClearAllPoints()
        counter:SetPoint("TOP", statsFrame, "TOPLEFT", centerX, topY - counterTopOffset)
        counter.texture:SetAllPoints(counter)
        for i = 1, 3 do
            local slot = digits[i]
            local digitX = (i - 2) * counterWidth * COUNTER_DIGIT_SPACING
            if i == 2 then
                digitX = digitX + COUNTER_MIDDLE_DIGIT_NUDGE
            elseif i == 3 then
                digitX = digitX + (counterWidth * COUNTER_RIGHT_DIGIT_OFFSET) + COUNTER_RIGHT_DIGIT_NUDGE
            end
            slot:ClearAllPoints()
            slot:SetPoint(
                "CENTER",
                counter,
                "CENTER",
                digitX,
                counterHeight * COUNTER_DIGIT_Y
            )
            slot:SetSize(counterWidth * 0.18, digitSize + 4)
            slot.oldText:SetSize(counterWidth * 0.18, digitSize + 4)
            slot.newText:SetSize(counterWidth * 0.18, digitSize + 4)
        end
    end

    if showRusted then
        PositionCounter(statsFrame.rustedCounter, statsFrame.rustedDigits, rustedCenterX)
    end
    if showDestroyed then
        PositionCounter(statsFrame.destroyedCounter, statsFrame.destroyedDigits, destroyedCenterX)
    end

    if statsFrame.selfFoundLabel then
        statsFrame.selfFoundLabel:ClearAllPoints()
        statsFrame.selfFoundLabel:SetPoint("TOP", statsFrame, "TOPLEFT", selfFoundCenterX, topY)
        statsFrame.selfFoundLabel:SetWidth(selfFoundCellWidth)
    end
    if statsFrame.selfFoundIcon then
        statsFrame.selfFoundIcon:SetSize(iconSize, iconSize)
        statsFrame.selfFoundIcon:ClearAllPoints()
        statsFrame.selfFoundIcon:SetPoint("TOP", statsFrame.selfFoundLabel, "BOTTOM", 0, -elementGap)
    end

    statsFrame.bestLabel:ClearAllPoints()
    statsFrame.bestLabel:SetPoint("TOP", statsFrame, "TOPLEFT", width * 0.5, bottomY)
    statsFrame.bestLabel:SetWidth(bestContentWidth)

    statsFrame.itemLostFrame:SetSize(bestFrameWidth, bestFrameHeight)
    statsFrame.itemLostFrame:ClearAllPoints()
    statsFrame.itemLostFrame:SetPoint("TOP", statsFrame.bestLabel, "BOTTOM", 0, -elementGap)
    statsFrame.itemLostFrame.texture:SetAllPoints(statsFrame.itemLostFrame)

    statsFrame.bestValue:ClearAllPoints()
    statsFrame.bestValue:SetPoint("CENTER", statsFrame.itemLostFrame, "CENTER", 0, 0)
    statsFrame.bestValue:SetWidth(bestFrameWidth * ITEM_LINK_WIDTH_RATIO)

    statsFrame.bestHitbox:ClearAllPoints()
    statsFrame.bestHitbox:SetPoint("CENTER", statsFrame.bestValue, "CENTER", 0, 0)
    statsFrame.bestHitbox:SetSize(math.max(1, statsFrame.bestValue:GetStringWidth() or 0), bestValueSize + 8)

    local backgroundWidth = math.max(BACKGROUND_REF_WIDTH, width)
    local backgroundHeight = math.max(BACKGROUND_REF_HEIGHT, height)
    if statsFrame.background then
        statsFrame.background:SetTexCoord(0, 1, 0, 1)
        statsFrame.background:SetSize(backgroundWidth, backgroundHeight)
    end
    if statsFrame.backgroundClip then
        statsFrame.backgroundClip:SetSize(math.max(1, width), math.max(1, height))
    end
    if statsFrame.backgroundScrollChild then
        statsFrame.backgroundScrollChild:SetSize(backgroundWidth, backgroundHeight)
    end
end

local function GetAutoFitWidth()
    if not statsFrame then return DEFAULT_WIDTH end
    RustcoreStats.RefreshLayout()

    local showRusted, showDestroyed = GetCounterVisibility()
    local showSelfFound = statsFrame.selfFoundIcon and statsFrame.selfFoundIcon:IsShown()
    local visibleCounterCount = (showRusted and 1 or 0) + (showDestroyed and 1 or 0)
    local counterCellWidth = math.max(
        68,
        showRusted and (statsFrame.rustedLabel:GetStringWidth() or 0) or 0,
        showDestroyed and (statsFrame.destroyedLabel:GetStringWidth() or 0) or 0
    )
    if showSelfFound and visibleCounterCount == 2 then
        counterCellWidth = math.max(
            counterCellWidth,
            (statsFrame.selfFoundLabel:GetStringWidth() or 0) / SELF_FOUND_CELL_RATIO,
            44 / SELF_FOUND_CELL_RATIO
        )
    end

    local topWidth
    if visibleCounterCount == 2 and showSelfFound then
        topWidth = (counterCellWidth * (2 + SELF_FOUND_CELL_RATIO)) + (COLUMN_GAP * 2)
    elseif visibleCounterCount == 2 then
        topWidth = (counterCellWidth * 2) + COLUMN_GAP
    elseif visibleCounterCount == 1 and showSelfFound then
        topWidth = counterCellWidth + COLUMN_GAP + 44
    elseif visibleCounterCount == 1 then
        topWidth = counterCellWidth
    elseif showSelfFound then
        topWidth = 44
    else
        topWidth = 0
    end
    local bestLabelWidth = statsFrame.bestLabel:GetStringWidth() or 0
    local bestValueWidth = statsFrame.bestValue:GetStringWidth() or 0
    local bottomWidth = math.max(140, bestLabelWidth, bestValueWidth / ITEM_LINK_WIDTH_RATIO)
    local requiredTopWidth = topWidth + (TEXT_PAD * 2)
    local requiredBottomWidth = bottomWidth + (BEST_ITEM_SIDE_PAD * 2)
    return Clamp(math.ceil(math.max(requiredTopWidth, requiredBottomWidth)), MIN_WIDTH, MAX_WIDTH)
end

local function AutoFitWidth(frame)
    frame:SetWidth(GetAutoFitWidth())
    SaveSize(frame)
    RustcoreStats.RefreshLayout()
end

local function BuildStatsFrame()
    local f = CreateFrame("Frame", "RustcoreStatsFrame", UIParent)
    ApplySavedSize(f)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    if f.SetResizable then f:SetResizable(true) end
    f:EnableMouse(true)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    elseif f.SetMinResize and f.SetMaxResize then
        f:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
        f:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
    end

    local bgClip = CreateFrame("ScrollFrame", nil, f)
    bgClip:SetAllPoints(f)
    bgClip:EnableMouse(false)
    bgClip:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))

    local bgChild = CreateFrame("Frame", nil, bgClip)
    bgChild:SetSize(BACKGROUND_REF_WIDTH, BACKGROUND_REF_HEIGHT)
    bgClip:SetScrollChild(bgChild)

    local bg = bgChild:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", bgChild, "TOPLEFT", 0, 0)
    bg:SetSize(BACKGROUND_REF_WIDTH, BACKGROUND_REF_HEIGHT)
    bg:SetTexture(Rustcore.GetAssetPath("UI/background" .. Rustcore.GetSetting("difficulty") .. " copy.tga"))
    bg:SetAlpha(BACKGROUND_ALPHA)

    local shade = f:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints(f)
    shade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shade:SetVertexColor(0, 0, 0, 0.10)

    local function CreateCorner(point, textureName, xOff, yOff)
        local corner = f:CreateTexture(nil, "ARTWORK")
        corner:SetTexture(Rustcore.GetAssetPath("UI/" .. textureName))
        corner:SetSize(CORNER_SIZE, CORNER_SIZE)
        corner:SetPoint(point, f, point, xOff, yOff)
        corner:SetTexCoord(0, 1, 0, 1)
        corner:SetAlpha(BACKGROUND_ALPHA)
        return corner
    end

    CreateCorner("TOPLEFT", "NutcornerUL.tga", 3, -3)
    CreateCorner("TOPRIGHT", "NutcornerUR.tga", -3, -3)
    CreateCorner("BOTTOMLEFT", "NutcornerUR.tga", 3, 3)
    CreateCorner("BOTTOMRIGHT", "NutcornerUL.tga", -3, 3)

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f:SetScript("OnSizeChanged", function()
        RustcoreStats.RefreshLayout()
    end)

    local textLayer = CreateFrame("Frame", nil, f)
    textLayer:SetAllPoints(f)
    textLayer:SetFrameLevel(f:GetFrameLevel() + 3)

    local function CreateStatsText(color, parent)
        local text = (parent or textLayer):CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetJustifyH("CENTER")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(false)
        text:SetTextColor(unpack(color))
        text:SetAlpha(1)
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        ApplyBodyFont(text)
        return text
    end

    local destroyedLabel = CreateStatsText(LABEL_COLOR)
    local rustedLabel = CreateStatsText(LABEL_COLOR)
    local selfFoundLabel = CreateStatsText(LABEL_COLOR)
    selfFoundLabel:SetText("SF")
    selfFoundLabel:Hide()
    local bestLabel = CreateStatsText(LABEL_COLOR)

    local function CreateArtFrame(texturePath)
        local frame = CreateFrame("Frame", nil, textLayer)
        frame.texture = frame:CreateTexture(nil, "ARTWORK")
        frame.texture:SetAllPoints(frame)
        frame.texture:SetTexture(Rustcore.GetAssetPath(texturePath))
        frame.texture:SetTexCoord(0, 1, 0, 1)
        return frame
    end

    local function CreateCounter()
        local counter = CreateArtFrame("UI/Counter frame.tga")
        local digits = {}
        for i = 1, 3 do
            local slot = CreateFrame("Frame", nil, counter)
            if slot.SetClipsChildren then
                slot:SetClipsChildren(true)
            end
            slot.oldText = CreateStatsText(COUNTER_VALUE_COLOR, slot)
            slot.newText = CreateStatsText(COUNTER_VALUE_COLOR, slot)
            slot.oldText:SetDrawLayer("OVERLAY", 1)
            slot.newText:SetDrawLayer("OVERLAY", 1)
            slot.oldText:SetShadowColor(0, 0, 0, 0)
            slot.newText:SetShadowColor(0, 0, 0, 0)
            slot.oldText:SetShadowOffset(0, 0)
            slot.newText:SetShadowOffset(0, 0)
            slot.oldText:SetPoint("CENTER", slot, "CENTER", 0, 0)
            slot.newText:SetPoint("CENTER", slot, "CENTER", 0, 0)
            slot.newText:Hide()
            digits[i] = slot
        end
        return counter, digits
    end

    local rustedCounter, rustedDigits = CreateCounter()
    local destroyedCounter, destroyedDigits = CreateCounter()
    local itemLostFrame = CreateArtFrame("UI/Lostitemframe.tga")
    local bestValue = CreateStatsText(VALUE_COLOR, itemLostFrame)

    local bestHitbox = CreateFrame("Frame", nil, itemLostFrame)
    bestHitbox:EnableMouse(true)
    bestHitbox:SetScript("OnEnter", function(self)
        local link = EnsureStatsDB().bestItemLostLink
        if not link then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, -32)
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    bestHitbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local selfFoundIcon = CreateFrame("Frame", nil, textLayer)
    selfFoundIcon:EnableMouse(true)
    selfFoundIcon.texture = selfFoundIcon:CreateTexture(nil, "ARTWORK")
    selfFoundIcon.texture:SetAllPoints(selfFoundIcon)
    selfFoundIcon.texture:SetTexture(Rustcore.GetAssetPath("UI/Rustcore Selffound copy.tga"))
    selfFoundIcon.tooltipText = SELF_FOUND_TOOLTIP
    selfFoundIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, -32)
        GameTooltip:SetText(self.tooltipText or SELF_FOUND_TOOLTIP, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    selfFoundIcon:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    selfFoundIcon:Hide()

    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetFrameLevel(f:GetFrameLevel() + 4)
    resizeGrip:RegisterForClicks("LeftButtonDown", "RightButtonUp")
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:Hide()
    resizeGrip:SetScript("OnEnter", function(self)
        self:Show()
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, -32)
        GameTooltip:SetText(RESIZE_TOOLTIP, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self.resizing = true
        self:Show()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            AutoFitWidth(f)
            return
        end
        if button ~= "LeftButton" then return end
        self.resizing = false
        f:StopMovingOrSizing()
        SaveSize(f)
        RustcoreStats.RefreshLayout()
        if not self.IsMouseOver or not self:IsMouseOver() then self:Hide() end
    end)
    resizeGrip:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not self.resizing then self:Hide() end
    end)

    local resizeHotspot = CreateFrame("Frame", nil, f)
    resizeHotspot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    resizeHotspot:SetSize(24, 24)
    resizeHotspot:SetFrameLevel(f:GetFrameLevel() + 3)
    resizeHotspot:EnableMouse(true)
    resizeHotspot:SetScript("OnEnter", function(self)
        resizeGrip:Show()
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, -32)
        GameTooltip:SetText(RESIZE_TOOLTIP, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    resizeHotspot:SetScript("OnLeave", function()
        GameTooltip:Hide()
        C_Timer.After(0, function()
            if not resizeGrip.resizing and (not resizeGrip.IsMouseOver or not resizeGrip:IsMouseOver()) then
                resizeGrip:Hide()
            end
        end)
    end)
    resizeHotspot:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            AutoFitWidth(f)
            return
        end
        if button ~= "LeftButton" then return end
        resizeGrip.resizing = true
        resizeGrip:Show()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeHotspot:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then return end
        if button ~= "LeftButton" then return end
        resizeGrip.resizing = false
        f:StopMovingOrSizing()
        SaveSize(f)
        RustcoreStats.RefreshLayout()
        if not resizeGrip.IsMouseOver or not resizeGrip:IsMouseOver() then resizeGrip:Hide() end
    end)

    f.destroyedLabel = destroyedLabel
    f.rustedLabel = rustedLabel
    f.destroyedCounter = destroyedCounter
    f.destroyedDigits = destroyedDigits
    f.rustedCounter = rustedCounter
    f.rustedDigits = rustedDigits
    f.selfFoundLabel = selfFoundLabel
    f.bestLabel = bestLabel
    f.bestValue = bestValue
    f.itemLostFrame = itemLostFrame
    f.bestHitbox = bestHitbox
    f.selfFoundIcon = selfFoundIcon
    f.backgroundClip = bgClip
    f.backgroundScrollChild = bgChild
    f.background = bg
    f.resizeGrip = resizeGrip
    ApplySavedPosition(f)
    RefreshText()
    f:Hide()
    return f
end

local function EnsureFrame()
    if not statsFrame then
        statsFrame = BuildStatsFrame()
    end
    return statsFrame
end

function RustcoreStats.ApplyVisibility()
    local frame = EnsureFrame()
    RefreshText()
    if Rustcore.GetSetting("showStatsWindow") then
        RustcoreStats.RefreshStyle()
        frame:Show()
    else
        frame:Hide()
    end
end

function RustcoreStats.RefreshStyle()
    if statsFrame and statsFrame.background then
        statsFrame.background:SetTexture(Rustcore.GetAssetPath("UI/background" .. Rustcore.GetSetting("difficulty") .. " copy.tga"))
    end
end

function RustcoreStats.RefreshSelfFoundIcon()
    if not statsFrame or not statsFrame.selfFoundIcon then return end
    if not Rustcore.GetSelfFoundIconState then
        statsFrame.selfFoundIcon:Hide()
        statsFrame.selfFoundLabel:Hide()
        RustcoreStats.RefreshLayout()
        return
    end

    local state = Rustcore.GetSelfFoundIconState()
    if state == "verified" then
        statsFrame.selfFoundIcon.tooltipText = SELF_FOUND_TOOLTIP
        statsFrame.selfFoundIcon.texture:SetVertexColor(1, 1, 1, 1)
        statsFrame.selfFoundIcon:Show()
        statsFrame.selfFoundLabel:Show()
    else
        statsFrame.selfFoundIcon:Hide()
        statsFrame.selfFoundLabel:Hide()
    end
    RustcoreStats.RefreshLayout()
end

function RustcoreStats.RegisterDestroyedItem(item)
    if not item then return end
    local stats = EnsureStatsDB()
    local slotKey, itemKey = GetSlotStateKey(item.slot, item.link)
    if itemKey and stats.rustedItemKeys and stats.rustedItemKeys[itemKey] then
        UpdateBestItem(item)
        RefreshText()
        return
    end
    stats.destroyedItems = (stats.destroyedItems or 0) + 1
    UpdateBestItem(item)
    RefreshText()
end

function RustcoreStats.RegisterRustedItem(item)
    if not item then return end
    local stats = EnsureStatsDB()
    local _, itemKey = GetSlotStateKey(item.slot, item.link)
    if itemKey then
        stats.rustedItemKeys[itemKey] = true
    end
    stats.rustedItems = (stats.rustedItems or 0) + 1
    UpdateBestItem(item)
    RefreshText()
end

GetSlotStateKey = function(slot, link)
    local owner = Rustcore.GetCharacterKey and Rustcore.GetCharacterKey() or UnitName("player") or "player"
    return owner .. ":" .. slot, owner .. ":" .. slot .. ":" .. (link or "")
end

local function ScanDurability(seedOnly)
    if scanning or not GetInventoryItemDurability then return end
    scanning = true
    local stats = EnsureStatsDB()
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        local current, maximum = GetInventoryItemDurability(slot)
        local slotKey, itemKey = GetSlotStateKey(slot, link)
        if link and current and maximum and maximum > 0 then
            if current <= 0 then
                if stats.zeroDurabilitySlots[slotKey] ~= itemKey then
                    if not seedOnly then
                        local name, _, _, ilvl = GetItemInfo(link)
                        RustcoreStats.RegisterRustedItem({
                            slot = slot,
                            link = link,
                            name = name,
                            ilvl = ilvl or 0,
                        })
                    end
                    stats.zeroDurabilitySlots[slotKey] = itemKey
                end
            else
                stats.zeroDurabilitySlots[slotKey] = nil
            end
        end
    end
    scanning = false
end

function RustcoreStats.Init()
    if initialized then return end
    initialized = true
    EnsureStatsDB()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_INVENTORY_DURABILITY" then
            ScanDurability(false)
        else
            ScanDurability(true)
        end
    end)
    C_Timer.After(1, function()
        ScanDurability(true)
        RustcoreStats.ApplyVisibility()
    end)
end
