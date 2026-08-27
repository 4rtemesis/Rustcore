-- Rustcore: minimal item loss stats window

RustcoreStats = {}

local statsFrame
local eventFrame
local initialized = false
local scanning = false
local GetSlotStateKey

local GEAR_SLOTS = { 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18 }
local BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 350, 150
local MIN_WIDTH, MIN_HEIGHT = 200, 125
local MIN_HEIGHT_HORIZONTAL = 68
local MAX_WIDTH, MAX_HEIGHT = 680, 300
local BACKGROUND_ALPHA = 0.78
local STATS_BORDER_SIZE = 18
local STATS_CONTENT_EDGE_PAD = 22
local TEXT_PAD = 10
-- Horizontal layout packs graphics much closer to the window's left/right
-- edges than the two-row layout does, so it gets its own, roomier side
-- margin instead of sharing TEXT_PAD.
local HORIZONTAL_SIDE_PAD = 20
local BEST_ITEM_SIDE_PAD = 16
local COLUMN_GAP = 4
local ROW_GAP = 2
local BEST_CELL_RATIO = 1.8
local COUNTER_REF_WIDTH, COUNTER_REF_HEIGHT = 229, 103
local COUNTER_DIGIT_SPACING = 0.235
local COUNTER_LEFT_DIGIT_NUDGE = -3
local COUNTER_MIDDLE_DIGIT_NUDGE = 0
local COUNTER_RIGHT_DIGIT_OFFSET = 0.012
local COUNTER_RIGHT_DIGIT_NUDGE = 1
local COUNTER_DIGIT_Y = -0.01
local COUNTER_ROLL_DURATION = 0.20
local ITEM_FRAME_REF_WIDTH, ITEM_FRAME_REF_HEIGHT = 846, 190
local ITEM_LINK_WIDTH_RATIO = 0.80
local LABEL_COLOR = { 1, 0.82, 0 }
local VALUE_COLOR = { 1, 1, 1 }
local COUNTER_VALUE_COLOR = { 0.91, 0.88, 0.8 }
local RESIZE_TOOLTIP = "Left click and drag to adjust. Right click to auto adjust."
local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

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
    RustcoreStats.RefreshLayout()
end

local function SavePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint()
    Rustcore.SetProfileValue("statsWindowPoint", {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    })
end

local function ApplySavedPosition(frame)
    frame:ClearAllPoints()
    local pos = Rustcore.GetProfileValue("statsWindowPoint")
    if pos and pos.point and pos.relativePoint and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
end

local function SaveSize(frame)
    local width, height = frame:GetSize()
    Rustcore.SetProfileValue("statsWindowSize", {
        width = width,
        height = height,
    })
end

-- The horizontal layout packs everything into one row of graphics, so it
-- doesn't need the taller minimum the two-row layout requires to avoid
-- clipping; letting it go shorter is what makes a wide-but-short bar possible.
local function GetMinHeight()
    return Rustcore.GetSetting("statsHorizontalLayout") and MIN_HEIGHT_HORIZONTAL or MIN_HEIGHT
end

local function ApplyResizeBounds()
    if not statsFrame then return end
    local minH = GetMinHeight()
    if statsFrame.SetResizeBounds then
        statsFrame:SetResizeBounds(MIN_WIDTH, minH, MAX_WIDTH, MAX_HEIGHT)
    elseif statsFrame.SetMinResize and statsFrame.SetMaxResize then
        statsFrame:SetMinResize(MIN_WIDTH, minH)
        statsFrame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
    end
    -- SetResizeBounds only constrains future drags; if the layout mode just
    -- switched to one with a taller minimum, pull an already-too-short frame
    -- back in bounds instead of leaving it stuck below the new floor.
    local w, h = statsFrame:GetSize()
    local clampedW, clampedH = Clamp(w, MIN_WIDTH, MAX_WIDTH), Clamp(h, minH, MAX_HEIGHT)
    if clampedW ~= w or clampedH ~= h then
        statsFrame:SetSize(clampedW, clampedH)
    end
