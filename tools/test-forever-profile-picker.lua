-- Run from the repository root with Lua 5.1.
local file = assert(io.open('dist/Forever/Rustcore/RustcoreOptions.lua', 'rb'))
local source = file:read('*a'):gsub('\r\n', '\n'); file:close()
local first = assert(source:find('    -- Forever uses the self-contained picker', 1, true))
local last = assert(source:find('    importBtn:SetScript("OnClick"', first, true))
local nodes = {}
local methods = {}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsShown() return self.shown end
function methods:GetName() return self.name end
function methods:GetFrameLevel() return 1 end
function methods:SetText(text) self.text = text end
function methods:SetHeight(height) self.height = height end
function methods:CreateTexture() return CreateFrame('Texture', nil, self) end
function methods:CreateFontString() return CreateFrame('FontString', nil, self) end
function methods:GetFontString() return self:CreateFontString() end
setmetatable(methods, {__index = function() return function() end end})
function CreateFrame(kind, name, parent, template)
    assert(not template or template == 'UIPanelButtonTemplate', 'Legacy dropdown must not be used on Forever')
    local node = setmetatable({kind=kind, name=name, parent=parent, scripts={}, shown=true}, {__index=methods})
    nodes[#nodes+1] = node
    return node
end
RustcoreCompat = {interfaceVersion=16002, caps={uiDropDownMenu=true}}
RustcoreTheme = {SkinButton=function() end}
Rustcore = {GetAssetPath=function(s) return s end, GetCharacterKey=function() return 'current' end}
RustcoreDB = {profiles={current={characterLabel='Current'}}}
local chunk = assert(loadstring([[
local gameplayPage, profileDesc = CreateFrame('Frame'), CreateFrame('Frame')
local function ApplyBodyFont() end
local function SettingsLocked() return combat end
]] .. source:sub(first, last-1) .. [[
return ddClick, importDropdown, ddText
]]))
local click, dropdown, label = chunk()
click.scripts.OnClick()
local list, empty
for _, n in ipairs(nodes) do
    if n.parent == dropdown and n.kind == 'Frame' then list = n end
    if type(n.text) == 'string' and n.text:find('No other saved characters', 1, true) then empty = n end
end
assert(list and list:IsShown() and empty:IsShown(), 'Empty picker must explain why no characters are listed')
click.scripts.OnClick(); assert(not list:IsShown())
RustcoreDB.profiles.z = {characterLabel='Zed'}
RustcoreDB.profiles.a = {characterLabel='Alice'}
click.scripts.OnClick()
assert(list:IsShown() and not empty:IsShown() and list.height == 40)
local rows = {}
for _, n in ipairs(nodes) do if rawget(n, "profileKey") then rows[#rows+1] = n end end
assert(#rows == 2 and rows[1].profileKey == 'a' and rows[2].profileKey == 'z')
rows[1].scripts.OnClick(rows[1]); assert(label.text == 'Alice' and not list:IsShown())
click.scripts.OnClick(); dropdown:Hide(); assert(not list:IsShown())
combat = true; click.scripts.OnClick(); assert(not list:IsShown())
rows[2].scripts.OnClick(rows[2]); assert(label.text == 'Alice')
combat = false
RustcoreDB.profiles.z = nil
click.scripts.OnClick(); assert(list.height == 20 and not rows[2]:IsShown())
print('Forever profile picker: empty state, sorted choices, selection, closing, combat guards and refresh passed')
