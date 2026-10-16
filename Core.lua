-- BBF Animated Portraits
-- Replaces the flat 2D unit-frame portrait with a live 3D model (idle "breathing"
-- animation, like the character screen). Companion to BetterBlizzFrames; never edits BBF.
--
-- Layering (bottom to top), see CLAUDE.md for why:
--   bgFrame   (root child, level container-2)  dark circle behind the model
--   model     (root child, level container-1)  PlayerModel, a square we can't mask
--   container (Blizzard)                       hidden 2D portrait (sublevel 1),
--                                              our vignette (sublevel 1),
--                                              border ring art (sublevel 2) covers the model's corners
-- The vignette fades the circle's edge to dark so the model's straight edges don't show.

local ADDON_NAME, ns = ...

local PARTY = { "party1", "party2", "party3", "party4" }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local VIGNETTE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\vignette"

local defaults = {
    enabled  = true,
    zoom     = 1,     -- 0..1, 1 = head & shoulders
    vignette = true,
    bgR = 0.05, bgG = 0.05, bgB = 0.07,
    -- inset: model square as a fraction of the portrait (corners should stay under the ring)
    -- cam:   camera distance (lower = closer = bigger face)
    sizes = {
        large = { inset = 0.82, cam = 0.85 },
        small = { inset = 0.82, cam = 0.85 },
    },
    units = {
        player = true,
        target = true, focus = true,
        targettarget = true, focustarget = true,
        party1 = true, party2 = true, party3 = true, party4 = true,
    },
}

-- Unit -> function returning the portrait texture on the Blizzard frame.
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

local SIZE_OF = {
    player = "large", target = "large", focus = "large",
    targettarget = "small", focustarget = "small",
    party1 = "small", party2 = "small", party3 = "small", party4 = "small",
}

-- Slash-command groups -> units
local GROUPS = {
    player = { "player" }, target = { "target" }, focus = { "focus" },
    tot = { "targettarget", "focustarget" },
    party = PARTY,
}

local db
local layers = {}    -- unit -> layer record
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

local function UnitState(unit)
    if not UnitExists(unit) then return "none" end
    local guid = Safe(UnitGUID(unit)) or "?"
    local visible = Safe(UnitIsVisible(unit))
    local online = Safe(UnitIsConnected(unit))
    return guid .. (visible == false and ":h" or ":v") .. (online == false and ":d" or ":c")
end

local function ApplyCamera(model, size)
    model:SetPortraitZoom(db.zoom)
    model:SetCamDistanceScale(db.sizes[size].cam)
    model:SetPosition(0, 0, 0)
end

-- Layers --------------------------------------------------------------------

local Refresh -- forward declaration

local function SetLayerAlpha(p, alpha)
    p.bgFrame:SetAlpha(alpha)
    p.model:SetAlpha(alpha)
    p.vignette:SetAlpha(alpha)
end

local function Deactivate(p)
    p.bgFrame:Hide()
    p.model:Hide()
    p.vignette:Hide()
    if p.active then
        p.active = false
        if p.portraitWasShown then p.portrait:Show() end
    end
end

local function Activate(p)
    -- Sit just below the Blizzard container so its border ring draws over us.
    local level = p.container:GetFrameLevel()
    local strata = p.container:GetFrameStrata()
    p.bgFrame:SetFrameStrata(strata)
    p.model:SetFrameStrata(strata)
    p.bgFrame:SetFrameLevel(math.max(level - 2, 0))
    p.model:SetFrameLevel(math.max(level - 1, 0))

    p.bgFrame:Show()
    p.model:Show()
    p.vignette:SetShown(db.vignette)
    if not p.active then
        p.active = true
        p.portraitWasShown = p.portrait:IsShown()
        p.portrait:Hide()
    end
end

