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

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local DEFAULT_TITLE_TEXT = "Rustcore Options"
local COMBAT_TITLE_TEXT = "Settings are locked\nwhile in combat"
local TITLE_FONT_PATH = Rustcore.GetAssetPath("Font/RUSTED PERSONAL USE.ttf")
local BODY_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")
local TITLE_COLOR = { 0.85, 0.15, 0.15 }
local PROFILE_SECTION_HEIGHT = 170

local function ApplyBodyFont(fontString, size)
    if not fontString then return end
    fontString:SetFont(BODY_FONT_PATH, math.max(10, (size or 18) - 2), "")
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
        local txt = _G[slider:GetName().."Text"]
        if txt then txt:SetText(DIFF_LABELS[v]) end
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
    local txt = _G[slider:GetName().."Text"]
    if txt then txt:SetText(DIFF_LABELS[v]) end
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

    local controls = {
        frame.cbSelfFound,
        frame.cbWeapon,
        frame.cbRepair,
        frame.cbPvpDeathProtection,
        frame.cbMinimap,
        frame.cbBroadcast,
        frame.cbGuildMessage,
        frame.cbShowPopup,
        frame.cbShowWarning,
        frame.cbStats,
        frame.cbStatsBlizzardFrame,
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

    if frame.combatNote then
        if locked then
            if frame.titleText then
                frame.titleText:SetText(COMBAT_TITLE_TEXT)
            end
            frame.combatNote:Show()
        else
            if frame.titleText then
                frame.titleText:SetText(DEFAULT_TITLE_TEXT)
            end
            frame.combatNote:Hide()
        end
    end
end

-- ── Frame construction ────────────────────────────────────────────────────────

local function BuildOptionsFrame()
    local f = CreateFrame("Frame", "RustcoreOptionsFrame", UIParent, backdropTemplate)
    f:SetSize(630, 618 + PROFILE_SECTION_HEIGHT)
    f:SetPoint("CENTER", 0, 55)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    RustcoreTheme.ApplyFrameSkin(f)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -32)
    title:SetFont(TITLE_FONT_PATH, 30, "")
    title:SetTextColor(unpack(TITLE_COLOR))
    title:SetShadowColor(0, 0, 0, 0.6)
    title:SetShadowOffset(1, -1)
    title:SetText(DEFAULT_TITLE_TEXT)
    f.titleText = title

    local bgShade = f:CreateTexture(nil, "ARTWORK")
    bgShade:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -18)
    bgShade:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18)
    bgShade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    bgShade:SetVertexColor(0, 0, 0, 0.10)

    local dragHandle = CreateFrame("Frame", nil, f)
    dragHandle:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    dragHandle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -10)
    dragHandle:SetHeight(28)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() f:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -6)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    RustcoreTheme.SkinExitButton(closeBtn)

    local leftColX = 34
    local rightColX = 290

    -- Assigned later, near the OnShow handler; referenced by the Character
    -- Profile import button, which is built earlier in this function.
    local RefreshAllControls

    -- ── Difficulty section ────────────────────────────────────────────────────
    local diffHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    diffHeader:SetPoint("TOP", title, "BOTTOM", 0, -30)
    diffHeader:SetJustifyH("CENTER")
    diffHeader:SetText("Difficulty Mode")
    ApplyBodyFont(diffHeader, 20)
    f.diffHeader = diffHeader

    -- Five-step slider (1=Lite, 2=Normal, 3=Hard, 4=Brutal, 5=Extreme)
    local slider = CreateFrame("Slider", "RustcoreDifficultySlider", f, "OptionsSliderTemplate")
    slider:SetPoint("TOP", diffHeader, "BOTTOM", 0, -34)
    slider:SetWidth(342)
    slider:SetMinMaxValues(1, 5)
    slider:SetValueStep(1)
    local sliderTrack = RustcoreTheme.SkinSlider(slider, 376, -1)

    local sliderLow  = _G[slider:GetName().."Low"]
    local sliderHigh = _G[slider:GetName().."High"]
    local sliderText = _G[slider:GetName().."Text"]
    if sliderLow then
        sliderLow:SetText("Rusted")
        sliderLow:ClearAllPoints()
        sliderLow:SetPoint("TOPLEFT", sliderTrack, "BOTTOMLEFT", 10, -6)
        ApplyBodyFont(sliderLow, 16)
    end
    if sliderHigh then
        sliderHigh:SetText("Dust")
        sliderHigh:ClearAllPoints()
        sliderHigh:SetPoint("TOPRIGHT", sliderTrack, "BOTTOMRIGHT", -10, -6)
        ApplyBodyFont(sliderHigh, 16)
    end
    if sliderText then
        sliderText:SetText(DIFF_LABELS[Rustcore.GetSetting("difficulty")])
        sliderText:ClearAllPoints()
        sliderText:SetPoint("TOP", diffHeader, "BOTTOM", 0, -10)
        sliderText:SetJustifyH("CENTER")
        sliderText:SetWidth(110)
        ApplyBodyFont(sliderText, 18)
    end
    f.sliderText = sliderText

    local diffDesc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    diffDesc:SetPoint("TOPLEFT", sliderTrack, "BOTTOMLEFT", 8, -26)
    diffDesc:SetWidth(420)
    diffDesc:SetJustifyH("LEFT")
    diffDesc:SetTextColor(1, 0.82, 0)
    diffDesc:SetText(DIFF_DESCS[Rustcore.GetSetting("difficulty")])
    ApplyBodyFont(diffDesc, 18)

    local combatNote = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatNote:SetPoint("BOTTOMLEFT", diffHeader, "TOPLEFT", -150, 8)
    combatNote:SetWidth(480)
    combatNote:SetJustifyH("LEFT")
    combatNote:SetWordWrap(true)
    combatNote:Hide()
    ApplyBodyFont(combatNote, 16)
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

    -- ── Exceptions section ────────────────────────────────────────────────────
    local excHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    excHeader:SetPoint("TOPLEFT", diffDesc, "BOTTOMLEFT", -8, -26)
    excHeader:SetText("Exceptions")
    ApplyBodyFont(excHeader, 20)

    local cbWeapon = MakeCheckbox(f,
        "Keep Main Weapon",
        "Spares your main weapon from deletion.\n"
        .."Hunter: Ranged slot\n"
        .."Melee (Warrior/Paladin/Rogue/Shaman/Druid): Main Hand\n"
        .."Caster (Priest/Mage/Warlock): Wand if equipped, else Main Hand",
        excHeader, -8, "keepMainWeapon")

    local cbRepair = MakeCheckbox(f,
        "Allow Item Repair",
        "Allows repair at merchants. By default repair is always blocked.",
        cbWeapon, -8, "allowRepair")

    local cbPvpDeathProtection = MakeCheckbox(f,
        "Ignore PVP Death",
        "If an enemy player damages you at any point during a combat, dying in the same combat will not mark any items for deletion.",
        cbRepair, -8, "ignoreDeathAfterEnemyPlayerDamage")

    local uiHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiHeader:SetPoint("TOPLEFT", cbPvpDeathProtection, "BOTTOMLEFT", 0, -16)
    uiHeader:SetText("Interface")
    ApplyBodyFont(uiHeader, 20)

    local cbMinimap = MakeCheckbox(f,
        "Show Minimap Button",
        "Show or hide the Rustcore minimap button.",
        uiHeader, -8, "showMinimapButton")

    local cbDurHUD = MakeCheckbox(f,
        "Show Durability HUD",
        "Replaces WoW's native durability frame with per-slot artwork. Only slots near 0 durability are shown by default. Reload UI to restore the original durability frame after disabling.",
        cbMinimap, -8, "showDurabilityHUD")

    local cbDurShowAll = MakeCheckbox(f,
        "Always Show All Slots",
        "Show durability for every equipped slot at all times, not just items with low durability.",
        cbDurHUD, -6, "showAllDurability", 34, 20, 14)

    local cbDurGrowUpward = MakeCheckbox(f,
        "Grow Upward",
        "Makes the durability HUD grow upward from its anchor point instead of downward.",
        cbDurShowAll, -6, "durHUDGrowUpward", 0, 20, 14)

    local cbDurReverseOrder = MakeCheckbox(f,
        "Reverse Order",
        "Reverses the durability HUD stack order, placing the most damaged item at the bottom instead of the top.",
        cbDurGrowUpward, -6, "durHUDReverseOrder", 0, 20, 14)

    local cbStats = MakeCheckbox(f,
        "Show Stats Window",
        "Show or hide the Rustcore item loss stats window.",
        cbDurReverseOrder, -12, "showStatsWindow", -34)

    local cbStatsHorizontal = MakeCheckbox(f,
        "Horizontal Display",
        "Arranges all stats window elements in a single row instead of two.",
        cbStats, -6, "statsHorizontalLayout", 34, 20, 14)

    local cbStatsBlizzardFrame = MakeCheckbox(f,
        "Use Default Blizzard Frame",
        "Replaces the stats window's corner rivets with a standard Blizzard UI window border.",
        cbStatsHorizontal, -6, "statsUseBlizzardFrame", 0, 20, 14)

    local opacitySlider = CreateFrame("Slider", "RustcoreStatsOpacitySlider", f, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", cbStatsBlizzardFrame, "BOTTOMLEFT", 4, -34)
    opacitySlider:SetWidth(140)

    local opacityLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    opacityLabel:SetPoint("BOTTOM", opacitySlider, "TOP", 0, 6)
    opacityLabel:SetText("Background Opacity")
    ApplyBodyFont(opacityLabel, 14)

    opacitySlider:SetMinMaxValues(0, 1)
    opacitySlider:SetValueStep(0.01)
    local opacityTrack = RustcoreTheme.SkinSlider(opacitySlider, 140, -1)

    local opacityLow  = _G[opacitySlider:GetName().."Low"]
    local opacityHigh = _G[opacitySlider:GetName().."High"]
    local opacityText = _G[opacitySlider:GetName().."Text"]
    if opacityLow  then opacityLow:SetText("")  end
    if opacityHigh then opacityHigh:SetText("") end
    if opacityText then
        opacityText:ClearAllPoints()
        opacityText:SetPoint("TOP", opacityTrack, "BOTTOM", 0, -4)
        ApplyBodyFont(opacityText, 14)
    end

    local function ApplyOpacityValue(slider, value)
        local v = math.floor(math.max(0, math.min(1, value)) * 100 + 0.5) / 100
        if math.abs((slider:GetValue() or v) - v) > 0.001 then
            slider:SetValue(v)
            return
        end
        if opacityText then opacityText:SetText(math.floor(v * 100 + 0.5) .. "%") end

        if Rustcore.GetSetting("statsBackgroundOpacity") == v then return end
        if not Rustcore.SetSetting("statsBackgroundOpacity", v) then
            local current = Rustcore.GetSetting("statsBackgroundOpacity")
            if math.abs((slider:GetValue() or current) - current) > 0.001 then
                slider:SetValue(current)
            end
        end
    end

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        ApplyOpacityValue(self, value)
    end)
    opacitySlider:SetValue(Rustcore.GetSetting("statsBackgroundOpacity"))

    local shadowSlider = CreateFrame("Slider", "RustcoreStatsShadowSlider", f, "OptionsSliderTemplate")
    shadowSlider:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, -48)
    shadowSlider:SetWidth(140)

    local shadowLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    shadowLabel:SetPoint("BOTTOM", shadowSlider, "TOP", 0, 6)
    shadowLabel:SetText("Background Shadow")
    ApplyBodyFont(shadowLabel, 14)

    shadowSlider:SetMinMaxValues(0, 1)
    shadowSlider:SetValueStep(0.01)
    local shadowTrack = RustcoreTheme.SkinSlider(shadowSlider, 140, -1)

    local shadowLow  = _G[shadowSlider:GetName().."Low"]
    local shadowHigh = _G[shadowSlider:GetName().."High"]
    local shadowText = _G[shadowSlider:GetName().."Text"]
    if shadowLow  then shadowLow:SetText("")  end
    if shadowHigh then shadowHigh:SetText("") end
    if shadowText then
        shadowText:ClearAllPoints()
        shadowText:SetPoint("TOP", shadowTrack, "BOTTOM", 0, -4)
        ApplyBodyFont(shadowText, 14)
    end

    local function ApplyShadowValue(slider, value)
        local v = math.floor(math.max(0, math.min(1, value)) * 100 + 0.5) / 100
        if math.abs((slider:GetValue() or v) - v) > 0.001 then
            slider:SetValue(v)
            return
        end
        if shadowText then shadowText:SetText(math.floor(v * 100 + 0.5) .. "%") end

        if Rustcore.GetSetting("statsBackgroundShadow") == v then return end
        if not Rustcore.SetSetting("statsBackgroundShadow", v) then
            local current = Rustcore.GetSetting("statsBackgroundShadow")
            if math.abs((slider:GetValue() or current) - current) > 0.001 then
                slider:SetValue(current)
            end
        end
    end

    shadowSlider:SetScript("OnValueChanged", function(self, value)
        ApplyShadowValue(self, value)
    end)
    shadowSlider:SetValue(Rustcore.GetSetting("statsBackgroundShadow"))

    -- ── Self-Found section ────────────────────────────────────────────────────
    local sfHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sfHeader:SetPoint("TOPLEFT", diffDesc, "BOTTOMLEFT", rightColX - leftColX - 8, -26)
    sfHeader:SetText("Self-Found")
    ApplyBodyFont(sfHeader, 20)

    local cbSelfFound = MakeCheckbox(f,
        "Self-Found Mode",
        "Blocks access to the mailbox, auction house, and player trading.",
        sfHeader, -8, "selfFound")

    -- ── Death broadcast section ───────────────────────────────────────────────
    local bcHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bcHeader:SetPoint("TOPLEFT", cbSelfFound, "BOTTOMLEFT", 0, -16)
    bcHeader:SetText("Death Broadcast")
    ApplyBodyFont(bcHeader, 20)

    local cbBroadcast = MakeCheckbox(f,
        "Broadcast My Death",
        "Announces your death and the item you lost to other Rustcore users.",
        bcHeader, -8, "broadcastDeaths")

    local cbGuildMessage = MakeCheckbox(f,
        "Guild Message",
        "Send a message in guild chat when you die with the item you lost.",
        cbBroadcast, -8, "guildDeathMessage")

    local cbShowPopup = MakeCheckbox(f,
        "Show Death Messages",
        "Display a chat message when another Rustcore player dies.",
        cbGuildMessage, -8, "showDeathPopup")

    local cbShowWarning = MakeCheckbox(f,
        "Show Center Warning",
        "Display a center-screen raid warning when another Rustcore player dies.",
        cbShowPopup, -8, "showDeathWarning")

    -- ── Character Profile ─────────────────────────────────────────────
    local profileHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileHeader:SetPoint("TOPLEFT", cbShowWarning, "BOTTOMLEFT", 0, -20)
    profileHeader:SetText("Character Profile")
    ApplyBodyFont(profileHeader, 20)

    local profileDesc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileDesc:SetPoint("TOPLEFT", profileHeader, "BOTTOMLEFT", 0, -6)
    profileDesc:SetWidth(230)
    profileDesc:SetJustifyH("LEFT")
    profileDesc:SetText("Import settings from another character.")
    ApplyBodyFont(profileDesc, 14)

    -- Custom-skinned dropdown: all native UIDropDownMenuTemplate art
    -- (side textures + arrow button) is hidden, replaced with the
    -- "Lostitemframe Dark copy" texture sized/centered directly (not
    -- inset from the template's own bounds, so it isn't constrained by
    -- the template's built-in padding). A full-size invisible button
    -- handles clicks anywhere on the art.
    local importDropdown = CreateFrame("Frame", "RustcoreImportProfileDropdown", f, "UIDropDownMenuTemplate")
    importDropdown:SetPoint("TOPLEFT", profileDesc, "BOTTOMLEFT", 0, -10)
    UIDropDownMenu_SetWidth(importDropdown, 150)

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
    ddBg:SetSize(141, 24) -- ~20% larger than the original inset-derived size, +10% more to match text overflow
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

    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(69, 18)
    importBtn:SetPoint("TOPLEFT", ddBg, "BOTTOMLEFT", 0, -10)
    importBtn:SetText("Import")
    RustcoreTheme.SkinButton(importBtn)
    ApplyBodyFont(importBtn:GetFontString(), 14)

    local LAYOUT_IMPORT_KEYS = { "durHUDPos", "statsWindowPoint", "statsWindowSize", "minimapAngle" }
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

    -- Re-font the popout menu buttons to match BPpong and recenter the
    -- list frame below our custom graphic whenever this dropdown's list
    -- opens. Blizzard's ToggleDropDownMenu repositions and re-backdrops
    -- the list frame AFTER calling Show() on it, so hooking OnShow was
    -- too early (our changes got overwritten). Hooking the outer function
    -- itself with hooksecurefunc runs after Blizzard's own logic finishes,
    -- so our styling is the last thing applied and actually sticks.
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
        if Rustcore.RefreshMinimapPosition then Rustcore.RefreshMinimapPosition() end
        if RefreshAllControls then RefreshAllControls(f) end

        PlaySoundFile(Rustcore.GetAssetPath("Audio/ticksound2.wav"), "Master")
    end)

    RefreshImportDropdownText()

    -- Store refs for Refresh
    f.cbSelfFound   = cbSelfFound
    f.cbWeapon      = cbWeapon
    f.cbRepair      = cbRepair
    f.cbPvpDeathProtection = cbPvpDeathProtection
    f.cbMinimap     = cbMinimap
    f.cbBroadcast   = cbBroadcast
    f.cbGuildMessage= cbGuildMessage
    f.cbShowPopup   = cbShowPopup
    f.cbShowWarning = cbShowWarning
    f.cbStats       = cbStats
    f.cbStatsBlizzardFrame = cbStatsBlizzardFrame
    f.opacitySlider = opacitySlider
    f.cbDurHUD      = cbDurHUD
    f.cbDurShowAll  = cbDurShowAll
    f.cbDurGrowUpward = cbDurGrowUpward
    f.cbDurReverseOrder = cbDurReverseOrder
    f.cbStatsHorizontal = cbStatsHorizontal
    f.importBtn     = importBtn
    f.importDropdown = importDropdown
    f.importDropdownClick = ddClick
    f.RefreshImportDropdownText = RefreshImportDropdownText

    RefreshAllControls = function(self)
        local v = Rustcore.GetSetting("difficulty")
        RustcoreTheme.SetDifficultyBackground(self, v)
        self.diffSlider:SetValue(v)
        if self.sliderText then self.sliderText:SetText(DIFF_LABELS[v]) end
        self.diffDesc:SetText(DIFF_DESCS[v])
        self.cbSelfFound:Refresh()
        self.cbWeapon:Refresh()
        self.cbRepair:Refresh()
        self.cbPvpDeathProtection:Refresh()
        self.cbMinimap:Refresh()
        self.cbBroadcast:Refresh()
        self.cbGuildMessage:Refresh()
        self.cbShowPopup:Refresh()
        self.cbShowWarning:Refresh()
        self.cbStats:Refresh()
        self.cbStatsBlizzardFrame:Refresh()
        self.opacitySlider:SetValue(Rustcore.GetSetting("statsBackgroundOpacity"))
        self.cbDurHUD:Refresh()
        self.cbDurShowAll:Refresh()
        self.cbDurGrowUpward:Refresh()
        self.cbDurReverseOrder:Refresh()
        self.cbStatsHorizontal:Refresh()
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
