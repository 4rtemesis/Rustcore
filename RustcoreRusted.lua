RustcoreRusted = RustcoreRusted or {}

local rustedFrame        = nil
local pendingRustedItems = {}

local TITLE_FONT_PATH = Rustcore.GetAssetPath("Font/RUSTED PERSONAL USE.ttf")
local BODY_FONT_PATH  = Rustcore.GetAssetPath("Font/BPpong.otf")
local TITLE_COLOR     = { 0.85, 0.15, 0.15 }

local ICON_SIZE                = 38
local COMPACT_CELL_GAP         = 6
local ICON_IMAGE_SIZE          = 32
local ICON_TEX_INSET           = 0.10
local ICON_BORDER_SIZE         = 60
local COMPACT_ICON_BG_SIZE     = ICON_IMAGE_SIZE - 2
local MAX_ROWS_PER_COLUMN      = 9
local COMPACT_FRAME_MIN_HEIGHT = 300
local COMPACT_FRAME_MIN_WIDTH  = 280
local ICON_ROW_OFFSET_Y        = -125

-- Equipped slots that can have durability
local DURABLE_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18 }

-- ── Compat bag helpers ────────────────────────────────────────────────────────

local function BagGetNumSlots(bag)
    if C_Container then return C_Container.GetContainerNumSlots(bag) end
    return GetContainerNumSlots(bag)
end

local function BagGetItemLink(bag, slot)
    if C_Container then return C_Container.GetContainerItemLink(bag, slot) end
    return GetContainerItemLink(bag, slot)
end

local function BagPickupItem(bag, slot)
    if C_Container then
        C_Container.PickupContainerItem(bag, slot)
    else
        PickupContainerItem(bag, slot)
    end
end

-- ── Item ID helpers ───────────────────────────────────────────────────────────

local function GetItemID(link)
    if not link then return nil end
    return link:match("item:(%d+)")
end

local function IsDismissed(itemID)
    return itemID and RustcoreDB and RustcoreDB.rustedDismissed
        and RustcoreDB.rustedDismissed[itemID] == true
end

local function MarkDismissed(itemID)
    if not itemID then return end
    if not RustcoreDB then return end
    if not RustcoreDB.rustedDismissed then RustcoreDB.rustedDismissed = {} end
    RustcoreDB.rustedDismissed[itemID] = true
end

local function IsAlreadyPending(itemID)
    for _, item in ipairs(pendingRustedItems) do
        if GetItemID(item.link) == itemID then return true end
    end
    return false
end

-- ── Find + pick up item by ID ─────────────────────────────────────────────────

local function FindAndPickupItem(link)
    local targetID = GetItemID(link)
    if not targetID then return false end

    for _, slot in ipairs(DURABLE_SLOTS) do
        local eLink = GetInventoryItemLink("player", slot)
        if eLink and GetItemID(eLink) == targetID then
            ClearCursor()
            PickupInventoryItem(slot)
            if CursorHasItem() then return true end
        end
    end

    for bag = 0, 4 do
        for slot = 1, BagGetNumSlots(bag) do
            local bLink = BagGetItemLink(bag, slot)
            if bLink and GetItemID(bLink) == targetID then
                ClearCursor()
                BagPickupItem(bag, slot)
                if CursorHasItem() then return true end
            end
        end
    end

    return false
end

local function UpdateSubLabel(f, count)
    if not f or not f.subLabel then return end
    if count and count > 1 then
        f.subLabel:SetText("These items have rusted away and are no longer usable, do you wish to destroy them?")
    else
        f.subLabel:SetText("This item has rusted away and is no longer usable, do you wish to destroy it?")
    end
end

-- ── Icon grid ─────────────────────────────────────────────────────────────────

local function ClearRustedIcons()
    if not rustedFrame then return end
    for _, cell in ipairs(rustedFrame.compactIcons or {}) do
        if cell.fallTimer  then cell.fallTimer:Cancel();  cell.fallTimer  = nil end
        if cell.fallTicker then cell.fallTicker:Cancel(); cell.fallTicker = nil end
        cell:Hide()
        cell:SetParent(nil)
    end
    wipe(rustedFrame.compactIcons)
end