end

local function ApplySavedSize(frame)
    local size = Rustcore.GetProfileValue("statsWindowSize")
    local width = size and tonumber(size.width) or DEFAULT_WIDTH
    local height = size and tonumber(size.height) or DEFAULT_HEIGHT
    frame:SetSize(
        Clamp(width, MIN_WIDTH, MAX_WIDTH),
        Clamp(height, GetMinHeight(), MAX_HEIGHT)
    )
end

local function ApplyBodyFont(fontString, size)
    if fontString then
        fontString:SetFont(BODY_FONT_PATH, size or 15, "")
    end
end

local function CreateStatsPanelArt(parent)
    local opacity = Rustcore.GetSetting("statsBackgroundOpacity") or BACKGROUND_ALPHA
    local shadowOpacity = Rustcore.GetSetting("statsBackgroundShadow") or 0
    local borderSize = STATS_BORDER_SIZE
    local pieces = {}
    local shadowPieces = {}
    local borderPieces = {}
    local shadowBorderPieces = {}

    local function CreatePiece(name, textureName, layer, sublevel)
        local texture = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
        texture:SetTexture(Rustcore.GetAssetPath("UI/" .. textureName))
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetAlpha(opacity)
        pieces[name] = texture
        return texture
    end

    local function CreateShadowPiece(name, textureName)
        local texture = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
        texture:SetTexture(Rustcore.GetAssetPath("UI/" .. textureName))
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(0, 0, 0, 1)
        texture:SetAlpha(shadowOpacity)
        shadowPieces[name] = texture
        return texture
    end

    local centerShadow = CreateShadowPiece("center", "newstatsC.tga")
    local center = CreatePiece("center", "newstatsC.tga")
    centerShadow:SetPoint("TOPLEFT", parent, "TOPLEFT", borderSize, -borderSize)
    centerShadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -borderSize, borderSize)
    center:SetPoint("TOPLEFT", parent, "TOPLEFT", borderSize, -borderSize)
    center:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -borderSize, borderSize)

    local shade = parent:CreateTexture(nil, "ARTWORK")
    shade:SetPoint("TOPLEFT", center, "TOPLEFT", 0, 0)
    shade:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", 0, 0)
    shade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shade:SetVertexColor(0, 0, 0, 0.10 * opacity)

    local topShadow = CreateShadowPiece("top", "newstatsUB.tga")
    local top = CreatePiece("top", "newstatsUB.tga", "ARTWORK")
    topShadow:SetPoint("TOPLEFT", parent, "TOPLEFT", borderSize, 0)
    topShadow:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -borderSize, -borderSize)
    top:SetPoint("TOPLEFT", parent, "TOPLEFT", borderSize, 0)
    top:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -borderSize, -borderSize)

    local bottomShadow = CreateShadowPiece("bottom", "newstatsBB.tga")
    local bottom = CreatePiece("bottom", "newstatsBB.tga", "ARTWORK")
    bottomShadow:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", borderSize, borderSize)
    bottomShadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -borderSize, 0)
    bottom:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", borderSize, borderSize)
    bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -borderSize, 0)

    local leftShadow = CreateShadowPiece("left", "newstatsLB.tga")
    local left = CreatePiece("left", "newstatsLB.tga", "ARTWORK")
    leftShadow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -borderSize)
    leftShadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", borderSize, borderSize)
    left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -borderSize)
    left:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", borderSize, borderSize)

    local rightShadow = CreateShadowPiece("right", "newstatsRB.tga")
    local right = CreatePiece("right", "newstatsRB.tga", "ARTWORK")
    rightShadow:SetPoint("TOPLEFT", parent, "TOPRIGHT", -borderSize, -borderSize)
    rightShadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, borderSize)
    right:SetPoint("TOPLEFT", parent, "TOPRIGHT", -borderSize, -borderSize)
    right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, borderSize)

    local topLeftShadow = CreateShadowPiece("topLeft", "newstatsULC.tga")
    local topLeft = CreatePiece("topLeft", "newstatsULC.tga", "ARTWORK")
    topLeftShadow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    topLeftShadow:SetSize(borderSize, borderSize)
    topLeft:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    topLeft:SetSize(borderSize, borderSize)

    local topRightShadow = CreateShadowPiece("topRight", "newstatsURC.tga")
    local topRight = CreatePiece("topRight", "newstatsURC.tga", "ARTWORK")
    topRightShadow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    topRightShadow:SetSize(borderSize, borderSize)
    topRight:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    topRight:SetSize(borderSize, borderSize)

    local bottomLeftShadow = CreateShadowPiece("bottomLeft", "newstatsLLC.tga")
    local bottomLeft = CreatePiece("bottomLeft", "newstatsLLC.tga", "ARTWORK")
    bottomLeftShadow:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    bottomLeftShadow:SetSize(borderSize, borderSize)
    bottomLeft:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    bottomLeft:SetSize(borderSize, borderSize)

    local bottomRightShadow = CreateShadowPiece("bottomRight", "newstatsLRC.tga")
    local bottomRight = CreatePiece("bottomRight", "newstatsLRC.tga", "ARTWORK")
    bottomRightShadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bottomRightShadow:SetSize(borderSize, borderSize)
    bottomRight:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    bottomRight:SetSize(borderSize, borderSize)

    borderPieces[1] = top
    borderPieces[2] = bottom
    borderPieces[3] = left
    borderPieces[4] = right
    borderPieces[5] = topLeft
    borderPieces[6] = topRight
    borderPieces[7] = bottomLeft
    borderPieces[8] = bottomRight
    shadowBorderPieces[1] = topShadow
    shadowBorderPieces[2] = bottomShadow
    shadowBorderPieces[3] = leftShadow
    shadowBorderPieces[4] = rightShadow
    shadowBorderPieces[5] = topLeftShadow
    shadowBorderPieces[6] = topRightShadow
    shadowBorderPieces[7] = bottomLeftShadow
    shadowBorderPieces[8] = bottomRightShadow

    return {
        pieces = pieces,
        shadowPieces = shadowPieces,
        borderPieces = borderPieces,
        shadowBorderPieces = shadowBorderPieces,
        center = center,
        shade = shade,
    }
