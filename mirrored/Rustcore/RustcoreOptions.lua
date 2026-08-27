-- Rustcore: Options window
-- Accessible via /rustcore or /rc

RustcoreOptions = {}

local optFrame

local DIFF_LABELS = { [1]="Rusted", [2]="Broken", [3]="Shattered", [4]="Crumbling", [5]="Dust" }
local DIFF_DESCS  = {
    [1] = "Only repair is blocked. No items are lost on death.",
    [2] = "Lose 1 random equipped item on death.",
    [3] = "Lose 25% of your equipped items on death (rounded up).",
    [4] = "Lose 50% of your equipped items on death (rounded up).",
    [5] = "Lose every equipped item on death.",
}
local DIFF_COLORS = {
    [1] = { 0.494, 0.663, 0.337 },
    [2] = { 0.62, 0.58, 0.28 },
    [3] = { 0.72, 0.43, 0.19 },
    [4] = { 0.62, 0.22, 0.16 },
    [5] = { 0.52, 0.07, 0.06 },
}

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local DEFAULT_TITLE_TEXT = "OPTIONS"
local COMBAT_NOTE_TEXT = "Settings locked in combat"
local RUSTED_FONT_PATH = Rustcore.GetAssetPath("Font/RUSTED PERSONAL USE.ttf")
local BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")
local TITLE_COLOR = { 1, 1, 1 }

local function ApplyBodyFont(fontString, size)
    if not fontString then return end
    fontString:SetFont(BODY_FONT_PATH, math.max(10, (size or 18) - 2), "")
end

local function ApplyDifficultyLabelStyle(slider, value)
    local label = slider and slider.GetName and _G[slider:GetName().."Text"]
    if not label then return end

    local v = math.max(1, math.min(5, math.floor((value or 1) + 0.5)))
    local color = DIFF_COLORS[v] or DIFF_COLORS[1]
    label:SetText(DIFF_LABELS[v])
    label:SetFont(RUSTED_FONT_PATH, 34, "")
    label:SetTextColor(color[1], color[2], color[3])
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(2, -2)
end

local function SettingsLocked()
    return Rustcore and Rustcore.SettingsLocked and Rustcore.SettingsLocked()
end

local function ApplyDifficultyValue(slider, diffDesc, value)
    local v = math.max(1, math.min(5, math.floor(value + 0.5)))
    local previous = Rustcore.GetSetting("difficulty")
    if math.abs((slider:GetValue() or v) - v) > 0.001 then
        slider:SetValue(v)
        return
    end

    if previous == v then
        ApplyDifficultyLabelStyle(slider, v)
        diffDesc:SetText(DIFF_DESCS[v])
        local parent = slider:GetParent()
        if parent then
            RustcoreTheme.SetDifficultyBackground(parent, v)
        end
        return
    end

    if not Rustcore.SetSetting("difficulty", v) then
        local current = Rustcore.GetSetting("difficulty")
        if math.abs((slider:GetValue() or current) - current) > 0.001 then
            slider:SetValue(current)
        end
        return
    end
    PlaySoundFile(Rustcore.GetAssetPath("Audio/difficultysound.wav"), "Master")
    ApplyDifficultyLabelStyle(slider, v)
    diffDesc:SetText(DIFF_DESCS[v])
    local parent = slider:GetParent()
    if parent then
        RustcoreTheme.SetDifficultyBackground(parent, v)
    end
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function MakeCheckbox(parent, labelText, tooltipText, anchorTo, yOff, settingKey, xOff, size, fontSize)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(size or 26, size or 26)
    cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", xOff or 0, yOff)

    RustcoreTheme.SkinCheckbox(cb)

    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(labelText)
    ApplyBodyFont(lbl, fontSize or 17)

    if tooltipText then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    cb:SetScript("OnClick", function(self)
        PlaySoundFile(Rustcore.GetAssetPath("Audio/ticksound2.wav"), "Master")
        if not Rustcore.SetSetting(settingKey, self:GetChecked() and true or false) then
            cb:Refresh()
        end
    end)

    cb.Refresh = function()
        cb:SetChecked(Rustcore.GetSetting(settingKey))
    end

    return cb
end

local function MakeSettingSlider(parent, name, labelText, y, minValue, maxValue, step, settingKey, formatter)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, y)
    slider:SetWidth(180)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    local track = RustcoreTheme.SkinSlider(slider, 180, -1)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("BOTTOM", slider, "TOP", 0, 6)
    label:SetText(labelText)
    ApplyBodyFont(label, 14)

    local low = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local valueText = _G[name .. "Text"]
    if low then low:SetText("") end
    if high then high:SetText("") end
    if valueText then
        valueText:ClearAllPoints()
        valueText:SetPoint("TOP", track, "BOTTOM", 0, -4)
        ApplyBodyFont(valueText, 14)
    end

    slider:SetScript("OnValueChanged", function(self, value)
        local normalized
        if step >= 1 then
            normalized = math.floor(value + 0.5)
        else
            normalized = math.floor(value * 100 + 0.5) / 100
        end
        if math.abs((self:GetValue() or normalized) - normalized) > 0.001 then
            self:SetValue(normalized)
            return
        end
        if valueText then valueText:SetText(formatter(normalized)) end
        if Rustcore.GetSetting(settingKey) ~= normalized and not Rustcore.SetSetting(settingKey, normalized) then
            self:SetValue(Rustcore.GetSetting(settingKey))
        end
    end)
    slider:SetValue(Rustcore.GetSetting(settingKey))
    return slider
