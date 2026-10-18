local _, ns = ...
local UnitFrameOf = ns.UnitFrameOf
local Safe = ns.Safe
local IsSecret = ns.IsSecret
local squares = ns.squares
local GetBarFrames = ns.GetBarFrames
local BorderSize = ns.BorderSize

-- Target-of-target clearance ------------------------------------------------
-- Our layout makes the target/focus stack taller. Blizzard's small focus frame (Edit Mode)
-- shrinks the focus to 75% but scales its focus-target back up and tucks it closer, so it
-- ran into our box and bars. After layout, the ToT frame is nudged down just enough to
-- clear them, measured from the anchor Blizzard/BBF gave it (re-read whenever they move
-- it) and put back on hand-back. Out of combat only: the ToT is a secure unit button.
local TOT_OF = { target = "targettarget", focus = "focustarget" }
local PARENT_OF = { targettarget = "target", focustarget = "focus" }
local TOT_CLEARANCE = 2 -- UI units between our stack and the ToT

local function TotFrameOf(unit)
    local f = TOT_OF[unit] and UnitFrameOf(unit)
    return f and f.totFrame
end

-- Screen-space edges (frame coords x effective scale), nil when unknown or secret.
local function ScreenEdge(frame, method)
    local v = frame and Safe(frame[method](frame))
    if type(v) ~= "number" then return end
    return v * frame:GetEffectiveScale()
end

local function RestoreTot(unit)
    local tot = TotFrameOf(unit)
    local o = tot and tot.bapOrig
    if not o or InCombatLockdown() then return end
    tot:SetPoint(o[1], o[2], o[3], o[4], o[5])
    tot.bapOrig, tot.bapShift = nil, nil
end

local function ClearTot(unit)
    local tot = TotFrameOf(unit)
    local sq = squares[unit]
    if not (tot and sq and sq.box:IsShown()) or InCombatLockdown() then return end
    local point, rel, relPoint, x, y = tot:GetPoint(1)
    if not point or IsSecret(x) or IsSecret(y) then return end
    -- The anchor before our nudge; take a new one if Blizzard/BBF re-anchored it since.
    local o, shift = tot.bapOrig, tot.bapShift or 0
    if not (o and o[1] == point and o[2] == rel and o[4] == x and o[5] - shift == y) then
        o, shift = { point, rel, relPoint, x or 0, y or 0 }, 0
        tot.bapOrig = o
    end
    if shift ~= 0 then tot:SetPoint(o[1], o[2], o[3], o[4], o[5]) end -- measure from the original spot
    -- Our stack's bottom (box or bars, whichever is lower) and the ToT's top (its frame
    -- or its own box, whichever is higher), in screen space.
    local hpPos, manaPos = GetBarFrames(unit)
    local ours, totTop
    for _, v in ipairs({ ScreenEdge(sq.box, "GetBottom") or false, ScreenEdge(manaPos or hpPos, "GetBottom") or false }) do
        if v and (not ours or v < ours) then ours = v end
    end
    local totSq = squares[TOT_OF[unit]]
    for _, v in ipairs({ ScreenEdge(tot, "GetTop") or false, totSq and totSq.box:IsShown() and ScreenEdge(totSq.box, "GetTop") or false }) do
        if v and (not totTop or v > totTop) then totTop = v end
    end
    -- Side by side (no horizontal overlap) needs no nudge.
    local l1, r1 = ScreenEdge(hpPos, "GetLeft"), ScreenEdge(sq.box, "GetRight")
    local l2, r2 = ScreenEdge(tot, "GetLeft"), ScreenEdge(tot, "GetRight")
    local apart = l1 and r1 and l2 and r2 and (r2 < math.min(l1, ScreenEdge(sq.box, "GetLeft") or l1)
        or l2 > math.max(r1, ScreenEdge(hpPos, "GetRight") or r1))
    shift = 0
    if ours and totTop and not apart then
        local totScale = tot:GetEffectiveScale()
        local need = (totTop - ours) / totScale + TOT_CLEARANCE + BorderSize() -- clear the bottom border too
        if need > 0 then shift = need end
    end
    tot.bapShift = shift
    if shift ~= 0 then tot:SetPoint(o[1], o[2], o[3], o[4], o[5] - shift) end
end

ns.RestoreTot = RestoreTot
ns.ClearTot = ClearTot
ns.PARENT_OF = PARENT_OF
