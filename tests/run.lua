-- Offline test harness for BBF Animated Portraits.
-- Stubs just enough of the WoW API to load Core.lua and exercise its logic.
-- Run from the repo root:  lua5.1 tests/run.lua
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
    "HealthBar", "ManaBar", "BBFPositionFrame" }

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
    function f:CreateTexture()
        local t = newTexture()
        local list = rawget(self, "textures") or {}
        self.textures = list
        list[#list + 1] = t
        return t
    end
    function f:CreateMaskTexture() return stubIndex({}) end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameStrata() return "MEDIUM" end
    function f:GetEffectiveScale() return 1 end
    function f:GetTop() return rawget(self, "top") end
    function f:GetBottom() return rawget(self, "bottom") end
    function f:GetLeft() return rawget(self, "left") end
    function f:GetRight() return rawget(self, "right") end
    function f:GetPoint() local a = rawget(self, "anchor"); if a then return unpack(a) end end
    function f:SetPoint(point, rel, relPoint, x, y) self.anchor = { point, rel, relPoint, x, y } end
    function f:IsVisible()
        local up = rawget(self, "parent")
        return self.shown and (not up or up:IsVisible())
    end
    return f
end

function CreateFrame(kind, _, parent)
    local f = newFrame(kind, parent, parent and parent.level + 1)
    if kind == "PlayerModel" then models[#models + 1] = f end
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
function issecretvalue() return world.secret end
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

-- BBF present at load (OptionalDeps), with a function the addon should hook
BBF = { SetCustomFonts = function() end }

-- Load the addon --------------------------------------------------------------
local chunk = assert(loadfile("Core.lua"))
chunk("BBF_AnimatedPortraits", {})

local function fire(event, arg) eventFrame.OnEvent(eventFrame, event, arg) end
local function slash(msg) SlashCmdList.BBFANIMPORTRAITS(msg) end
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
BBFAnimatedPortraitsDB = { enabled = true, sizes = { large = { inset = 0.82, cam = 0.85 }, small = { inset = 0.82, cam = 0.85 } } }
fire("ADDON_LOADED", "BBF_AnimatedPortraits")
local bbfHooked = BBF.SetCustomFonts
BBF = nil
check("old saved inset migrated to new default", BBFAnimatedPortraitsDB.sizes.small.inset == 0.80)
check("settings version recorded", BBFAnimatedPortraitsDB.version == 10)
check("defaults applied", BBFAnimatedPortraitsDB.enabled == true and BBFAnimatedPortraitsDB.sizes.large.inset == 0.80)

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
check("/bap circlebg 0 hides the circle background", BBFAnimatedPortraitsDB.circleBg == 0)
local corners = rawget(playerContainer, "textures")[2]
check("dark corners hidden with a clear background", corners and not corners.shown)
check("soft edge hidden too with a clear background (no dark ring)", not vig.shown)
slash("circlebg 1")

-- Centering offset and calibration
check("measured default offsets applied", BBFAnimatedPortraitsDB.offsets.tot[1] == -1.3 and BBFAnimatedPortraitsDB.offsets.tot[2] == 2.2)
local defA = modelFor("player").anchor
check("player portrait uses its measured offset", defA and defA[4] == -0.5 and defA[5] == 0.6)
slash("offset player 2 -1")
check("/bap offset stores the nudge", BBFAnimatedPortraitsDB.offsets.player[1] == 2 and BBFAnimatedPortraitsDB.offsets.player[2] == -1)
local pmA = modelFor("player").anchor
check("offset moves the model off the portrait center", pmA and pmA[4] == 2 and pmA[5] == -1)
check("offset moves the circle edge with it", vig.anchor and vig.anchor[4] == 2 and vig.anchor[5] == -1)
slash("offset player 0 0")
slash("calibrate")
check("/bap calibrate turns calibration on", BBFAnimatedPortraitsDB.calibrate == true)
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
check("/bap unit party hides party", not shownFor("party1") and not shownFor("party2"))
slash("unit party")
check("/bap unit party restores party", shownFor("party1"))
slash("unit tot")
check("/bap unit tot hides tot", not shownFor("targettarget"))
slash("unit tot")

-- Global toggle restores the 2D portrait
slash("toggle")
check("/bap toggle hides everything", not shownFor("player") and not shownFor("target"))
check("/bap toggle restores 2D portrait", playerContainer.PlayerPortrait.shown)
slash("toggle")
check("/bap toggle restores", shownFor("player"))

-- Sized settings
slash("inset 0.9 small")
check("inset small only", BBFAnimatedPortraitsDB.sizes.small.inset == 0.9 and BBFAnimatedPortraitsDB.sizes.large.inset == 0.80)
slash("inset 0.5 large")
check("circle edge follows a smaller inset", math.abs(vig.w - 30) < 0.01)
slash("inset 0.9 large")
check("circle edge follows a larger inset", math.abs(vig.w - 54) < 0.01)
slash("inset 0.80 large")
slash("cam 0.7")
check("cam without size sets both", BBFAnimatedPortraitsDB.sizes.small.cam == 0.7 and BBFAnimatedPortraitsDB.sizes.large.cam == 0.7)
slash("cam 9 large"); check("cam clamped to 2", BBFAnimatedPortraitsDB.sizes.large.cam == 2)
slash("zoom 5");      check("zoom clamped to 1", BBFAnimatedPortraitsDB.zoom == 1)
slash("vignette");    check("vignette toggles off", BBFAnimatedPortraitsDB.vignette == false)
slash("reset")
check("reset restores defaults", BBFAnimatedPortraitsDB.sizes.large.cam == 0.85 and BBFAnimatedPortraitsDB.vignette == true)

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
    local pf = newFrame("Frame", bar, 8)
    pf.left, pf.right, pf.h = pos.left, pos.right, pos.h
    function pf:GetTop() return bar.baseTop + (bar.anchor[5] - bar.origY) end
    function pf:GetBottom() return self:GetTop() - self.h end
    function pf:GetCenter() return 0, self:GetTop() - self.h / 2 end
    bar.BBFPositionFrame = pf
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
PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = {
    HealthBarsContainer = playerHpHolder,
    ManaBarArea = { ManaBar = playerMana },
} }
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
check("box spans name row to mana bottom (38)", box and box.w == 38 and box.h == 38)
check("box top at the top of the name row", box and box.anchor[5] == 12)
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
check("long name stops short of the level", bn.w == math.ceil(123 - 2 - (12 + 4)) + 1)
check("player box sits left of the health bar", box and box.anchor[1] == "TOPRIGHT" and box.anchor[3] == "TOPLEFT")

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
check("/bap namerow 0 tot gives ToT its full bars back", totHp.h == 15 and BBFAnimatedPortraitsDB.nameRow.large == 12)
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
check("/bap bg shows the background", sqBg and sqBg.shown and BBFAnimatedPortraitsDB.squareBg == 0.5)
slash("bg 0")
check("/bap bg 0 hides it again", sqBg and not sqBg.shown)

slash("extend 4 large")
-- Stack 19 + 8 + 4 = 31, bars 19: health 13, mana 6, box 33
check("/bap extend large resizes the stack", playerHp.h == 13 and playerMana.h == 6)
check("/bap extend keeps box aligned with bars (32)", box.w == 32)
check("/bap extend large leaves small alone", BBFAnimatedPortraitsDB.stackExtra.small == 6)
slash("split 0.5")
check("/bap split changes the health share", playerHp.h == 10 and playerMana.h == 9)
slash("split 0.66")

-- Turning alignment off restores the original offset
slash("alignmana")
check("/bap alignmana turns alignment off", BBFAnimatedPortraitsDB.alignMana == false)
check("mana bar back at its original x offset", targetMana.anchor[4] == -8)
slash("alignmana")
check("re-aligning is stable", targetMana.anchor[4] == 0)
-- In combat the bars are left alone
inCombat = true
slash("extend 8 large")
check("bars not resized in combat", playerHp.h == 13)
inCombat = false

slash("style circle")
check("style circle hides the box", not box.shown)
check("style circle restores BBF's bar heights", playerHp.h == 19 and playerMana.h == 8 and playerMana.BBFPositionFrame.h == 8)
check("style circle restores bar positions", playerMana.anchor[5] == 0 and targetMana.anchor[4] == -8)
check("style circle restores text positions", playerHpHolder.LeftText.anchor[5] == 0)
check("style circle restores name and level", PlayerName.points[1][1] == "TOPLEFT" and PlayerLevelText.points[1][4] == 88)
check("style circle restores BBF's name", PlayerFrame.bbfName.points[1][1] == "TOPLEFT" and PlayerFrame.bbfName.justify == "CENTER")
check("circle stays off while BBF hides the portrait", not shownFor("player"))
slash("reset")
check("reset defaults to square style", BBFAnimatedPortraitsDB.style == "square")
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
local okDebug, debugErr = pcall(SlashCmdList.BBFANIMPORTRAITS, "debug player"); if not okDebug then realPrint(debugErr) end
check("/bap debug runs without errors", okDebug)

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

-- Secret values must not error
world.secret = true
local ok = pcall(tick)
check("secret values don't error", ok)
world.secret = false

realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
