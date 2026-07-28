-- Rustcore: first-login "select your difficulty" popup
-- Shown once per character, the first time it logs in, unless already dismissed.

RustcoreDifficultyPopup = {}

local f

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local HEADER_FONT_PATH = Rustcore.GetAssetPath("Font/RUSTED PERSONAL USE.ttf")
local BODY_FONT_PATH   = Rustcore.GetAssetPath("Font/BPpong.otf")
local BODY_COLOR = { 1, 0.82, 0 } -- same yellow as the options window's difficulty description text

local FRAME_WIDTH, FRAME_HEIGHT = 560, 414
local PANEL_WIDTH = 150
local PANEL_HEIGHT = 136
local PANEL_GAP  = 16
local PANEL_CORNER_SIZE = 14
local HEADER_FONT_SIZE = 23
local HEADER_LETTER_SPACING = 3
local HEADER_Y_OFFSET = 26
local BODY_FONT_SIZE = 15
local CORNER_COLOR_NORMAL   = { 0.55, 0.55, 0.55, 0.85 }
local CORNER_COLOR_SELECTED = { 1, 1, 1, 1 }
local UNSELECTED_BG_COLOR = { 0.55, 0.55, 0.55 }
local DESATURATE_DIM = 0.55

-- Grayscale-and-dim a color for the unselected-panel text state.
local function DesaturatedColor(color)
    local lum = (0.3 * color[1] + 0.59 * color[2] + 0.11 * color[3]) * DESATURATE_DIM
    return { lum, lum, lum }
end

-- Same label styling as the DELETE button (RustcoreTheme.lua) so the SELECT
-- button matches it exactly.
local SELECT_FONT_PATH = Rustcore.GetAssetPath("Font/BPpong.otf")
local SELECT_FONT_SIZE = 22
local SELECT_LETTER_SPACING = 4
local SELECT_TEXT_COLOR = { 0.85, 0.85, 0.82 }

-- index -> { difficulty value, background art, header text/color, body text }
-- Header colors run green -> yellow -> orange -> orange -> red across the
-- five difficulty tiers (only the Rusted/Broken/Dust tiers are offered in
-- this popup).
local PANEL_DATA = {
    {
        value = 1,
        bg = "UI/background1 copy.tga",
        header = "RUSTED",
        headerColor = { 0.41, 0.58, 0.20 },
        body = "You can no longer repair items.",
    },
    {
        value = 2,
        bg = "UI/background2 copy.tga",
        header = "BROKEN",
        headerColor = { 0.64, 0.50, 0.11 },
        body = "Death will break one of your equipped items and you can no longer repair.",
    },
    {
        value = 5,
        bg = "UI/background5 copy.tga",
        header = "DUST",
        headerColor = { 0.85, 0.15, 0.15 }, -- same red as the options window title
        body = "Death will disintigrate ALL of your equipped items and you can no longer repair.",
    },
}

local DEFAULT_PANEL_INDEX = 2 -- Broken

