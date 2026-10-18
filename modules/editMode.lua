-- Edit Mode selection (box style): BBF's No Portrait mode re-anchors each unit frame's Edit Mode
-- selection art (the nine-slice corners of frame.Selection) around the health bar, or around
-- the party frame for party (noPortrait.lua FixSelectionHighlight), and hooks the corners'
-- SetPoint to keep them there. Our portrait boxes sit beside the bars, outside that outline.
-- BBF only moves the art: the Selection frame itself still covers the whole old unit frame, and
-- that frame is what Edit Mode snaps, clamps, draws its guide lines and takes clicks from
-- (GetScaledSelectionSides, GetSelectionOffset). So while a box shows, the Selection frame is
-- sized to BBF's outline grown to include every showing box (with margins), as TOPLEFT /
-- BOTTOMRIGHT offsets from the system frame (Blizzard reads points 1 and 2 as those offsets),
-- and the corners are pinned to its corners. Our corner writes set BBF's own `changing` flag so
-- its hook skips them, and our SetPoint hook (added after BBF's, so it runs last) re-applies
-- ours when BBF re-anchors.

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UnitFrameOf = ns.UnitFrameOf
local PARTY = ns.PARTY
local squares = ns.squares
local Safe = ns.Safe

-- The health bar BBF anchors the selection to (party: the party frame itself).
local function HealthOf(frame)
    return frame.healthBar or frame.HealthBar or frame.healthbar
end

-- Each Edit Mode system with our boxes: its frame, the region BBF outlines with BBF's margins
-- (left, right, top, bottom; noPortrait.lua FixSelectionHighlight) and the units whose boxes
-- belong in it.
local SYSTEMS = {
    { frame = function() return UnitFrameOf("player") end, ref = HealthOf, margins = { -16, 15, 21, -25 }, units = { "player" } },
    { frame = function() return UnitFrameOf("target") end, ref = HealthOf, margins = { -16, 15, 21, -25 }, units = { "target" } },
    { frame = function() return UnitFrameOf("focus") end, ref = HealthOf, margins = { -16, 15, 21, -25 }, units = { "focus" } },
    { frame = function() return PartyFrame end, ref = function(f) return f end, margins = { 27, 12, 15, -5 }, units = PARTY },
}
-- Around each box: like BBF's around the bars (15 over the box, which already reaches over
-- the name row; 16 under it matches BBF's 25 under the health bar for the player).
local BOX_LEFT, BOX_RIGHT, BOX_TOP, BOX_BOTTOM = -16, 15, 15, -16
local CORNERS = {
    { "TopLeftCorner", "TOPLEFT" }, { "TopRightCorner", "TOPRIGHT" },
    { "BottomLeftCorner", "BOTTOMLEFT" }, { "BottomRightCorner", "BOTTOMRIGHT" },
}

local applying -- our own corner SetPoint calls

-- The system's boxes that are on screen (box style, the unit exists, its frame shows).
local function ShownBoxes(sys)
    local list
    for _, unit in ipairs(sys.units) do
        local sq = squares[unit]
        if sq and sq.box:IsVisible() then
            list = list or {}
            list[#list + 1] = sq.box
        end
    end
    return list
end

local function PinCorner(sel, corner, point)
    applying = true
    corner.changing = true -- BBF's hook skips while this is set
    corner:ClearAllPoints()
    corner:SetPoint(point, sel, point, 0, 0)
    corner.changing = false
    applying = false
end

-- The Selection frame over BBF's outline + the boxes, as offsets from the system frame. false
-- when a position isn't readable yet (not laid out, or secret).
local function FitSelection(sys, frame, sel, ref, boxes)
    local m = sys.margins
    local l, r, t, b = Safe(ref:GetLeft()), Safe(ref:GetRight()), Safe(ref:GetTop()), Safe(ref:GetBottom())
    local fl, fr, ft, fb = Safe(frame:GetLeft()), Safe(frame:GetRight()), Safe(frame:GetTop()), Safe(frame:GetBottom())
    if not (l and r and t and b and fl and fr and ft and fb) then return false end
    l, r, t, b = l + m[1], r + m[2], t + m[3], b + m[4]
    for _, box in ipairs(boxes) do
        local bl, br, bt, bb = Safe(box:GetLeft()), Safe(box:GetRight()), Safe(box:GetTop()), Safe(box:GetBottom())
        if not (bl and br and bt and bb) then return false end
        l, r = math.min(l, bl + BOX_LEFT), math.max(r, br + BOX_RIGHT)
        t, b = math.max(t, bt + BOX_TOP), math.min(b, bb + BOX_BOTTOM)
    end
    -- Child frames share the system frame's scale, so these are in its units already.
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", frame, "TOPLEFT", l - fl, t - ft)
    sel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", r - fr, b - fb)
    return true
end

-- Back to Blizzard's Selection (all points on the frame) and BBF's corners: a plain SetPoint
-- on each corner, which BBF's own hook turns back into its anchor.
local function HandBack(frame, sel)
    sel:ClearAllPoints()
    sel:SetAllPoints(frame)
    for _, c in ipairs(CORNERS) do
        local corner = sel[c[1]]
        if corner then corner:SetPoint(c[2], sel, c[2], 0, 0) end
    end
end

local function UpdateSystem(sys, retried)
    local frame = sys.frame()
    local sel = frame and frame.Selection
    local ref = frame and sys.ref(frame)
    if not (sel and sel.TopLeftCorner and ref) or InCombatLockdown() then return end
    if not sys.hooked then
        sys.hooked = true
        for _, c in ipairs(CORNERS) do
            local corner = sel[c[1]]
            if corner then
                hooksecurefunc(corner, "SetPoint", function(self)
                    if not applying and sys.fitted then PinCorner(sel, self, c[2]) end
                end)
            end
        end
    end
    -- Boxes show and hide per unit (targets, party members joining or leaving): re-check then.
    for _, unit in ipairs(sys.units) do
        local sq = squares[unit]
        if sq and not sq.box.bapEditHook then
            sq.box.bapEditHook = true
            sq.box:HookScript("OnShow", function() UpdateSystem(sys) end)
            sq.box:HookScript("OnHide", function() UpdateSystem(sys) end)
        end
    end
    local boxes = db and db.enabled and db.style == "square" and sel.bbfRepositioned and ShownBoxes(sys)
    if boxes and FitSelection(sys, frame, sel, ref, boxes) then
        sys.fitted = true
        for _, c in ipairs(CORNERS) do
            if sel[c[1]] then PinCorner(sel, sel[c[1]], c[2]) end
        end
        return
    end
    if boxes and not retried then
        C_Timer.After(0, function() UpdateSystem(sys, true) end) -- not laid out yet
    end
    if sys.fitted then
        sys.fitted = nil
        HandBack(frame, sel)
    end
end

local function UpdateEditMode()
    for _, sys in ipairs(SYSTEMS) do UpdateSystem(sys) end
end

-- BBF fixes the selection on entering Edit Mode (its hook runs before ours: next frame).
local function HookEditMode()
    if not (EditModeManagerFrame and EditModeManagerFrame.EnterEditMode) then return end
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() C_Timer.After(0, UpdateEditMode) end)
end

ns.UpdateEditMode = UpdateEditMode
ns.HookEditMode = HookEditMode
