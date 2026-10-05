local R, A = RustcoreReforge, RustcoreReforgeAPI
local panel, buff, allButton, statusText
local rows, offset = {}, 0
local merchantItems = {}
local tooltipBusy
local merchantOpen = false

local function Money(copper)
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function R.Tooltip(tip, item, id)
    if tooltipBusy or not id or not R.Unlocked() then return end
    if not item and not RustcoreReforgeSources.items[id] then
        if not (C_Item and C_Item.GetItemInfoInstant) then return end
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
        if not equipLoc or equipLoc == "" then return end
    end
    tooltipBusy = true
    local source = R.Source(item or { id = id })
    tip:AddLine("|cffcc8c40Reforge Source:|r " .. R.SourceName(source), 1, 1, 1)
    tip:AddLine("|cffff8c26Reforge Shard:|r " .. (item and R.HasShard(item) and "Ready" or "Missing"), 1, 1, 1)
    tooltipBusy = false
end

local function InstallTooltip()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
            if tooltipBusy or tip == _G.RustcoreReforgeCostTooltip or not data then return end
            pcall(function()
                if not A.Public(data.id) or not A.Public(data.guid) then return end
                local item = data.guid and R.Find(data.guid)
                -- Never attribute a Shard to an item-ID-only hyperlink or bank tooltip.
                R.Tooltip(tip, item, data.id)
            end)
        end)
    elseif hooksecurefunc and GameTooltip then
        hooksecurefunc(GameTooltip, "SetInventoryItem", function(tip, unit, slot)
            if unit ~= "player" then return end
            local item = A.Read(nil, slot)
            if item then R.Tooltip(tip, item, item.id) end
        end)
        hooksecurefunc(GameTooltip, "SetBagItem", function(tip, bag, slot)
            if bag < 0 or bag > (NUM_BAG_SLOTS or 4) then return end
            local item = A.Read(bag, slot)
            if item then R.Tooltip(tip, item, item.id) end
        end)
    end
end

