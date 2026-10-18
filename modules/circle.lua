-- Circle style: the model inside Blizzard's round portrait.
--
-- Layering (bottom to top), see CLAUDE.md for why:
--   bgFrame   (root child, level container-2)  dark circle behind the model
--   model     (root child, level container-1)  PlayerModel, a square we can't mask
--   container (Blizzard)                       hidden 2D portrait (sublevel 1),
--                                              our vignette (sublevel 1),
--                                              border ring art (sublevel 2) covers the model's corners
-- The vignette fades the circle's edge to dark so the model's straight edges don't show.

local ADDON_NAME, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local UnitFrameOf = ns.UnitFrameOf
local Safe = ns.Safe
local ApplyCamera = ns.ApplyCamera
local QueueRefresh = ns.QueueRefresh
local layers = ns.layers

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local VIGNETTE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\vignette"
local CORNERS  = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\corners"
-- vignette.tga is the soft round edge (fades in over the last 12% of the radius, clear
-- outside the circle); corners.tga covers only what's outside the circle. Both are sized
-- like the model. The corners follow circleBg: with a clear background, dark corners
-- would show as a square, so they fade out with it.


local function SetLayerAlpha(p, alpha)
    p.bgFrame:SetAlpha(alpha)
    p.model:SetAlpha(alpha)
    p.vignette:SetAlpha(alpha)
    if p.corners then p.corners:SetAlpha(alpha) end
end

local function Deactivate(p)
    p.bgFrame:Hide()
    p.model:Hide()
    p.vignette:Hide()
    p.corners:Hide()
    if p.ringLevel and not InCombatLockdown() then
        p.applyingLayers = true -- our own restore, not an outside change
        p.ringFrame:SetFrameLevel(p.ringLevel)
        p.applyingLayers = nil
        p.ringLevel = nil
    end
    if p.active then
        p.active = false
        if p.portraitWasShown then p.portrait:Show() end
    end
end

