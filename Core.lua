-- BBF Animated Portraits
-- Replaces the flat 2D unit-frame portrait with a live 3D model (idle "breathing"
-- animation, like the character screen). Does not modify BetterBlizzFrames itself:
-- we layer a circle-masked background + a PlayerModel on top of the existing portrait,
-- and hide our layers to fall back to the normal portrait whenever the model can't load.

local ADDON_NAME, ns = ...

local PARTY = { "party1", "party2", "party3", "party4" }

local defaults = {
    enabled = true,
    zoom    = 1,     -- 0..1, 1 = head & shoulders
    inset   = 0.72,  -- model size as a fraction of the portrait (~0.70 fits inside the circle)
    bgR = 0.05, bgG = 0.05, bgB = 0.07,
    units = {
        player = true,
        target = true, focus = true,
        targettarget = true, focustarget = true,
        party1 = true, party2 = true, party3 = true, party4 = true,
    },
}

-- Unit -> function returning the portrait texture on the Blizzard frame.
-- The model/background are parented to the portrait's own parent frame.
local PORTRAITS = {
    player       = function() local c = PlayerFrame and PlayerFrame.PlayerFrameContainer; return c and c.PlayerPortrait end,
    target       = function() local c = TargetFrame and TargetFrame.TargetFrameContainer; return c and c.Portrait end,
    focus        = function() local c = FocusFrame and FocusFrame.TargetFrameContainer;  return c and c.Portrait end,
    targettarget = function() local f = TargetFrame and TargetFrame.totFrame; return f and f.Portrait end,
    focustarget  = function() local f = FocusFrame and FocusFrame.totFrame;   return f and f.Portrait end,
}
for i, unit in ipairs(PARTY) do
    PORTRAITS[unit] = function()
        local f = PartyFrame and PartyFrame["MemberFrame" .. i]
        return f and f.Portrait
    end
end

-- Slash-command groups -> units
local GROUPS = {
    player = { "player" }, target = { "target" }, focus = { "focus" },
    tot = { "targettarget", "focustarget" },
    party = PARTY,
}

local db
local layers = {}   -- unit -> { model, bg, portrait }
local lastState = {} -- unit -> state key, so the ticker only refreshes on change

-- Helpers -------------------------------------------------------------------

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = type(dst[k]) == "table" and dst[k] or {}
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Newer clients can return "secret" values that error if compared or concatenated.
local function Safe(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function BBFHidesPortrait(unit)
    return BBF and BBF.HasNoPortrait and BBF.HasNoPortrait(unit)
end

-- Use whichever mask Blizzard/BBF already put on the portrait.
local function GetPortraitMask(portrait)
    if portrait.GetNumMaskTextures and portrait:GetNumMaskTextures() > 0 then
        return portrait:GetMaskTexture(1)
    end
    local parent = portrait:GetParent()
    return parent and (parent.PortraitMask or parent.PlayerPortraitMask)
end

local function UnitState(unit)
    if not UnitExists(unit) then return "none" end
    local guid = Safe(UnitGUID(unit)) or "?"
    local visible = Safe(UnitIsVisible(unit))
    local online = Safe(UnitIsConnected(unit))
    return guid .. (visible == false and ":h" or ":v") .. (online == false and ":d" or ":c")
end

-- Layers --------------------------------------------------------------------

local function CreateLayers(unit)
    local getter = PORTRAITS[unit]
    local portrait = getter and getter()
    if not portrait then return end
    local container = portrait:GetParent()
    if not container then return end

    local layer, sub = portrait:GetDrawLayer()
    local bg = container:CreateTexture(nil, layer, nil, math.min((sub or 0) + 1, 7))
    bg:SetAllPoints(portrait)
    bg:SetColorTexture(1, 1, 1, 1)
    local mask = GetPortraitMask(portrait)
    if mask then bg:AddMaskTexture(mask) end
    bg:Hide()

    local model = CreateFrame("PlayerModel", nil, container)
    model:SetPoint("CENTER", portrait, "CENTER")
    model:SetScript("OnModelLoaded", function(self)
        self:SetPortraitZoom(db.zoom)
        self:SetCamDistanceScale(1)
        self:SetPosition(0, 0, 0)
    end)
    model:Hide()

    local p = { model = model, bg = bg, portrait = portrait }
    layers[unit] = p
    return p
end

local function HideLayers(p)
    p.model:Hide()
    p.bg:Hide()
end

local function Refresh(unit)
    lastState[unit] = nil
    if not db then return end
    local p = layers[unit]
    if not db.units[unit] then
        if p then HideLayers(p) end
        return
    end
    p = p or CreateLayers(unit)
    if not p then return end

    if not db.enabled or BBFHidesPortrait(unit) or not UnitExists(unit)
       or Safe(UnitIsVisible(unit)) == false or Safe(UnitIsConnected(unit)) == false then
        HideLayers(p)
        lastState[unit] = UnitState(unit)
        return
    end

    local w, h = p.portrait:GetSize()
    p.model:SetSize(w * db.inset, h * db.inset)
    p.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, 1)

    p.model:ClearModel()
    p.model:SetUnit(unit)
    p.model:SetPortraitZoom(db.zoom)

    p.bg:Show()
    p.model:Show()
    lastState[unit] = UnitState(unit)
