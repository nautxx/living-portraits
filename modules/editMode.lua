-- Edit Mode selection (box style): BBF's No Portrait mode re-anchors each unit frame's Edit Mode
-- selection art (the nine-slice corners of frame.Selection) around the health bar
-- (noPortrait.lua FixSelectionHighlight: 16/15 px out, 21 up, 25 down) and hooks the corners'
-- SetPoint to keep them there. Our portrait box sits beside the bars, outside that outline.
-- BBF only moves the art: the Selection frame itself still covers the whole old unit frame, and
-- that frame is what Edit Mode snaps, clamps, draws its guide lines and takes clicks from
-- (GetScaledSelectionSides, GetSelectionOffset). So while our box shows, the Selection frame is
-- sized to the bars + box (BBF's margins, up to the box's top) as TOPLEFT / BOTTOMRIGHT offsets
-- from the unit frame (Blizzard reads points 1 and 2 as those offsets), and the corners are
-- pinned to its corners. Our corner writes set BBF's own `changing` flag so its hook skips them,
-- and our SetPoint hook (added after BBF's, so it runs last) re-applies ours when BBF re-anchors.
-- Player, target and focus. Party has one selection around all members (not handled yet).

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UNITS = ns.UNITS
local UnitFrameOf = ns.UnitFrameOf
local squares = ns.squares
local Safe = ns.Safe

local EDIT_UNITS = { "player", "target", "focus" }
-- BBF's margins around the health bar (left, right, top, bottom). Above the box: 15, like
-- BBF's top without its extra 6 for the name (the box already reaches over the name row).
local LEFT, RIGHT, TOP, BOTTOM = -16, 15, 15 + 6, -25
local BOX_TOP = 15
local CORNERS = {
    { "TopLeftCorner", "TOPLEFT" }, { "TopRightCorner", "TOPRIGHT" },
    { "BottomLeftCorner", "BOTTOMLEFT" }, { "BottomRightCorner", "BOTTOMRIGHT" },
}

local hooked = {}  -- unit -> corner hooks added
local fitted = {}  -- unit -> our Selection size and corner anchors are applied
local applying     -- our own corner SetPoint calls

-- The health bar BBF anchors the selection to.
local function HealthOf(frame)
    return frame.healthBar or frame.HealthBar or frame.healthbar
end

-- Our box when it's showing (box style, the unit exists).
local function ShownBox(unit)
    local sq = squares[unit]
    return sq and sq.box:IsShown() and sq.box
end

local function Wanted(unit, sel)
    return db and db.enabled and db.units[unit] and db.style == "square" and sel.bbfRepositioned
        and ShownBox(unit) and true or false
end

local function PinCorner(sel, corner, point)
    applying = true
    corner.changing = true -- BBF's hook skips while this is set
    corner:ClearAllPoints()
    corner:SetPoint(point, sel, point, 0, 0)
    corner.changing = false
    applying = false
end

-- The Selection frame over the health bar + box, as offsets from the unit frame. false when a
-- position isn't readable yet (not laid out, or secret).
local function FitSelection(unit, frame, sel, hp, box)
    local side = UNITS[unit].side
    local l, r = Safe(hp:GetLeft()), Safe(hp:GetRight())
    local t, b = Safe(hp:GetTop()), Safe(hp:GetBottom())
    local top = t and t + TOP
    if side == "LEFT" then l = Safe(box:GetLeft()) else r = Safe(box:GetRight()) end
    local boxTop = Safe(box:GetTop())
    if boxTop then top = boxTop + BOX_TOP end
    local fl, fr, ft, fb = Safe(frame:GetLeft()), Safe(frame:GetRight()), Safe(frame:GetTop()), Safe(frame:GetBottom())
    if not (l and r and top and b and fl and fr and ft and fb) then return false end
    -- Child frames share the unit frame's scale, so these are in its units already.
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", frame, "TOPLEFT", l + LEFT - fl, top - ft)
    sel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", r + RIGHT - fr, b + BOTTOM - fb)
    return true
end

-- Back to Blizzard's Selection (all points on the unit frame) and BBF's corners: a plain
-- SetPoint on each corner, which BBF's own hook turns back into its anchor.
local function HandBack(frame, sel)
    sel:ClearAllPoints()
    sel:SetAllPoints(frame)
    for _, c in ipairs(CORNERS) do
        local corner = sel[c[1]]
        if corner then corner:SetPoint(c[2], sel, c[2], 0, 0) end
    end
end

local function UpdateSelection(unit, retried)
    local frame = UnitFrameOf(unit)
    local sel = frame and frame.Selection
    local hp = frame and HealthOf(frame)
    if not (sel and sel.TopLeftCorner and hp) or InCombatLockdown() then return end
    if not hooked[unit] then
        hooked[unit] = true
        for _, c in ipairs(CORNERS) do
            local corner = sel[c[1]]
            if corner then
                hooksecurefunc(corner, "SetPoint", function(self)
                    if not applying and fitted[unit] then PinCorner(sel, self, c[2]) end
                end)
            end
        end
    end
    -- The box shows and hides per target: re-check then.
    local sq = squares[unit]
    if sq and not sq.box.bapEditHook then
        sq.box.bapEditHook = true
        sq.box:HookScript("OnShow", function() UpdateSelection(unit) end)
        sq.box:HookScript("OnHide", function() UpdateSelection(unit) end)
    end
    local box = Wanted(unit, sel) and ShownBox(unit)
    if box and FitSelection(unit, frame, sel, hp, box) then
        fitted[unit] = true
        for _, c in ipairs(CORNERS) do
            if sel[c[1]] then PinCorner(sel, sel[c[1]], c[2]) end
        end
        return
    end
    if box and not retried then
        C_Timer.After(0, function() UpdateSelection(unit, true) end) -- not laid out yet
    end
    if fitted[unit] then
        fitted[unit] = nil
        HandBack(frame, sel)
    end
end

local function UpdateEditMode()
    for _, unit in ipairs(EDIT_UNITS) do UpdateSelection(unit) end
end

-- BBF fixes the selection on entering Edit Mode (its hook runs before ours: next frame).
local function HookEditMode()
    if not (EditModeManagerFrame and EditModeManagerFrame.EnterEditMode) then return end
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() C_Timer.After(0, UpdateEditMode) end)
end

ns.UpdateEditMode = UpdateEditMode
ns.HookEditMode = HookEditMode