-- Keep the model and backing just below the Blizzard container so its border ring and
-- our circle edge draw over them. That needs the container at level 2+; some (the
-- target's: level 0 in the BACKGROUND strata) sit lower, so raise them within their
-- strata (restored on deactivate). BBF/Blizzard can re-set the container's level or
-- strata later, so this re-runs from hooks and the ticker (see LayeringOK).
local function ApplyLayering(p)
    if p.applyingLayers then return end
    p.applyingLayers = true
    local ring = p.ringFrame
    local level = ring:GetFrameLevel()
    if level < 2 and not InCombatLockdown() then
        p.ringLevel = p.ringLevel or level
        ring:SetFrameLevel(2)
        level = 2
    end
    local strata = ring:GetFrameStrata()
    p.bgFrame:SetFrameStrata(strata)
    p.model:SetFrameStrata(strata)
    p.bgFrame:SetFrameLevel(math.max(level - 2, 0))
    p.model:SetFrameLevel(math.max(level - 1, 0))
    p.applyingLayers = nil
end

local function LayeringOK(p)
    return p.model:GetFrameStrata() == p.ringFrame:GetFrameStrata()
        and p.model:GetFrameLevel() < p.ringFrame:GetFrameLevel()
end

local function Activate(p)
    ApplyLayering(p)
    if not p.layerHooks then
        p.layerHooks = true
        local function Reapply() if p.active then ApplyLayering(p) end end
        hooksecurefunc(p.ringFrame, "SetFrameLevel", Reapply)
        hooksecurefunc(p.ringFrame, "SetFrameStrata", Reapply)
    end

    p.bgFrame:SetShown(db.circleBg > 0)
    p.model:Show()
    local edge = db.vignette and (db.circleBg > 0 or db.calibrate)
    p.vignette:SetShown(edge)
    p.corners:SetShown(edge)
    if not p.active then
        p.active = true
        p.portraitWasShown = p.portrait:IsShown()
        p.portrait:Hide()
    end
end

local function CreateLayers(unit)
    local portrait = Lookup(unit, "portrait")
    if not portrait then return end
    local container = portrait:GetParent()
    if not container then return end
    -- Parent to the unit frame itself (PlayerFrame, TargetFrame, ...). The container's
    -- direct parent isn't always the unit frame (the target's is an unnamed level-501
    -- frame), and drawing our model as part of that group put it above the ring art.
    local root = UnitFrameOf(unit) or container:GetParent() or container

    -- The frame that owns the ring art: our layers go just beneath it, the circle edge on it.
    local ringTex = Lookup(unit, "ring")
    local ringFrame = ringTex and ringTex:GetParent() or container

    local p = { unit = unit, size = UNITS[unit].size, portrait = portrait, container = container, ringFrame = ringFrame }

    -- Dark circle behind the model
    local bgFrame = CreateFrame("Frame", nil, root)
    bgFrame:SetPoint("CENTER", portrait, "CENTER")
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
    -- Reload the unit whenever the model becomes visible (e.g. its unit frame re-shows).
    model:SetScript("OnShow", function(self)
        if p.active and UnitExists(unit) then
            self:SetUnit(unit)
            ApplyCamera(self, p.size)
        end
    end)
    model:Hide()

    -- Circle edge: on the ring's frame, one sublevel beneath the ring texture.
    local layer, sub
    if ringTex then
        layer, sub = ringTex:GetDrawLayer()
        sub = math.max((sub or 0) - 1, -8)
    else
        layer, sub = portrait:GetDrawLayer()
    end
    local vignette = ringFrame:CreateTexture(nil, layer, nil, sub or 0)
    vignette:SetTexture(VIGNETTE)
    local corners = ringFrame:CreateTexture(nil, layer, nil, sub or 0)
    corners:SetTexture(CORNERS)
    corners:SetAllPoints(vignette)
    corners:Hide()
    p.corners = corners
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
    container:HookScript("OnShow", function() QueueRefresh(unit) end)
    container:HookScript("OnHide", function() Deactivate(p) end)

    layers[unit] = p
    return p
end

local NO_OFFSET = { 0, 0 }

local function CenterOn(region, portrait, x, y, w, h)
    region:ClearAllPoints()
    region:SetPoint("CENTER", portrait, "CENTER", x, y)
    region:SetSize(w, h)
end

local function RefreshCircle(p, unit)
    local w, h = p.portrait:GetSize()
    local inset = db.sizes[p.size].inset
    local off = db.offsets[UNITS[unit].offset] or NO_OFFSET
    local ox, oy = off[1] or 0, off[2] or 0
    -- Model, its rounding vignette and the dark backing all share one center (+ offset).
    CenterOn(p.model, p.portrait, ox, oy, w * inset, h * inset)
    CenterOn(p.vignette, p.portrait, ox, oy, w * inset, h * inset)
    CenterOn(p.bgFrame, p.portrait, ox, oy, w, h)
    p.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, db.circleBg)
    -- The edge and corners fade with the background: with a clear background, a dark edge
    -- would show as a ring (and dark corners as a square). Calibrate tints them red.
    local r, g, b, a = db.bgR, db.bgG, db.bgB, db.circleBg
    if db.calibrate then r, g, b, a = 1, 0.1, 0.1, 1 end
    p.vignette:SetVertexColor(r, g, b, a)
    p.corners:SetVertexColor(r, g, b, a)

    -- Show first, then load: a model loaded while hidden sometimes never draws.
    Activate(p)
    p.model:ClearModel()
    p.model:SetUnit(unit)
    ApplyCamera(p.model, p.size)
end

ns.Deactivate = Deactivate
ns.ApplyLayering = ApplyLayering
ns.LayeringOK = LayeringOK
ns.CreateLayers = CreateLayers
ns.RefreshCircle = RefreshCircle
