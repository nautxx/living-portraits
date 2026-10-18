-- Class resource (box style): combo points, soul shards, arcane charges and holy charges under
-- the player's bars. db.resource:
--   "pixel": our own circles (gems for soul shards, like Blizzard's), bordered like the box
--            (border color, thickness), filled with the resource's color (db.resourceColors),
--            sized by db.resourceRadius.
--   "bbf":   rogue/druid: BBF's own combo point art, moved under the bars the same way.
--            Warlock/mage/paladin: nothing (BBF draws nothing for them here).
--
-- Rogue/druid: BBF's "Move Combo Points under PlayerFrame" bar (BBF.ComboPointBar, its
-- foreverComboPoints setting) sits at the top of the player's bottom container, which our
-- taller bar stack covers (it drew over the mana bar). With circles, BBF's bar stays the source
-- of truth (shown/hidden, max points, its "hide when empty" / "only show filled" fades) but is
-- see-through, sitting on our circles so its tooltip still works.
-- Warlock/mage/paladin: Camelot loads no Blizzard bar for these (Blizzard_UnitFrame.toc
-- excludes ShardBar, MageArcaneChargesBar and PaladinPowerBar) and BBF's options for them look
-- for those frames, so the circles read UnitPower directly and follow BBF's visibility settings
-- themselves. Nothing shows while the class's UnitPowerMax is 0.
-- Not handled: Blizzard's legacy combo frame and BBF's "Move Resource to TargetFrame" layout.
-- All non-secure frames, so this also runs in combat.

local ADDON_NAME, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local defaults = ns.defaults
local Safe = ns.Safe
local Clamp = ns.Clamp
local BBFHidesPortrait = ns.BBFHidesPortrait
local GetBarFrames = ns.GetBarFrames
local BorderSize = ns.BorderSize
local BorderRGBA = ns.BorderRGBA
local HexRGB = ns.HexRGB

