local path = arg[1] or 'dist/Forever/Rustcore/RustcoreDragon.lua'
local file = assert(io.open(path, 'rb'))
local source = file:read('*a'):gsub('\r\n', '\n'); file:close()
local start = assert(source:find('local function IsClassicUIFrame', 1, true))
local stop = assert(source:find('local function RaiseLevelText', start, true))
local sync, syncBadge = assert(loadstring(source:sub(start, stop - 1)
    .. '\nreturn SyncDragonLayering, SyncClassicLevelBadge'))()
local combat = false
function InCombatLockdown() return combat end

for _, unit in ipairs({'player', 'target'}) do
    -- ClassicUIForever: art at base+3, level/status at base+4, PvP/text at +7.
    local container = {level = 13}
    local contextual = {level = 14}
    local texts = {level = 17}
    local frame = {}
    frame[unit == 'player' and 'PlayerFrameContainer' or 'TargetFrameContainer'] = container
    local holder = {level = 30, GetParent = function() return frame end}
    local texture = {parent = holder, layer = 'ARTWORK', sublevel = 0, changes = 0,
        rustcoreHolder = holder, anchor = holder, shown = false}
    function texture:GetParent() return self.parent end
    function texture:SetParent(parent) self.parent = parent; self.changes = self.changes + 1 end
    function texture:GetDrawLayer() return self.layer, self.sublevel end
    function texture:SetDrawLayer(layer, sublevel)
        self.layer, self.sublevel = layer, sublevel
        self.changes = self.changes + 1
    end

    local restored = 0
    texture.rustcoreRestoreNative = function() restored = restored + 1 end
    sync(texture, unit)
    assert(texture.parent == holder and texture.changes == 0, 'native layout changed')
    -- The skin can load after Rustcore, or be enabled later.
    local enabled = true
    frame.fcui = {host = {IsShown = function() return enabled end}, texts = texts}
    combat = true
    sync(texture, unit)
    assert(texture.parent == holder and texture.changes == 0, 'changed layout in combat')
    combat = false
    sync(texture, unit)
    assert(texture.parent == container and texture.layer == 'OVERLAY')
    assert(texture.parent.level < contextual.level, 'level/status obscured')
    assert(texture.parent.level < texts.level, 'PvP/text obscured')
    assert(texture.anchor == holder and not texture.shown, 'position or visibility changed')
    local changes = texture.changes
    sync(texture, unit)
    assert(texture.changes == changes, 'unchanged layout rewritten on every tick')
    -- Turning the skin off restores native layering, deferred through combat.
    enabled = false
    combat = true
    sync(texture, unit)
    assert(texture.parent == container)
    combat = false
    sync(texture, unit)
    assert(texture.parent == holder and texture.layer == 'ARTWORK')
    assert(restored == 1, 'native text layering was not restored')
    enabled = true
    sync(texture, unit)
    assert(texture.parent == container, 're-enabling skin failed')
end
for _, unit in ipairs({'player', 'target'}) do
    local left, right = 0.09375, 1
    if unit == 'player' then left, right = right, left end
    local art = {
        GetTexCoord = function() return left, 0, left, 0.78125, right, 0, right, 0.78125 end,
        GetTexture = function() return 'classic-frame-sheet' end,
        GetVertexColor = function() return 1, 1, 1, 1 end,
        GetAlpha = function() return 1 end,
        IsShown = function() return true end,
    }
    local container = {FrameTexture = art}
    function container:CreateTexture(_, layer, _, sublevel)
        local badge = {parent = self, layer = layer, sublevel = sublevel}
        function badge:SetTexture(value) self.texture = value end
        function badge:SetTexCoord(...) self.coords = {...} end
        function badge:SetSize(w, h) self.width, self.height = w, h end
        function badge:ClearAllPoints() end
        function badge:SetPoint(...) self.point = {...} end
        function badge:SetVertexColor(...) end
        function badge:SetAlpha(value) self.alpha = value end
        function badge:SetShown(value) self.shown = value end
        function badge:Hide() self.shown = false end
        return badge
    end
    local visible = true
    local texture = {IsShown = function() return visible end}
    syncBadge(texture, unit, container)
    local badge = texture.rustcoreClassicBadge
    assert(badge.parent == container and badge.layer == 'OVERLAY' and badge.sublevel == 1)
    assert(badge.width == 28 and badge.height == 28 and badge.shown)
    -- Match the skin's level anchors (player is mirrored and offset by 1px).
    local centerX = unit == 'player' and 201 or 202
    assert(math.abs((badge.coords[1] + badge.coords[2]) / 2 - centerX / 256) < 0.00001)
    assert(math.abs((badge.coords[3] + badge.coords[4]) / 2 - 67 / 128) < 0.00001)
    assert(badge.point[2] == art and badge.point[5] == -67)
    visible = false
    syncBadge(texture, unit, container)
    assert(not badge.shown, 'badge remained after dragon was hidden')
    visible = true
    syncBadge(texture, unit, container)
    syncBadge(texture, unit, nil)
    assert(not badge.shown, 'badge remained after ClassicUI was disabled')
end
print(path .. ': ClassicUI player/target layering, late load, toggles and combat deferral passed')
