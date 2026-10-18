-- Offline test harness for Living Portraits.
-- Stubs just enough of the WoW API to load the addon and exercise its logic.
-- Run from the repo root:  luajit tests/run.lua
-- Not listed in the .toc, so WoW never loads this file.

local realPrint = print
local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1
    else failed = failed + 1; realPrint("FAIL  " .. name) end
end

-- WoW API stubs ---------------------------------------------------------------
local function stubIndex(t)
    -- Unknown Capitalized keys act as no-op WoW methods; lowercase fields are nil like in WoW.
    return setmetatable(t, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
    end })
end

-- Child keys the addon probes; real WoW returns nil when absent, the stub must too.
local CHILD_KEYS = { "TargetFrameContent", "PlayerFrameContent", "HealthBarContainer",
    "HealthBar", "ManaBar", "BBFPositionFrame", "BossPortraitFrameTexture", "HighLevelTexture",
    "Selection" }

local function region(t)
    t = stubIndex(t or {})
    for _, k in ipairs(CHILD_KEYS) do
        if rawget(t, k) == nil then t[k] = false end
    end
    t.shown = t.shown or false
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:SetShown(v) self.shown = not not v end
    function t:IsShown() return self.shown end
    function t:SetAlpha(a) self.alpha = a end
    function t:GetAlpha() return rawget(self, "alpha") or 1 end
    function t:SetSize(w, h) self.w, self.h = w, h end
    function t:SetPoint(point, rel, relPoint, x, y) self.anchor = { point, rel, relPoint, x, y } end
    function t:SetHeight(h) self.h = h end
    function t:GetHeight() return rawget(self, "h") or 0 end
    function t:SetWidth(w) self.w = w end
    function t:GetWidth() return rawget(self, "w") or 0 end
    return t
end

local function newTexture(shown)
    local t = region({ shown = shown or false })
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:GetDrawLayer() return "BACKGROUND", 1 end
    function t:GetSize() return 60, 60 end
    return t
end