-- Each resource's outline: a mask (the ring and the fill both use it) and height / width.
-- Shards are gems like Blizzard's (media/shard.tga, tools/make_shard_mask.py); the rest circles.
local CIRCLE = { mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask", tall = 1 }
local SHAPES = {
    shards = { mask = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\shard", tall = 1.25 },
}
local RESOURCE_GAP = 3     -- px between the bars' bottom border and the circles
local RESOURCE_SPACING = 3 -- px between two circles
local EMPTY_RGBA = { 0.08, 0.08, 0.08, 0.85 } -- an empty circle's fill
local BBF_POINT_SIZE = 20 -- BBF's combo point frames (BBF_Rogue/DruidComboPointTemplate)
local RESOURCE_MODES = { pixel = "pixel", bbf = "bbf", moved = "bbf" }
-- db.resourceAlign: which edge of the mana bar the circles line up with (point, x direction).
-- Left/right line the outer circle up with the bar border's outer edge.
local RESOURCE_ALIGN = { left = { "LEFT", -1 }, center = { "", 0 }, right = { "RIGHT", 1 } }
-- Class -> resource (the db.resourceColors key). Combo points come from BBF's bar; the others
-- from UnitPower (power type, and the token UNIT_POWER_FREQUENT passes).
local CLASS_RESOURCE = { ROGUE = "combo", DRUID = "combo", WARLOCK = "shards", MAGE = "arcane", PALADIN = "holy" }
local POWER = {
    shards = { "SoulShards", "SOUL_SHARDS" },
    arcane = { "ArcaneCharges", "ARCANE_CHARGES" },
    holy   = { "HolyPower", "HOLY_POWER" },
}

local hooked      -- the BBF bar we've hooked
local events      -- UnitPower updates for the classes we draw from UnitPower
local row         -- holder of our circles; row.dots[i] = { frame, ring, fill }
local pixelOn     -- our circles are showing (and BBF's bar, if any, is see-through)
local moved       -- we've anchored BBF's bar (hand it back with BBF's own re-anchor)
local positioning -- our own SetPoint/SetAlpha/SetScale calls, which the hooks ignore
local bbfScale    -- BBF's own scale for its bar (its Class Resource Scale), put back on hand-back

local function Bar() return BBF and BBF.ComboPointBar end

local function Resource()
    local _, class = UnitClass("player")
    return CLASS_RESOURCE[class or ""]
end

-- Where the resource goes: under the player's mana bar (health without a mana row). nil = leave
-- it alone: not box style, or BBF has its bar on the target frame or is dragging it.
local function Anchor(bar)
    if not (db and db.enabled and db.units.player and db.style == "square") then return end
    if bar and (bar.bbfOnTarget or bar.bbfResourceDragging) then return end
    if not BBFHidesPortrait("player") then return end
    local hpPos, manaPos = GetBarFrames("player")
    return manaPos or hpPos
end

local function MaskedTexture(parent, layer)
    local t = parent:CreateTexture(nil, layer)
    local mask = parent:CreateMaskTexture()
    mask:SetAllPoints(t)
    t:AddMaskTexture(mask)
    return t, mask
end

-- One circle (or shard): the shape in the border color with the filled shape on top, inset by
-- the border.
local function Dot(i)
    local d = row.dots[i]
    if d then return d end
    local f = CreateFrame("Frame", nil, row)
    d = { frame = f }
    d.ring, d.ringMask = MaskedTexture(f, "BORDER")
    d.fill, d.fillMask = MaskedTexture(f, "ARTWORK")
    d.ring:SetAllPoints(f)
    row.dots[i] = d
    return d
end

local function SetShape(d, shape)
    if d.shape == shape then return end
    d.shape = shape
    d.ringMask:SetTexture(shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    d.fillMask:SetTexture(shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
end

-- BBF's "Hide Combo Points/Resource When Empty" / "Only Show Filled" for the player frame (with
-- "Include Player & Target Frame"), as BBF applies them to its own bars.
local function BBFVisibility()
    local b = BetterBlizzFramesDB
    if not (b and b.comboVisibilityUnitFrames) then return end
    if b.hideEmptyComboPoints then return "bar" end
    if b.onlyActiveComboPoints then return "points" end
end

-- points: BBF's point frames (follow their fades); else vis: a BBFVisibility() mode.
local function DotShown(i, count, points, vis)
    if points then return (Safe(points[i]:GetAlpha()) or 1) > 0 end
    if vis == "bar" then return count > 0 end
    if vis == "points" then return i <= count end
    return true
end

-- A circle's width: radius + border, twice.
local function DotSize()
    return (Clamp(math.floor((db.resourceRadius or defaults.resourceRadius) + 0.5), 2, 16) + BorderSize()) * 2
end

-- Lay out and color n circles, filled up to count.
local function Paint(n, count, points, vis)
    if not pixelOn then return end
    local border = BorderSize()
    local size = DotSize()
    local br, bg, bb, ba = BorderRGBA()
    local key = Resource() or "combo"
    local fr, fg, fb = HexRGB(db.resourceColors[key], defaults.resourceColors[key])
    local shape = SHAPES[key] or CIRCLE
    local height = math.floor(size * shape.tall + 0.5)
    for i = 1, math.max(n, #row.dots) do
        if i > n then
            row.dots[i].frame:Hide()
        else
            local d = Dot(i)
            local f = d.frame
            SetShape(d, shape)
            f:SetSize(size, height)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (size + RESOURCE_SPACING), 0)
            d.ring:SetColorTexture(br, bg, bb, ba)
            d.fill:ClearAllPoints()
            d.fill:SetPoint("TOPLEFT", f, "TOPLEFT", border, -border)
            d.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -border, border)
            if i <= count then
                d.fill:SetColorTexture(fr, fg, fb, 1)
            else
                d.fill:SetColorTexture(EMPTY_RGBA[1], EMPTY_RGBA[2], EMPTY_RGBA[3], EMPTY_RGBA[4])
            end
            f:SetShown(DotShown(i, count, points, vis))
        end
    end
    row:SetSize(math.max(n * size + (n - 1) * RESOURCE_SPACING, 1), height)
end

-- Combo points: one circle per BBF point, filled up to the combo count.
local function PaintBar(bar)
    local points = bar.classResourceButtonTable or {}
    Paint(#points, Safe(GetComboPoints("player", "target")) or 0, points)
end

local function SetFaded(bar, on)
    positioning = true
    bar:SetAlpha(on and 0 or 1)
    positioning = false
end

local function ShowRow(anchor, shown)
    if not row then
        row = CreateFrame("Frame", nil, PlayerFrame)
        row.dots = {}
    end
    row:SetFrameStrata(anchor:GetFrameStrata())
    row:SetFrameLevel(anchor:GetFrameLevel() + 2)
    row:SetShown(shown)
    pixelOn = true
end

local function HideRow()
    if not pixelOn then return end
    pixelOn = false
    row:Hide()
end

-- Our row (when showing) under the anchor, BBF's bar (if any) on our row or, with BBF's art,
-- in the same spot. BBF's bar keeps an empty band (topPadding) above its points, so it's
-- raised by that much. The size setting scales BBF's bar so a point is a circle's width (its
-- offsets are in its own scale, hence / scale).
local function Place(bar, anchor)
    local border = BorderSize()
    local gap = border + RESOURCE_GAP -- the bars' bottom border hangs below the anchor
    local align = RESOURCE_ALIGN[db.resourceAlign] or RESOURCE_ALIGN.center
    local top, bottom, x = "TOP" .. align[1], "BOTTOM" .. align[1], align[2] * border
    positioning = true
    if pixelOn then
        row:ClearAllPoints()
        row:SetPoint(top, anchor, bottom, x, -gap)
    end
    if bar then
        if not moved then bbfScale = Safe(bar:GetScale()) end
        local scale = DotSize() / BBF_POINT_SIZE
        bar:SetScale(scale)
        bar:ClearAllPoints()
        if pixelOn then
            bar:SetPoint(top, row, top, 0, bar.topPadding or 0)
        else
            bar:SetPoint(top, anchor, bottom, x / scale, -gap / scale + (bar.topPadding or 0))
        end
        moved = true
    end
    positioning = false
end

-- Stop drawing ours and make BBF's bar visible again. reanchor: also ask BBF to put it back
-- (not when BBF is anchoring it itself right now, e.g. moving it to the target frame).
local function Release(bar, reanchor)
    if pixelOn then
        HideRow()
        SetFaded(bar, false)
    end
    if moved then
        moved = false
        if bbfScale then
            positioning = true
            bar:SetScale(bbfScale)
            positioning = false
        end
        if reanchor and BBF.ReanchorComboPointBar then BBF.ReanchorComboPointBar() end
    end
end

-- Combo points under the bars: our circles with BBF's bar see-through on them, or BBF's own
-- art (also when BBF re-anchors its bar, e.g. back from the target frame).
local function ApplyBar(bar, anchor)
    if db.resource == "pixel" then
        ShowRow(anchor, bar:IsShown())
        SetFaded(bar, true)
    elseif pixelOn then
        HideRow()
        SetFaded(bar, false)
    end
    Place(bar, anchor)
    PaintBar(bar)
end

local function UpdateBar()
    local bar = Bar()
    if not bar then return end
    if bar ~= hooked then
        hooked = bar
        -- BBF re-anchors its bar (scale changes, settings, PLAYER_ENTERING_WORLD): keep ours.
        hooksecurefunc(bar, "SetPoint", function(self)
            if positioning or self ~= Bar() then return end
            local anchor = Anchor(self)
            if anchor then ApplyBar(self, anchor) else Release(self, false) end
        end)
        -- BBF's Class Resource Scale: remember it for hand-back; BBF re-anchors right after,
        -- and that puts our scale back.
        hooksecurefunc(bar, "SetScale", function(self, scale)
            if not positioning and self == Bar() then bbfScale = Safe(scale) or bbfScale end
        end)
        hooksecurefunc(bar, "SetAlpha", function(self, alpha)
            if pixelOn and not positioning and self == Bar() and Safe(alpha) ~= 0 then SetFaded(self, true) end
        end)
        -- BBF calls it on every combo point change, after its own fades.
        hooksecurefunc(bar, "UpdatePower", function(self) if self == Bar() then PaintBar(self) end end)
        local function Sync(self)
            if pixelOn and self == Bar() then row:SetShown(self:IsShown()) end
        end
        bar:HookScript("OnShow", Sync)
        bar:HookScript("OnHide", Sync)
    end
    local anchor = Anchor(bar)
    if anchor then ApplyBar(bar, anchor) else Release(bar, true) end
end

-- Shards, arcane charges, holy charges: circles straight from UnitPower.
local function PowerType(key)
    local types = Enum and Enum.PowerType
    return types and POWER[key] and types[POWER[key][1]]
end

local function UpdateOwn()
    local key = Resource()
    local powerType = PowerType(key)
    local anchor = powerType and db.resource == "pixel" and Anchor()
    local max = anchor and Safe(UnitPowerMax("player", powerType)) or 0
    if max <= 0 then
        HideRow()
        return
    end
    ShowRow(anchor, true)
    Place(nil, anchor)
    Paint(max, Safe(UnitPower("player", powerType)) or 0, nil, BBFVisibility())
end

local function UpdateClassResource()
    if not db then return end
    db.resource = RESOURCE_MODES[db.resource] or defaults.resource -- "moved" was "bbf"'s old name
    local key = Resource()
    if key == "combo" then
        UpdateBar()
    elseif key then
        if not events then
            events = CreateFrame("Frame")
            events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
            events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
            events:SetScript("OnEvent", function(_, event, _, token)
                local power = POWER[Resource() or ""]
                if event == "UNIT_MAXPOWER" or (power and token == power[2]) then UpdateOwn() end
            end)
        end
        UpdateOwn()
    end
end

-- BBF creates its combo point bar on its own schedule (maybe after our first refresh): the
-- ticker checks.
local function CheckResourceBar()
    local bar = Bar()
    if bar and bar ~= hooked then UpdateClassResource() end
end

-- /lp debug player: where BBF's bar and our circles are.
local function ResourceDebug()
    local head = ("resource: %s mode=%s pixel=%s moved=%s row=%s"):format(tostring(Resource()),
        tostring(db.resource), tostring(pixelOn), tostring(moved), tostring(row and row:IsShown()))
    local bar = Bar()
    if not bar then return head .. "  (no BBF combo point bar)" end
    local point, rel, relPoint, x, y = bar:GetPoint(1)
    return head .. ("  bar %s>%s (%s,%s) shown=%s alpha=%s points=%d"):format(tostring(point),
        tostring(rel == row and "ours" or rel and rel.GetName and rel:GetName() or rel), tostring(relPoint),
        tostring(Safe(x)), tostring(Safe(y)), tostring(bar:IsShown()), tostring(Safe(bar:GetAlpha())),
        #(bar.classResourceButtonTable or {}))
end

ns.RESOURCE_MODES = RESOURCE_MODES
ns.RESOURCE_ALIGN = RESOURCE_ALIGN
ns.Resource = Resource
ns.UpdateClassResource = UpdateClassResource
ns.CheckResourceBar = CheckResourceBar
ns.ResourceDebug = ResourceDebug