local function CreateIconGlow(frame)
    local glow = CreateFrame("Frame", nil, frame)
    glow:SetPoint("TOPLEFT", frame.iconTex, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", frame.iconTex, "BOTTOMRIGHT", 0, 0)
    -- Keep the glow below the rust and counter artwork (+3 and +4).
    glow:SetFrameLevel(frame:GetFrameLevel() + 2)
    glow:EnableMouse(false)
    -- Additive passes brighten the same highlight without changing its shape.
    for pass = 1, 3 do
        local texture = glow:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints(glow)
        texture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        texture:SetDesaturated(true)
        texture:SetVertexColor(1, 0.82, 0.25)
        texture:SetBlendMode("ADD")
    end
    return glow
end

function R.UpdateHUDIndicator(frame, slot)
    local item = A.Read(nil, slot)
    local ready = item and R.HasShard(item)
    if frame.reforgeReady then frame.reforgeReady:Hide() end
    frame.reforgeGlow = frame.reforgeGlow or CreateIconGlow(frame)
    frame.reforgeGlow:SetShown(ready == true and Rustcore.GetSetting("reforgeGlow") ~= false)
    return ready
end

local function RefreshRustbound()
    if not buff then return end
    buff:SetShown(R.HasRustbound() == true)
    if RustcoreSelfFoundBuff and RustcoreSelfFoundBuff.RefreshPlayerLayout then
        RustcoreSelfFoundBuff.RefreshPlayerLayout()
    end
end

local function StyleText(text, size)
    text:SetFont(Rustcore.GetAssetPath("Font/BPpong.otf"), size, "")
end

function R.Refresh()
    if RustcoreOptions and RustcoreOptions.RefreshReforgePage then RustcoreOptions.RefreshReforgePage() end
    RefreshRustbound()
    if RustcoreDurability and RustcoreDurability.Refresh then RustcoreDurability.Refresh() end
    if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshDataNextUpdate then
        GameTooltip:RefreshDataNextUpdate()
    end
    if not panel then return end
    panel:SetShown(merchantOpen and A.AtMerchant() and R.Unlocked() or false)
    if not panel:IsShown() then return end
    RustcoreTheme.SetDifficultyBackground(panel, Rustcore.GetSetting("difficulty") or 1)
    merchantItems = {}
    for _, item in ipairs(A.Scan()) do
        if R.HasShard(item) then merchantItems[#merchantItems + 1] = item end
    end
    offset = math.max(0, math.min(offset, math.max(0, #merchantItems - #rows)))
    statusText:SetText((R.IsDebug() and "Developer test\n" or "") .. "Reforge All: at or below " .. R.Threshold() .. "%")
    for index, row in ipairs(rows) do
        local item = merchantItems[index + offset]
        row.item = item
        row:SetShown(item ~= nil)
        if item then
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item.id)
            local cost = A.Cost(item)
            row.label:SetText((name or ("Item " .. item.id)) .. " (" .. math.floor(item.cur * 100 / item.max) .. "%)\n"
                .. (cost and Money(cost) or "Repair cost unavailable"))
            row.button:SetEnabled(item.cur < item.max and cost ~= nil)
        end
    end
    allButton:SetEnabled(#merchantItems > 0)
end

local function BuildUI()
    if not buff then
    buff = CreateFrame("Button", "RustcoreRustboundBuff", UIParent)
    buff:SetSize(32, 32)
    buff:SetNormalTexture(R.RUSTBOUND_ICON)
    buff:Hide()
    if RustcoreSelfFoundBuff and RustcoreSelfFoundBuff.SetRustboundIcon then
        RustcoreSelfFoundBuff.SetRustboundIcon(buff)
    end
    buff:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Rustbound", 0.85, 0.6, 0.3)
        GameTooltip:AddLine("This character has never repaired an item.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    buff:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buff:Hide()
    end

    if panel or not MerchantFrame then return end
    panel = CreateFrame("Frame", "RustcoreReforgeMerchant", MerchantFrame)
    panel:SetSize(400, 438)
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0)
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("DIALOG")
    RustcoreTheme.ApplyFrameSkin(panel)
    local shade = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    shade:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -18)
    shade:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 18)
    shade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    shade:SetVertexColor(0, 0, 0, 0.62)
    local titleFrame = CreateFrame("Frame", nil, panel)
    titleFrame:SetSize(180, 24)
    titleFrame:SetPoint("CENTER", panel, "TOP", 0, -15)
    titleFrame:SetFrameLevel(panel:GetFrameLevel() + 5)
    local titleArt = titleFrame:CreateTexture(nil, "ARTWORK")
    titleArt:SetTexture(Rustcore.GetAssetPath("UI/Window-title-panel.tga"))
    titleArt:SetSize(220, 30)
    titleArt:SetPoint("CENTER")
    local title = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", 0, -1)
    title:SetText("Boss Reforging")
    StyleText(title, 16)
    title:SetTextColor(1, 1, 1)
    title:SetShadowColor(0, 0, 0, 0.6)
    title:SetShadowOffset(1, -1)
    local content = CreateFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -44)
    content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 20)
    content:SetFrameLevel(panel:GetFrameLevel() + 2)
    statusText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOP", 0, 0)
    StyleText(statusText, 12)
    statusText:SetTextColor(0.85, 0.75, 0.5)
    for index = 1, 6 do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(352, 42); row:SetPoint("TOPLEFT", 0, -42 - (index - 1) * 44)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT"); row.label:SetWidth(250); row.label:SetJustifyH("LEFT")
        StyleText(row.label, 12)
        row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.button:SetSize(90, 28); row.button:SetPoint("RIGHT"); row.button:SetText("Reforge")
        RustcoreTheme.SkinButton(row.button)
        StyleText(row.button:GetFontString(), 12)
        row.button:SetScript("OnClick", function()
            if row.item then
                local ok, reason = R.Repair(row.item.guid)
                if not ok then print("Rustcore: " .. reason) end
                R.Refresh()
            end
        end)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local item = self.item
            if not item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if item.bag == nil then GameTooltip:SetInventoryItem("player", item.slot)
            else GameTooltip:SetBagItem(item.bag, item.slot) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[index] = row
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta; R.Refresh() end)
    allButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    allButton:SetSize(130, 30); allButton:SetPoint("BOTTOM", 0, 8); allButton:SetText("Reforge All")
    RustcoreTheme.SkinButton(allButton)
    StyleText(allButton:GetFontString(), 12)
    allButton:SetScript("OnClick", function()
        local plan = R.Plan()
        if plan.error then print("Rustcore: " .. plan.error); return end
        if #plan.items == 0 then print("Rustcore: No items qualify for Reforge All."); return end
        local text = "Reforge " .. #plan.items .. " items?\n\nThis will consume " .. #plan.items
            .. " Reforge Shards and cost " .. Money(plan.cost) .. "."
        if plan.skipped > 0 then text = text .. "\n\n" .. plan.skipped .. " additional items are above your "
            .. plan.threshold .. "% threshold. Their Shards will remain unused." end
        StaticPopup_Show("RUSTCORE_REFORGE_ALL", text, nil, plan)
    end)
    StaticPopupDialogs.RUSTCORE_REFORGE_ALL = {
        text = "%s", button1 = "Reforge", button2 = "Cancel", timeout = 0, whileDead = false, hideOnEscape = true,
        OnAccept = function(_, plan)
            if not R.Execute(plan) then print("Rustcore: Reforge All stopped. Review the items and try again.") end
        end,
    }
    panel:Hide()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "BOSS_KILL", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE",
    "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        BuildUI(); InstallTooltip(); R.LoadPending(); R.Observe(); R.CheckRustbound(); R.Refresh()
    elseif event == "BOSS_KILL" then
        local id = ...
        if A.Public(id) then R.AwardBoss(id) end
    elseif event == "PLAYER_LEVEL_UP" then
        C_Timer.After(0, function() R.CheckRustbound(); R.Refresh() end)
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        -- Blizzard may show MerchantFrame after our event listener runs.
        C_Timer.After(0, function()
            if not merchantOpen then return end
            BuildUI(); R.Observe(); R.CheckRustbound(); R.Refresh()
        end)
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        if panel then panel:Hide() end
        StaticPopup_Hide("RUSTCORE_REFORGE_ALL"); R.Observe(); R.Refresh()
    else
        R.Observe(); R.CheckRustbound(); R.Refresh()
    end
end)
local elapsed = 0
events:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 1 then return end
    elapsed = 0
    R.Observe()
    RefreshRustbound()
    if merchantOpen and not panel then BuildUI() end
    local shouldShow = merchantOpen and A.AtMerchant() and R.Unlocked() or false
    if panel and panel:IsShown() ~= shouldShow then R.Refresh() end
end)
