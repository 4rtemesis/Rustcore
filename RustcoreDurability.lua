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
local frameBySlot  = {} -- slot id -> icon frame, built once in BuildHUD
local activeOrder  = {} -- slot ids in current stack order (1 = nearest anchor);
                         -- stable across updates so existing icons don't
                         -- reshuffle as durability percentages change —
                         -- newly-visible slots are inserted by rank instead

-- Anchor corner used to pin the HUD container: a top-based corner keeps the
-- top edge fixed and lets rows extend downward as they're added; a
-- bottom-based corner keeps the bottom edge fixed so rows extend upward.
local function GetHUDAnchorCorner()
    return Rustcore.GetSetting("durHUDGrowUpward") and "BOTTOMRIGHT" or "TOPRIGHT"
end

-- Keep at least this many pixels of the HUD on-screen along each axis, so a
-- freshly-seeded position (or a drag) can never leave it somewhere the user
-- can't find to drag back.
local MIN_ONSCREEN = 40

-- Base left-shift applied to the native-mirrored default so a fresh HUD
-- doesn't hug the exact edge Blizzard's own frame sits at.
local DEFAULT_X_INSET = 26

-- Extra left-shift applied per visible right-side vertical action bar
-- (MultiBarLeft/MultiBarRight sit in that column below the minimap in the
-- default UI), so a fresh HUD doesn't land underneath them. Only ever
-- applied to a position the user hasn't dragged themselves — see
-- GetOrSeedCornerPos and StopHUDDrag's "userMoved" flag.
local ACTIONBAR_X_SHIFT = 42

local function GetRightActionBarShift()
    local shift = 0
    if MultiBarRight and MultiBarRight:IsShown() then
        shift = shift + ACTIONBAR_X_SHIFT
    end
    if MultiBarLeft and MultiBarLeft:IsShown() then
        shift = shift + ACTIONBAR_X_SHIFT
    end
    return shift
end

