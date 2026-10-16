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
    return setmetatable(t, { __index = function() return function() end end })
end

local function region(t)
    t = stubIndex(t or {})
    t.shown = t.shown or false
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:SetShown(v) self.shown = not not v end
    function t:IsShown() return self.shown end
    function t:SetAlpha(a) self.alpha = a end
    function t:GetAlpha() return rawget(self, "alpha") or 1 end
    function t:SetSize(w, h) self.w, self.h = w, h end
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
    function f:CreateTexture() return newTexture() end
    function f:CreateMaskTexture() return stubIndex({}) end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameStrata() return "MEDIUM" end
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

local tick
C_Timer = {
    After = function(_, fn) fn() end,
    NewTicker = function(_, fn) tick = fn; return {} end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print() end -- silence addon chat output
SlashCmdList = {}

-- Load the addon --------------------------------------------------------------
local chunk = assert(loadfile("Core.lua"))
chunk("BBF_AnimatedPortraits", {})

local function fire(event, arg) eventFrame.OnEvent(eventFrame, event, arg) end
local function slash(msg) SlashCmdList.BBFANIMPORTRAITS(msg) end
local function modelFor(unit)
    for _, m in ipairs(models) do if m.unit == unit then return m end end
end
local function shownFor(unit)
    local m = modelFor(unit)
    return m ~= nil and m.shown
end

-- Tests -----------------------------------------------------------------------
world.exists = { player = true, target = true, targettarget = true, party1 = true, party2 = true }
world.visible.party2 = false

fire("ADDON_LOADED", "BBF_AnimatedPortraits")
check("defaults applied", BBFAnimatedPortraitsDB.enabled == true and BBFAnimatedPortraitsDB.sizes.large.inset == 1.0)

fire("PLAYER_ENTERING_WORLD")
check("one model per supported unit (9)", #models == 9)
check("player model shown", shownFor("player"))
check("target model shown", shownFor("target"))
check("tot model shown", shownFor("targettarget"))
check("party1 model shown", shownFor("party1"))
check("party2 out of range -> hidden", not shownFor("party2"))
check("focus missing -> hidden", not shownFor("focus"))

local pm = modelFor("player")
check("model sized by large inset", pm.w and math.abs(pm.w - 60 * 1.0) < 0.01)
check("model sits below the Blizzard container (ring on top)", pm.level < playerContainer.level)
check("model parented to the unit frame root", pm.parent == PlayerFrame)
check("2D portrait hidden while active", not playerContainer.PlayerPortrait.shown)

-- Blizzard/BBF re-showing the portrait while active gets re-hidden
playerContainer.PlayerPortrait:Show()
check("portrait stays hidden if re-shown while active", not playerContainer.PlayerPortrait.shown)

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
check("inset small only", BBFAnimatedPortraitsDB.sizes.small.inset == 0.9 and BBFAnimatedPortraitsDB.sizes.large.inset == 1.0)
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

-- Secret values must not error
world.secret = true
local ok = pcall(tick)
check("secret values don't error", ok)
world.secret = false

realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
