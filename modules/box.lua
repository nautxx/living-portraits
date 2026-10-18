-- Box style (when BBF's No Portrait / Pixel Border mode is on): a box with BBF's 1px
-- black border sits beside the health/mana bars and the model fills it exactly.
-- No masking needed. Falls back to the circle style when BBF still shows portraits.

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local defaults = ns.defaults
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local Safe = ns.Safe
local ApplyCamera = ns.ApplyCamera
local RetryRefresh = ns.RetryRefresh
local retryDelay = ns.retryDelay
local squares = ns.squares
local GetBarFrames = ns.GetBarFrames
local BorderSize = ns.BorderSize
local LayoutEdges = ns.LayoutEdges
local CreatePixelBorder = ns.CreatePixelBorder
local HexRGB = ns.HexRGB
local BorderRGBA = ns.BorderRGBA
local ColorEdges = ns.ColorEdges
local RestoreBorders = ns.RestoreBorders
local LayoutBars = ns.LayoutBars
local CenterBarTexts = ns.CenterBarTexts
local RestoreBar = ns.RestoreBar
local RestoreTexts = ns.RestoreTexts
local HP_TEXT_KEYS = ns.HP_TEXT_KEYS
local MANA_TEXT_KEYS = ns.MANA_TEXT_KEYS
local BoxGap = ns.BoxGap
local EliteIcon = ns.EliteIcon
local TintElite = ns.TintElite
local RestorePins = ns.RestorePins
local LayoutNameRow = ns.LayoutNameRow
local LayoutPartyIcons = ns.LayoutPartyIcons
local RestoreTot = ns.RestoreTot
local ClearTot = ns.ClearTot
local PARENT_OF = ns.PARENT_OF

local function CreateSquare(unit, unitFrame)
    local box = CreateFrame("Frame", nil, unitFrame)
    box:Hide()
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    local edges = CreatePixelBorder(box)
    local model = CreateFrame("PlayerModel", nil, box)
    model:SetAllPoints(box)
    model:SetScript("OnModelLoaded", function(self) ApplyCamera(self, "square") end)
    local sq = { unit = unit, box = box, bg = bg, model = model, unitFrame = unitFrame, edges = edges }
    -- Mirror Blizzard's portrait fading (party out of range) even though BBF hid the portrait.
    local portrait = Lookup(unit, "portrait")
    if portrait then
        box:SetAlpha(Safe(portrait:GetAlpha()) or 1)
        hooksecurefunc(portrait, "SetAlpha", function(_, alpha) box:SetAlpha(Safe(alpha) or 1) end)
    end
    squares[unit] = sq
    return sq
end

-- Border color (square style): our box border and BBF's health/mana borders get the
-- same color and opacity. BBF colors its edges once (black, when it creates them) and
-- keeps them on the bar (bar.BBFBlackBorder), so recoloring them at runtime sticks.
-- Edges are top, right, bottom, left. With the defaults, borders share pixel lines (box
-- and bars at squareGap 1, health and mana at barSpacing 0); below full opacity a shared
-- line would draw twice and show darker, so the duplicate edge is hidden.
local EDGE_RIGHT, EDGE_LEFT, EDGE_TOP = 2, 4, 1

-- Elite/rare on target and focus: the box and bar borders turn gold (elite, boss) or silver (rare,
-- rare elite), like classic's dragon around the portrait. The small elite icon alone was too
-- easy to miss. Both colors are settings. nil for normal units, other frames, or a secret
-- classification.
local ELITE_COLOR_KEY = { elite = "eliteColor", worldboss = "eliteColor", rare = "rareColor", rareelite = "rareColor" }
-- The icon always takes it; the borders only with Elite Border on.
local function EliteColor(unit)
    if not (UNITS[unit].elite and UnitExists(unit)) then return end
    local key = ELITE_COLOR_KEY[Safe(UnitClassification(unit)) or ""]
    if key then return HexRGB(db[key], defaults[key]) end
end

local function ApplyBorders(unit, manaBar, hpBar)
    local r, g, b, a = BorderRGBA()
    local er, eg, eb = EliteColor(unit) -- elite/rare: box and bars all get its color
    if er and db.eliteBorder then r, g, b = er, eg, eb end
    local size = BorderSize()
    local sq = squares[unit]
    if sq then
        LayoutEdges(sq.edges, sq.box, size)
        ColorEdges(sq.edges, r, g, b, a)
    end
    LayoutEdges(hpBar and hpBar.BBFBlackBorder, hpBar and hpBar.BBFPositionFrame, size)
    LayoutEdges(manaBar and manaBar.BBFBlackBorder, manaBar and manaBar.BBFPositionFrame, size)
    -- The bars' edge on the box side is the same line as the box's edge (gap 1).
    local boxSide = db.squareGap == 1 and (UNITS[unit].side == "RIGHT" and EDGE_RIGHT or EDGE_LEFT) or nil
    ColorEdges(hpBar and hpBar.BBFBlackBorder, r, g, b, a, boxSide)
    -- Mana's top edge is the same line as health's bottom edge (spacing 0).
    ColorEdges(manaBar and manaBar.BBFBlackBorder, r, g, b, a, boxSide, db.barSpacing == 0 and EDGE_TOP or nil)
    -- The elite icon takes the elite/rare color even with Elite Border off (here, not in the
    -- name row: this also runs in combat).
    local elite = EliteIcon(unit)
    if elite then TintElite(elite, er, eg, eb) end
end

-- Put the bars and texts back exactly as BBF/Blizzard had them.
local function RestoreBars(unit)
    if InCombatLockdown() then return end
    local hpPos, manaPos, manaBar, hpBar = GetBarFrames(unit)
    if not hpBar then return end
    RestoreTot(unit)
    RestoreBorders(manaBar, hpBar)
    RestoreBar(hpBar, hpPos)
    RestoreBar(manaBar, manaPos)
    RestoreTexts(hpBar, HP_TEXT_KEYS)
    RestoreTexts(hpBar:GetParent(), HP_TEXT_KEYS)
    RestoreTexts(manaBar, MANA_TEXT_KEYS)
    hpPos.bapRow = nil
    RestorePins(unit) -- names, level, skull, elite, status and party icons
end

-- Anchor the box beside the bars; height spans the health bar top to the mana bar bottom.
-- Returns false if the bars haven't been laid out yet.
-- Tall portraits (player, target and focus): px for the talent build's own line above the name
-- row. It grows the box upward, so the box becomes a taller rectangle while the bars keep
-- their size and spot. Reserved even with no build to show (NPC targets): bars can't be
-- re-laid out in combat, so the layout can't change per target. Off: square box, and the
-- build sits next to the level.
-- Party (no name row, no build) just gets the same taller box beside the name above its bars.
local TALL_LINE = 9
local TALL_GROUP = {
    player = "player", target = "target", focus = "target",
    party1 = "party", party2 = "party", party3 = "party", party4 = "party",
}
local function TallLine(unit)
    local group = TALL_GROUP[unit]
    if not (group and db.tallPortraits[group]) then return 0 end -- independent of showBuild
    return TALL_LINE
end

local function PlaceSquare(sq, hpPos, manaPos)
    local box = sq.box
    local bottomRef = manaPos or hpPos
    -- Positions can read back as secret (PvP, tainted): skip until they're readable again.
    local top, bottom = Safe(hpPos:GetTop()), Safe(bottomRef:GetBottom())
    if not top or not bottom then return false end
    local row = hpPos.bapRow or 0 -- the name row sits above the health bar, inside the box
    -- The build line sits above the name row; units with a name row (texts) only get it while
    -- the row is on (no build without one). Party has no name row: its box always grows.
    local extra = (row > 0 or not UNITS[sq.unit].texts) and TallLine(sq.unit) or 0
    local scale = hpPos:GetEffectiveScale() / box:GetEffectiveScale()
    local size = (top + row - bottom) * scale
    if size <= 0 then return false end

    box:ClearAllPoints()
    if UNITS[sq.unit].side == "RIGHT" then
        box:SetPoint("TOPLEFT", hpPos, "TOPRIGHT", BoxGap(), row + extra)
    else
        box:SetPoint("TOPRIGHT", hpPos, "TOPLEFT", -BoxGap(), row + extra)
    end
    box:SetSize(size, size + extra * scale)
    box:SetFrameStrata(hpPos:GetFrameStrata())
    box:SetFrameLevel(hpPos:GetFrameLevel())
    return true
end

local function DeactivateSquare(unit)
    if squares[unit] then squares[unit].box:Hide() end
end

-- empty: the unit is out of view range (not zoned in yet) or offline, so there's no model to
-- load. The box still shows (border and backing, no model) so its bars line up with the rest.
local function ActivateSquare(unit, unitFrame, hpPos, manaPos, empty)
    local sq = squares[unit] or CreateSquare(unit, unitFrame)
    if not PlaceSquare(sq, hpPos, manaPos) then
        sq.box:Hide()
        return false
    end
    sq.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, db.squareBg)
    sq.bg:SetShown(db.squareBg > 0)
    sq.box:Show() -- show first, then load (see circle Refresh)
    sq.model:ClearModel()
    sq.model:SetShown(not empty)
    if empty then return true end
    sq.model:SetUnit(unit)
    ApplyCamera(sq.model, "square")
    return true
