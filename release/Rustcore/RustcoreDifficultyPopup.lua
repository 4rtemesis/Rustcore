-- Rustcore: first-login "select your difficulty" popup
-- Shown once per character, the first time it logs in, unless already dismissed.

RustcoreDifficultyPopup = {}

local f

local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local HEADER_FONT_PATH = Rustcore.GetAssetPath("Font/RUSTED PERSONAL USE.ttf")
local BODY_FONT_PATH   = Rustcore.GetAssetPath("Font/BPpong.otf")
local BODY_COLOR = { 0.92, 0.89, 0.82 } -- off-white, used for the difficulty panel descriptions
local WELCOME_TEXT_COLOR = { 1, 0.82, 0 } -- yellow, used for the intro description lines
local INTRO_TITLE_COLOR = { 0.85, 0.15, 0.15 } -- same red as the options window title

local FRAME_WIDTH, FRAME_HEIGHT = 560, 415
local PANEL_WIDTH = 150
local PANEL_HEIGHT = 136
local PANEL_GAP  = 16
local PANEL_CORNER_SIZE = 14
local HEADER_FONT_SIZE = 25
local HEADER_LETTER_SPACING = 0
local HEADER_Y_OFFSET = 26
local BODY_FONT_SIZE = 15
local CORNER_COLOR_NORMAL   = { 0.55, 0.55, 0.55, 0.85 }
local CORNER_COLOR_SELECTED = { 1, 1, 1, 1 }
local UNSELECTED_BG_COLOR = { 0.55, 0.55, 0.55 }
local SELECTED_BG_COLOR = { 0.9, 0.9, 0.9 } -- kept slightly dark rather than full white
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
        headerColor = { 0.31, 0.49, 0.09 }, -- slightly more saturated, darker green
        body = "You can no longer repair items.",
    },
    {
        value = 2,
        bg = "UI/background2 copy.tga",
        header = "BROKEN",
        headerColor = { 0.68, 0.50, 0.02 }, -- slightly more saturated gold
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
        shadowFs:Show()
        shadows[i] = shadowFs

        local fs = panel:CreateFontString(nil, "OVERLAY")
        fs:SetFont(HEADER_FONT_PATH, HEADER_FONT_SIZE, "")
        fs:SetTextColor(unpack(color))
        fs:SetText(text:sub(i, i))
        fs:Show()
        -- On a freshly built (never-yet-rendered) frame, GetStringWidth can
        -- come back as 0 for a custom font that hasn't been measured before
        -- this session, which collapses every letter to the same spot. Fall
        -- back to an estimate so letters stay readable even then.
        local w = fs:GetStringWidth()
        if not w or w <= 0 then
            w = HEADER_FONT_SIZE * 0.55
        end
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
        sh:Show()
        shadows[i] = sh

        local fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetFont(SELECT_FONT_PATH, SELECT_FONT_SIZE, "")
        fs:SetTextColor(unpack(SELECT_TEXT_COLOR))
        fs:SetText(text:sub(i, i))
        fs:Show()
        local w = fs:GetStringWidth()
        if not w or w <= 0 then
            w = SELECT_FONT_SIZE * 0.55
        end
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

-- Recompute a panel's header/body text colors from its selected + hovering
-- state. Hovering an unselected panel fully removes its desaturation, same
-- as being selected.
local function ApplyPanelTextColors(panel)
    local headerColor, bodyColor
    if panel.selected or panel.hovering then
        headerColor = panel.headerColor
        bodyColor = BODY_COLOR
    else
        headerColor = DesaturatedColor(panel.headerColor)
        bodyColor = DesaturatedColor(BODY_COLOR)
    end
    for _, letter in ipairs(panel.headerLetters) do
        letter:SetTextColor(unpack(headerColor))
    end
    panel.body:SetTextColor(unpack(bodyColor))
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
    -- Sized with a single anchor + explicit SetWidth (like diffDesc in
    -- RustcoreOptions.lua) rather than a two-point TOPLEFT/BOTTOMRIGHT
    -- anchor: on a freshly built, never-yet-rendered frame the dual-anchor
    -- form was resolving to zero width, wrapping every word onto its own
    -- line and rendering nothing at all.
    local bodyShadow = panel:CreateFontString(nil, "OVERLAY")
    bodyShadow:SetPoint("TOP", panel, "TOP", 1, -HEADER_Y_OFFSET - 23)
    bodyShadow:SetWidth(PANEL_WIDTH - 20)
    bodyShadow:SetFont(BODY_FONT_PATH, BODY_FONT_SIZE, "")
    bodyShadow:SetTextColor(0, 0, 0, 0.75)
    bodyShadow:SetJustifyH("CENTER")
    bodyShadow:SetJustifyV("TOP")
    bodyShadow:SetWordWrap(true)
    bodyShadow:SetText(data.body)

    local body = panel:CreateFontString(nil, "OVERLAY")
    body:SetPoint("TOP", panel, "TOP", 0, -HEADER_Y_OFFSET - 22)
    body:SetWidth(PANEL_WIDTH - 20)
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

    panel:SetScript("OnEnter", function()
        panel.hovering = true
        ApplyPanelTextColors(panel)
    end)
    panel:SetScript("OnLeave", function()
        panel.hovering = false
        ApplyPanelTextColors(panel)
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
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    RustcoreTheme.ApplyFrameSkin(frame)

    -- Darken the popup's background: a black plane behind the theme's
    -- background art. The art itself stays near-opaque so the world behind
    -- the popup doesn't show through; the plane only tints what little
    -- bleeds through the art's remaining transparency, so the art on top
    -- stays fully visible rather than getting covered/dimmed itself.
    local bgDarken = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgDarken:SetColorTexture(0, 0, 0, 0.95)
    bgDarken:SetAllPoints(frame.rustcoreThemeBackground)
    frame.rustcoreThemeBackground:SetAlpha(0.88)

    local WELCOME_LINE1 = "Your gear is temporary. Your scars are not."
    local WELCOME_LINE2 = "Choose the hardship that will define your journey."
    local WELCOME_NOTE  = "(You can change these settings and find more customization in the options window.)"

    -- Fake shadow (see BuildSpacedHeader note): black copy offset behind
    -- the real text, since native shadowing doesn't render here.
    local titleShadow = frame:CreateFontString(nil, "OVERLAY")
    titleShadow:SetPoint("TOP", frame, "TOP", 1, -33)
    titleShadow:SetFont(HEADER_FONT_PATH, 30, "")
    titleShadow:SetTextColor(0, 0, 0, 0.75)
    titleShadow:SetJustifyH("CENTER")
    titleShadow:SetWidth(FRAME_WIDTH - 40)
    titleShadow:SetWordWrap(false)
    titleShadow:SetText("RUSTCORE")

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", frame, "TOP", 0, -32)
    title:SetFont(HEADER_FONT_PATH, 30, "")
    title:SetTextColor(unpack(INTRO_TITLE_COLOR))
    title:SetJustifyH("CENTER")
    title:SetWidth(FRAME_WIDTH - 40)
    title:SetWordWrap(false)
    title:SetText("RUSTCORE")

    -- Line 2 uses a smaller font than line 1 so the whole sentence fits on one line.
    local line1Shadow = frame:CreateFontString(nil, "OVERLAY")
    line1Shadow:SetPoint("TOP", title, "BOTTOM", 1, -13)
    line1Shadow:SetFont(BODY_FONT_PATH, 18, "")
    line1Shadow:SetTextColor(0, 0, 0, 0.75)
    line1Shadow:SetJustifyH("CENTER")
    line1Shadow:SetWidth(FRAME_WIDTH - 40)
    line1Shadow:SetWordWrap(false)
    line1Shadow:SetText(WELCOME_LINE1)

    local line1 = frame:CreateFontString(nil, "OVERLAY")
    line1:SetPoint("TOP", title, "BOTTOM", 0, -12)
    line1:SetFont(BODY_FONT_PATH, 18, "")
    line1:SetTextColor(unpack(WELCOME_TEXT_COLOR))
    line1:SetJustifyH("CENTER")
    line1:SetWidth(FRAME_WIDTH - 40)
    line1:SetWordWrap(false)
    line1:SetText(WELCOME_LINE1)

    local line2Shadow = frame:CreateFontString(nil, "OVERLAY")
    line2Shadow:SetPoint("TOP", line1, "BOTTOM", 1, -4)
    line2Shadow:SetFont(BODY_FONT_PATH, 18, "")
    line2Shadow:SetTextColor(0, 0, 0, 0.75)
    line2Shadow:SetJustifyH("CENTER")
    line2Shadow:SetWidth(FRAME_WIDTH - 40)
    line2Shadow:SetWordWrap(false)
    line2Shadow:SetText(WELCOME_LINE2)

    local line2 = frame:CreateFontString(nil, "OVERLAY")
    line2:SetPoint("TOP", line1, "BOTTOM", 0, -3)
    line2:SetFont(BODY_FONT_PATH, 18, "")
    line2:SetTextColor(unpack(WELCOME_TEXT_COLOR))
    line2:SetJustifyH("CENTER")
    line2:SetWidth(FRAME_WIDTH - 40)
    line2:SetWordWrap(false)
    line2:SetText(WELCOME_LINE2)

    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -6)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    closeBtn:SetScript("OnClick", function()
        MarkSeen()
        frame:Hide()
    end)
    RustcoreTheme.SkinExitButton(closeBtn)

    local panelRow = CreateFrame("Frame", nil, frame)
    panelRow:SetPoint("TOP", line2, "BOTTOM", 0, -20)
    panelRow:SetSize(PANEL_WIDTH * 3 + PANEL_GAP * 2, PANEL_HEIGHT)

    frame.panels = {}
    for i, data in ipairs(PANEL_DATA) do
        local panel = BuildPanel(panelRow, i, data)
        panel:SetPoint("TOPLEFT", panelRow, "TOPLEFT", (i - 1) * (PANEL_WIDTH + PANEL_GAP), 0)
        frame.panels[i] = panel
    end

    local noteShadow = frame:CreateFontString(nil, "OVERLAY")
    noteShadow:SetPoint("TOP", panelRow, "BOTTOM", 1, -13)
    noteShadow:SetFont(BODY_FONT_PATH, 11, "")
    noteShadow:SetTextColor(0, 0, 0, 0.75)
    noteShadow:SetJustifyH("CENTER")
    noteShadow:SetWidth(FRAME_WIDTH - 60)
    noteShadow:SetWordWrap(true)
    noteShadow:SetText(WELCOME_NOTE)

    local note = frame:CreateFontString(nil, "OVERLAY")
    note:SetPoint("TOP", panelRow, "BOTTOM", 0, -12)
    note:SetFont(BODY_FONT_PATH, 11, "")
    note:SetTextColor(0.6, 0.6, 0.6)
    note:SetJustifyH("CENTER")
    note:SetWidth(FRAME_WIDTH - 60)
    note:SetWordWrap(true)
    note:SetText(WELCOME_NOTE)

    local selectBtn = CreateFrame("Button", "RustcoreDifficultySelectButton", frame)
    selectBtn:SetSize(150, 56)
    selectBtn:SetPoint("TOP", note, "BOTTOM", 0, -18)
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
        panel.selected = selected
        if selected then
            panel.bg:SetVertexColor(unpack(SELECTED_BG_COLOR))
        else
            panel.bg:SetVertexColor(unpack(UNSELECTED_BG_COLOR))
        end
        SetCornersColor(panel.corners, selected and CORNER_COLOR_SELECTED or CORNER_COLOR_NORMAL)
        ApplyPanelTextColors(panel)
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