end

function RustcoreStats.RefreshPosition()
    if not statsFrame then return end
    ApplySavedPosition(statsFrame)
    ApplySavedSize(statsFrame)
    RustcoreStats.RefreshLayout()
end

-- Snaps the window height to whichever layout's natural size fits it best:
-- short for the single-row horizontal layout, the original default for the
-- taller two-row layout. Called whenever the horizontal toggle changes so
-- the background isn't left oversized (or undersized) for the new layout.
function RustcoreStats.ApplyLayoutModeChange()
    if not statsFrame then return end
    local horizontal = Rustcore.GetSetting("statsHorizontalLayout")
    local targetHeight = horizontal and MIN_HEIGHT_HORIZONTAL or DEFAULT_HEIGHT
    local _, currentHeight = statsFrame:GetSize()
    if currentHeight ~= targetHeight then
        statsFrame:SetHeight(targetHeight)
        SaveSize(statsFrame)
    end
    RustcoreStats.RefreshLayout()
end

function RustcoreStats.RefreshLayout()
    if not statsFrame then return end
    ApplyResizeBounds()
    local width, height = statsFrame:GetSize()
    local pad = TEXT_PAD
    local horizontal = Rustcore.GetSetting("statsHorizontalLayout")
    local sidePad = math.max(horizontal and HORIZONTAL_SIDE_PAD or pad, STATS_CONTENT_EDGE_PAD)
    local bestSidePad = math.max(BEST_ITEM_SIDE_PAD, STATS_CONTENT_EDGE_PAD)
    local contentWidth = math.max(1, width - (sidePad * 2))
    local bestContentWidth = math.max(1, width - (bestSidePad * 2))
    local contentHeight = math.max(1, height - (pad * 2))
    local rowHeight = horizontal and contentHeight or ((contentHeight - ROW_GAP) / 2)
    local showRusted, showDestroyed = GetCounterVisibility()
    local visibleCounterCount = (showRusted and 1 or 0) + (showDestroyed and 1 or 0)
    local elementGap = 2
    local counterCellWidth
    local bestCellWidth = bestContentWidth
    local labelSize
    local bestLabelSize
    local graphicHeight
    local horizontalRowWidth = 0
    if horizontal then
        -- Single row: every visible graphic (rusted/destroyed counters,
        -- best-item frame) shares one graphicHeight so they line up at the
        -- same height; only their widths differ, each scaled from that
        -- shared height by its own aspect ratio.
        labelSize = Clamp(math.floor(contentHeight * 0.16) + 1, 11, 16)
        bestLabelSize = labelSize
        local slotCount = visibleCounterCount + 1
        local gaps = math.max(0, slotCount - 1) * COLUMN_GAP
        local counterAspect = COUNTER_REF_WIDTH / COUNTER_REF_HEIGHT
        local itemAspect = ITEM_FRAME_REF_WIDTH / ITEM_FRAME_REF_HEIGHT
        local aspectSum = (visibleCounterCount * counterAspect) + itemAspect
        local heightFromContent = math.max(1, contentHeight - labelSize - elementGap)
        local heightFromWidth = (contentWidth - gaps) / math.max(aspectSum, 0.001)
        graphicHeight = math.max(1, math.min(heightFromContent, heightFromWidth))

        counterCellWidth = graphicHeight * counterAspect
        bestCellWidth = graphicHeight * itemAspect
        horizontalRowWidth = (visibleCounterCount * counterCellWidth) + bestCellWidth + gaps
    else
        labelSize = Clamp(math.floor(rowHeight * 0.17) + 1, 12, 18)
        bestLabelSize = Clamp(math.floor(rowHeight * 0.19), 11, 17)
        if visibleCounterCount == 2 then
            counterCellWidth = (contentWidth - COLUMN_GAP) / 2
        else
            counterCellWidth = contentWidth
        end
    end
    local counterWidth = horizontal and counterCellWidth or math.min(counterCellWidth, rowHeight * 1.33)
    local counterHeight = counterWidth * (COUNTER_REF_HEIGHT / COUNTER_REF_WIDTH)
    local counterTopOffset = labelSize + elementGap
    local digitSize = Clamp(math.floor(counterHeight * 0.34), 12, 25)
    local bestFrameMaxHeight = horizontal and graphicHeight or math.max(1, rowHeight - bestLabelSize - elementGap)
    local bestFrameWidth = horizontal and bestCellWidth or math.min(
        bestCellWidth,
        bestFrameMaxHeight * (ITEM_FRAME_REF_WIDTH / ITEM_FRAME_REF_HEIGHT)
    )
    local bestFrameHeight = bestFrameWidth * (ITEM_FRAME_REF_HEIGHT / ITEM_FRAME_REF_WIDTH)
    local bestValueSize = Clamp(math.floor(bestFrameHeight * 0.22) + 2, 12, 20)

    ApplyBodyFont(statsFrame.destroyedLabel, labelSize)
    ApplyBodyFont(statsFrame.rustedLabel, labelSize)
    ApplyBodyFont(statsFrame.bestLabel, bestLabelSize)
    ApplyBodyFont(statsFrame.bestValue, bestValueSize)
    for i = 1, 3 do
        ApplyBodyFont(statsFrame.rustedDigits[i].oldText, digitSize)
        ApplyBodyFont(statsFrame.rustedDigits[i].newText, digitSize)
        ApplyBodyFont(statsFrame.destroyedDigits[i].oldText, digitSize)
        ApplyBodyFont(statsFrame.destroyedDigits[i].newText, digitSize)
    end

    local topY = -pad
    local bottomY = horizontal and topY or (-pad - rowHeight - ROW_GAP)
    local rustedCenterX
    local destroyedCenterX
    local bestCenterX = width * 0.5
    if horizontal then
        -- Center the whole row within contentWidth instead of left-packing
        -- it, so extra window width becomes empty margin rather than forcing
        -- the graphics themselves to grow.
        local cursor = sidePad + math.max(0, (contentWidth - horizontalRowWidth) * 0.5)
        local function PlaceCell(w)
            local centerX = cursor + (w * 0.5)
            cursor = cursor + w + COLUMN_GAP
            return centerX
        end
        if showRusted then rustedCenterX = PlaceCell(counterCellWidth) end
        if showDestroyed then destroyedCenterX = PlaceCell(counterCellWidth) end
        bestCenterX = PlaceCell(bestCellWidth)
    elseif visibleCounterCount == 2 then
        rustedCenterX = sidePad + (counterCellWidth * 0.5)
        destroyedCenterX = sidePad + counterCellWidth + COLUMN_GAP + (counterCellWidth * 0.5)
    elseif visibleCounterCount == 1 then
        rustedCenterX = width * 0.5
        destroyedCenterX = width * 0.5
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
            if i == 1 then
                digitX = digitX + COUNTER_LEFT_DIGIT_NUDGE
            elseif i == 2 then
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

    statsFrame.bestLabel:ClearAllPoints()
    statsFrame.bestLabel:SetPoint("TOP", statsFrame, "TOPLEFT", bestCenterX, bottomY)
    statsFrame.bestLabel:SetWidth(bestCellWidth)

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