end

local function RefreshCombatLockState(frame)
    local locked = SettingsLocked()
    if frame.diffSlider then
        if locked then frame.diffSlider:Disable() else frame.diffSlider:Enable() end
        frame.diffSlider:SetAlpha(locked and 0.5 or 1)
    end
    if frame.opacitySlider then
        if locked then frame.opacitySlider:Disable() else frame.opacitySlider:Enable() end
        frame.opacitySlider:SetAlpha(locked and 0.5 or 1)
    end
    if frame.shadowSlider then
        if locked then frame.shadowSlider:Disable() else frame.shadowSlider:Enable() end
        frame.shadowSlider:SetAlpha(locked and 0.5 or 1)
    end
    if frame.minLevelSlider then
        if locked then frame.minLevelSlider:Disable() else frame.minLevelSlider:Enable() end
        frame.minLevelSlider:SetAlpha(locked and 0.5 or 1)
    end
    for _, slider in ipairs({ frame.deathlogOpacitySlider, frame.deathlogShadowSlider, frame.deathlogFontSlider }) do
        if slider then
            if locked then slider:Disable() else slider:Enable() end
            slider:SetAlpha(locked and 0.5 or 1)
        end
    end

    local controls = {
        frame.cbSelfFound,
        frame.cbWeapon,
        frame.cbRepair,
        frame.cbPvpDeathProtection,
        frame.cbMinimap,
        frame.cbBroadcast,
        frame.cbGuildMessage,
        frame.cbRealmBroadcast,
        frame.cbShowPopup,
        frame.cbShowWarning,
        frame.cbStats,
        frame.cbDeathlog,
        frame.cbDeathlogLevel,
        frame.cbDeathlogCount,
        frame.cbDeathlogItem,
        frame.cbDeathlogSource,
        frame.cbDurHUD,
        frame.cbDurShowAll,
        frame.cbDurGrowUpward,
        frame.cbDurReverseOrder,
        frame.cbStatsHorizontal,
        frame.importBtn,
    }
    for _, control in ipairs(controls) do
        if control then
            if locked then control:Disable() else control:Enable() end
            control:SetAlpha(locked and 0.5 or 1)
        end
    end

    if frame.importDropdown then
        frame.importDropdown:SetAlpha(locked and 0.5 or 1)
    end
    if frame.importDropdownClick then
        frame.importDropdownClick:EnableMouse(not locked)
    end

    if frame.titleText then
        frame.titleText:SetText(DEFAULT_TITLE_TEXT)
    end
    if frame.combatNote then
        if locked then frame.combatNote:Show() else frame.combatNote:Hide() end
    end
end

-- ── Frame construction ────────────────────────────────────────────────────────