local function ClampEdgeOffset(offset, frameSize, screenSize)
    -- offset grows as the frame moves away from its anchored edge. The far
    -- bound scales with the SCREEN (how far it can travel before it's gone),
    -- and the near bound with the FRAME (how far it can back up past its own
    -- anchor before it's gone).
    local lo, hi = -(frameSize - MIN_ONSCREEN), screenSize - MIN_ONSCREEN
    if lo > hi then return offset end -- frame bigger than the screen minus margins; leave it alone
    return Clamp(offset, lo, hi)
end

-- Both anchor corners sit on the right, so x always has the same sense
-- (moving into the screen is negative x); y's sense flips with the corner.
-- Clamping the corner-agnostic "distance from the anchored edge, growing
-- into the screen" form lets the same bounds apply correctly on both axes,
-- and guarantees the result can never end up off-screen.
local function ClampToScreen(corner, x, y, w, h, sw, sh)
    local edgeX = ClampEdgeOffset(-x, w, sw)
    local edgeY = ClampEdgeOffset((corner == "TOPRIGHT") and -y or y, h, sh)
    return -edgeX, (corner == "TOPRIGHT") and -edgeY or edgeY
end

-- Re-express a saved offset in the other corner's coordinate space while
-- keeping the HUD's actual on-screen position unchanged. Both corners share
-- UIParent's right edge, so only Y needs conversion: a y-offset means
-- "distance below the top edge" relative to a top corner but "distance
-- above the bottom edge" relative to a bottom corner.
local function ConvertCornerOffset(fromCorner, y, h, screenHeight)
    if fromCorner == "TOPRIGHT" then
        local topDist = -y
        return screenHeight - topDist - h -- now a bottom-distance
    else
        local bottomDist = y
        return -(screenHeight - bottomDist - h) -- now a top-distance
    end
end

-- Best-effort seed for the very first time the HUD is ever shown (no saved
-- position yet): mirror wherever Blizzard's own DurabilityFrame currently
-- sits on screen, converted into an offset from our anchor corner, so the
-- custom HUD starts out where players already expect it. Uses the resolved
-- on-screen extents (not GetPoint's raw anchor) so it works no matter what
-- frame the native durability frame happens to be anchored to. Returns nil
-- if the native frame isn't laid out yet, so callers can fall back.
local function GetNativeDurabilityDefault(corner)
    if not DurabilityFrame or not DurabilityFrame.GetRight then return nil end
    local right, top, bottom = DurabilityFrame:GetRight(), DurabilityFrame:GetTop(), DurabilityFrame:GetBottom()
    local uiRight, uiTop, uiBottom = UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom()
    if not (right and top and bottom and uiRight and uiTop and uiBottom) then return nil end

    local x = right - uiRight - DEFAULT_X_INSET - GetRightActionBarShift()
    local y = (corner == "BOTTOMRIGHT") and (bottom - uiBottom) or (top - uiTop)
    return x, y
end

-- Saved positions are kept per-corner ({ TOPRIGHT = {x,y}, BOTTOMRIGHT =
-- {x,y} }) instead of one spot that gets converted back and forth on every
-- toggle. Once a corner has been used, switching back to it is a plain table
-- lookup with no runtime math — nothing left to drift or jump on repeat
-- toggles. Old saves used a flat { point, x, y } shape; migrate those in.
local function GetHUDPosTable()
    local raw = Rustcore.GetProfileValue("durHUDPos")
    if raw and raw.point and raw.x and not raw.TOPRIGHT and not raw.BOTTOMRIGHT then
        raw = { [raw.point] = { x = raw.x, y = raw.y } }
    end
    return raw or {}
end

-- A corner with nothing saved yet is seeded once: converted from the other
-- corner's spot if one exists (so it starts out looking like the HUD didn't
-- move at all), otherwise from Blizzard's native frame or a hardcoded
-- fallback. Returns whether a seed was needed so the caller knows to persist it.
--
-- As long as the user has never actually dragged the HUD (raw.userMoved),
-- a "saved" corner here is really just last session's auto-seed, not a
-- real placement choice — so it's recomputed fresh instead of reused. That's
-- what lets the default spot auto-adjust for right-side action bars turning
-- on/off between sessions without ever touching a position the user picked.
local function GetOrSeedCornerPos(corner, raw, h, sh)
    local saved = raw[corner]
    if saved and raw.userMoved then return saved.x, saved.y, false end

    local otherCorner = (corner == "TOPRIGHT") and "BOTTOMRIGHT" or "TOPRIGHT"
    local other = raw[otherCorner]
    if other and raw.userMoved then
        return other.x, ConvertCornerOffset(otherCorner, other.y, h, sh), true
    end

    local nx, ny = GetNativeDurabilityDefault(corner)
    return nx or (-60 - GetRightActionBarShift()), ny or (corner == "BOTTOMRIGHT" and 220 or -220), true
end

-- This only ever runs at init, on manual drag-stop, or when the grow-upward
-- setting actually changes — never on a routine durability update.
local function ApplyHUDPosition()
    if not hudContainer then return end
    local corner = GetHUDAnchorCorner()
    local w, h = hudContainer:GetWidth(), hudContainer:GetHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    local raw = GetHUDPosTable()
    local x0, y0, isNew = GetOrSeedCornerPos(corner, raw, h, sh)
    local x, y = ClampToScreen(corner, x0, y0, w, h, sw, sh)

    hudContainer:ClearAllPoints()
    hudContainer:SetPoint(corner, UIParent, corner, x, y)

    -- Persist when freshly seeded, or when the clamp actually had to move a
    -- stale/out-of-bounds saved value — that permanently heals it instead of
    -- reclamping the same bad value on every future login.
    if isNew or x ~= x0 or y ~= y0 then
        raw[corner] = { x = x, y = y }
        Rustcore.SetProfileValue("durHUDPos", raw)
    end
end

-- Forces the container's live on-screen rect back onto a single explicit
-- (corner, UIParent, corner, x, y) point, deriving x/y from the *current
-- rendered edges* rather than any cached raw[corner] entry (which goes
-- stale the moment a different corner was active last). Needed anywhere the
-- real anchor corner can end up different from what GetHUDAnchorCorner()
-- expects — most importantly right after a drag: StopMovingOrSizing()
-- always snaps to whichever screen corner ended up closest to the mouse,
-- which is frequently NOT the corner this addon treats as fixed. Left
-- alone, that mismatch means a later SetHeight (during a routine item
-- add/remove) ends up moving an edge the render loop believes is pinned —
-- which is what made counters drift or "shrink from the middle" instead of
-- extending cleanly from one fixed end, but only once the HUD had been
-- dragged somewhere the closest corner wasn't the intended one. Returns the
-- resulting x, y, or nil if the live rect isn't available yet.
local function ReanchorToFixedCorner(corner)
    if not hudContainer then return nil end
    local right, top, bottom = hudContainer:GetRight(), hudContainer:GetTop(), hudContainer:GetBottom()
    local uiRight, uiTop, uiBottom = UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom()
    if not (right and top and bottom and uiRight and uiTop and uiBottom) then return nil end

    local w, h = hudContainer:GetWidth(), hudContainer:GetHeight()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

    local x0 = right - uiRight
    local y0 = (corner == "BOTTOMRIGHT") and (bottom - uiBottom) or (top - uiTop)
    local x, y = ClampToScreen(corner, x0, y0, w, h, sw, sh)

    hudContainer:ClearAllPoints()
    hudContainer:SetPoint(corner, UIParent, corner, x, y)
    return x, y
end

-- Re-anchors to the opposite corner in response to the grow-upward setting
-- changing, keeping the HUD pixel-identical on screen.
local function RepositionForAnchorChange()
    if not hudContainer then return end
    local corner = GetHUDAnchorCorner()
    local x, y = ReanchorToFixedCorner(corner)
    if not x then
        ApplyHUDPosition()
        return
    end

    local raw = GetHUDPosTable()
    raw[corner] = { x = x, y = y }
    Rustcore.SetProfileValue("durHUDPos", raw)
end

-- Re-seeds the default position live when a right-side action bar toggles
-- on/off mid-session, so the auto-adjust in GetOrSeedCornerPos doesn't just
-- apply on next login. No-ops once the user has actually dragged the HUD
-- (raw.userMoved), since that's a real placement, not a default.
local function MaybeReseedDefaultPosition()
    if not hudContainer then return end
    if GetHUDPosTable().userMoved then return end
    ApplyHUDPosition()
end

-- Dragging is initiated from whichever icon frame is under the cursor (they
-- sit on top of the container and would otherwise swallow the mouse), but
-- every icon frame gets Hidden/Shown on each durability update. If the icon
-- that started the drag gets hidden mid-drag, its OnDragStop never fires and
-- StopMovingOrSizing() never runs — leaving the whole HUD glued to the mouse
-- cursor from then on. Routing both container and icon frames through these
-- shared start/stop functions, and hooking OnHide on all of them as a safety
-- net, guarantees the drag always gets released no matter which frame vanishes.
local function StopHUDDrag()
    if hudContainer and hudContainer.isDragging then
        hudContainer.isDragging = nil
        hudContainer:StopMovingOrSizing()

        -- StopMovingOrSizing() snaps to whichever screen corner ended up
        -- closest to the drag, not necessarily the corner this addon
        -- treats as fixed (see ReanchorToFixedCorner) — force it back so
        -- every later routine update can keep trusting that corner stayed
        -- put, instead of only fixing it up on the next toggle/reload.
        local corner = GetHUDAnchorCorner()
        local x, y = ReanchorToFixedCorner(corner)
        if not x then
            local _, _, _, gx, gy = hudContainer:GetPoint()
            x, y = gx, gy
        end

        local raw = GetHUDPosTable()
        raw[corner] = { x = x, y = y }
        -- Marks this as a real user placement, so the default-position
        -- auto-adjust (see GetOrSeedCornerPos) never overrides it again.
        raw.userMoved = true
        Rustcore.SetProfileValue("durHUDPos", raw)
    end
end

local function StartHUDDrag()
    if hudContainer and not hudContainer.isDragging then
        hudContainer.isDragging = true
        hudContainer:StartMoving()
    end
end

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
    f:SetScript("OnDragStart", StartHUDDrag)
    f:SetScript("OnDragStop", StopHUDDrag)
    f:HookScript("OnHide", StopHUDDrag)
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
    f:SetScript("OnDragStart", StartHUDDrag)
    f:SetScript("OnDragStop", StopHUDDrag)
    f:HookScript("OnHide", StopHUDDrag)

    hudContainer = f
    ApplyHUDPosition()

    -- Right-side action bars (MultiBarLeft/MultiBarRight) share screen space
    -- with the default HUD spot; re-seed the default live if either toggles
    -- while the user hasn't dragged the HUD themselves.
    if MultiBarRight then
        MultiBarRight:HookScript("OnShow", MaybeReseedDefaultPosition)
        MultiBarRight:HookScript("OnHide", MaybeReseedDefaultPosition)
    end
    if MultiBarLeft then
        MultiBarLeft:HookScript("OnShow", MaybeReseedDefaultPosition)
        MultiBarLeft:HookScript("OnHide", MaybeReseedDefaultPosition)
    end

    f:Hide()

    slotEntries = {}
    for _, slot in ipairs(SLOT_DATA) do
        local sf = BuildSlotFrame(f, slot)
        slotEntries[#slotEntries + 1] = { slot = slot, frame = sf }
        frameBySlot[slot] = sf
    end
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
    local visibleSlots = {} -- { slot = slot, pct = pct }, this pass only

    for _, entry in ipairs(slotEntries) do
        local slot    = entry.slot
        local link    = GetInventoryItemLink("player", slot)
        local visible = false
        local pct     = 1  -- default; overwritten when durability is read

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
            visibleSlots[#visibleSlots + 1] = { slot = slot, pct = pct }
        end
    end

    -- Stable stack order: a slot keeps its spot once placed, even as its
    -- percentage drifts — durability ticks on already-shown items never
    -- reshuffle the stack. A newly-visible slot is inserted by rank against
    -- the other currently-placed slots (worst-first), so a freshly equipped
    -- item lands in the correct spot relative to everything already shown
    -- instead of only ever comparing against the current worst item.
    local pctBySlot = {}
    for _, entry in ipairs(visibleSlots) do
        pctBySlot[entry.slot] = entry.pct
    end

    local newOrder = {}
    for _, slot in ipairs(activeOrder) do
        if pctBySlot[slot] then
            newOrder[#newOrder + 1] = slot
        end
    end

    local placed = {}
    for _, slot in ipairs(newOrder) do
        placed[slot] = true
    end

    for _, entry in ipairs(visibleSlots) do
        if not placed[entry.slot] then
            -- Find the first already-placed slot that's less damaged than
            -- this one and insert just before it, so the new slot lands in
            -- correct worst-first rank order; if nothing already placed is
            -- less damaged, it joins the far (best) end. Every frame gets
            -- SetPoint'd fresh from activeOrder each update (below), so a
            -- mid-stack insertion here is not a source of visual jumps.
            local insertAt = #newOrder + 1
            for i, slot in ipairs(newOrder) do
                if entry.pct < pctBySlot[slot] then
                    insertAt = i
                    break
                end
            end
            table.insert(newOrder, insertAt, entry.slot)
            placed[entry.slot] = true
        end
    end
    activeOrder = newOrder

    if #activeOrder > 0 then
        local totalH = #activeOrder * FRAME_H + (#activeOrder - 1) * SLOT_GAP
        hudContainer:SetHeight(totalH)
        -- No repositioning here: the container keeps a single anchor point
        -- (SetPoint(corner, ...)), and SetHeight only moves the unanchored
        -- edge, so the anchor itself never drifts on its own. Re-running the
        -- clamp/corner-conversion math on every tick was the actual source of
        -- the "HUD jumps on equip" bugs — position is now only touched on
        -- manual drag (StopHUDDrag) or when the grow-upward setting itself
        -- changes (RefreshPosition), matching how this worked before that
        -- setting was added.
        local growUpward = Rustcore.GetSetting("durHUDGrowUpward")
        local reverseOrder = Rustcore.GetSetting("durHUDReverseOrder")
        local yOff = 0
        -- activeOrder is always sorted worst-first regardless of anchor mode.
        -- Grow-down anchors the top edge, so worst-first order is walked
        -- forward (worst lands at the fixed top). Grow-up anchors the bottom
        -- edge instead, so the same array is walked in reverse (best lands
        -- at the fixed bottom) — this keeps the worst item at the visual top
        -- in both modes and makes toggling the setting a no-op for on-screen
        -- pixels, since it's just reinterpreting the same ranks from the
        -- other end. durHUDReverseOrder flips which end the walk starts
        -- from (XOR'd against growUpward) so the worst item lands at the
        -- visual bottom instead, independent of which edge is anchored.
        local walkReversed = growUpward
        if reverseOrder then walkReversed = not walkReversed end
        local first, last, step = 1, #activeOrder, 1
        if walkReversed then
            first, last, step = #activeOrder, 1, -1
        end
        for i = first, last, step do
            local sf = frameBySlot[activeOrder[i]]
            sf:ClearAllPoints()
            if growUpward then
                sf:SetPoint("BOTTOMLEFT", hudContainer, "BOTTOMLEFT", 0, -yOff)
            else
                sf:SetPoint("TOPLEFT", hudContainer, "TOPLEFT", 0, yOff)
            end
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

-- Jumps to whatever position is saved/seeded for the current corner. Used
-- when there's no on-screen position worth preserving continuity with —
-- e.g. importing another profile's layout, where landing on the imported
-- spot is the whole point.
function RustcoreDurability.RefreshPosition()
    ApplyHUDPosition()
    UpdateHUD()
end

-- Re-anchors to the corner matching the current grow-upward setting while
-- keeping the HUD's on-screen position unchanged, then re-lays-out the
-- stack immediately so direction/order corrects itself right away instead
-- of waiting for the next durability-changing event. Use this (not
-- RefreshPosition) whenever durHUDGrowUpward itself just changed.
function RustcoreDurability.HandleGrowUpwardChanged()
    RepositionForAnchorChange()
    UpdateHUD()
end

-- Reverse order only flips which end of the stable stack the walk starts
-- from (see UpdateHUD); the anchor corner is untouched, so a plain re-layout
-- is enough.
function RustcoreDurability.HandleReverseOrderChanged()
    UpdateHUD()
end