end

-- Square style, where BBF has removed the round portrait. Returns false when the bars
-- haven't been laid out yet (retries shortly; the ticker keeps trying meanwhile).
local function RefreshSquare(unit, unitFrame, empty)
    local hpPos, manaPos, manaBar, hpBar = GetBarFrames(unit)
    if db.style ~= "square" or not hpPos then
        DeactivateSquare(unit)
        RestoreBars(unit)
        return true
    end
    LayoutBars(unit, hpPos, manaPos, manaBar, hpBar)
    if not InCombatLockdown() then LayoutNameRow(unit, hpPos) end
    if not ActivateSquare(unit, unitFrame, hpPos, manaPos, empty) then
        RetryRefresh(unit) -- bars not laid out yet, or their positions are secret
        return false
    end
    retryDelay[unit] = nil
    ApplyBorders(unit, manaBar, hpBar)
    LayoutPartyIcons(unit)
    -- Once the resized bars have been laid out: re-measure the box, center the texts.
    C_Timer.After(0, function()
        PlaceSquare(squares[unit], hpPos, manaPos)
        CenterBarTexts(hpPos, manaPos, manaBar, hpBar)
        if not InCombatLockdown() then LayoutNameRow(unit, hpPos) end
        -- Keep the ToT clear of this stack (also when the ToT itself was re-laid out).
        ClearTot(PARENT_OF[unit] or unit)
    end)
    return true
end

ns.TallLine = TallLine
ns.DeactivateSquare = DeactivateSquare
ns.RestoreBars = RestoreBars
ns.RefreshSquare = RefreshSquare