local function PopulateRustedIcons(items, skipAnim)
    local f = rustedFrame
    if not f then return end
    ClearRustedIcons()

    local itemCount = #items
    if itemCount == 0 then
        f:Hide()
        return
    end

    local columns       = math.max(1, math.ceil(itemCount / MAX_ROWS_PER_COLUMN))
    local rowsPerColumn = math.ceil(itemCount / columns)
    local rowsInTallest = math.min(itemCount, rowsPerColumn)
    local totalW        = columns * ICON_SIZE + (columns - 1) * COMPACT_CELL_GAP
    local totalH        = rowsInTallest * ICON_SIZE + math.max(0, rowsInTallest - 1) * COMPACT_CELL_GAP
    local frameW        = math.max(totalW + 86, COMPACT_FRAME_MIN_WIDTH)
    local frameH        = math.max(totalH + 260, COMPACT_FRAME_MIN_HEIGHT)

    f:SetSize(frameW, frameH)
    UpdateSubLabel(f, itemCount)

    f.rowContainer:ClearAllPoints()
    f.rowContainer:SetPoint("TOP", f, "TOP", 0, ICON_ROW_OFFSET_Y)
    f.rowContainer:SetWidth(totalW)
    f.rowContainer:SetHeight(totalH)

    for i, item in ipairs(items) do
        local col  = math.floor((i - 1) / rowsPerColumn)
        local row  = (i - 1) % rowsPerColumn
        local xOff = col * (ICON_SIZE + COMPACT_CELL_GAP)
        local yOff = -(row * (ICON_SIZE + COMPACT_CELL_GAP))

        local cell = CreateFrame("Frame", nil, f.rowContainer)
        cell:SetSize(ICON_SIZE, ICON_SIZE)
        cell:SetPoint("TOPLEFT", f.rowContainer, "TOPLEFT", xOff, yOff)
        cell._fallX    = xOff
        cell._fallY    = yOff
        cell._itemLink = item.link

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            if self._itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self._itemLink)
                GameTooltip:Show()
            end
        end)
        cell:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        local bg = cell:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(COMPACT_ICON_BG_SIZE, COMPACT_ICON_BG_SIZE)
        bg:SetPoint("CENTER", cell, "CENTER", 0, 0)
        bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
        bg:SetVertexColor(0, 0, 0, 1)

        local icon = cell:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_IMAGE_SIZE, ICON_IMAGE_SIZE)
        icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
        icon:SetTexture(item.tex or "Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetTexCoord(ICON_TEX_INSET, 1 - ICON_TEX_INSET, ICON_TEX_INSET, 1 - ICON_TEX_INSET)

        local border = CreateFrame("Frame", nil, cell)
        border:SetSize(ICON_BORDER_SIZE, ICON_BORDER_SIZE)
        border:SetPoint("CENTER", cell, "CENTER", 0, 0)
        border:SetFrameLevel(cell:GetFrameLevel() + 4)
        border.tex = border:CreateTexture(nil, "OVERLAY")
        border.tex:SetAllPoints(border)
        border.tex:SetTexture("Interface\\Buttons\\UI-Quickslot2")

        cell:Show()
        f.compactIcons[#f.compactIcons + 1] = cell
    end

    if not skipAnim then
        local fallOrder = {}
        for i = 1, itemCount do fallOrder[i] = i end
        for i = itemCount, 2, -1 do
            local j = math.random(1, i)
            fallOrder[i], fallOrder[j] = fallOrder[j], fallOrder[i]
        end

        local FALL_HEIGHT   = 110
        local FALL_DURATION = 0.22
        local SOUND_LEAD_IN = 0.1

        for pos, idx in ipairs(fallOrder) do
            local cell  = f.compactIcons[idx]
            local cxOff = cell._fallX
            local cyOff = cell._fallY
            local startY = cyOff + FALL_HEIGHT

            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", f.rowContainer, "TOPLEFT", cxOff, startY)
            cell:SetAlpha(0)

            local delay = math.max((pos - 1) * 0.3, 0.016)
            cell.fallTimer = C_Timer.NewTicker(delay, function(self)
                self:Cancel()
                cell.fallTimer = nil
                if not cell:GetParent() then return end
                cell:SetAlpha(1)
                local t0 = GetTime()
                local soundPlayed = false
                cell.fallTicker = C_Timer.NewTicker(0.016, function(ticker)
                    if not cell:GetParent() then ticker:Cancel(); return end
                    local elapsed = GetTime() - t0
                    if not soundPlayed and elapsed >= FALL_DURATION - SOUND_LEAD_IN then
                        soundPlayed = true
                        PlaySoundFile(Rustcore.GetAssetPath("Audio/crash" .. math.random(1, 5) .. ".wav"), "Master")
                    end
                    if elapsed >= FALL_DURATION then
                        ticker:Cancel()
                        cell.fallTicker = nil
                        cell:ClearAllPoints()
                        cell:SetPoint("TOPLEFT", f.rowContainer, "TOPLEFT", cxOff, cyOff)
                        return
                    end
                    local t = elapsed / FALL_DURATION
                    cell:ClearAllPoints()
                    cell:SetPoint("TOPLEFT", f.rowContainer, "TOPLEFT", cxOff, startY + (cyOff - startY) * (t * t))
                end)
            end, 1)
        end
    end
end

-- ── Frame construction ────────────────────────────────────────────────────────

local function BuildRustedFrame()
    if rustedFrame then return rustedFrame end

    local f = CreateFrame("Frame", "RustcoreRustedFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(COMPACT_FRAME_MIN_WIDTH, COMPACT_FRAME_MIN_HEIGHT)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    RustcoreTheme.ApplyFrameSkin(f)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", f, "TOP", 0, -26)
    title:SetFont(TITLE_FONT_PATH, 30, "")
    title:SetTextColor(unpack(TITLE_COLOR))
    title:SetShadowColor(0, 0, 0, 0.6)
    title:SetShadowOffset(1, -1)
    title:SetText("Rusted")

    local subLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subLabel:SetPoint("TOP", title, "BOTTOM", 0, -10)
    subLabel:SetWidth(220)
    subLabel:SetJustifyH("CENTER")
    subLabel:SetWordWrap(true)
    subLabel:SetFont(BODY_FONT_PATH, 16, "")
    subLabel:SetText("This item has rusted away and is no longer usable, do you wish to destroy it?")
    f.subLabel = subLabel

    local rowContainer = CreateFrame("Frame", nil, f)
    rowContainer:SetSize(ICON_SIZE, ICON_SIZE)
    f.rowContainer = rowContainer

    -- Exit button — dismisses all shown items permanently
    local exitBtn = CreateFrame("Button", nil, f)
    exitBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -6)
    exitBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    exitBtn:SetScript("OnClick", function()
        for _, item in ipairs(pendingRustedItems) do
            MarkDismissed(GetItemID(item.link))
        end
        wipe(pendingRustedItems)
        ClearRustedIcons()
        f:Hide()
    end)
    RustcoreTheme.SkinExitButton(exitBtn)

    -- Delete button
    local btn = CreateFrame("Button", "RustcoreRustedDeleteButton", f)
    btn:SetSize(200, 75)
    local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnLabel:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn:SetFontString(btnLabel)
    btn:SetText("")
    btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 36)
    btn:SetScript("OnClick", function() RustcoreRusted.ExecuteDeletion() end)
    RustcoreTheme.SkinDeleteButton(btn)
    f.deleteBtn = btn

    f.compactIcons = {}
    f:Hide()

    rustedFrame = f
    return f