end

local function RefreshAll()
    for unit in pairs(PORTRAITS) do Refresh(unit) end
end

local function RefreshList(list)
    for _, unit in ipairs(list) do Refresh(unit) end
end

-- Catches changes with no reliable event (ToT swaps, party range/visibility).
local function Tick()
    if not (db and db.enabled) then return end
    for unit in pairs(PORTRAITS) do
        if db.units[unit] and lastState[unit] ~= UnitState(unit) then
            Refresh(unit)
        end
    end
end

-- Events --------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        BBFAnimatedPortraitsDB = BBFAnimatedPortraitsDB or {}
        db = BBFAnimatedPortraitsDB
        CopyDefaults(defaults, db)
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
        self:RegisterEvent("PLAYER_FOCUS_CHANGED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        self:RegisterEvent("UNIT_TARGET")
        self:RegisterEvent("UNIT_MODEL_CHANGED")
        self:RegisterEvent("UNIT_PORTRAIT_UPDATE")
        self:RegisterEvent("UNIT_CONNECTION")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- small delay so BBF finishes resizing portraits first
        C_Timer.After(0.5, RefreshAll)
        if not ns.ticker then ns.ticker = C_Timer.NewTicker(0.5, Tick) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        Refresh("target"); Refresh("targettarget")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Refresh("focus"); Refresh("focustarget")
    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshList(PARTY)
    elseif event == "UNIT_TARGET" then
        if arg1 == "target" then Refresh("targettarget")
        elseif arg1 == "focus" then Refresh("focustarget") end
    elseif arg1 and PORTRAITS[arg1] then
        Refresh(arg1)
    end
end)

-- Slash command: /bap -------------------------------------------------------

local function PrintStatus()
    local on = {}
    for name, list in pairs(GROUPS) do
        if db.units[list[1]] then on[#on + 1] = name end
    end
    table.sort(on)
    print("|cff00c0ffBBF Animated Portraits|r  enabled=" .. tostring(db.enabled)
        .. "  zoom=" .. db.zoom .. "  inset=" .. db.inset
        .. "  units=" .. (#on > 0 and table.concat(on, ",") or "none"))
end

SLASH_BBFANIMPORTRAITS1 = "/bap"
SlashCmdList.BBFANIMPORTRAITS = function(msg)
    local cmd, arg = strsplit(" ", (msg or ""):lower(), 2)
    local val = tonumber(arg)
    if cmd == "toggle" then
        db.enabled = not db.enabled
    elseif cmd == "zoom" and val then
        db.zoom = math.max(0, math.min(1, val))
    elseif cmd == "inset" and val then
        db.inset = math.max(0.3, math.min(1.2, val))
    elseif cmd == "unit" and arg and GROUPS[arg] then
        local list = GROUPS[arg]
        local newValue = not db.units[list[1]]
        for _, unit in ipairs(list) do db.units[unit] = newValue end
    elseif cmd == "reset" then
        wipe(db); CopyDefaults(defaults, db)
    else
        PrintStatus()
        print("  /bap toggle  |  /bap zoom 0-1  |  /bap inset 0.3-1.2  |  /bap reset")
        print("  /bap unit player|target|focus|tot|party")
        return
    end
    RefreshAll()
    PrintStatus()
end