-- WoW font strings have no letter-tracking control, so spaced headers are
-- laid out as individually positioned font strings (same approach used for
-- the DELETE/SELECT button label in RustcoreTheme.lua).
--
-- Native SetShadowColor/SetShadowOffset doesn't render on this client, so the
-- shadow is faked with a second, black, offset copy of each letter drawn
-- underneath the real one instead.
local function BuildSpacedHeader(panel, text, color)
    local widths, letters, shadows, totalWidth = {}, {}, {}, 0
    for i = 1, #text do
        local shadowFs = panel:CreateFontString(nil, "OVERLAY")
        shadowFs:SetFont(HEADER_FONT_PATH, HEADER_FONT_SIZE, "")
        shadowFs:SetTextColor(0, 0, 0, 0.75)
        shadowFs:SetText(text:sub(i, i))
        shadows[i] = shadowFs

        local fs = panel:CreateFontString(nil, "OVERLAY")
        fs:SetFont(HEADER_FONT_PATH, HEADER_FONT_SIZE, "")
        fs:SetTextColor(unpack(color))
        fs:SetText(text:sub(i, i))
        local w = fs:GetStringWidth()
        widths[i] = w
        letters[i] = fs
        totalWidth = totalWidth + w + (i < #text and HEADER_LETTER_SPACING or 0)
    end

    local x = -totalWidth / 2
    for i = 1, #text do
        local fs = letters[i]
        local sh = shadows[i]
        fs:ClearAllPoints()
        sh:ClearAllPoints()
        fs:SetPoint("LEFT", panel, "TOP", x, -HEADER_Y_OFFSET)
        sh:SetPoint("LEFT", panel, "TOP", x + 1, -HEADER_Y_OFFSET - 1)
        x = x + widths[i] + HEADER_LETTER_SPACING
    end

    return letters
end

-- Same letter-by-letter layout as BuildSpacedHeader, but matching the DELETE
-- button's exact font/size/spacing/shadow (RustcoreTheme.lua) so SELECT
-- looks identical to it.
local function BuildSelectButtonText(button, text)
    local widths, letters, shadows, totalWidth = {}, {}, {}, 0
    for i = 1, #text do
        local sh = button:CreateFontString(nil, "OVERLAY")
        sh:SetFont(SELECT_FONT_PATH, SELECT_FONT_SIZE, "")
        sh:SetTextColor(0, 0, 0, 1)
        sh:SetText(text:sub(i, i))
        shadows[i] = sh

        local fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont(SELECT_FONT_PATH, SELECT_FONT_SIZE, "")
        fs:SetTextColor(unpack(SELECT_TEXT_COLOR))
        fs:SetText(text:sub(i, i))
        local w = fs:GetStringWidth()
        widths[i] = w
        letters[i] = fs
        totalWidth = totalWidth + w + (i < #text and SELECT_LETTER_SPACING or 0)
    end

    local x = -totalWidth / 2
    for i = 1, #text do
        local fs = letters[i]
        local sh = shadows[i]
        fs:SetPoint("LEFT", button, "CENTER", x, 0)
        sh:SetPoint("LEFT", button, "CENTER", x + 1.5, -1.5)
        x = x + widths[i] + SELECT_LETTER_SPACING
    end
end

-- Corner artwork: same rivet-style Nutcorner pieces used on the stats panel
-- (RustcoreStats.lua), reused across all four corners with no rotation.
local function ApplyPanelCorners(panel)
    local corners = {}
    local function corner(point, texture, xOff, yOff)
        local tex = panel:CreateTexture(nil, "OVERLAY")
        tex:SetPoint(point, panel, point, xOff, yOff)
        tex:SetSize(PANEL_CORNER_SIZE, PANEL_CORNER_SIZE)
        tex:SetTexture(Rustcore.GetAssetPath("UI/" .. texture))
        tex:SetTexCoord(0, 1, 0, 1)
        corners[#corners + 1] = tex
    end

    corner("TOPLEFT",     "NutcornerUL.tga", 5, -5)
    corner("TOPRIGHT",    "NutcornerUR.tga", -5, -5)
    corner("BOTTOMLEFT",  "NutcornerUR.tga", 5, 5)
    corner("BOTTOMRIGHT", "NutcornerUL.tga", -5, 5)

    return corners
end

local function SetCornersColor(corners, color)
    for _, tex in ipairs(corners) do
        tex:SetVertexColor(unpack(color))
    end
end

local function BuildPanel(parent, index, data)
    -- Cast-shadow plane, offset behind the panel. Sized to match the (inset)
    -- bg art and shifted further down-right than it, so the shadow only
    -- peeks out past the bottom and right edges, not all four.
    local shadow = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
    shadow:SetSize(PANEL_WIDTH - 6, PANEL_HEIGHT - 6)
    shadow:SetColorTexture(0, 0, 0, 0.4)

    local panel = CreateFrame("Button", nil, parent)
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)

    shadow:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
    bg:SetTexture(Rustcore.GetAssetPath(data.bg))
    panel.bg = bg

    panel.corners = ApplyPanelCorners(panel)
    SetCornersColor(panel.corners, CORNER_COLOR_NORMAL)

    panel.headerColor = data.headerColor
    panel.headerLetters = BuildSpacedHeader(panel, data.header, data.headerColor)

    -- Fake shadow (see BuildSpacedHeader note): black copy offset behind
    -- the real body text, since native shadowing doesn't render here.
    local bodyShadow = panel:CreateFontString(nil, "OVERLAY")
    bodyShadow:SetPoint("TOPLEFT", panel, "TOPLEFT", 11, -HEADER_Y_OFFSET - 23)
    bodyShadow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -9, 7)
    bodyShadow:SetFont(BODY_FONT_PATH, BODY_FONT_SIZE, "")
    bodyShadow:SetTextColor(0, 0, 0, 0.75)
    bodyShadow:SetJustifyH("CENTER")
    bodyShadow:SetJustifyV("TOP")
    bodyShadow:SetWordWrap(true)
    bodyShadow:SetText(data.body)

    local body = panel:CreateFontString(nil, "OVERLAY")
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -HEADER_Y_OFFSET - 22)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    body:SetFont(BODY_FONT_PATH, BODY_FONT_SIZE, "")
    body:SetTextColor(unpack(BODY_COLOR))
    body:SetJustifyH("CENTER")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetText(data.body)
    panel.body = body

    panel:SetScript("OnClick", function()
        PlaySoundFile(Rustcore.GetAssetPath("Audio/ticksound2.wav"), "Master")
        RustcoreDifficultyPopup.SetSelected(index)
    end)

    return panel