end

-- ── Public API ────────────────────────────────────────────────────────────────

function RustcoreRusted.ExecuteDeletion()
    if #pendingRustedItems == 0 then return end
    local item = pendingRustedItems[1]

    ClearCursor()
    FindAndPickupItem(item.link)
    if CursorHasItem() then
        DeleteCursorItem()
        PlaySoundFile(Rustcore.GetAssetPath("Audio/Breaksound.flac"), "Master")
    end

    -- Mark dismissed regardless of whether popup is confirmed — same as exit
    MarkDismissed(GetItemID(item.link))
    table.remove(pendingRustedItems, 1)

    if #pendingRustedItems == 0 then
        ClearRustedIcons()
        if rustedFrame then rustedFrame:Hide() end
    else
        PopulateRustedIcons(pendingRustedItems, true)
    end
end

-- ── Durability scan ───────────────────────────────────────────────────────────

local function ScanBrokenItems()
    if not RustcoreDB then return end
    if not RustcoreDB.rustedDismissed then RustcoreDB.rustedDismissed = {} end

    local newBroken = {}
    for _, slot in ipairs(DURABLE_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local current, max = GetInventoryItemDurability(slot)
            if current ~= nil and max and max > 0 and current == 0 then
                local itemID = GetItemID(link)
                if itemID and not IsDismissed(itemID) and not IsAlreadyPending(itemID) then
                    newBroken[#newBroken + 1] = {
                        link = link,
                        tex  = GetInventoryItemTexture("player", slot),
                    }
                end
            end
        end
    end

    if #newBroken == 0 then return end

    local f = BuildRustedFrame()
    RustcoreTheme.SetDifficultyBackground(f, Rustcore.GetSetting("difficulty"))

    local playAnim = not f:IsShown()
    for _, item in ipairs(newBroken) do
        pendingRustedItems[#pendingRustedItems + 1] = item
    end

    PopulateRustedIcons(pendingRustedItems, not playAnim)
    if playAnim then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 60, 60)
    end
    f:Show()
end

-- ── Events ────────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "GearCore" or arg1 == "Rustcore" then
            if RustcoreDB and not RustcoreDB.rustedDismissed then
                RustcoreDB.rustedDismissed = {}
            end
        end
    elseif event == "PLAYER_ALIVE" then
        -- spirit healer applies durability loss just before this fires;
        -- defer one frame so the API values are settled
        C_Timer.After(0.5, ScanBrokenItems)
    elseif event == "UPDATE_INVENTORY_DURABILITY"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_DEAD" then
        ScanBrokenItems()
    end
end)