local function BuildOptionsFrame()
    local f = CreateFrame("Frame", "RustcoreOptionsFrame", UIParent, backdropTemplate)
    f:SetSize(640, 580)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    RustcoreTheme.ApplyFrameSkin(f)

    -- Keep the difficulty artwork, but darken it enough for controls and labels.
    local bgShade = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    bgShade:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
    bgShade:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    bgShade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bgShade:SetVertexColor(0, 0, 0, 0.62)

    -- The border art (RustcoreTheme.ApplyFrameSkin) lives on its own child
    -- frame at f's level + 1; a plain texture painted directly on f would
    -- always lose to that child frame regardless of draw layer, so the
    -- panel and its text both live on this one elevated child frame instead.
    local titleFrame = CreateFrame("Frame", nil, f)
    titleFrame:SetSize(96, 18)
    titleFrame:SetPoint("CENTER", f, "TOP", 0, -3)
    titleFrame:SetFrameLevel(f:GetFrameLevel() + 5)

    local titlePanel = titleFrame:CreateTexture(nil, "ARTWORK")
    titlePanel:SetTexture(Rustcore.GetAssetPath("UI/Window-title-panel.tga"))
    titlePanel:SetSize(140, 30)
    titlePanel:SetPoint("CENTER", titleFrame, "CENTER", 0, 0)

    local title = titleFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", titleFrame, "CENTER", 0, -1)
    title:SetWidth(92)
    ApplyBodyFont(title, 16)
    title:SetTextColor(unpack(TITLE_COLOR))
    title:SetShadowColor(0, 0, 0, 0.6)
    title:SetShadowOffset(1, -1)
    title:SetText(DEFAULT_TITLE_TEXT)
    f.titleText = title

    local dragHandle = CreateFrame("Frame", nil, f)
    dragHandle:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    dragHandle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -10)
    dragHandle:SetHeight(38)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() f:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -6)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    RustcoreTheme.SkinExitButton(closeBtn)

    local RefreshAllControls

    local diffHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diffHeader:SetPoint("TOP", f, "TOP", 0, -48)
    diffHeader:SetJustifyH("CENTER")
    diffHeader:SetText("")
    ApplyBodyFont(diffHeader, 18)
    f.diffHeader = diffHeader

    local slider = CreateFrame("Slider", "RustcoreDifficultySlider", f, "OptionsSliderTemplate")
    slider:SetPoint("TOP", diffHeader, "BOTTOM", 0, -30)
    slider:SetWidth(380)
    slider:SetMinMaxValues(1, 5)
    slider:SetValueStep(1)
    local sliderTrack = RustcoreTheme.SkinSlider(slider, 400, -1)

    local sliderLow  = _G[slider:GetName().."Low"]
    local sliderHigh = _G[slider:GetName().."High"]
    local sliderText = _G[slider:GetName().."Text"]
    if sliderLow then
        sliderLow:SetText("Rusted")
        sliderLow:ClearAllPoints()
        sliderLow:SetPoint("TOPLEFT", sliderTrack, "BOTTOMLEFT", 4, -4)
        ApplyBodyFont(sliderLow, 14)
    end
    if sliderHigh then
        sliderHigh:SetText("Dust")
        sliderHigh:ClearAllPoints()
        sliderHigh:SetPoint("TOPRIGHT", sliderTrack, "BOTTOMRIGHT", -4, -4)
        ApplyBodyFont(sliderHigh, 14)
    end
    if sliderText then
        sliderText:SetText(DIFF_LABELS[Rustcore.GetSetting("difficulty")])
        sliderText:ClearAllPoints()
        sliderText:SetPoint("CENTER", diffHeader, "CENTER", 0, 0)
        sliderText:SetJustifyH("CENTER")
        sliderText:SetWidth(220)
        ApplyDifficultyLabelStyle(slider, Rustcore.GetSetting("difficulty"))
    end
    f.sliderText = sliderText

    local diffDesc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diffDesc:SetPoint("TOP", sliderTrack, "BOTTOM", 0, -22)
    diffDesc:SetWidth(490)
    diffDesc:SetJustifyH("CENTER")
    diffDesc:SetTextColor(1, 0.82, 0)
    diffDesc:SetText(DIFF_DESCS[Rustcore.GetSetting("difficulty")])
    ApplyBodyFont(diffDesc, 14)

    local combatNote = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatNote:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -32)
    combatNote:SetWidth(160)
    combatNote:SetJustifyH("RIGHT")
    combatNote:SetTextColor(1, 0.35, 0.25)
    combatNote:SetText(COMBAT_NOTE_TEXT)
    ApplyBodyFont(combatNote, 13)
    combatNote:Hide()
    f.combatNote = combatNote

    slider:SetScript("OnValueChanged", function(self, value)
        ApplyDifficultyValue(self, diffDesc, value)
    end)
    slider:SetScript("OnMouseUp", function(self)
        ApplyDifficultyValue(self, diffDesc, self:GetValue())
    end)
    slider:SetValue(Rustcore.GetSetting("difficulty"))

    f.diffSlider = slider
    f.diffDesc   = diffDesc

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -154)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)

    local topRule = content:CreateTexture(nil, "ARTWORK")
    topRule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    topRule:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    topRule:SetHeight(4)
    topRule:SetTexture(Rustcore.GetAssetPath("UI/Line-horizontal.tga"))

    local navWidth = 160
    local navShade = content:CreateTexture(nil, "BACKGROUND", nil, 3)
    navShade:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
    navShade:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    navShade:SetWidth(navWidth)
    navShade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    navShade:SetVertexColor(0, 0, 0, 0.72)

    local navRule = content:CreateTexture(nil, "ARTWORK")
    navRule:SetPoint("TOPLEFT", content, "TOPLEFT", navWidth, -2)
    navRule:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", navWidth, 0)
    navRule:SetWidth(4)
    navRule:SetTexture(Rustcore.GetAssetPath("UI/Line-vertical.tga"))

    local function MakePage()
        local page = CreateFrame("Frame", nil, content)
        page:SetPoint("TOPLEFT", content, "TOPLEFT", navWidth + 2, -2)
        page:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        page:Hide()
        return page
    end

    local function MakeHeader(page, text, y)
        local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", page, "TOPLEFT", 26, y)
        header:SetText(text)
        ApplyBodyFont(header, 19)
        return header
    end

    local function MakeRule(page, y)
        local rule = page:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("TOPLEFT", page, "TOPLEFT", 20, y)
        rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -20, y)
        rule:SetHeight(4)
        rule:SetTexture(Rustcore.GetAssetPath("UI/Line-horizontal.tga"))
        return rule
    end

    local gameplayPage = MakePage()
    local interfacePage = MakePage()
    local notificationsPage = MakePage()
    local appearancePage = MakePage()
    local temperedPage = MakePage()

    local function PercentFormatter(value) return math.floor(value * 100 + 0.5) .. "%" end

    local interfaceScroll = CreateFrame(
        "ScrollFrame",
        "RustcoreInterfaceOptionsScrollFrame",
        interfacePage,
        "UIPanelScrollFrameTemplate"
    )
    interfaceScroll:SetPoint("TOPLEFT", interfacePage, "TOPLEFT", 0, 0)
    interfaceScroll:SetPoint("BOTTOMRIGHT", interfacePage, "BOTTOMRIGHT", -24, 0)
    interfaceScroll:EnableMouseWheel(true)

    local interfaceContent = CreateFrame("Frame", nil, interfaceScroll)
    interfaceContent:SetSize(410, 500)
    interfaceScroll:SetScrollChild(interfaceContent)

    local interfaceScrollBar = interfaceScroll.ScrollBar
        or _G[interfaceScroll:GetName().."ScrollBar"]
    interfaceScroll:SetScript("OnMouseWheel", function(_, delta)
        if not interfaceScrollBar then return end
        local minValue, maxValue = interfaceScrollBar:GetMinMaxValues()
        local nextValue = interfaceScrollBar:GetValue() - (delta * 28)
        interfaceScrollBar:SetValue(math.max(minValue, math.min(maxValue, nextValue)))
    end)

    local notificationsScroll = CreateFrame(
        "ScrollFrame",
        "RustcoreNotificationsOptionsScrollFrame",
        notificationsPage,
        "UIPanelScrollFrameTemplate"
    )
    notificationsScroll:SetPoint("TOPLEFT", notificationsPage, "TOPLEFT", 0, 0)
    notificationsScroll:SetPoint("BOTTOMRIGHT", notificationsPage, "BOTTOMRIGHT", -24, 0)
    notificationsScroll:EnableMouseWheel(true)

    local notificationsContent = CreateFrame("Frame", nil, notificationsScroll)
    notificationsContent:SetSize(410, 700)
    notificationsScroll:SetScrollChild(notificationsContent)

    local notificationsScrollBar = notificationsScroll.ScrollBar
        or _G[notificationsScroll:GetName().."ScrollBar"]
    notificationsScroll:SetScript("OnMouseWheel", function(_, delta)
        if not notificationsScrollBar then return end
        local minValue, maxValue = notificationsScrollBar:GetMinMaxValues()
        local nextValue = notificationsScrollBar:GetValue() - (delta * 28)
        notificationsScrollBar:SetValue(math.max(minValue, math.min(maxValue, nextValue)))
    end)

    local appearanceScroll = CreateFrame(
        "ScrollFrame",
        "RustcoreAppearanceOptionsScrollFrame",
        appearancePage,
        "UIPanelScrollFrameTemplate"
    )
    appearanceScroll:SetPoint("TOPLEFT", appearancePage, "TOPLEFT", 0, 0)
    appearanceScroll:SetPoint("BOTTOMRIGHT", appearancePage, "BOTTOMRIGHT", -24, 0)
    appearanceScroll:EnableMouseWheel(true)

    local appearanceContent = CreateFrame("Frame", nil, appearanceScroll)
    appearanceContent:SetSize(410, 520)
    appearanceScroll:SetScrollChild(appearanceContent)

    local appearanceScrollBar = appearanceScroll.ScrollBar
        or _G[appearanceScroll:GetName().."ScrollBar"]
    appearanceScroll:SetScript("OnMouseWheel", function(_, delta)
        if not appearanceScrollBar then return end
        local minValue, maxValue = appearanceScrollBar:GetMinMaxValues()
        local nextValue = appearanceScrollBar:GetValue() - (delta * 28)
        appearanceScrollBar:SetValue(math.max(minValue, math.min(maxValue, nextValue)))
    end)

    -- Gameplay
    local rulesHeader = MakeHeader(gameplayPage, "Rules", -20)
    local cbSelfFound = MakeCheckbox(gameplayPage,
        "Self-Found Mode",
        "Blocks access to the mailbox, auction house, and player trading.",
        rulesHeader, -6, "selfFound")

    local cbPvpDeathProtection = MakeCheckbox(gameplayPage,
        "Ignore PVP Death",
        "If an enemy player damages you at any point during a combat, dying in the same combat will not mark any items for deletion.",
        cbSelfFound, -4, "ignoreDeathAfterEnemyPlayerDamage")

    local cbWeapon = MakeCheckbox(gameplayPage,
        "Keep Main Weapon",
        "Spares your main weapon from deletion.\n"
        .."Hunter: Ranged slot\n"
        .."Melee (Warrior/Paladin/Rogue/Shaman/Druid): Main Hand\n"
        .."Caster (Priest/Mage/Warlock): Wand if equipped, else Main Hand",
        cbPvpDeathProtection, -4, "keepMainWeapon")

    local cbRepair = MakeCheckbox(gameplayPage,
        "Allow Item Repair",
        "Allows repair at merchants. By default repair is always blocked.",
        cbWeapon, -4, "allowRepair")

    MakeRule(gameplayPage, -190)
    local profileHeader = MakeHeader(gameplayPage, "Character Profile", -210)

    local profileDesc = gameplayPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileDesc:SetPoint("TOPLEFT", profileHeader, "BOTTOMLEFT", 0, -6)
    profileDesc:SetWidth(360)
    profileDesc:SetJustifyH("LEFT")
    profileDesc:SetText("Import settings from another character.")
    ApplyBodyFont(profileDesc, 14)

    -- Interface
    local featuresHeader = MakeHeader(interfaceContent, "Features", -20)
    local cbMinimap = MakeCheckbox(interfaceContent,
        "Show Minimap Button",
        "Show or hide the Rustcore minimap button.",
        featuresHeader, -6, "showMinimapButton")

    local cbDurHUD = MakeCheckbox(interfaceContent,
        "Show Durability HUD",
        "Replaces WoW's native durability frame with per-slot artwork. Only slots near 0 durability are shown by default. Reload UI to restore the original durability frame after disabling.",
        cbMinimap, -4, "showDurabilityHUD")

    local cbDurShowAll = MakeCheckbox(interfaceContent,
        "Always Show All Slots",
        "Show durability for every equipped slot at all times, not just items with low durability.",
        cbDurHUD, -3, "showAllDurability", 34, 20, 14)

    local cbDurGrowUpward = MakeCheckbox(interfaceContent,
        "Grow Upward",
        "Makes the durability HUD grow upward from its anchor point instead of downward.",
        cbDurShowAll, -3, "durHUDGrowUpward", 0, 20, 14)

    local cbDurReverseOrder = MakeCheckbox(interfaceContent,
        "Reverse Order",
        "Reverses the durability HUD stack order, placing the most damaged item at the bottom instead of the top.",
        cbDurGrowUpward, -3, "durHUDReverseOrder", 0, 20, 14)

    local cbStats = MakeCheckbox(interfaceContent,
        "Show Stats Window",
        "Show or hide the Rustcore item loss stats window.",
        cbDurReverseOrder, -7, "showStatsWindow", -34)

    local cbStatsHorizontal = MakeCheckbox(interfaceContent,
        "Horizontal Display",
        "Arranges all stats window elements in a single row instead of two.",
        cbStats, -3, "statsHorizontalLayout", 34, 20, 14)

    local cbDragonPlayerFrame = MakeCheckbox(interfaceContent,
        "Dragon on Player Frame",
        "Shows a dragon on your own player frame that reflects your current difficulty tier.",
        cbStatsHorizontal, -7, "dragonPlayerFrame", -34)

    local cbDragonTargetFrame = MakeCheckbox(interfaceContent,
        "Dragon on Target Frame",
        "Shows a dragon on the target frame reflecting the difficulty tier of the targeted player, when they also run Rustcore. Also shown when targeting yourself.",
        cbDragonPlayerFrame, -7, "dragonTargetFrame")

    -- Notifications
    local bcHeader = MakeHeader(notificationsContent, "Broadcast", -20)
    local cbBroadcast = MakeCheckbox(notificationsContent,
        "Broadcast My Death",
        "Announces your death and the item you lost to other Rustcore users.",
        bcHeader, -6, "broadcastDeaths")

    local cbGuildMessage = MakeCheckbox(notificationsContent,
        "Guild Broadcast",
        "Send a message in guild chat when you die with the item you lost.",
        cbBroadcast, -4, "guildDeathMessage", 34, 20, 14)

    local cbRealmBroadcast = MakeCheckbox(notificationsContent,
        "Realm Broadcast",
        "Broadcast your death realm-wide to other Rustcore users via a shared channel, not just guild/group.",
        cbGuildMessage, -3, "broadcastDeathsRealmWide", 0, 20, 14)

    local cbShowPopup = MakeCheckbox(notificationsContent,
        "Show Death Messages",
        "Display a chat message when another Rustcore player dies.",
        cbRealmBroadcast, -8, "showDeathPopup", -34)

    local cbShowWarning = MakeCheckbox(notificationsContent,
        "Show Center Warning",
        "Display a center-screen raid warning when another Rustcore player dies.",
        cbShowPopup, -4, "showDeathWarning")

    MakeRule(notificationsContent, -195)
    local deathlogHeader = MakeHeader(notificationsContent, "Death Log", -215)
    local cbDeathlog = MakeCheckbox(notificationsContent,
        "Show Death Log",
        "Show or hide the Rustcore death log window listing other players' deaths.",
        deathlogHeader, -6, "showDeathlogWindow")

    local cbDeathlogLevel = MakeCheckbox(notificationsContent,
        "Show Level", "Show the victim's level in each death log entry.",
        cbDeathlog, -3, "showDeathlogLevel", 34, 20, 14)

    local cbDeathlogSource = MakeCheckbox(notificationsContent,
        "Show Death Source", "Show what killed the player.",
        cbDeathlogLevel, -3, "showDeathlogSource", 0, 20, 14)

    local cbDeathlogCount = MakeCheckbox(notificationsContent,
        "Show Items", "Show the number of items lost in each death log entry.",
        cbDeathlogSource, -3, "showDeathlogCount", 0, 20, 14)

    local cbDeathlogItem = MakeCheckbox(notificationsContent,
        "Show Lost Item", "Show an icon (with tooltip) for the most valuable item lost.",
        cbDeathlogCount, -3, "showDeathlogItem", 0, 20, 14)

    local minLevelSlider = MakeSettingSlider(
        notificationsContent,
        "RustcoreDeathlogMinLevelSlider",
        "Minimum Level",
        -400, 0, 60, 1, "deathlogMinLevel",
        function(value) return value == 0 and "Off" or tostring(value) end
    )

    -- Appearance
    MakeHeader(appearanceContent, "Stats Panel", -20)
    local opacitySlider = MakeSettingSlider(
        appearanceContent,
        "RustcoreStatsOpacitySlider",
        "Background Opacity",
        -65, 0, 1, 0.01, "statsBackgroundOpacity",
        PercentFormatter
    )
    local shadowSlider = MakeSettingSlider(
        appearanceContent,
        "RustcoreStatsShadowSlider",
        "Dark Overlay",
        -130, 0, 1, 0.01, "statsBackgroundShadow",
        PercentFormatter
    )
    MakeRule(appearanceContent, -170)
    MakeHeader(appearanceContent, "Death Log", -190)
    local deathlogOpacitySlider = MakeSettingSlider(
        appearanceContent,
        "RustcoreDeathlogOpacitySlider",
        "Background Opacity",
        -235, 0, 1, 0.01, "deathlogBackgroundOpacity",
        PercentFormatter
    )
    local deathlogShadowSlider = MakeSettingSlider(
        appearanceContent,
        "RustcoreDeathlogShadowSlider",
        "Dark Overlay",
        -300, 0, 1, 0.01, "deathlogBackgroundShadow",
        PercentFormatter
    )
    local deathlogFontSlider = MakeSettingSlider(
        appearanceContent,
        "RustcoreDeathlogFontSlider",
        "Font Size",
        -365, 9, 16, 1, "deathlogFontSize",
        function(value) return tostring(value) end
    )

    -- Tempered Souls
    local waitingText = temperedPage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    waitingText:SetPoint("TOPLEFT", temperedPage, "TOPLEFT", 26, -28)
    waitingText:SetPoint("TOPRIGHT", temperedPage, "TOPRIGHT", -26, -28)
    waitingText:SetJustifyH("LEFT")
    waitingText:SetText("Waiting for tempered souls to appear.")
    ApplyBodyFont(waitingText, 17)

    local importDropdown = CreateFrame("Frame", "RustcoreImportProfileDropdown", gameplayPage, "UIDropDownMenuTemplate")
    importDropdown:SetPoint("TOPLEFT", profileDesc, "BOTTOMLEFT", 0, -10)
    UIDropDownMenu_SetWidth(importDropdown, 190)

    local ddName = importDropdown:GetName()
    local ddLeft, ddMiddle, ddRight, ddButton, ddText, ddIcon =
        _G[ddName.."Left"], _G[ddName.."Middle"], _G[ddName.."Right"],
        _G[ddName.."Button"], _G[ddName.."Text"], _G[ddName.."Icon"]
    if ddLeft then ddLeft:Hide() end
    if ddMiddle then ddMiddle:Hide() end
    if ddRight then ddRight:Hide() end
    if ddIcon then ddIcon:Hide() end
    if ddButton then ddButton:Hide(); ddButton:EnableMouse(false) end

    local ddBg = importDropdown:CreateTexture(nil, "BACKGROUND")
    ddBg:SetTexture(Rustcore.GetAssetPath("UI/Lostitemframe Dark copy.tga"))
    ddBg:SetSize(190, 26)
    ddBg:SetPoint("TOPLEFT", importDropdown, "TOPLEFT", 0, 0)

    local PLACEHOLDER_COLOR = { 0.6, 0.6, 0.6 }
    local SELECTED_COLOR = { 1, 1, 1 }

    if ddText then
        ddText:ClearAllPoints()
        ddText:SetJustifyH("LEFT")
        ddText:SetPoint("LEFT", ddBg, "LEFT", 10, -1)
        ApplyBodyFont(ddText, 14)
    end

    local ddClick = CreateFrame("Button", nil, importDropdown)
    ddClick:SetAllPoints(ddBg)

    local importBtn = CreateFrame("Button", nil, gameplayPage, "UIPanelButtonTemplate")
    importBtn:SetSize(82, 22)
    importBtn:SetPoint("LEFT", ddBg, "RIGHT", 12, 0)
    importBtn:SetText("Import")
    RustcoreTheme.SkinButton(importBtn)
    ApplyBodyFont(importBtn:GetFontString(), 14)

    local LAYOUT_IMPORT_KEYS = { "durHUDPos", "statsWindowPoint", "statsWindowSize", "minimapAngle", "deathlogWindowPoint", "deathlogWindowSize" }
    local selectedProfileKey = nil

    local function RefreshImportDropdownText()
        local profiles = RustcoreDB.profiles or {}
        local currentKey = Rustcore.GetCharacterKey()
        if selectedProfileKey and (selectedProfileKey == currentKey or not profiles[selectedProfileKey]) then
            selectedProfileKey = nil
        end
        if selectedProfileKey and profiles[selectedProfileKey] then
            UIDropDownMenu_SetText(importDropdown, profiles[selectedProfileKey].characterLabel or selectedProfileKey)
            if ddText then ddText:SetTextColor(unpack(SELECTED_COLOR)) end
        else
            UIDropDownMenu_SetText(importDropdown, "Click to select")
            if ddText then ddText:SetTextColor(unpack(PLACEHOLDER_COLOR)) end
        end
    end

    ddClick:SetScript("OnClick", function()
        if SettingsLocked() then return end
        ToggleDropDownMenu(1, nil, importDropdown, importDropdown, 0, 0)
    end)

    local function ApplyDropdownListStyle(level, value, dropDownFrame)
        if dropDownFrame ~= importDropdown then return end
        if UIDROPDOWNMENU_OPEN_MENU ~= ddName then return end
        level = level or 1
        local listFrame = _G["DropDownList"..level]
        if not (listFrame and listFrame:IsShown()) then return end
        if level == 1 then
            listFrame:ClearAllPoints()
            listFrame:SetPoint("TOP", ddBg, "BOTTOM", -6, 2)
            if listFrame.SetBackdrop then listFrame:SetBackdrop(nil) end
            local listBackdrop = _G[listFrame:GetName().."Backdrop"]
            if listBackdrop then
                listBackdrop:Hide()
                if listBackdrop.SetBackdrop then listBackdrop:SetBackdrop(nil) end
            end
        end
        for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
            local btn = _G["DropDownList"..level.."Button"..i]
            if not btn or not btn:IsShown() then break end
            local btnText = _G[btn:GetName().."NormalText"]
            if btnText then ApplyBodyFont(btnText, 14) end
        end
    end
    hooksecurefunc("ToggleDropDownMenu", ApplyDropdownListStyle)

    UIDropDownMenu_Initialize(importDropdown, function(self, level)
        local profiles = RustcoreDB.profiles or {}
        local currentKey = Rustcore.GetCharacterKey()
        for key, profile in pairs(profiles) do
            if key ~= currentKey then
                local info = UIDropDownMenu_CreateInfo()
                info.text = profile.characterLabel or key
                info.value = key
                info.justificationH = "RIGHT"
                info.func = function()
                    selectedProfileKey = key
                    RefreshImportDropdownText()
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)

    importBtn:SetScript("OnClick", function()
        if not selectedProfileKey then return end
        if SettingsLocked() then
            print("|cffff4444Rustcore:|r Settings cannot be changed while in combat.")
            return
        end
        local profiles = RustcoreDB.profiles or {}
        local source = profiles[selectedProfileKey]
        if not source then return end

        for _, key in ipairs(LAYOUT_IMPORT_KEYS) do
            if source[key] ~= nil then
                Rustcore.SetProfileValue(key, source[key])
            end
        end
        for _, key in ipairs(Rustcore.GetDefaultSettingKeys()) do
            if source[key] ~= nil then
                Rustcore.SetSetting(key, source[key])
            end
        end

        if RustcoreDurability and RustcoreDurability.RefreshPosition then RustcoreDurability.RefreshPosition() end
        if RustcoreStats and RustcoreStats.RefreshPosition then RustcoreStats.RefreshPosition() end
        if RustcoreDeathlog and RustcoreDeathlog.RefreshPosition then RustcoreDeathlog.RefreshPosition() end
        if Rustcore.RefreshMinimapPosition then Rustcore.RefreshMinimapPosition() end
        if RefreshAllControls then RefreshAllControls(f) end

        PlaySoundFile(Rustcore.GetAssetPath("Audio/ticksound2.wav"), "Master")
    end)

    RefreshImportDropdownText()

    local pages = {
        gameplay = gameplayPage,
        interface = interfacePage,
        notifications = notificationsPage,
        appearance = appearancePage,
        tempered = temperedPage,
    }
    local tabs = {}

    local function ShowPage(pageKey)
        for key, page in pairs(pages) do
            if key == pageKey then page:Show() else page:Hide() end
        end
        for key, tab in pairs(tabs) do
            local selected = key == pageKey
            local normalTexture = tab:GetNormalTexture()
            if normalTexture then
                if selected then
                    normalTexture:SetVertexColor(0.52, 0.68, 1, 1)
                else
                    normalTexture:SetVertexColor(1, 1, 1, 1)
                end
            end
            local tabText = tab:GetFontString()
            if tabText then
                tabText:SetTextColor(selected and 1 or 0.95, selected and 0.82 or 0.78, selected and 0 or 0.52)
            end
        end
        f.activePage = pageKey
    end

    local function MakeTab(pageKey, label, index)
        local tab = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        tab:SetSize(navWidth, 42)
        tab:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2 - ((index - 1) * 42))
        tab:SetText(label)
        RustcoreTheme.SkinButton(tab)
        ApplyBodyFont(tab:GetFontString(), 17)

        local nativeHighlight = tab:GetHighlightTexture()
        if nativeHighlight then
            nativeHighlight:SetTexture(nil)
            nativeHighlight:Hide()
        end
        local normalTexture = tab:GetNormalTexture()
        if normalTexture and normalTexture.SetDesaturated then
            normalTexture:SetDesaturated(true)
        end
        local pushedTexture = tab:GetPushedTexture()
        if pushedTexture then
            if pushedTexture.SetDesaturated then pushedTexture:SetDesaturated(true) end
            pushedTexture:SetVertexColor(0.42, 0.62, 1, 1)
        end
        if tab.rustcoreThemeHover then
            tab.rustcoreThemeHover:SetBlendMode("BLEND")
            tab.rustcoreThemeHover:SetVertexColor(0.16, 0.4, 0.86, 0.38)
        end

        tab:SetScript("OnClick", function()
            PlaySoundFile(Rustcore.GetAssetPath("Audio/ticksound2.wav"), "Master")
            ShowPage(pageKey)
        end)
        tabs[pageKey] = tab
    end

    MakeTab("gameplay", "Gameplay", 1)
    MakeTab("interface", "Interface", 2)
    MakeTab("notifications", "Notifications", 3)
    MakeTab("appearance", "Appearance", 4)
    MakeTab("tempered", "Tempered Souls", 5)
    ShowPage("gameplay")

    -- Store refs for Refresh
    f.cbSelfFound   = cbSelfFound
    f.cbWeapon      = cbWeapon
    f.cbRepair      = cbRepair
    f.cbPvpDeathProtection = cbPvpDeathProtection
    f.cbMinimap     = cbMinimap
    f.cbBroadcast   = cbBroadcast
    f.cbGuildMessage= cbGuildMessage
    f.cbRealmBroadcast = cbRealmBroadcast
    f.cbShowPopup   = cbShowPopup
    f.cbShowWarning = cbShowWarning
    f.cbStats       = cbStats
    f.cbDeathlog = cbDeathlog
    f.cbDeathlogLevel = cbDeathlogLevel
    f.cbDeathlogCount = cbDeathlogCount
    f.cbDeathlogItem = cbDeathlogItem
    f.cbDeathlogSource = cbDeathlogSource
    f.opacitySlider   = opacitySlider
    f.shadowSlider    = shadowSlider
    f.minLevelSlider  = minLevelSlider
    f.deathlogOpacitySlider = deathlogOpacitySlider
    f.deathlogShadowSlider = deathlogShadowSlider
    f.deathlogFontSlider = deathlogFontSlider
    f.cbDurHUD      = cbDurHUD
    f.cbDurShowAll  = cbDurShowAll
    f.cbDurGrowUpward = cbDurGrowUpward
    f.cbDurReverseOrder = cbDurReverseOrder
    f.cbStatsHorizontal = cbStatsHorizontal
    f.cbDragonPlayerFrame = cbDragonPlayerFrame
    f.cbDragonTargetFrame = cbDragonTargetFrame
    f.importBtn     = importBtn
    f.importDropdown = importDropdown
    f.importDropdownClick = ddClick
    f.RefreshImportDropdownText = RefreshImportDropdownText

    RefreshAllControls = function(self)
        local v = Rustcore.GetSetting("difficulty")
        RustcoreTheme.SetDifficultyBackground(self, v)
        self.diffSlider:SetValue(v)
        ApplyDifficultyLabelStyle(self.diffSlider, v)
        self.diffDesc:SetText(DIFF_DESCS[v])
        self.cbSelfFound:Refresh()
        self.cbWeapon:Refresh()
        self.cbRepair:Refresh()
        self.cbPvpDeathProtection:Refresh()
        self.cbMinimap:Refresh()
        self.cbBroadcast:Refresh()
        self.cbGuildMessage:Refresh()
        self.cbRealmBroadcast:Refresh()
        self.cbShowPopup:Refresh()
        self.cbShowWarning:Refresh()
        self.cbStats:Refresh()
        self.cbDeathlog:Refresh()
        self.cbDeathlogLevel:Refresh()
        self.cbDeathlogCount:Refresh()
        self.cbDeathlogItem:Refresh()
        self.cbDeathlogSource:Refresh()
        self.opacitySlider:SetValue(Rustcore.GetSetting("statsBackgroundOpacity"))
        self.shadowSlider:SetValue(Rustcore.GetSetting("statsBackgroundShadow"))
        self.minLevelSlider:SetValue(Rustcore.GetSetting("deathlogMinLevel"))
        self.deathlogOpacitySlider:SetValue(Rustcore.GetSetting("deathlogBackgroundOpacity"))
        self.deathlogShadowSlider:SetValue(Rustcore.GetSetting("deathlogBackgroundShadow"))
        self.deathlogFontSlider:SetValue(Rustcore.GetSetting("deathlogFontSize"))
        self.cbDurHUD:Refresh()
        self.cbDurShowAll:Refresh()
        self.cbDurGrowUpward:Refresh()
        self.cbDurReverseOrder:Refresh()
        self.cbStatsHorizontal:Refresh()
        self.cbDragonPlayerFrame:Refresh()
        self.cbDragonTargetFrame:Refresh()
        self.RefreshImportDropdownText()
    end

    f:SetScript("OnShow", function(self)
        RefreshAllControls(self)
        RefreshCombatLockState(self)
    end)

    f:SetScript("OnUpdate", function(self)
        if self._combatLocked ~= SettingsLocked() then
            self._combatLocked = SettingsLocked()
            RefreshCombatLockState(self)
        end
    end)

    f:Hide()
    return f
end

-- ── Public API ────────────────────────────────────────────────────────────────

function RustcoreOptions.Toggle()
    if not optFrame then optFrame = BuildOptionsFrame() end
    if optFrame:IsShown() then
        optFrame:Hide()
    else
        PlaySoundFile(Rustcore.GetAssetPath("Audio/Metalsound.wav"), "Master")
        optFrame:Show()
    end
end

function RustcoreOptions.Hide()
    if optFrame and optFrame:IsShown() then
        optFrame:Hide()
    end
end
