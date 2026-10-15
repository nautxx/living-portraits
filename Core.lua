-- BBF Animated Portraits
-- Replaces the flat 2D unit-frame portrait with a live 3D model (idle "breathing"
-- animation, like the character screen). Does not modify BetterBlizzFrames itself:
-- we layer a circle-masked background + a PlayerModel on top of the existing portrait,
-- and hide our layers to fall back to the normal portrait whenever the model can't load.

local ADDON_NAME, ns = ...

local defaults = {
    enabled = true,
    zoom    = 1,     -- 0..1, 1 = head & shoulders
    inset   = 0.72,  -- model size as a fraction of the portrait (0.70 ~ fits inside the circle)
    bgR = 0.05, bgG = 0.05, bgB = 0.07,
    units = { player = true },
}

local db
local portraits = {} -- unit -> { model, bg, portrait, mask }

-- Where each unit's portrait lives on the Blizzard frames.
local function GetPortraitInfo(unit)
    if unit == "player" then
        local c = PlayerFrame and PlayerFrame.PlayerFrameContainer
        if c then return c, c.PlayerPortrait, c.PlayerPortraitMask end
    end
    -- target / focus / party come in step 2
end

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

local function BBFHidesPortrait(unit)
    return BBF and BBF.HasNoPortrait and BBF.HasNoPortrait(unit)
end

local function CreateLayers(unit)
    local container, portrait, mask = GetPortraitInfo(unit)
    if not (container and portrait) then return end

    local layer, sub = portrait:GetDrawLayer()
    local bg = container:CreateTexture(nil, layer, nil, math.min((sub or 0) + 1, 7))
    bg:SetAllPoints(portrait)
    bg:SetColorTexture(1, 1, 1, 1)
    if mask then bg:AddMaskTexture(mask) end

    local model = CreateFrame("PlayerModel", nil, container)
    model:SetPoint("CENTER", portrait, "CENTER")
    model:SetScript("OnModelLoaded", function(self)
        self:SetPortraitZoom(db.zoom)
        self:SetCamDistanceScale(1)
        self:SetPosition(0, 0, 0)
    end)

    local p = { model = model, bg = bg, portrait = portrait, mask = mask }
    portraits[unit] = p
    return p
end

local function HideLayers(p)
    p.model:Hide()
    p.bg:Hide()
end

local function Refresh(unit)
    if not db or not db.units[unit] then
        if portraits[unit] then HideLayers(portraits[unit]) end
        return
    end
    local p = portraits[unit] or CreateLayers(unit)
    if not p then return end

    if not db.enabled or BBFHidesPortrait(unit)
       or not UnitExists(unit) or not UnitIsVisible(unit) or not UnitIsConnected(unit) then
        HideLayers(p)
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
end

local function RefreshAll()
    for unit in pairs(db.units) do Refresh(unit) end
end

-- Events -------------------------------------------------------------------
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
        self:RegisterEvent("UNIT_MODEL_CHANGED")
        self:RegisterEvent("UNIT_PORTRAIT_UPDATE")
        self:RegisterEvent("UNIT_CONNECTION")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- small delay so BBF finishes resizing portraits first
        C_Timer.After(0.5, RefreshAll)
    elseif arg1 and db.units[arg1] then
        Refresh(arg1)
    end
end)

-- Slash command for quick tuning: /bap
SLASH_BBFANIMPORTRAITS1 = "/bap"
SlashCmdList.BBFANIMPORTRAITS = function(msg)
    local cmd, val = strsplit(" ", (msg or ""):lower(), 2)
    val = tonumber(val)
    if cmd == "toggle" then
        db.enabled = not db.enabled
    elseif cmd == "zoom" and val then
        db.zoom = math.max(0, math.min(1, val))
    elseif cmd == "inset" and val then
        db.inset = math.max(0.3, math.min(1.2, val))
    elseif cmd == "reset" then
        wipe(db); CopyDefaults(defaults, db)
    else
        print("|cff00c0ffBBF Animated Portraits|r  enabled=" .. tostring(db.enabled)
            .. "  zoom=" .. db.zoom .. "  inset=" .. db.inset)
        print("  /bap toggle  |  /bap zoom 0-1  |  /bap inset 0.3-1.2  |  /bap reset")
        return
    end
    RefreshAll()
    print("|cff00c0ffBBF Animated Portraits|r  enabled=" .. tostring(db.enabled)
        .. "  zoom=" .. db.zoom .. "  inset=" .. db.inset)
end