local eventFrame
local models, frames = {}, {}
local function newFrame(kind, parent, level)
    local f = region({ kind = kind, parent = parent, shown = true, level = level or 1, scripts = {} })
    function f:SetScript(name, fn) self[name] = fn end
    function f:HookScript(name, fn) self.scripts[name] = fn end
    function f:SetUnit(unit) self.unit = unit end
    function f:SetText(t) self.text = t end
    function f:GetText() return rawget(self, "text") end
    function f:CreateTexture()
        local t = newTexture()
        local list = rawget(self, "textures") or {}
        self.textures = list
        list[#list + 1] = t
        return t
    end
    function f:CreateMaskTexture()
        local m = stubIndex({})
        function m:SetTexture(t) self.texture = t end
        self.masks = rawget(self, "masks") or {}
        table.insert(self.masks, m)
        return m
    end
    function f:CreateFontString()
        local fs = region({})
        function fs:SetText(t) self.text = t end
        function fs:GetText() return self.text end
        function fs:GetUnboundedStringWidth() return #(self.text or "") * 6 end
        function fs:SetPoint(point, rel, relPoint, x, y) self.anchor = { point, rel, relPoint, x, y } end
        self.fontStrings = self.fontStrings or {}
        table.insert(self.fontStrings, fs)
        return fs
    end
    function f:SetScale(s) self.scale = s end
    function f:GetScale() return rawget(self, "scale") or 1 end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameStrata() return "MEDIUM" end
    function f:GetEffectiveScale() return 1 end
    function f:GetTop() return rawget(self, "top") end
    function f:GetBottom() return rawget(self, "bottom") end
    function f:GetLeft() return rawget(self, "left") end
    function f:GetRight() return rawget(self, "right") end
    function f:GetPoint() local a = rawget(self, "anchor"); if a then return unpack(a) end end
    function f:SetPoint(point, rel, relPoint, x, y)
        self.anchor = { point, rel, relPoint, x, y }
        self.points = rawget(self, "points") or {}
        table.insert(self.points, self.anchor)
    end
    function f:ClearAllPoints() self.points = {} end
    function f:IsVisible()
        local up = rawget(self, "parent")
        return self.shown and (not up or up:IsVisible())
    end
    return f
end

function CreateFrame(kind, _, parent)
    local f = newFrame(kind, parent, parent and parent.level + 1)
    if kind == "PlayerModel" then models[#models + 1] = f end
    if kind == "StatusBar" then
        local fill = newTexture(true)
        function f:GetStatusBarTexture() return fill end
    end
    frames[#frames + 1] = f
    eventFrame = eventFrame or f
    return f
end

PixelUtil = {
    SetHeight = function(r, h) r.h = h end,
    SetWidth = function(r, w) r.w = w end,
    SetPoint = function(r, ...) r.anchor = { ... } end,
}

function hooksecurefunc(obj, method, hook)
    local orig = obj[method]
    obj[method] = function(...) local r = orig(...); hook(...); return r end
end

-- Blizzard frame tree: root (level 5) > container (level 6) > portrait texture
local function unitFrame(field)
    local root = newFrame("Frame", nil, 5)
    local c = newFrame("Frame", root, 6)
    local p = newTexture(true)
    function p:GetParent() return c end
    function c:GetParent() return root end
    c[field] = p
    return root, c
end

local playerRoot, playerContainer = unitFrame("PlayerPortrait")
PlayerFrame = playerRoot;  PlayerFrame.PlayerFrameContainer = playerContainer
local targetRoot, targetContainer = unitFrame("Portrait")
TargetFrame = targetRoot;  TargetFrame.TargetFrameContainer = targetContainer
local _, totContainer = unitFrame("Portrait"); TargetFrame.totFrame = totContainer
local focusRoot, focusContainer = unitFrame("Portrait")
FocusFrame = focusRoot;    FocusFrame.TargetFrameContainer = focusContainer
local _, fotContainer = unitFrame("Portrait"); FocusFrame.totFrame = fotContainer
PartyFrame = newFrame("Frame", nil, 5)
for i = 1, 4 do local _, c = unitFrame("Portrait"); PartyFrame["MemberFrame" .. i] = c end

-- World state the tests control
local world = { exists = {}, visible = {}, connected = {}, guid = {}, secret = false }
function UnitExists(u) return world.exists[u] end
function UnitGUID(u) return world.guid[u] or ("G-" .. u) end
function UnitIsVisible(u) return world.visible[u] ~= false end
function UnitIsConnected(u) return world.connected[u] ~= false end
function UnitClassification() return "normal" end
world.class = "ROGUE"
function UnitClass() return "Class", world.class end
function issecretvalue() return world.secret end
-- Players and talents: world.players marks units that are players; talent trees are
-- 3 groups (11, 12, 13) and configs map to points per group (zero groups left out).
world.players = {}
function UnitIsPlayer(u) return world.players[u] or false end
-- Camelot names: UnitName returns (first name, surname)
world.names = { player = { "Naut", "Sfw" } }
function UnitName(u) local n = world.names[u]; if n then return n[1], n[2] end return "Mob" end
function UnitIsUnit(a, b) return a == b or (a == "target" and b == "player" and world.targetIsMe) or false end
local now = 100
function GetTime() return now end
local inspects = {}
function NotifyInspect(u) inspects[#inspects + 1] = u end
function CanInspect() return true end
Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
local talentConfigs = { [7] = { [11] = 5 }, [-1] = { [11] = 2, [12] = 8 } }
C_ClassTalents = { GetActiveConfigID = function() return 7 end }
C_Traits = {
    GetConfigInfo = function(id) return talentConfigs[id] and { treeIDs = { 1112 } } end,
    GetGroupDisplayInfoByTreeID = function() return { { groupID = 11 }, { groupID = 12 }, { groupID = 13 } } end,
    GetGroupCurrencyInfo = function(id)
        local out = {}
        for group, spent in pairs(talentConfigs[id] or {}) do
            out[#out + 1] = { traitNodeGroupID = group, currencyInfos = { { spent = spent } } }
        end
        return out
    end,
}
local inCombat = false
function InCombatLockdown() return inCombat end

local tick
C_Timer = {
    After = function(_, fn) fn() end,
    NewTicker = function(_, fn) tick = fn; return {} end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print() end -- silence addon chat output
SlashCmdList = {}

-- Settings API (Options > AddOns): records what the addon registers
local proxies, buttons, notified, openedCategory, popupShown = {}, {}, {}, nil, nil
local elementInitializers = {}
Settings = {
    RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return 42 end } end,
    RegisterProxySetting = function(_, var, _, name, default, get, set)
        local s = { var = var, name = name, default = default, get = get, set = set }
        proxies[var] = s
        return s
    end,
    CreateCheckbox = function() end,
    CreateSlider = function() end,
    CreateDropdown = function(_, _, options) options() end,
    CreateColorSwatch = function() end,
    CreateElementInitializer = function(template, data)
        local i = { template = template, data = data }
        elementInitializers[#elementInitializers + 1] = i
        return i
    end,
    CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
    CreateControlTextContainer = function()
        local c = { data = {} }
        function c:Add(value, label) self.data[#self.data + 1] = { value, label } end
        function c:GetData() return self.data end
        return c
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) openedCategory = id end,
    NotifyUpdate = function(var) notified[var] = (notified[var] or 0) + 1 end,
}
SettingsPanel = { GetLayout = function() return { AddInitializer = function() end } end }
function CreateSettingsListSectionHeaderInitializer(text) return { header = text } end
local buttonInits = {}
function CreateSettingsButtonInitializer(name, text, click)
    buttons[name] = click
    local i = { name = name, text = text, click = click }
    function i:InitFrame(frame) frame.Button.text = self.text; frame.Button.shown = true end
    function i:Resetter() end
    buttonInits[name] = i
    return i
end
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
StaticPopupDialogs = {}
local popupData
function StaticPopup_Show(which, _, _, data) popupShown = which; popupData = data end
local reloaded = false
function ReloadUI() reloaded = true end
-- Addon list: the pre-rename addon can be installed next to us
local oldAddon = { loaded = false, disabled = false }
C_AddOns = {
    IsAddOnLoaded = function(name) return name == "BBF_AnimatedPortraits" and oldAddon.loaded end,
    DisableAddOn = function(name) if name == "BBF_AnimatedPortraits" then oldAddon.disabled = true end end,
}

-- BBF present at load (OptionalDeps), with a function the addon should hook
BBF = { SetCustomFonts = function() end }

-- Load the addon --------------------------------------------------------------
-- Every file in .toc order, sharing one namespace table like WoW does.
local ns = {}
for line in io.lines("LivingPortraits.toc") do
    local file = line:gsub("\r", ""):gsub("\\", "/")
    if file:match("%.lua$") then assert(loadfile(file))("LivingPortraits", ns) end
end

local function fire(event, arg) eventFrame.OnEvent(eventFrame, event, arg) end
local function slash(msg) SlashCmdList.LIVINGPORTRAITS(msg) end
local function modelFor(unit)
    for _, m in ipairs(models) do if m.unit == unit then return m end end
end
local function shownFor(unit)
    for _, m in ipairs(models) do
        if m.unit == unit and m:IsVisible() then return true end
    end
    return false
end

-- Tests -----------------------------------------------------------------------
world.exists = { player = true, target = true, targettarget = true, party1 = true, party2 = true }
world.visible.party2 = false

-- Saved settings from an older version (inset 0.82) must be upgraded
LivingPortraitsDB = { enabled = true, sizes = { large = { inset = 0.82, cam = 0.85 }, small = { inset = 0.82, cam = 0.85 } } }
fire("ADDON_LOADED", "LivingPortraits")
local bbfHooked = BBF.SetCustomFonts
BBF = nil
check("old saved inset migrated to new default", LivingPortraitsDB.sizes.small.inset == 0.80)
check("settings version recorded", LivingPortraitsDB.version == ns.SETTINGS_VERSION)
check("defaults applied", LivingPortraitsDB.enabled == true and LivingPortraitsDB.sizes.large.inset == 0.80)

-- v13: Jason's settings became the defaults. Old defaults move, picked values stay, dev keys go.
do
    local current = LivingPortraitsDB
    LivingPortraitsDB = { version = 12, eliteIcon = "center", eliteBorder = true, restIcon = "name",
        barText = "percent", resourceAlign = "left", resourceRadius = 6, comboRadius = 5, comboPoints = "pixel" }
    ns.LoadSettings()
    local m = LivingPortraitsDB
    check("v13: untouched old defaults move to the new ones", m.eliteIcon == "bottom" and m.eliteBorder == false
        and m.restIcon == "corner" and m.resourceRadius == 5)
    check("v13: values someone picked stay", m.barText == "percent" and m.resourceAlign == "left")
    check("v13: class resource dev keys dropped", m.comboRadius == nil and m.comboPoints == nil)
    check("fresh defaults are Jason's settings", ns.defaults.barText == "max" and ns.defaults.barTextStyle == "shadow")
    LivingPortraitsDB = current
    ns.LoadSettings()
end

fire("PLAYER_ENTERING_WORLD")
check("models created lazily, only for units on screen (4 of 9)", #models == 4)
check("player model shown", shownFor("player"))
check("target model shown", shownFor("target"))
check("tot model shown", shownFor("targettarget"))
check("party1 model shown", shownFor("party1"))
check("party2 out of range -> hidden", not shownFor("party2"))
check("focus missing -> hidden", not shownFor("focus"))

local pm = modelFor("player")
check("model sized by large inset", pm.w and math.abs(pm.w - 60 * 0.80) < 0.01)
local vig = rawget(playerContainer, "textures")[1]
check("circle edge is exactly the model's size (48)", math.abs(vig.w - 48) < 0.01)
check("model sits below the Blizzard container (ring on top)", pm.level < playerContainer.level)
check("model parented to the unit frame root", pm.parent == PlayerFrame)
check("2D portrait hidden while active", not playerContainer.PlayerPortrait.shown)

-- Blizzard/BBF re-showing the portrait while active gets re-hidden
playerContainer.PlayerPortrait:Show()
check("portrait stays hidden if re-shown while active", not playerContainer.PlayerPortrait.shown)

-- Circle background opacity
slash("circlebg 0")
check("/lp circlebg 0 hides the circle background", LivingPortraitsDB.circleBg == 0)
local corners = rawget(playerContainer, "textures")[2]
check("dark corners hidden with a clear background", corners and not corners.shown)
check("soft edge hidden too with a clear background (no dark ring)", not vig.shown)
slash("circlebg 1")

-- Centering offset and calibration
check("measured default offsets applied", LivingPortraitsDB.offsets.tot[1] == -1.3 and LivingPortraitsDB.offsets.tot[2] == 0)
local defA = modelFor("player").anchor
check("player portrait uses its measured offset", defA and defA[4] == -0.5 and defA[5] == 0.6)
slash("offset player 2 -1")
check("/lp offset stores the nudge", LivingPortraitsDB.offsets.player[1] == 2 and LivingPortraitsDB.offsets.player[2] == -1)
local pmA = modelFor("player").anchor
check("offset moves the model off the portrait center", pmA and pmA[4] == 2 and pmA[5] == -1)
check("offset moves the circle edge with it", vig.anchor and vig.anchor[4] == 2 and vig.anchor[5] == -1)
slash("offset player 0 0")
slash("calibrate")
check("/lp calibrate turns calibration on", LivingPortraitsDB.calibrate == true)
slash("calibrate")

-- A container at level 0 (the target's) is raised so the model can sit beneath it
targetContainer.level = 0
slash("toggle"); slash("toggle")
check("low container raised to level 2", targetContainer.level == 2)
local tm = modelFor("target")
check("model sits below the raised container", tm.level < targetContainer.level)
slash("toggle")
check("container level restored when turned off", targetContainer.level == 0)
slash("toggle")
targetContainer.level = 6; slash("toggle"); slash("toggle")

-- BBF/Blizzard re-sets the container level later: our layering re-applies via the hook
targetContainer.level = 6; slash("toggle"); slash("toggle")
local tmod = modelFor("target")
targetContainer:SetFrameLevel(0)
check("container level change re-applies layering", targetContainer.level == 2 and tmod.level < targetContainer.level)
-- ...and the ticker catches changes that bypass the hook
targetContainer.level = 0; tmod.level = 5
tick()
check("ticker restores model below container", tmod.level < targetContainer.level)

-- Target-style layout: ring art in its own frame (LOW strata, level 501), portrait
-- in a separate BACKGROUND frame. Layers must go just beneath the ring's frame.
do
    local ringFrame = newFrame("Frame", TargetFrame, 501)
    function ringFrame:GetFrameStrata() return "LOW" end
    local ringTex = newTexture(true)
    function ringTex:GetDrawLayer() return "BACKGROUND", 2 end
    function ringTex:GetParent() return ringFrame end
    function ringFrame:CreateTexture() local tx = newTexture(); self.made = tx; return tx end
    local focusPortrait = FocusFrame.TargetFrameContainer.Portrait
    FocusFrame.TargetFrameContainer.FrameTexture = ringTex
    world.exists.focus = true
    fire("PLAYER_FOCUS_CHANGED")
    local fm = modelFor("focus")
    check("model placed just beneath the ring's frame (500)", fm and fm.level == 500)
    check("circle edge created on the ring's frame", ringFrame.made ~= nil)
    check("focus portrait hidden", not focusPortrait.shown)
end

-- Ticker: party2 comes into range
world.visible.party2 = nil
tick()
check("ticker shows party2 when in range", shownFor("party2"))

-- Ticker: no change -> no re-SetUnit
local setCount = 0
for _, m in ipairs(models) do
    local orig = m.SetUnit
    m.SetUnit = function(self, u) setCount = setCount + 1; orig(self, u) end
end
tick()
check("ticker idle when nothing changed", setCount == 0)

-- Alpha mirrors Blizzard's portrait (party out-of-range fade)
PartyFrame.MemberFrame1.Portrait:SetAlpha(0.55)
check("model mirrors portrait alpha", modelFor("party1").alpha == 0.55)
PartyFrame.MemberFrame1.Portrait:SetAlpha(1)

-- Unit frame hides (e.g. raid-style party frames) -> our layers hide
local member1 = PartyFrame.MemberFrame1
member1.shown = false; member1.scripts.OnHide()
check("container OnHide hides model", not shownFor("party1"))
check("container OnHide restores 2D portrait", member1.Portrait.shown)
member1.shown = true; member1.scripts.OnShow()
check("container OnShow brings model back", shownFor("party1"))

-- Focus set
world.exists.focus = true
fire("PLAYER_FOCUS_CHANGED")
check("focus shown after PLAYER_FOCUS_CHANGED", shownFor("focus"))

-- Disconnect
world.connected.party1 = false
fire("UNIT_CONNECTION", "party1")
check("disconnected party1 -> hidden", not shownFor("party1"))
world.connected.party1 = nil

-- Group toggles
slash("unit party")
check("/lp unit party hides party", not shownFor("party1") and not shownFor("party2"))
slash("unit party")
check("/lp unit party restores party", shownFor("party1"))
slash("unit tot")
check("/lp unit tot hides tot", not shownFor("targettarget"))
slash("unit tot")

-- Global toggle restores the 2D portrait
slash("toggle")
check("/lp toggle hides everything", not shownFor("player") and not shownFor("target"))
check("/lp toggle restores 2D portrait", playerContainer.PlayerPortrait.shown)
slash("toggle")
check("/lp toggle restores", shownFor("player"))

-- Sized settings
slash("inset 0.9 small")
check("inset small only", LivingPortraitsDB.sizes.small.inset == 0.9 and LivingPortraitsDB.sizes.large.inset == 0.80)
slash("inset 0.5 large")
check("circle edge follows a smaller inset", math.abs(vig.w - 30) < 0.01)
slash("inset 0.9 large")
check("circle edge follows a larger inset", math.abs(vig.w - 54) < 0.01)
slash("inset 0.80 large")
slash("cam 0.7")
check("cam without size sets both", LivingPortraitsDB.sizes.small.cam == 0.7 and LivingPortraitsDB.sizes.large.cam == 0.7)
slash("cam 9 large"); check("cam clamped to 2", LivingPortraitsDB.sizes.large.cam == 2)
slash("zoom 5");      check("zoom clamped to 1", LivingPortraitsDB.zoom == 1)
slash("vignette");    check("vignette toggles off", LivingPortraitsDB.vignette == false)
slash("reset")
check("reset restores defaults", LivingPortraitsDB.sizes.large.cam == 0.85 and LivingPortraitsDB.vignette == true)

-- BBF no-portrait mode
BBF = { HasNoPortrait = function(u) return u == "target" end }
fire("PLAYER_TARGET_CHANGED")
check("BBF no-portrait -> target hidden", not shownFor("target"))
BBF = nil

-- Square style: BBF No Portrait / Pixel Border on for player and target
-- A bar with BBF's pixel-border position frame. Like WoW, the posFrame's top follows the
-- bar's anchor offset and its bottom follows top - height.
local function barWithPos(parent, pos, anchor)
    local bar = newFrame("Frame", parent, 7)
    bar.h = pos.h
    bar.anchor = anchor or { "TOPLEFT", parent, "TOPLEFT", 0, 0 }
    bar.baseTop, bar.origY = pos.top, bar.anchor[5]
    bar.origX = bar.anchor[4]
    local pf = newFrame("Frame", bar, 8)
    pf.h = pos.h
    -- Left/right follow the bar's x offset; the right edge also follows a width change
    function pf:GetLeft() return pos.left + (bar.anchor[4] - bar.origX) end
    function pf:GetWidth() return rawget(self, "w") or (pos.right - pos.left) end
    function pf:GetRight() return self:GetLeft() + self:GetWidth() end
    function pf:GetTop() return bar.baseTop + (bar.anchor[5] - bar.origY) end
    function pf:GetBottom() return self:GetTop() - self.h end
    function pf:GetCenter() return 0, self:GetTop() - self.h / 2 end
    bar.BBFPositionFrame = pf
    -- BBF's pixel border edges (top, right, bottom, left), black like BBF makes them
    bar.BBFBlackBorder = {}
    for i = 1, 4 do
        local e = newTexture(true)
        e.color = { 0, 0, 0, 1 }
        bar.BBFBlackBorder[i] = e
    end
    return bar
end
-- A bar text whose vertical center follows its anchor's y offset.
local function barText(centerY)
    local fs = region({ shown = true })
    fs.anchor = { "LEFT", UIParent, "LEFT", 2, 0 }
    fs.baseCY = centerY
    function fs:GetNumPoints() return 1 end
    function fs:GetPoint() return unpack(self.anchor) end
    function fs:SetPoint(point, rel, relPoint, x, y) self.anchor = { point, rel, relPoint, x, y } end
    function fs:GetCenter() return 0, self.baseCY + self.anchor[5] end
    return fs
end
-- Name/level text: records its anchors so the name-row layout can be checked.
local function rowText()
    local fs = region({ shown = true })
    fs.points = { { "TOPLEFT", PlayerFrame, "TOPLEFT", 88, -27 } }
    fs.justify = "LEFT"
    function fs:GetNumPoints() return #self.points end
    function fs:GetPoint(i) return unpack(self.points[i]) end
    function fs:ClearAllPoints() self.points = {} end
    function fs:SetPoint(...) table.insert(self.points, { ... }) end
    function fs:GetJustifyH() return self.justify end
    function fs:SetJustifyH(j) self.justify = j end
    fs.text, fs.w = "", 120 -- BBF gives names a fixed-width box
    function fs:SetText(t) self.text = t end
    function fs:GetText() return self.text end
    function fs:GetUnboundedStringWidth() return #self.text * 6 end
    return fs
end
PlayerName, PlayerLevelText = rowText(), rowText()
PlayerFrame.bbfName = rowText() -- BBF's replacement name, laid out by BBF itself
PlayerFrame.bbfName.justify = "CENTER"

local function withParent(bar, holder)
    function bar:GetParent() return holder end
    return bar
end

local playerHpHolder = { LeftText = barText(95) }
local playerHp = withParent(barWithPos(PlayerFrame, { top = 100, h = 19, left = 50, right = 173 }), playerHpHolder)
playerHpHolder.HealthBar = playerHp
local playerMana = barWithPos(PlayerFrame, { top = 79, h = 8, left = 50, right = 173 })
playerMana.ManaBarText = barText(80)
local playerCombatIcon, playerRestIcon = rowText(), rowText()
PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = {
    HealthBarsContainer = playerHpHolder,
    ManaBarArea = { ManaBar = playerMana },
}, PlayerFrameContentContextual = { AttackIcon = playerCombatIcon, PlayerRestLoop = playerRestIcon } }
local targetName, targetLevel = rowText(), rowText()
local targetHpHolder = {}
local targetHp = withParent(barWithPos(TargetFrame, { top = 100, h = 19, left = 50, right = 173 }), targetHpHolder)
targetHpHolder.HealthBar = targetHp
local targetMana = barWithPos(TargetFrame, { top = 79, h = 8, left = 42, right = 165 },
    { "TOPRIGHT", targetHpHolder, "BOTTOMRIGHT", -8, 0 })
TargetFrame.TargetFrameContent = { TargetFrameContentMain = {
    HealthBarsContainer = targetHpHolder,
    ManaBar = targetMana,
    Name = targetName, LevelText = targetLevel,
} }

-- Target-of-target: health anchored at its bottom, mana anchored under the health bar
local totHp = barWithPos(totContainer, { top = 60, h = 12, left = 200, right = 263 },
    { "BOTTOMRIGHT", totContainer, "RIGHT", -6, -2.5 })
local totMana = barWithPos(totContainer, { top = 47, h = 4, left = 200, right = 263 },
    { "TOPLEFT", totHp, "BOTTOMLEFT", 0, -1 })
totContainer.HealthBar, totContainer.ManaBar = totHp, totMana
totContainer.Name = rowText()
totContainer.bbfName = rowText()

-- BBF's No Portrait mode moves the player's portrait container into a hidden frame
playerContainer.shown = false
BBF = { HasNoPortrait = function(u) return u == "player" or u == "target" or u == "targettarget" end }
-- Target text mirrors the player's by default; the layout checks below start unmirrored
-- (the mirror block under the talent build turns it back on)
check("target text mirrored by default", LivingPortraitsDB.mirrorTarget == true)
slash("mirror")
slash("style square")
local function squareModel(unit, root)
    for _, m in ipairs(models) do
        if m.unit == unit and m.parent and m.parent.parent == root then return m end
    end
end
local sqModel = squareModel("player", PlayerFrame)
check("player square works even though BBF hid the portrait container", sqModel and sqModel:IsVisible())
check("square box parented to the unit frame", sqModel and sqModel.parent.parent == PlayerFrame)
check("circle model hidden in square mode", not modelFor("player"):IsVisible())
local box = sqModel and sqModel.parent

-- Stack 19 + 8 + 10 extra = 37, name row 12, bars 25 split 0.66: health 17, mana 8
check("health bar is 2/3 of the bars (17)", playerHp.h == 17 and playerHp.BBFPositionFrame.h == 17)
check("mana bar gets the remaining 1/3 (8)", playerMana.h == 8 and playerMana.BBFPositionFrame.h == 8)
check("health bar starts below the 12px name row", playerHp.anchor[5] == -12)
check("mana bar sits right under the health bar (-9)", playerMana.anchor[5] == -9)
check("health and mana borders share one line", playerMana.BBFPositionFrame:GetTop() == playerHp.BBFPositionFrame:GetBottom() - 1)
check("tall box: 38 wide, name row to mana bottom plus the 9px build line", box and box.w == 38 and box.h == 38 + 9)
check("tall box top at the build line above the name row", box and box.anchor[5] == 12 + 9)
local pn = PlayerName.points[1]
check("player name pinned left in the name row", pn[1] == "LEFT" and pn[3] == "TOPLEFT" and pn[5] == 6 and PlayerName.justify == "LEFT")
local pl = PlayerLevelText.points[1]
check("player level pinned right on the same line", pl[1] == "RIGHT" and pl[3] == "TOPRIGHT" and pl[5] == 6)
PlayerLevelText:SetPoint("LEFT", PlayerFrame, "LEFT", 194, 17) -- BBF re-positions it
check("level stays pinned if BBF moves it", #PlayerLevelText.points == 1 and PlayerLevelText.points[1][1] == "RIGHT")
local bn = PlayerFrame.bbfName
check("BBF's name pinned left on the level's line", bn.points[1][1] == "LEFT" and bn.points[1][5] == 6 and bn.justify == "LEFT")
bn:SetPoint("BOTTOM", PlayerFrame, "TOP", 0, 0); bn:SetJustifyH("CENTER") -- BBF re-lays it out
check("BBF's name stays pinned and left-aligned after BBF re-layout", #bn.points == 1 and bn.points[1][1] == "LEFT" and bn.justify == "LEFT")
check("target name pinned left like the player", targetName.points[1][1] == "LEFT" and targetName.justify == "LEFT")
check("target level pinned right like the player", targetLevel.points[1][1] == "RIGHT")
bn.shown = true
playerHp.BBFPositionFrame.w = 123
PlayerLevelText.shown = true
PlayerLevelText:SetText("14")
bn:SetText("Naut")
check("name box shrinks to its text, so a centered justify can't indent it", bn.w == 25)
bn:SetWidth(120) -- BBF re-sets its fixed width on SetText
check("name box stays shrunk after BBF resets its width", bn.w == 25)
bn:SetText(string.rep("x", 40))
check("long name stops short of the level and the status icon room", bn.w == math.ceil(123 - 2 - (12 + 4) - 18) + 1)
check("player box sits left of the health bar", box and box.anchor[1] == "TOPRIGHT" and box.anchor[3] == "TOPLEFT")

-- Resting Zzz: on the portrait box's top-right corner by default, or after the name
local rp = playerRestIcon.points[1]
check("rest icon on the box's top-right corner by default", LivingPortraitsDB.restIcon == "corner" and #playerRestIcon.points == 1
    and rp[1] == "CENTER" and rp[2] == box and rp[3] == "TOPRIGHT")
check("combat icon stays after the name", playerCombatIcon.points[1][2] == bn)
playerRestIcon:SetPoint("CENTER", PlayerFrame, "TOPLEFT", 40, -30) -- Blizzard/BBF re-place it
check("rest icon stays on the corner", #playerRestIcon.points == 1 and playerRestIcon.points[1][2] == box)
slash("resticon top")
check("unknown rest icon spot is ignored", LivingPortraitsDB.restIcon == "corner")
slash("resticon name")
check("/lp resticon name puts it back after the name", playerRestIcon.points[1][2] == bn)

-- Edit Mode: BBF anchors the selection art around the health bar (and hooks it to stay); the
-- Selection frame itself (snapping, guide lines, clicks) is sized to the bars + our box
do
    local hpPos = playerHp.BBFPositionFrame
    PlayerFrame.healthbar = hpPos
    PlayerFrame.left, PlayerFrame.right, PlayerFrame.top, PlayerFrame.bottom = 0, 232, 120, 40
    box.left, box.right, box.top, box.bottom = 10, 48, 109, 71
    local sel = newFrame("Frame", PlayerFrame, 9)
    sel.bbfRepositioned = true
    function sel:SetAllPoints(rel) self.points = { { "ALL", rel } } end
    local BBF_SPOT = { TopLeftCorner = { "TOPLEFT", -16, 21 }, TopRightCorner = { "TOPRIGHT", 15, 21 },
        BottomLeftCorner = { "BOTTOMLEFT", -16, -25 }, BottomRightCorner = { "BOTTOMRIGHT", 15, -25 } }
    for key, spot in pairs(BBF_SPOT) do
        local c = rowText()
        hooksecurefunc(c, "SetPoint", function(self) -- BBF's FixSelectionHighlight hook
            if self.changing then return end
            self.changing = true
            self:ClearAllPoints()
            self:SetPoint(spot[1], hpPos, spot[1], spot[2], spot[3])
            self.changing = false
        end)
        sel[key] = c
    end
    PlayerFrame.Selection = sel
    slash("refresh")
    local p1, p2 = sel.points[1], sel.points[2]
    check("edit mode: Selection's TOPLEFT on the unit frame, 16 left of the box, 15 over it",
        p1[1] == "TOPLEFT" and p1[2] == PlayerFrame and p1[4] == 10 - 16 - 0 and p1[5] == 109 + 15 - 120)
    check("edit mode: Selection's BOTTOMRIGHT 15 right of / 25 under the health bar",
        p2[1] == "BOTTOMRIGHT" and p2[4] == hpPos:GetRight() + 15 - 232 and p2[5] == hpPos:GetBottom() - 25 - 40)
    local tl = sel.TopLeftCorner.points
    check("edit mode: outline corners pinned to the Selection", #tl == 1 and tl[1][2] == sel and tl[1][4] == 0
        and sel.BottomRightCorner.points[1][2] == sel)
    sel.TopLeftCorner:SetPoint("TOPLEFT", hpPos, "TOPLEFT", -16, 21) -- BBF re-anchors it
    check("edit mode: our anchor wins over BBF's re-anchor", sel.TopLeftCorner.points[1][2] == sel)
    slash("style circle")
    check("edit mode: circle style gives the Selection back its full frame", sel.points[1][1] == "ALL")
    check("edit mode: circle style hands the corners back to BBF", sel.TopLeftCorner.points[1][2] == hpPos
        and sel.BottomRightCorner.points[1][2] == hpPos)
    slash("style square")
    check("edit mode: box style again", sel.points[1][1] == "TOPLEFT" and sel.TopLeftCorner.points[1][2] == sel)
    PlayerFrame.Selection = false
    PlayerFrame.healthbar = nil
end

-- Edit Mode, party: one Selection around all members (BBF's margins around the party frame:
-- 27 in on the left, 12 out right, 15 up, 5 down), grown to include each member's box
do
    PartyFrame.left, PartyFrame.right, PartyFrame.top, PartyFrame.bottom = 0, 200, 300, 100
    local sel = newFrame("Frame", PartyFrame, 9)
    sel.bbfRepositioned = true
    function sel:SetAllPoints(rel) self.points = { { "ALL", rel } } end
    for _, key in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }) do
        local c = rowText()
        hooksecurefunc(c, "SetPoint", function(self) -- BBF's hook: back on the party frame
            if self.changing then return end
            self.changing = true
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", PartyFrame, "TOPLEFT", 27, 15)
            self.changing = false
        end)
        sel[key] = c
    end
    PartyFrame.Selection = sel
    local squaresBefore = { ns.squares.party1, ns.squares.party2 }
    local function partyBox(i, l, r, t, b)
        local bx = newFrame("Frame", PartyFrame["MemberFrame" .. i], 8)
        bx.left, bx.right, bx.top, bx.bottom = l, r, t, b
        ns.squares["party" .. i] = { box = bx }
        return bx
    end
    local b1 = partyBox(1, 5, 40, 310, 270)
    local b2 = partyBox(2, 5, 40, 250, 210)
    ns.UpdateEditMode()
    local p1, p2 = sel.points[1], sel.points[2]
    check("edit mode party: left edge 16 past the member boxes, top 15 over the first box",
        p1[1] == "TOPLEFT" and p1[2] == PartyFrame and p1[4] == 5 - 16 and p1[5] == 310 + 15 - 300)
    check("edit mode party: right and bottom keep BBF's party margins", p2[4] == 12 and p2[5] == -5)
    check("edit mode party: corners pinned to the Selection", sel.TopLeftCorner.points[1][2] == sel)
    b1:Hide()
    ns.UpdateEditMode() -- the box's OnHide hook does this in game
    check("edit mode party: first member leaves, top follows the second box", sel.points[1][5] == 15
        and sel.points[1][4] == 5 - 16)
    b2:Hide()
    ns.UpdateEditMode() -- the box's OnHide hook does this in game
    check("edit mode party: no boxes, Selection and corners back to Blizzard/BBF",
        sel.points[1][1] == "ALL" and sel.TopLeftCorner.points[1][2] == PartyFrame)
    ns.squares.party1, ns.squares.party2 = squaresBefore[1], squaresBefore[2]
    PartyFrame.Selection = false
end

-- Edit Mode's "Party Frames" option shows party frames solo: they get the box layout with an
-- empty box (BBF's party bars leave a 2px gap between health and mana; ours share a line)
do
    local member = PartyFrame.MemberFrame3
    local hp = barWithPos(member, { top = 200, h = 12, left = 60, right = 140 })
    local mana = barWithPos(member, { top = 186, h = 6, left = 60, right = 140 })
    member.HealthBarContainer, member.ManaBar = { HealthBar = hp }, mana
    member.PartyMemberOverlay = false
    local oldHas = BBF.HasNoPortrait
    BBF.HasNoPortrait = function(u) return oldHas(u) or u == "party3" end
    local forced = true
    EditModeManagerFrame = { ArePartyFramesForcedShown = function() return forced end }
    world.exists.party3 = false
    slash("refresh")
    local sq = ns.squares.party3
    check("edit mode sample party frame: empty box shows", sq and sq.box.shown and not sq.model.shown)
    check("edit mode sample party frame: bars laid out, health and mana share a line",
        hp.h == 16 and mana.BBFPositionFrame:GetTop() == hp.BBFPositionFrame:GetBottom() - 1)
    forced = false
    slash("refresh")
    check("edit mode sample party frame: box hides when the sample frames go", not sq.box.shown)
    BBF.HasNoPortrait = oldHas
    EditModeManagerFrame = nil
    member.HealthBarContainer, member.ManaBar = false, false
end

local function centered(fs, pos) local _, a = fs:GetCenter(); local _, b = pos:GetCenter(); return math.abs(a - b) < 0.5 end
check("health text vertically centered in its bar", centered(playerHpHolder.LeftText, playerHp.BBFPositionFrame))
check("mana text vertically centered in its bar", centered(playerMana.ManaBarText, playerMana.BBFPositionFrame))
check("text keeps its horizontal offset", playerHpHolder.LeftText.anchor[4] == 2)

local tBox = squareModel("target", TargetFrame)
tBox = tBox and tBox.parent
check("target box sits right of the health bar", tBox and tBox.anchor[1] == "TOPLEFT" and tBox.anchor[3] == "TOPRIGHT")
check("target mana bar shifted to line up with health (right edges)", targetMana.anchor[4] == 0)
check("target mana border same width as health border", targetMana.BBFPositionFrame.w == targetHp.BBFPositionFrame:GetWidth())
check("target mana bar sits right under the health bar", targetMana.anchor[5] == -9)

-- ToT: stack 12 + 4 + 6 = 22, name row 9, bars 13 split 0.66: health 9, mana 4
check("ToT health shortened below its name row (9)", totHp.h == 9)
check("ToT mana gets the rest (4)", totMana.h == 4)
check("ToT bottom-anchored health keeps its top edge, minus the row", totHp.anchor[5] == -2.5 - (9 - 12) - 9)
check("ToT mana closes BBF's gap under the health bar", totMana.BBFPositionFrame:GetTop() == totHp.BBFPositionFrame:GetBottom() - 1)
check("ToT name pinned left in its row", totContainer.bbfName.points[1][1] == "LEFT" and totContainer.bbfName.points[1][5] == 4.5)
slash("namerow 0 tot")
check("/lp namerow 0 tot gives ToT its full bars back", totHp.h == 15 and LivingPortraitsDB.nameRow.large == 12)
slash("namerow 9 tot")

-- NPC with no power: Blizzard hides the mana bar, BBF keeps its empty slot visible
targetMana.shown = false
targetMana.BBFPositionFrame.parent = TargetFrame -- BBF reparents the slot to stay visible
fire("PLAYER_TARGET_CHANGED")
check("NPC: empty mana slot still laid out (8)", targetMana.BBFPositionFrame.h == 8)
check("NPC: empty mana slot sits under the health bar", targetMana.anchor[5] == -9)
check("NPC: box still spans health and the empty mana slot (38)", tBox.w == 38)
-- BBF's "hide target mana": slot hidden too, health takes the whole stack
targetMana.BBFPositionFrame.shown = false
fire("PLAYER_TARGET_CHANGED")
check("no mana slot: health fills the bars (25)", targetHp.h == 25)
check("no mana slot: box spans name row + health (37)", tBox.w == 37)
targetMana.shown, targetMana.BBFPositionFrame.shown = true, true
targetMana.BBFPositionFrame.parent = targetMana
fire("PLAYER_TARGET_CHANGED")
check("mana back: normal 2:1 layout again", targetHp.h == 17 and tBox.w == 38)

-- Target switch: no target for a moment, BBF re-places the level, then a new target
world.exists.target = false
fire("PLAYER_TARGET_CHANGED")
targetLevel:SetPoint("RIGHT", TargetFrame, "RIGHT", -196, 17) -- BBF's no-portrait spot
world.exists.target = true
fire("PLAYER_TARGET_CHANGED")
check("level stays pinned across a target switch", #targetLevel.points == 1 and targetLevel.points[1][1] == "RIGHT")
check("name stays pinned across a target switch", targetName.points[1][1] == "LEFT" and targetName.points[1][2] ~= TargetFrame)
check("bars keep their layout while there's no target", targetHp.h == 17)

-- Square background: off by default, adjustable
local sqBg = box and rawget(box, "textures") and box.textures[1]
check("square background hidden by default", sqBg and not sqBg.shown)
slash("bg 0.5")
check("/lp bg shows the background", sqBg and sqBg.shown and LivingPortraitsDB.squareBg == 0.5)
slash("bg 0")
check("/lp bg 0 hides it again", sqBg and not sqBg.shown)

slash("extend 4 large")
-- Stack 19 + 8 + 4 = 31, bars 19: health 13, mana 6, box 33
check("/lp extend large resizes the stack", playerHp.h == 13 and playerMana.h == 6)
check("/lp extend keeps box aligned with bars (32)", box.w == 32)
check("/lp extend large leaves small alone", LivingPortraitsDB.stackExtra.small == 6)
slash("split 0.5")
check("/lp split changes the health share", playerHp.h == 10 and playerMana.h == 9)
slash("split 0.66")

-- Turning alignment off restores the original offset
slash("alignmana")
check("/lp alignmana turns alignment off", LivingPortraitsDB.alignMana == false)
check("mana bar back at its original x offset", targetMana.anchor[4] == -8)
slash("alignmana")
check("re-aligning is stable", targetMana.anchor[4] == 0)

-- Class resource, rogue: BBF's combo point bar ("Move Combo Points under PlayerFrame") goes under the player's bars
do
    local comboBar = newFrame("Frame", PlayerFrame, 3)
    comboBar.topPadding = 10
    comboBar.classResourceButtonTable = {}
    for i = 1, 5 do comboBar.classResourceButtonTable[i] = newFrame("Frame", comboBar, 4) end
    function comboBar:UpdatePower() end
    comboBar.bbfTooltipMouse = true -- BBF gives its player bar a tooltip
    function comboBar:EnableMouse(v) self.mouse = v end
    local reanchored = 0
    BBF.ComboPointBar = comboBar
    BBF.ReanchorComboPointBar = function() reanchored = reanchored + 1 end
    local combo = 2
    function GetComboPoints() return combo end
    local manaPos = playerMana.BBFPositionFrame

    slash("refresh")
    check("class resource defaults to pixel circles", LivingPortraitsDB.resource == "pixel")
    local row0 = comboBar.anchor[2]
    check("class resource defaults: right-aligned, radius 5", row0 and row0.anchor[1] == "TOPRIGHT"
        and LivingPortraitsDB.resourceRadius == 5)
    slash("resourcealign center") -- the checks below were written for these
    slash("resourcesize 6")
    local row = comboBar.anchor[2]
    check("pixel row sits under the mana bar's border", row and row.anchor and row.anchor[1] == "TOP"
        and row.anchor[2] == manaPos and row.anchor[3] == "BOTTOM" and row.anchor[5] == -(1 + 3))
    check("BBF's bar sits on our row, raised by its top padding", comboBar.anchor[3] == "TOP" and comboBar.anchor[5] == 10)
    check("BBF's bar is see-through", comboBar:GetAlpha() == 0)
    local dots = {}
    for _, f in ipairs(frames) do if f.parent == row then dots[#dots + 1] = f end end
    check("one circle per combo point", #dots == 5)
    local size = (6 + 1) * 2
    check("circles: radius 6 + 1px border, 3px apart", dots[2].w == size and dots[2].h == size and dots[2].anchor[4] == size + 3)
    local fill2, fill3 = dots[2].textures[2], dots[3].textures[2]
    check("combo points are circles", dots[1].masks[1].texture:find("TempPortraitAlphaMask$") ~= nil)
    check("filled point takes the combo color", fill2.color[1] > 0.8 and fill2.color[2] < 0.3)
    check("empty point is dark", fill3.color[1] < 0.1)
    check("ring takes the border color", dots[1].textures[1].color[1] == 0 and dots[1].textures[1].color[4] == 1)

    comboBar:SetPoint("TOP", PlayerFrame, "TOP", 2, 8) -- BBF re-anchors it
    check("BBF re-anchoring keeps it on our row", comboBar.anchor[2] == row)
    comboBar:SetAlpha(1) -- BBF resets its alpha
    check("BBF's bar stays see-through", comboBar:GetAlpha() == 0)
    combo = 3
    comboBar.classResourceButtonTable[5].alpha = 0 -- BBF's "only show filled" fades a point
    comboBar:UpdatePower()
    check("combo change fills the next circle", dots[3].textures[2].color[1] > 0.8)
    check("a point BBF faded hides its circle", not dots[5].shown and dots[4].shown)
    comboBar.classResourceButtonTable[5].alpha = nil

    slash("resourcealign left")
    check("/lp resourcealign left: row's left edge on the bar border's outer edge", row.anchor[1] == "TOPLEFT"
        and row.anchor[3] == "BOTTOMLEFT" and row.anchor[4] == -1 and comboBar.anchor[1] == "TOPLEFT")
    slash("resourcealign right")
    check("/lp resourcealign right", row.anchor[1] == "TOPRIGHT" and row.anchor[3] == "BOTTOMRIGHT" and row.anchor[4] == 1)
    slash("resourcealign middle")
    check("unknown alignment is ignored", LivingPortraitsDB.resourceAlign == "right")
    slash("resourcealign center")
    check("/lp resourcealign center", row.anchor[1] == "TOP" and row.anchor[4] == 0)
    slash("resourcesize 8")
    slash("resourcecolor 00ff00")
    check("/lp resourcesize resizes the circles", dots[1].w == (8 + 1) * 2)
    check("/lp resourcecolor (no resource: your class's) recolors filled points", dots[1].textures[2].color[2] == 1 and dots[1].textures[2].color[1] == 0)

    LivingPortraitsDB.resource = "moved" -- saved while testing an earlier build
    slash("refresh")
    check("a saved \"moved\" becomes the BBF option", LivingPortraitsDB.resource == "bbf")
    slash("resourcesize 6")
    slash("resource bbf")
    check("bbf: BBF's own art shows", comboBar:GetAlpha() == 1 and not row.shown)
    check("bbf: BBF's bar under the mana bar too", comboBar.anchor[2] == manaPos
        and math.abs(comboBar.anchor[5] - (-(1 + 3) / 0.7 + 10)) < 0.01)
    check("bbf: size setting scales BBF's points to a circle's width (14 / 20)", math.abs(comboBar.scale - 0.7) < 1e-9)
    comboBar:SetScale(0.9) -- BBF applies its Class Resource Scale, then re-anchors
    comboBar:SetPoint("TOP", PlayerFrame, "TOP", 2, 8)
    check("bbf: our scale wins over BBF's re-scale", math.abs(comboBar.scale - 0.7) < 1e-9)
    slash("resourcesize 9")
    check("bbf: /lp resourcesize rescales BBF's points", math.abs(comboBar.scale - 1) < 1e-9)
    slash("resourcesize 6")
    slash("resourcealign right")
    check("bbf: alignment applies to BBF's bar", comboBar.anchor[1] == "TOPRIGHT" and math.abs(comboBar.anchor[4] - 1 / 0.7) < 0.01)
    slash("resourcealign center")
    slash("resource none")
    check("none: nothing shows", comboBar:GetAlpha() == 0 and not row.shown)
    check("none: BBF's invisible bar can't pop its tooltip", comboBar.mouse == false)
    comboBar:SetAlpha(1) -- BBF resets its alpha
    check("none: stays hidden", comboBar:GetAlpha() == 0)
    slash("resource bbf")
    check("none -> bbf: BBF's art and tooltip back", comboBar:GetAlpha() == 1 and comboBar.mouse == true)
    slash("resource pixel")
    comboBar.bbfOnTarget = true -- BBF's "Move Resource to TargetFrame"
    comboBar:SetPoint("LEFT", TargetFrame, "RIGHT", -43, 1)
    check("on the target frame: left to BBF", comboBar.anchor[2] == TargetFrame and comboBar:GetAlpha() == 1 and not row.shown)
    comboBar.bbfOnTarget = nil
    comboBar:SetPoint("TOP", PlayerFrame, "TOP", 2, 8) -- BBF puts it back under the player frame
    check("back from the target frame: on our row again", comboBar.anchor[2] == row)
    slash("refresh")
    check("back from the target frame: see-through again", comboBar:GetAlpha() == 0 and row.shown)
    slash("style circle")
    check("circle style: handed back to BBF", comboBar:GetAlpha() == 1 and reanchored == 1)
    check("circle style: BBF's own scale back", math.abs(comboBar.scale - 0.9) < 1e-9)
    slash("style square")
    slash("resourcesize 6")
    slash("resourcecolor combo e62e2e")
    check("rogue's color is the combo color", LivingPortraitsDB.resourceColors.combo == "ffe62e2e")
    BBF.ComboPointBar = nil

    -- Warlock: no bar in Camelot, so the circles come straight from UnitPower
    world.class = "WARLOCK"
    Enum = { PowerType = { SoulShards = 7 } }
    local shards, maxShards = 2, 5
    function UnitPower(_, pt) return pt == 7 and shards or 0 end
    function UnitPowerMax(_, pt) return pt == 7 and maxShards or 0 end
    slash("refresh")
    check("warlock: shards under the mana bar", row.shown and row.anchor[2] == manaPos and row.anchor[5] == -(1 + 3))
    check("warlock: one gem per shard, taller than wide", dots[5].shown and dots[5].w == 14 and dots[5].h == 18)
    check("warlock: shards use the shard mask (ring and fill)", dots[1].masks[1].texture:find("media\\shard$")
        and dots[1].masks[2].texture == dots[1].masks[1].texture)
    check("warlock: filled shards take the shard color", dots[2].textures[2].color[1] > 0.6 and dots[2].textures[2].color[3] == 1)
    check("warlock: empty shards are dark", dots[3].textures[2].color[1] < 0.1)
    slash("resourcecolor shards 00ff00")
    check("/lp resourcecolor shards", LivingPortraitsDB.resourceColors.shards == "ff00ff00" and dots[1].textures[2].color[2] == 1)
    slash("resourcecolor 112233")
    check("/lp resourcecolor without a resource sets your own class's", LivingPortraitsDB.resourceColors.shards == "ff112233")
    slash("resourcecolor shards a15cff")
    BetterBlizzFramesDB = { comboVisibilityUnitFrames = true, onlyActiveComboPoints = true }
    ns.UpdateClassResource()
    check("warlock: BBF's \"only show filled\" applies", dots[2].shown and not dots[3].shown)
    BetterBlizzFramesDB.onlyActiveComboPoints, BetterBlizzFramesDB.hideEmptyComboPoints = nil, true
    shards = 0
    ns.UpdateClassResource()
    check("warlock: BBF's \"hide when empty\" applies", not dots[1].shown)
    BetterBlizzFramesDB = nil
    slash("resource bbf")
    check("warlock: the BBF option shows nothing (BBF has no shard bar here)", not row.shown)
    slash("resource pixel")
    slash("resource none")
    check("warlock: none hides the shards", not row.shown)
    slash("resource pixel")
    maxShards = 0
    slash("refresh")
    check("warlock with no shards in this game: nothing shows", not row.shown)
    world.class = "ROGUE"
    Enum, UnitPower, UnitPowerMax = nil, nil, nil
end
-- In combat the bars are left alone
inCombat = true
slash("extend 8 large")
check("bars not resized in combat", playerHp.h == 13)
inCombat = false

-- Talent build in the target's name row (square style)
do
    local function buildFS()
        for _, fs in ipairs(rawget(TargetFrame, "fontStrings") or {}) do return fs end
    end
    world.players.target = false
    fire("PLAYER_TARGET_CHANGED")
    check("no build text for an NPC target", not buildFS() or not buildFS().shown)
    world.players.target = true
    world.guid.target = "Player-1"
    inspects = {}
    fire("PLAYER_TARGET_CHANGED")
    check("another player's build is inspected", #inspects == 1 and inspects[1] == "target")
    check("nothing shown until the inspect answers", not buildFS() or not buildFS().shown)
    tick()
    check("no second inspect while waiting for the reply", #inspects == 1)
    fire("INSPECT_READY", "Player-1")
    local fs = buildFS()
    check("inspected build shows points per tree, empty trees as 0", fs and fs.shown and fs.text == "2/8/0")
    local hpPos = targetHp.BBFPositionFrame
    check("build gets its own line above the name", fs and fs.anchor[1] == "LEFT" and fs.anchor[2] == hpPos
        and fs.anchor[3] == "TOPLEFT" and fs.anchor[5] == 12 + 9 / 2)
    check("the box grows upward by the build line (taller than wide)", tBox.h == tBox.w + 9 and tBox.anchor[5] == 12 + 9)
    local hpH, hpY = targetHp.h, targetHp.anchor[5]
    slash("tall")
    check("tall off puts the build next to the level", fs.anchor[1] == "RIGHT" and fs.anchor[2] == targetLevel and fs.anchor[3] == "LEFT")
    check("tall off makes the box square again", tBox.h == tBox.w and tBox.anchor[5] == 12)
    check("the build line doesn't change the health bar", targetHp.h == hpH and targetHp.anchor[5] == hpY)
    slash("tall")
    local pfs
    for _, f in ipairs(rawget(PlayerFrame, "fontStrings") or {}) do pfs = f end
    check("player frame shows your own build above your name", pfs and pfs.shown and pfs.text == "5/0/0"
        and pfs.anchor[1] == "LEFT" and pfs.anchor[2] == playerHp.BBFPositionFrame and pfs.anchor[5] == 12 + 9 / 2)
    -- Mirror target text: name and build on the portrait side (right), level on the outer edge
    slash("mirror")
    check("mirrored target name sits on the portrait side", targetName.points[1][1] == "RIGHT"
        and targetName.points[1][3] == "TOPRIGHT" and targetName.justify == "RIGHT")
    check("mirrored target level goes to the outer edge", targetLevel.points[1][1] == "LEFT" and targetLevel.points[1][3] == "TOPLEFT")
    check("mirrored build sits above the name on the portrait side", fs.anchor[1] == "RIGHT" and fs.anchor[3] == "TOPRIGHT")
    check("the player frame isn't mirrored", PlayerName.points[1][1] == "LEFT" and pfs.anchor[1] == "LEFT")
    slash("tall")
    check("mirrored, not tall: build between level and name", fs.anchor[1] == "LEFT" and fs.anchor[2] == targetLevel and fs.anchor[3] == "RIGHT")
    slash("tall")
    slash("mirror")
    check("mirror off puts the target text back", targetName.points[1][1] == "LEFT" and targetLevel.points[1][1] == "RIGHT"
        and fs.anchor[1] == "LEFT" and fs.anchor[3] == "TOPLEFT")
    world.guid.target = "Player-2"
    now = now + 0.5
    fire("PLAYER_TARGET_CHANGED")
    check("inspects are spaced out", #inspects == 1)
    now = now + 2
    tick()
    check("the ticker retries once the gap has passed", #inspects == 2)
    fire("INSPECT_READY", "Someone-Else")
    check("someone else's inspect is ignored", not fs.shown)
    world.guid.target = "Player-1"
    fire("PLAYER_TARGET_CHANGED")
    check("a cached build shows without a new inspect", fs.shown and fs.text == "2/8/0" and #inspects == 2)
    -- Focus: also inspected, but only one inspect at a time (Player-2's is still pending)
    local oldHas = BBF.HasNoPortrait
    BBF.HasNoPortrait = function(u) return oldHas(u) or u == "focus" end
    world.players.focus, world.guid.focus = true, "Player-3"
    fire("PLAYER_FOCUS_CHANGED")
    check("focus waits while another inspect is pending", #inspects == 2)
    now = now + 5 -- Player-2 never answered
    tick()
    check("after the timeout the focus gets its inspect", #inspects == 3 and inspects[3] == "focus")
    fire("INSPECT_READY", "Player-3")
    world.guid.target = "Player-2"
    now = now + 2
    tick()
    check("a player who didn't answer isn't asked again right away", #inspects == 3)
    now = now + 31
    tick()
    check("...but is asked again later", #inspects == 4 and inspects[4] == "target")
    fire("INSPECT_READY", "Player-2")
    BBF.HasNoPortrait, world.players.focus, world.guid.focus = oldHas, nil, nil
    world.guid.target = "Player-1"
    fire("PLAYER_TARGET_CHANGED")
    world.targetIsMe = true
    fire("PLAYER_TARGET_CHANGED")
    check("your own build is read directly", fs.text == "5/0/0" and #inspects == 4)
    world.targetIsMe = nil
    slash("build")
    check("/lp build hides it", LivingPortraitsDB.showBuild == false and not fs.shown)
    check("tall portraits stay tall with the build hidden", tBox.h == tBox.w + 9)
    slash("build")
    world.players.target = nil
    world.guid.target = nil
end

-- Target-of-target clearance: nudge the ToT down when our stack runs into it
do
    local manaPf = targetMana.BBFPositionFrame
    local oldTop = totContainer.GetTop
    totContainer.anchor = { "TOPRIGHT", TargetFrame, "BOTTOMRIGHT", 12, 10 }
    local base = manaPf:GetBottom() + 5 -- overlapping the target's mana bar by 5
    function totContainer:GetTop() return base + (self.anchor[5] - 10) end
    fire("PLAYER_TARGET_CHANGED")
    check("ToT nudged down to clear the target's bars and bottom border (2 + 1px)",
        math.abs(totContainer:GetTop() - (manaPf:GetBottom() - 3)) < 0.001 and totContainer.anchor[5] == 10 - 8)
    base = manaPf:GetBottom() - 20 -- already clear
    fire("PLAYER_TARGET_CHANGED")
    check("no nudge when the ToT is already clear", totContainer.anchor[5] == 10)
    totContainer:SetPoint("TOPRIGHT", TargetFrame, "BOTTOMRIGHT", 12, 30) -- BBF/Blizzard re-anchor it
    -- (base unchanged: 20 higher puts its top exactly at our bottom, so it only needs the clearance)
    fire("PLAYER_TARGET_CHANGED")
    check("a new anchor from Blizzard/BBF becomes the base", totContainer.anchor[5] == 30 - 3)
    slash("style circle")
    check("handing back puts the ToT exactly where it was", totContainer.anchor[5] == 30)
    slash("style square")
    totContainer.GetTop, totContainer.anchor = oldTop, nil
end

-- Border color and opacity: our box border and BBF's bar borders together
do
    local function same(c, r, g, b, a) return c and c[1] == r and c[2] == g and c[3] == b and c[4] == a end
    local hpE, manaE = playerHp.BBFBlackBorder, playerMana.BBFBlackBorder
    local boxEdges = {}
    for i, t in ipairs(rawget(box, "textures") or {}) do if i >= 2 then boxEdges[#boxEdges + 1] = t end end
    check("box border is black by default", same(boxEdges[1].color, 0, 0, 0, 1))
    check("bar edge shared with the box is hidden (gap 1, player box on the left)", not hpE[4].shown and hpE[2].shown)
    check("mana top edge shared with health is hidden (spacing 0)", not manaE[1].shown and manaE[3].shown)
    slash("bordercolor ff0000")
    slash("borderalpha 0.5")
    check("/lp bordercolor + borderalpha color the box border", same(boxEdges[1].color, 1, 0, 0, 0.5))
    check("...and BBF's bar borders", same(hpE[1].color, 1, 0, 0, 0.5) and same(manaE[3].color, 1, 0, 0, 0.5))
    local hpPf, manaPf = playerHp.BBFPositionFrame, playerMana.BBFPositionFrame
    check("see-through border: mana starts right where health ends (no 1px slot)", manaPf:GetTop() == hpPf:GetBottom())
    check("see-through border: box sits flush against the bars", box.anchor[4] == 0)
    slash("borderalpha 1")
    check("opaque border: health and mana share one 1px line again", manaPf:GetTop() == hpPf:GetBottom() - 1)
    check("opaque border: box and bars share one line again", box.anchor[4] == -1)
    slash("bordersize 3")
    check("/lp bordersize thickens the box border", boxEdges[1].h == 3 and boxEdges[2].w == 3)
    check("...and BBF's bar borders", hpE[1].h == 3 and manaE[4].w == 3)
    check("corners grow with the thickness", hpE[1].anchor[4] == 3)
    check("health and mana still share one (3px) line", manaPf:GetTop() == hpPf:GetBottom() - 3)
    check("box and bars still share one (3px) line", box.anchor[4] == -3)
    slash("bordersize 9")
    check("thickness is capped at heavy (3)", LivingPortraitsDB.borderSize == 3)
    slash("bordersize medium")
    check("/lp bordersize takes thin, medium or heavy", LivingPortraitsDB.borderSize == 2 and boxEdges[1].h == 2)
    slash("bordersize 1")
    slash("borderalpha 0.5")
    slash("bordercolor zz")
    check("bad colors are ignored", LivingPortraitsDB.borderColor == "ffff0000")
    slash("gap 3")
    check("with a gap, every bar edge shows again", hpE[4].shown)
    slash("gap 1")
end

slash("style circle")
check("style circle hands BBF its black 1px borders back", playerHp.BBFBlackBorder[1].h == 1 and playerHp.BBFBlackBorder[1].color[1] == 0
    and playerHp.BBFBlackBorder[1].color[4] == 1 and playerHp.BBFBlackBorder[4].shown and playerMana.BBFBlackBorder[1].shown)
check("style circle hides the box", not box.shown)
check("style circle restores BBF's bar heights", playerHp.h == 19 and playerMana.h == 8 and playerMana.BBFPositionFrame.h == 8)
check("style circle restores bar positions", playerMana.anchor[5] == 0 and targetMana.anchor[4] == -8)
check("style circle restores text positions", playerHpHolder.LeftText.anchor[5] == 0)
check("style circle restores name and level", PlayerName.points[1][1] == "TOPLEFT" and PlayerLevelText.points[1][4] == 88)
check("style circle restores BBF's name", PlayerFrame.bbfName.points[1][1] == "TOPLEFT" and PlayerFrame.bbfName.justify == "CENTER")
check("circle stays off while BBF hides the portrait", not shownFor("player"))
slash("reset")
check("reset defaults to square style", LivingPortraitsDB.style == "square")
BBF = nil
playerContainer.shown = true

-- BBF re-layout hooks: a BBF font change triggers our re-layout
-- Calling BBF's (hooked) font function queues our refresh
local refreshed = 0
for _, m in ipairs(models) do
    local orig = m.SetUnit
    m.SetUnit = function(self, u) refreshed = refreshed + 1; orig(self, u) end
end
bbfHooked()
check("BBF font change triggers our re-layout", refreshed > 0)
local okDebug, debugErr = pcall(SlashCmdList.LIVINGPORTRAITS, "debug player"); if not okDebug then realPrint(debugErr) end
check("/lp debug runs without errors", okDebug)
check("/lp, /livingportraits and the old /bap all work",
    SLASH_LIVINGPORTRAITS1 == "/lp" and SLASH_LIVINGPORTRAITS2 == "/livingportraits" and SLASH_LIVINGPORTRAITS3 == "/bap")

-- Frame scale change (Edit Mode 125% -> 150%) re-frames the camera
local setUnitCalls = 0
for _, m in ipairs(models) do
    local orig = m.SetUnit
    m.SetUnit = function(self, u) if u == "player" then setUnitCalls = setUnitCalls + 1 end; orig(self, u) end
end
tick()
check("no refresh while the scale is unchanged", setUnitCalls == 0)
function PlayerFrame:GetEffectiveScale() return 1.5 end
tick()
check("scale change refreshes the player portrait", setUnitCalls == 1)
tick()
check("refreshes only once per scale change", setUnitCalls == 1)
PlayerFrame.GetEffectiveScale = nil

-- Settings panel: proxy settings read and write the saved settings
do
    local n = 0
    for _ in pairs(proxies) do n = n + 1 end
    check("settings panel registers its options", n >= 25)
    local zoom = proxies.LivingPortraits_zoom
    zoom.set(0.5)
    check("panel slider writes the setting", LivingPortraitsDB.zoom == 0.5 and zoom.get() == 0.5)
    proxies.LivingPortraits_stackExtra_large.set(7.6)
    check("whole-number sliders round", LivingPortraitsDB.stackExtra.large == 8)
    proxies.LivingPortraits_unit_party.set(false)
    check("group checkbox toggles every unit in the group",
        not LivingPortraitsDB.units.party1 and not LivingPortraitsDB.units.party4)
    check("group checkbox reads the group", proxies.LivingPortraits_unit_party.get() == false)
    proxies.LivingPortraits_unit_party.set(true)
    check("defaults come from the addon's defaults", proxies.LivingPortraits_sizes_large_cam.default == 0.85 and proxies.LivingPortraits_style.default == "square")
    notified.LivingPortraits_zoom = 0
    slash("zoom 0.7")
    check("/lp changes show in the panel", notified.LivingPortraits_zoom > 0 and zoom.get() == 0.7)
    slash("options")
    check("/lp options opens the panel", openedCategory == 42)
    slash("reset")
end

-- Turning on BBF's Pixel Border mode from our panel: just the mode switches, the rest of BBF
-- stays; a full backup for Undo
do
    BBF = { ProfileData = {}, OldImportProfile = function() error("no profile should be loaded") end }
    BetterBlizzFramesDB = { noPortraitModes = false, noPortraitSkipTarget = true, classicFrames = true,
        myOwnSetting = "keep me", unitFrameFont = "Morpheus", auraBlacklist = { [1] = { id = 1 } } }
    local bdb = BetterBlizzFramesDB
    buttons["Pixel Border mode"]()
    check("Pixel Border mode: No Portrait + Pixel Border on every frame", bdb.noPortraitModes == true
        and bdb.noPortraitPixelBorder == true and bdb.noPortraitSkipTarget == false and bdb.noPortraitPartyOnly == false)
    check("Pixel Border mode: Classic Frames off (it wins over No Portrait)", bdb.classicFrames == false)
    check("Pixel Border mode: the rest of BBF stays", bdb.myOwnSetting == "keep me" and bdb.unitFrameFont == "Morpheus"
        and bdb.auraBlacklist[1].id == 1 and bdb.foreverComboPoints == nil)
    check("Pixel Border mode: offers a reload", popupShown == "LIVING_PORTRAITS_RELOAD")
    local full = LivingPortraitsDB.bbfBackupFull
    check("Pixel Border mode: backs up all of BBF's settings", full and full.noPortraitModes == false
        and full.classicFrames == true and full.auraBlacklist ~= bdb.auraBlacklist)
    buttons["Pixel Border mode"]()
    check("applying again keeps the original backup", LivingPortraitsDB.bbfBackupFull.noPortraitModes == false)
    slash("reset")
    check("/lp reset keeps BBF's Undo", LivingPortraitsDB.bbfBackupFull ~= nil)
    buttons["Undo setup / profile"]()
    check("Undo puts BBF's settings back", bdb.noPortraitModes == false and bdb.classicFrames == true
        and bdb.noPortraitPixelBorder == nil and bdb.myOwnSetting == "keep me")
    check("Undo clears the backup", LivingPortraitsDB.bbfBackupFull == nil)

    -- A v0.8.0/0.8.1 backup (only the keys that setup changed) is honored by Undo
    LivingPortraitsDB.bbfBackup = { noPortraitModes = "<nil>", unitFrameFont = "Friz Quadrata TT" }
    bdb.noPortraitModes, bdb.unitFrameFont = true, "2002"
    buttons["Undo setup / profile"]()
    check("Undo with an older backup restores those keys", bdb.noPortraitModes == nil and bdb.unitFrameFont == "Friz Quadrata TT"
        and LivingPortraitsDB.bbfBackup == nil)
    BBF, BetterBlizzFramesDB = nil, nil
end

RAID_CLASS_COLORS = { PALADIN = { r = 0.957, g = 0.549, b = 0.729, colorStr = "fff48cba" } }
-- Profiles: Living Portraits + BBF settings together. Built-in "Naut", export/import strings.
do
    -- Stand-ins for BBF's LibSerialize/LibDeflate (registry-backed, reversible)
    local stash = {}
    local libs = {
        LibDeflate = {
            CompressDeflate = function(_, str) return "Z" .. str end,
            DecompressDeflate = function(_, str) return str:sub(1, 1) == "Z" and str:sub(2) or nil end,
            EncodeForPrint = function(_, str) return str end,
            DecodeForPrint = function(_, str) return str end,
        },
        ["LibSerialize-BB"] = {
            Serialize = function(_, t) stash[#stash + 1] = ns.DeepCopy(t); return "S" .. #stash end,
            Deserialize = function(_, str)
                local t = stash[tonumber(str:match("^S(%d+)$") or "")]
                return t ~= nil, t and ns.DeepCopy(t)
            end,
        },
    }
    LibStub = { GetLibrary = function(_, name) return libs[name] end }
    BBF = {
        ProfileData = { { name = "Starter", importString = "!BBFs!BBF" }, { name = "Bodify", importString = "!BBFb!BBF" } },
        OldImportProfile = function(str)
            if str == "!BBFs!BBF" then return { starterKey = true, classicFrames = true } end
            return { darkModeUi = true, classicFrames = true, unitFrameFont = "Friz Quadrata TT" }
        end,
    }
    BetterBlizzFramesDB = { myOwnSetting = "keep me", unitFrameFont = "Morpheus" }
    local bdb = BetterBlizzFramesDB
    LivingPortraitsDB.zoom = 0.5
    LivingPortraitsDB.barText = "percent"
    check("built-in profiles: Starter, Naut, BlizzFrames", ns.PROFILES[1].name == "Starter" and ns.PROFILES[2].name == "Naut"
        and ns.PROFILES[3].name == "BlizzFrames")
    -- The profile row: Blizzard's button row with no name (its button sits where labels start),
    -- our own buttons to its right for further profiles
    table.insert(ns.PROFILES, { name = "Pal", desc = "Test." })
    local rowInit = buttonInits[""]
    check("profile row: Blizzard's button row with no name, the first profile on its button", rowInit
        and rowInit.text == "Starter")
    local row = newFrame("Frame", nil, 3)
    row.Button = newFrame("Button", row, 4)
    row.Button.h = 26
    rowInit:InitFrame(row)
    local pal = row.lpProfileButtons and row.lpProfileButtons[2]
    local nautBtn = row.lpProfileButtons and row.lpProfileButtons[2]
    pal = row.lpProfileButtons and row.lpProfileButtons[4]
    check("profile row: Naut's button next to Starter's, its name in paladin pink", nautBtn
        and nautBtn.text == "|cfff48cbaNaut|r" and nautBtn.anchor[2] == row.Button)
    check("profile row: more profiles get buttons to its right", pal and pal.text == "Pal" and pal.anchor[2] == row.lpProfileButtons[3]
        and pal.anchor[1] == "LEFT" and pal.anchor[3] == "RIGHT" and pal.shown and row.Button.w == 120)
    rowInit:Resetter(row)
    check("profile row: recycled row gets the stock button back", not pal.shown and row.Button.w == 200)
    table.remove(ns.PROFILES)

    -- Load: asks first, then replaces both addons' settings
    popupShown = nil
    row.lpProfileButtons[2].OnClick(row.lpProfileButtons[2])
    check("loading a profile asks first", popupShown == "LIVING_PORTRAITS_LOAD_PROFILE" and popupData == "Naut"
        and LivingPortraitsDB.zoom == 0.5)
    StaticPopupDialogs.LIVING_PORTRAITS_LOAD_PROFILE.OnAccept(nil, popupData)
    check("Naut: Living Portraits settings are Jason's (the rest defaults)", LivingPortraitsDB.barText == "max"
        and LivingPortraitsDB.zoom == 1 and LivingPortraitsDB.resourceRadius == 5 and LivingPortraitsDB.version == ns.SETTINGS_VERSION)
    check("Naut: BBF gets Bodify, then the setup on top", bdb.darkModeUi == true and bdb.classicFrames == false
        and bdb.noPortraitPixelBorder == true and bdb.unitFrameFont == "2002" and bdb.myOwnSetting == nil)
    check("Naut: offers a reload", popupShown == "LIVING_PORTRAITS_RELOAD")
    check("Naut: both addons backed up", LivingPortraitsDB.lpBackup and LivingPortraitsDB.lpBackup.zoom == 0.5
        and LivingPortraitsDB.lpBackup.barText == "percent" and LivingPortraitsDB.bbfBackupFull.myOwnSetting == "keep me")
    check("Naut: the backups aren't inside the backup", LivingPortraitsDB.lpBackup.lpBackup == nil)
    check("/lp profile lists and loads by name (asks first)", (function()
        popupShown = nil; slash("profile naut"); return popupShown == "LIVING_PORTRAITS_LOAD_PROFILE" and popupData == "Naut"
    end)())

    -- Undo: both addons back
    buttons["Undo setup / profile"]()
    check("Undo after Naut: BBF back", bdb.myOwnSetting == "keep me" and bdb.darkModeUi == nil)

    -- Starter: BBF's own Starter profile with Pixel Border mode, our defaults
    LivingPortraitsDB.zoom = 0.5
    ns.LoadProfile("Starter")
    check("Starter: BBF's Starter profile with Pixel Border mode on top", bdb.starterKey == true and bdb.classicFrames == false
        and bdb.noPortraitPixelBorder == true and bdb.unitFrameFont == nil and bdb.myOwnSetting == nil)
    check("Starter: bar texture switches on, realm names kept", bdb.changeUnitFrameHealthbarTexture == true
        and bdb.changeUnitFrameManabarTexture == true and bdb.removeRealmNames == false and bdb.unitFrameHealthbarTexture == nil)
    check("Starter: Jason's starter choices", LivingPortraitsDB.eliteBorder == true and LivingPortraitsDB.tallPortraits.player == false
        and LivingPortraitsDB.tallPortraits.target == false and LivingPortraitsDB.tallPortraits.party == false
        and LivingPortraitsDB.hideSurname == false and LivingPortraitsDB.showBuild == false
        and LivingPortraitsDB.barText == "default")
    check("Starter: everything else at the defaults", LivingPortraitsDB.zoom == 1 and LivingPortraitsDB.barTextStyle == "shadow")
    buttons["Undo setup / profile"]()

    -- BlizzFrames: BBF's Forever profile as it is, circle style with bigger large models
    BBF.ProfileData[#BBF.ProfileData + 1] = { name = "Forever", importString = "!BBFf!BBF" }
    local oldImport = BBF.OldImportProfile
    BBF.OldImportProfile = function(str) if str == "!BBFf!BBF" then return { foreverKey = true, classicFrames = true } end return oldImport(str) end
    ns.LoadProfile("blizzframes")
    check("BlizzFrames: BBF's Forever profile, nothing on top", bdb.foreverKey == true and bdb.classicFrames == true
        and bdb.noPortraitModes == nil and bdb.myOwnSetting == nil)
    check("BlizzFrames: circle style, large models 0.9, the rest of sizes default", LivingPortraitsDB.style == "circle"
        and LivingPortraitsDB.sizes.large.inset == 0.9 and LivingPortraitsDB.sizes.large.cam == 0.85
        and LivingPortraitsDB.sizes.small.inset == 0.80 and LivingPortraitsDB.barText == "default")
    buttons["Undo setup / profile"]()
    BBF.OldImportProfile = oldImport
    table.remove(BBF.ProfileData)
    check("Undo after a profile: Living Portraits settings back", LivingPortraitsDB.zoom == 0.5
        and LivingPortraitsDB.barText == "percent" and LivingPortraitsDB.lpBackup == nil)
    check("Undo after a profile: BBF settings back", bdb.myOwnSetting == "keep me" and bdb.unitFrameFont == "Morpheus"
        and bdb.darkModeUi == nil)

    -- Export, then import on "another PC"
    LivingPortraitsDB.resourceAlign = "left"
    bdb.auraWhitelist = { [10060] = { id = 10060 } }
    buttons["Export profile"]()
    local str = popupData
    check("export shows a profile string", popupShown == "LIVING_PORTRAITS_EXPORT" and type(str) == "string"
        and str:sub(1, 5) == "!LP1!")
    LivingPortraitsDB.resourceAlign, LivingPortraitsDB.zoom = "center", 1
    BetterBlizzFramesDB = { other = true }
    bdb = BetterBlizzFramesDB
    check("import: a bad string is refused, nothing changes", ns.ImportProfile("hello"):find("isn't") ~= nil
        and LivingPortraitsDB.resourceAlign == "center" and LivingPortraitsDB.lpBackup == nil)
    check("import: a damaged string is refused", ns.ImportProfile("!LP1!S99") ~= nil and LivingPortraitsDB.lpBackup == nil)
    buttons["Import profile"]()
    check("import asks for the string", popupShown == "LIVING_PORTRAITS_IMPORT")
    local fakeDialog = { GetEditBox = function() return { GetText = function() return "  " .. str .. "\n" end } end }
    StaticPopupDialogs.LIVING_PORTRAITS_IMPORT.OnAccept(fakeDialog)
    check("import: Living Portraits settings from the string", LivingPortraitsDB.resourceAlign == "left"
        and LivingPortraitsDB.zoom == 0.5)
    check("import: BBF settings from the string", bdb.myOwnSetting == "keep me" and bdb.auraWhitelist[10060].id == 10060
        and bdb.other == nil)
    check("import: backups kept for Undo, never imported", LivingPortraitsDB.lpBackup.resourceAlign == "center"
        and BetterBlizzFramesDB ~= nil and LivingPortraitsDB.bbfBackupFull.other == true)

    -- Imported settings are checked against the defaults' shape
    stash[#stash + 1] = { format = 1, lp = { zoom = "big", barText = "max", units = { player = false, bogus = true },
        notASetting = 1, sizes = 5, lpBackup = { zoom = 0 } } }
    ns.ImportProfile("!LP1!ZS" .. #stash)
    check("import: wrong types and unknown keys dropped", LivingPortraitsDB.zoom == 1 and LivingPortraitsDB.barText == "max"
        and LivingPortraitsDB.units.player == false and LivingPortraitsDB.units.bogus == nil
        and LivingPortraitsDB.notASetting == nil and type(LivingPortraitsDB.sizes) == "table"
        and LivingPortraitsDB.lpBackup.zoom ~= 0)

    buttons["Undo setup / profile"]()

    -- A built-in profile can be a friend's export string
    LivingPortraitsDB.resourceAlign = "left"
    local friendString = ns.ExportString()
    LivingPortraitsDB.resourceAlign = "center"
    table.insert(ns.PROFILES, { name = "Friend", desc = "Test.", string = friendString })
    local msg = ns.LoadProfile("friend")
    check("a profile stored as an export string loads like an import", LivingPortraitsDB.resourceAlign == "left"
        and msg:find("Loaded the Friend profile", 1, true) ~= nil)
    table.remove(ns.PROFILES)
    buttons["Undo setup / profile"]()
    LibStub, BBF, BetterBlizzFramesDB = nil, nil, nil
    check("export without BBF's libraries says so", ns.ShowExport():find("BetterBlizzFrames") ~= nil)
    LivingPortraitsDB.units.player = true
end

-- First run: a fresh install offers the BBF setup once (or recommends BBF without it)
do
    local printed = {}
    local oldPrint = print
    print = function(msg) printed[#printed + 1] = tostring(msg) end
    BBF = { HasNoPortrait = function() return false end }
    BetterBlizzFramesDB = {}
    LivingPortraitsDB.welcomed = nil
    popupShown = nil
    ns.CheckFirstRun()
    local welcome = StaticPopupDialogs.LIVING_PORTRAITS_WELCOME
    check("first run: BBF not set up, Starter and Naut are offered", popupShown == "LIVING_PORTRAITS_WELCOME"
        and welcome.button1 == "Starter" and welcome.button3 == "Naut" and welcome.OnAccept and welcome.OnAlt)
    popupShown = nil
    ns.CheckFirstRun()
    check("first run: only once", popupShown == nil and LivingPortraitsDB.welcomed == true)
    slash("reset")
    check("first run: /lp reset doesn't bring the welcome back", LivingPortraitsDB.welcomed == true)
    LivingPortraitsDB.welcomed = nil
    BBF.HasNoPortrait = function() return true end
    ns.CheckFirstRun()
    check("first run: already set up, nothing shown", popupShown == nil and LivingPortraitsDB.welcomed == true)
    LivingPortraitsDB.welcomed = nil
    BBF, BetterBlizzFramesDB = nil, nil
    ns.CheckFirstRun()
    check("first run: no BBF, a chat note recommends it", popupShown == nil and printed[#printed]
        and printed[#printed]:find("BetterBlizzFrames") ~= nil)
    print = oldPrint
end

-- BBF's Classic Frames draws its round portrait even with No Portrait on: no box style then
do
    BBF = { HasNoPortrait = function() return true end }
    BetterBlizzFramesDB = { classicFrames = true }
    check("Classic Frames on: BBF shows portraits", not ns.BBFHidesPortrait("player"))
    BetterBlizzFramesDB.classicFrames = false
    check("Classic Frames off: No Portrait decides", ns.BBFHidesPortrait("player") == true)
    BBF, BetterBlizzFramesDB = nil, nil
end

-- Hide surnames on our frames (on by default)
do
    PlayerName:SetText("Naut Sfw")
    PlayerFrame.bbfName:SetText("|cffffffffNaut Sfw|r")
    tick() -- hooks the name texts
    check("surnames hidden by default", LivingPortraitsDB.hideSurname == true and PlayerName.text == "Naut")
    check("only the surname goes; BBF's color codes stay", PlayerFrame.bbfName.text == "|cffffffffNaut|r")
    PlayerName:SetText("Naut Sfw") -- Blizzard updates the name
    check("later name updates are stripped too", PlayerName.text == "Naut")
    targetName:SetText("Wolf")
    check("names without a surname are left alone", targetName.text == "Wolf")
    slash("surname")
    check("turning it off puts the full name back", PlayerName.text == "Naut Sfw"
        and PlayerFrame.bbfName.text == "|cffffffffNaut Sfw|r")
    slash("surname")
    check("/lp surname strips the surname", PlayerName.text == "Naut")
    proxies.LivingPortraits_hideSurname.set(false)
    proxies.LivingPortraits_hideSurname.set(true)
    check("the panel checkbox applies right away, not on the next tick", PlayerName.text == "Naut")
    world.names.target = { "Creeg", "Head" }
    TargetFrame.bbfName = rowText() -- BBF creates its own name text after us
    TargetFrame.bbfName:SetText("Creeg Head")
    tick()
    check("name texts created later are picked up by the ticker", TargetFrame.bbfName.text == "Creeg")
    TargetFrame.bbfName:SetText("Creeg Head") -- target changed: BBF sets the name again
    check("...and stay stripped through the hook", TargetFrame.bbfName.text == "Creeg")
    proxies.LivingPortraits_hideSurname.set(false)
    TargetFrame.bbfName, world.names.target = nil, nil
end

-- The pre-rename addon (BBF_AnimatedPortraits) still enabled: offer to disable it
do
    popupShown = nil
    fire("PLAYER_ENTERING_WORLD")
    check("no old-addon warning when it isn't installed", popupShown == nil)
    oldAddon.loaded = true
    fire("PLAYER_ENTERING_WORLD")
    check("old addon still enabled -> offer to disable it", popupShown == "LIVING_PORTRAITS_OLD_ADDON")
    StaticPopupDialogs.LIVING_PORTRAITS_OLD_ADDON.OnAccept()
    check("accepting disables the old addon and reloads", oldAddon.disabled and reloaded)
    popupShown = nil
    fire("PLAYER_ENTERING_WORLD")
    check("the warning shows once per session", popupShown == nil)
    oldAddon.loaded = false
end

-- Target bar grow in PvP: the fill's alpha can read back as a secret value. The grow must
-- still end and give Blizzard's fill its alpha back (it errored every frame and left the
-- target's health bar invisible in battlegrounds).
do
    local hpFill = newTexture(true)
    function targetHp:GetStatusBarTexture() return hpFill end
    TargetFrame:Update() -- Blizzard's target update starts the grow
    check("grow hides Blizzard's fill while the overlay grows", hpFill.alpha == 0)
    local SECRET = {}
    function hpFill:GetAlpha() return world.secret and SECRET or (rawget(self, "alpha") or 1) end
    world.secret = true
    local driver
    for _, fr in ipairs(frames) do if rawget(fr, "OnUpdate") then driver = fr end end
    driver.OnUpdate(driver, 1) -- past growTime
    world.secret = false
    check("grow restores the fill when its alpha is secret", rawget(hpFill, "alpha") == 1)
    check("grow stops running after it ends", rawget(driver, "OnUpdate") == nil)
end

-- The focus frame's update grows the focus's bars (traced with /lp grow debug)
do
    local traced = {}
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        traced[#traced + 1] = table.concat(parts, " ")
    end
    slash("grow debug")
    local hadFocus = world.exists.focus
    world.exists.focus = false
    FocusFrame:Update()
    world.exists.focus = hadFocus
    slash("grow debug")
    print = function() end
    local hit = false
    for _, line in ipairs(traced) do if line:find("skip: grow", 1, true) and line:find("focus", 1, true) then hit = true end end
    check("a new focus runs the bar grow for the focus frame", hit)
end

-- Secret values must not error
world.secret = true
local ok = pcall(tick)
check("secret values don't error", ok)
world.secret = false

realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