end

local function GetAutoFitWidth()
    if not statsFrame then return DEFAULT_WIDTH end
    RustcoreStats.RefreshLayout()

    local showRusted, showDestroyed = GetCounterVisibility()
    local visibleCounterCount = (showRusted and 1 or 0) + (showDestroyed and 1 or 0)
    local counterCellWidth = math.max(
        68,
        showRusted and (statsFrame.rustedLabel:GetStringWidth() or 0) or 0,
        showDestroyed and (statsFrame.destroyedLabel:GetStringWidth() or 0) or 0
    )

    local bestLabelWidth = statsFrame.bestLabel:GetStringWidth() or 0
    local bestValueWidth = statsFrame.bestValue:GetStringWidth() or 0
    local bottomWidth = math.max(140, bestLabelWidth, bestValueWidth / ITEM_LINK_WIDTH_RATIO)

    if Rustcore.GetSetting("statsHorizontalLayout") then
        local slotCount = visibleCounterCount + 1
        local totalWidth = (counterCellWidth * visibleCounterCount)
            + bottomWidth
            + (math.max(0, slotCount - 1) * COLUMN_GAP)
        return Clamp(math.ceil(totalWidth + (math.max(HORIZONTAL_SIDE_PAD, STATS_CONTENT_EDGE_PAD) * 2)), MIN_WIDTH, MAX_WIDTH)
    end

    local topWidth
    if visibleCounterCount == 2 then
        topWidth = (counterCellWidth * 2) + COLUMN_GAP
    elseif visibleCounterCount == 1 then
        topWidth = counterCellWidth
    else
        topWidth = 0
    end
    local requiredTopWidth = topWidth + (math.max(TEXT_PAD, STATS_CONTENT_EDGE_PAD) * 2)
    local requiredBottomWidth = bottomWidth + (math.max(BEST_ITEM_SIDE_PAD, STATS_CONTENT_EDGE_PAD) * 2)
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
        f:SetResizeBounds(MIN_WIDTH, GetMinHeight(), MAX_WIDTH, MAX_HEIGHT)
    elseif f.SetMinResize and f.SetMaxResize then
        f:SetMinResize(MIN_WIDTH, GetMinHeight())
        f:SetMaxResize(MAX_WIDTH, MAX_HEIGHT)
    end

    local panelArt = CreateStatsPanelArt(f)

    -- Alternate to the corner-rivet look: a standard Blizzard dialog frame border.
    -- Sized larger than the frame itself so the border art fully encloses the
    -- background instead of the background bleeding past the drawn edge.
    local blizzardBorder = CreateFrame("Frame", nil, f, backdropTemplate)
    blizzardBorder:SetPoint("TOPLEFT", f, "TOPLEFT", -10, 11)
    blizzardBorder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 11, -10)
    blizzardBorder:SetFrameLevel(f:GetFrameLevel() + 3)
    blizzardBorder:EnableMouse(false)
    if blizzardBorder.SetBackdrop then
        blizzardBorder:SetBackdrop({
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    blizzardBorder:Hide()

    f.borderPieces = panelArt.borderPieces
    f.backgroundShadowBorderPieces = panelArt.shadowBorderPieces
    f.blizzardBorder = blizzardBorder

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f:SetScript("OnSizeChanged", function()
        RustcoreStats.RefreshLayout()
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            RustcoreOptions.Toggle()
        end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, -32)
        GameTooltip:AddLine("Rustcore Stats", 1, 1, 1)
        GameTooltip:AddLine("Right-click to open options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag from lower right corner to change size", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
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
        local counter = CreateArtFrame("UI/DarkCounter copy.tga")
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
    local itemLostFrame = CreateArtFrame("UI/Lostitemframe Dark copy.tga")
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
    f.bestLabel = bestLabel
    f.bestValue = bestValue
    f.itemLostFrame = itemLostFrame
    f.bestHitbox = bestHitbox
    f.backgroundPieces = panelArt.pieces
    f.backgroundShadowPieces = panelArt.shadowPieces
    f.background = panelArt.center
    f.shade = panelArt.shade
    f.resizeGrip = resizeGrip
    ApplySavedPosition(f)
    RefreshText()

    local useBlizzardFrame = Rustcore.GetSetting("statsUseBlizzardFrame")
    for _, piece in ipairs(f.borderPieces) do
        piece:SetShown(not useBlizzardFrame)
    end
    for _, piece in ipairs(f.backgroundShadowBorderPieces) do
        piece:SetShown(not useBlizzardFrame)
    end
    f.blizzardBorder:SetShown(useBlizzardFrame)

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
    RustcoreStats.RefreshBackgroundOpacity()
end

function RustcoreStats.RefreshFrameStyle()
    if not statsFrame then return end
    local useBlizzardFrame = Rustcore.GetSetting("statsUseBlizzardFrame")
    for _, piece in ipairs(statsFrame.borderPieces or {}) do
        piece:SetShown(not useBlizzardFrame)
    end
    for _, piece in ipairs(statsFrame.backgroundShadowBorderPieces or {}) do
        piece:SetShown(not useBlizzardFrame)
    end
    if statsFrame.blizzardBorder then
        statsFrame.blizzardBorder:SetShown(useBlizzardFrame)
    end
end

function RustcoreStats.RefreshBackgroundOpacity()
    if not statsFrame then return end
    local opacity = Rustcore.GetSetting("statsBackgroundOpacity") or BACKGROUND_ALPHA
    for _, piece in pairs(statsFrame.backgroundPieces or {}) do
        piece:SetAlpha(opacity)
    end
    if statsFrame.shade then
        statsFrame.shade:SetVertexColor(0, 0, 0, 0.10 * opacity)
    end
end

function RustcoreStats.RefreshBackgroundShadow()
    if not statsFrame then return end
    local opacity = Rustcore.GetSetting("statsBackgroundShadow") or 0
    for _, piece in pairs(statsFrame.backgroundShadowPieces or {}) do
        piece:SetAlpha(opacity)
    end
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