end

local function MarkSeen()
    Rustcore.SetProfileValue("hasSeenDifficultyPopup", true)
end

local function BuildFrame()
    local frame = CreateFrame("Frame", "RustcoreDifficultyPopupFrame", UIParent, backdropTemplate)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    -- FULLSCREEN_DIALOG sits above the DIALOG strata used by the options
    -- window, so the popup stays on top even if options is opened over it.
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    RustcoreTheme.ApplyFrameSkin(frame)

    -- Darken the popup's background: a black plane behind the theme's
    -- background art, both at 50% opacity, so the composite reads darker
    -- than the shared theme default without touching other frames.
    local bgDarken = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgDarken:SetColorTexture(0, 0, 0, 0.5)
    bgDarken:SetAllPoints(frame.rustcoreThemeBackground)
    frame.rustcoreThemeBackground:SetAlpha(0.5)

    local WELCOME_LINE1 = "Steel breaks. Armor fails. Death always takes its toll."
    local WELCOME_LINE2 = "Choose the hardship you are willing to endure on your journey."
    local WELCOME_NOTE  = "(You can change these settings and find more customization in the options window.)"

    -- Fake shadow (see BuildSpacedHeader note): black copy offset behind
    -- the real text, since native shadowing doesn't render here. Line 2
    -- uses a smaller font than line 1 so the whole sentence fits on one line.
    local line1Shadow = frame:CreateFontString(nil, "OVERLAY")
    line1Shadow:SetPoint("TOP", frame, "TOP", 1, -49)
    line1Shadow:SetFont(BODY_FONT_PATH, 18, "")
    line1Shadow:SetTextColor(0, 0, 0, 0.75)
    line1Shadow:SetJustifyH("CENTER")
    line1Shadow:SetWidth(FRAME_WIDTH - 40)
    line1Shadow:SetWordWrap(false)
    line1Shadow:SetText(WELCOME_LINE1)

    local line1 = frame:CreateFontString(nil, "OVERLAY")
    line1:SetPoint("TOP", frame, "TOP", 0, -48)
    line1:SetFont(BODY_FONT_PATH, 18, "")
    line1:SetTextColor(1, 1, 1)
    line1:SetJustifyH("CENTER")
    line1:SetWidth(FRAME_WIDTH - 40)
    line1:SetWordWrap(false)
    line1:SetText(WELCOME_LINE1)

    local line2Shadow = frame:CreateFontString(nil, "OVERLAY")
    line2Shadow:SetPoint("TOP", line1, "BOTTOM", 1, -7)
    line2Shadow:SetFont(BODY_FONT_PATH, 18, "")
    line2Shadow:SetTextColor(0, 0, 0, 0.75)
    line2Shadow:SetJustifyH("CENTER")
    line2Shadow:SetWidth(FRAME_WIDTH - 40)
    line2Shadow:SetWordWrap(false)
    line2Shadow:SetText(WELCOME_LINE2)

    local line2 = frame:CreateFontString(nil, "OVERLAY")
    line2:SetPoint("TOP", line1, "BOTTOM", 0, -6)
    line2:SetFont(BODY_FONT_PATH, 18, "")
    line2:SetTextColor(1, 1, 1)
    line2:SetJustifyH("CENTER")
    line2:SetWidth(FRAME_WIDTH - 40)
    line2:SetWordWrap(false)
    line2:SetText(WELCOME_LINE2)

    local noteShadow = frame:CreateFontString(nil, "OVERLAY")
    noteShadow:SetPoint("TOP", line2, "BOTTOM", 1, -9)
    noteShadow:SetFont(BODY_FONT_PATH, 11, "")
    noteShadow:SetTextColor(0, 0, 0, 0.75)
    noteShadow:SetJustifyH("CENTER")
    noteShadow:SetWidth(FRAME_WIDTH - 60)
    noteShadow:SetWordWrap(true)
    noteShadow:SetText(WELCOME_NOTE)

    local note = frame:CreateFontString(nil, "OVERLAY")
    note:SetPoint("TOP", line2, "BOTTOM", 0, -8)
    note:SetFont(BODY_FONT_PATH, 11, "")
    note:SetTextColor(0.6, 0.6, 0.6)
    note:SetJustifyH("CENTER")
    note:SetWidth(FRAME_WIDTH - 60)
    note:SetWordWrap(true)
    note:SetText(WELCOME_NOTE)

    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -6)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function()
        MarkSeen()
        frame:Hide()
    end)
    RustcoreTheme.SkinExitButton(closeBtn)

    local panelRow = CreateFrame("Frame", nil, frame)
    panelRow:SetPoint("TOP", note, "BOTTOM", 0, -20)
    panelRow:SetSize(PANEL_WIDTH * 3 + PANEL_GAP * 2, PANEL_HEIGHT)

    frame.panels = {}
    for i, data in ipairs(PANEL_DATA) do
        local panel = BuildPanel(panelRow, i, data)
        panel:SetPoint("TOPLEFT", panelRow, "TOPLEFT", (i - 1) * (PANEL_WIDTH + PANEL_GAP), 0)
        frame.panels[i] = panel
    end

    local selectBtn = CreateFrame("Button", "RustcoreDifficultySelectButton", frame)
    selectBtn:SetSize(150, 56)
    selectBtn:SetPoint("TOP", panelRow, "BOTTOM", 0, -30)
    RustcoreTheme.SkinDeleteButton(selectBtn)
    -- Built directly here (same font/size/spacing/shadow as the DELETE
    -- button's own LayoutDeleteButtonLetters) instead of going through
    -- SkinDeleteButton's SetText hook, which wasn't rendering a shadow here.
    BuildSelectButtonText(selectBtn, "SELECT")
    selectBtn:SetScript("OnClick", function()
        local data = PANEL_DATA[frame.selectedIndex or DEFAULT_PANEL_INDEX]
        Rustcore.SetSetting("difficulty", data.value)
        PlaySoundFile(Rustcore.GetAssetPath("Audio/difficultysound.wav"), "Master")
        MarkSeen()
        frame:Hide()
    end)

    frame:Hide()
    return frame
end

function RustcoreDifficultyPopup.SetSelected(index)
    if not f then return end
    f.selectedIndex = index
    for i, panel in ipairs(f.panels) do
        local selected = (i == index)
        if selected then
            panel.bg:SetVertexColor(1, 1, 1)
        else
            panel.bg:SetVertexColor(unpack(UNSELECTED_BG_COLOR))
        end
        SetCornersColor(panel.corners, selected and CORNER_COLOR_SELECTED or CORNER_COLOR_NORMAL)

        local headerColor = selected and panel.headerColor or DesaturatedColor(panel.headerColor)
        for _, letter in ipairs(panel.headerLetters) do
            letter:SetTextColor(unpack(headerColor))
        end
        local bodyColor = selected and BODY_COLOR or DesaturatedColor(BODY_COLOR)
        panel.body:SetTextColor(unpack(bodyColor))
    end
end

function RustcoreDifficultyPopup.Show()
    if not f then f = BuildFrame() end
    RustcoreDifficultyPopup.SetSelected(DEFAULT_PANEL_INDEX)
    f:Show()
end

function RustcoreDifficultyPopup.MaybeShowOnLogin()
    if Rustcore.GetProfileValue("hasSeenDifficultyPopup") then return end
    RustcoreDifficultyPopup.Show()
end
