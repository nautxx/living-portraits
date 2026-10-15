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

local function newTexture()
    local t = stubIndex({ shown = false })
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:GetDrawLayer() return "ARTWORK", 1 end
    function t:GetSize() return 60, 60 end
    function t:GetNumMaskTextures() return 1 end
    function t:GetMaskTexture() return stubIndex({}) end
    return t
end

local eventFrame
local models = {}
function CreateFrame(kind)
    local f = stubIndex({ kind = kind, shown = false })
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetScript(name, fn) self[name] = fn end
    function f:SetUnit(unit) self.unit = unit end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:CreateTexture() return newTexture() end
    if kind == "PlayerModel" then models[#models + 1] = f end
    eventFrame = eventFrame or f
    return f
end

local function container(field)
    local c = stubIndex({})
    function c:CreateTexture() return newTexture() end
    local p = newTexture()
    function p:GetParent() return c end
    c[field] = p
    return c
end

PlayerFrame = { PlayerFrameContainer = container("PlayerPortrait") }
TargetFrame = { TargetFrameContainer = container("Portrait"), totFrame = container("Portrait") }
FocusFrame  = { TargetFrameContainer = container("Portrait"), totFrame = container("Portrait") }
PartyFrame  = {}
for i = 1, 4 do PartyFrame["MemberFrame" .. i] = container("Portrait") end

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
function strsplit(_, s)
    local a, b = s:match("^(%S*)%s*(.-)$")
    if b == "" then b = nil end
    return a, b
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print() end -- silence addon chat output
SlashCmdList = {}

-- Load the addon --------------------------------------------------------------
local chunk = assert(loadfile("Core.lua"))
chunk("BBF_AnimatedPortraits", {})

local function fire(event, arg) eventFrame.OnEvent(eventFrame, event, arg) end
local function slash(msg) SlashCmdList.BBFANIMPORTRAITS(msg) end
local function shownFor(unit)
    for _, m in ipairs(models) do if m.shown and m.unit == unit then return true end end
    return false
end

-- Tests -----------------------------------------------------------------------
world.exists = { player = true, target = true, targettarget = true, party1 = true, party2 = true }
world.visible.party2 = false

fire("ADDON_LOADED", "BBF_AnimatedPortraits")
check("defaults applied", BBFAnimatedPortraitsDB.enabled == true and BBFAnimatedPortraitsDB.inset == 0.72)

fire("PLAYER_ENTERING_WORLD")
check("one model per supported unit (9)", #models == 9)
check("player model shown", shownFor("player"))
check("target model shown", shownFor("target"))
check("tot model shown", shownFor("targettarget"))
check("party1 model shown", shownFor("party1"))
check("party2 out of range -> hidden", not shownFor("party2"))
check("focus missing -> hidden", not shownFor("focus"))
local w
for _, m in ipairs(models) do if m.unit == "player" then w = rawget(m, "w") end end
check("model sized by inset", w and math.abs(w - 60 * 0.72) < 0.01)

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

-- Global toggle
slash("toggle")
check("/bap toggle hides everything", not shownFor("player") and not shownFor("target"))
slash("toggle")
check("/bap toggle restores", shownFor("player"))

-- Settings clamp
slash("zoom 5");  check("zoom clamped to 1", BBFAnimatedPortraitsDB.zoom == 1)
slash("inset 0"); check("inset clamped to 0.3", BBFAnimatedPortraitsDB.inset == 0.3)
slash("reset");   check("reset restores inset", BBFAnimatedPortraitsDB.inset == 0.72)

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