local function CreateLayers(unit)
    local getter = PORTRAITS[unit]
    local portrait = getter and getter()
    if not portrait then return end
    local container = portrait:GetParent()
    if not container then return end
    local root = container:GetParent() or container

    local p = { unit = unit, size = SIZE_OF[unit], portrait = portrait, container = container }

    -- Dark circle behind the model
    local bgFrame = CreateFrame("Frame", nil, root)
    bgFrame:SetAllPoints(portrait)
    local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bgFrame)
    local mask = bgFrame:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(bg)
    bg:AddMaskTexture(mask)
    bgFrame:Hide()

    -- The 3D model
    local model = CreateFrame("PlayerModel", nil, root)
    model:SetPoint("CENTER", portrait, "CENTER")
    model:SetScript("OnModelLoaded", function(self) ApplyCamera(self, p.size) end)
    model:Hide()

    -- Vignette: on the container, same sublevel as the (hidden) portrait, under the ring
    local layer, sub = portrait:GetDrawLayer()
    local vignette = container:CreateTexture(nil, layer, nil, sub or 0)
    vignette:SetTexture(VIGNETTE)
    vignette:SetAllPoints(portrait)
    vignette:Hide()

    p.bgFrame, p.bg, p.model, p.vignette = bgFrame, bg, model, vignette

    -- Keep Blizzard's portrait hidden while we're active.
    hooksecurefunc(portrait, "Show", function(self)
        if p.active then self:Hide() end
    end)
    -- Mirror Blizzard's portrait fading (e.g. party members out of range).
    SetLayerAlpha(p, Safe(portrait:GetAlpha()) or 1)
    hooksecurefunc(portrait, "SetAlpha", function(_, alpha)
        SetLayerAlpha(p, Safe(alpha) or 1)
    end)
    -- We're no longer inside the unit frame, so follow its visibility.
    container:HookScript("OnShow", function() Refresh(unit) end)
    container:HookScript("OnHide", function() Deactivate(p) end)

    layers[unit] = p
    return p
end

Refresh = function(unit)
    lastState[unit] = nil
    if not db then return end
    local p = layers[unit]
    if not db.units[unit] then
        if p then Deactivate(p) end
        return
    end
    p = p or CreateLayers(unit)
    if not p then return end

    if not db.enabled or BBFHidesPortrait(unit) or not p.container:IsVisible()
       or not UnitExists(unit)
       or Safe(UnitIsVisible(unit)) == false or Safe(UnitIsConnected(unit)) == false then
        Deactivate(p)
        lastState[unit] = UnitState(unit)
        return
    end

    local w, h = p.portrait:GetSize()
    local s = db.sizes[p.size]
    p.model:SetSize(w * s.inset, h * s.inset)
    p.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, 1)
    p.vignette:SetVertexColor(db.bgR, db.bgG, db.bgB, 1)

    p.model:ClearModel()
    p.model:SetUnit(unit)
    ApplyCamera(p.model, p.size)

    Activate(p)
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
        db.inset, db.bgInset = nil, nil -- settings from earlier versions
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
    local L, S = db.sizes.large, db.sizes.small
    print("|cff00c0ffBBF Animated Portraits|r  enabled=" .. tostring(db.enabled)
        .. "  zoom=" .. db.zoom .. "  vignette=" .. tostring(db.vignette)
        .. "  units=" .. (#on > 0 and table.concat(on, ",") or "none"))
    print(("  large: inset=%.2f cam=%.2f   small: inset=%.2f cam=%.2f"):format(L.inset, L.cam, S.inset, S.cam))
end

local function PrintHelp()
    print("  /bap toggle  |  /bap vignette  |  /bap zoom 0-1  |  /bap reset")
    print("  /bap inset 0.3-1.2 [large|small]  |  /bap cam 0.3-2 [large|small]")
    print("  /bap unit player|target|focus|tot|party")
end

-- Set a per-size value; no size given = both.
local function SetSized(key, value, size, lo, hi)
    value = math.max(lo, math.min(hi, value))
    for name, s in pairs(db.sizes) do
        if not size or size == name then s[key] = value end
    end
end

SLASH_BBFANIMPORTRAITS1 = "/bap"
SlashCmdList.BBFANIMPORTRAITS = function(msg)
    local args = {}
    for word in (msg or ""):lower():gmatch("%S+") do args[#args + 1] = word end
    local cmd, arg, size = args[1], args[2], args[3]
    local val = tonumber(arg)
    if size and not db.sizes[size] then size = nil end

    if cmd == "toggle" then
        db.enabled = not db.enabled
    elseif cmd == "vignette" then
        db.vignette = not db.vignette
    elseif cmd == "zoom" and val then
        db.zoom = math.max(0, math.min(1, val))
    elseif cmd == "inset" and val then
        SetSized("inset", val, size, 0.3, 1.2)
    elseif cmd == "cam" and val then
        SetSized("cam", val, size, 0.3, 2)
    elseif cmd == "unit" and arg and GROUPS[arg] then
        local list = GROUPS[arg]
        local newValue = not db.units[list[1]]
        for _, unit in ipairs(list) do db.units[unit] = newValue end
    elseif cmd == "reset" then
        wipe(db); CopyDefaults(defaults, db)
    else
        PrintStatus()
        PrintHelp()
        return
    end
    RefreshAll()
    PrintStatus()
end
