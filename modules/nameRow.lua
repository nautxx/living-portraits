-- Box style: name + level row, pinned BBF/Blizzard regions (names, level, skull, elite
-- icon, status icons) and the party icons.

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local Safe = ns.Safe
local AnySecret = ns.AnySecret
local GetBarFrames = ns.GetBarFrames
local squares = ns.squares
local buildTexts = ns.buildTexts

-- Name row: name and level on one line above the health bar, inside the box's height.
-- Every frame: name left, level right.
local function SavePoints(fs)
    if fs.bapPoints then return end
    local pts = {}
    for i = 1, fs:GetNumPoints() do pts[i] = { fs:GetPoint(i) } end
    fs.bapPoints = pts
    fs.bapJustify = fs.GetJustifyH and fs:GetJustifyH()
    fs.bapWidth = fs.GetWidth and Safe(fs:GetWidth())
end

local function RestorePoints(fs)
    if not (fs and fs.bapPoints) then return end
    fs.bapLayout = nil
    fs:ClearAllPoints()
    for _, pt in ipairs(fs.bapPoints) do fs:SetPoint(unpack(pt)) end
    if fs.bapJustify then fs:SetJustifyH(fs.bapJustify) end
    if fs.bapWidth and fs.SetWidth then fs:SetWidth(fs.bapWidth) end
    fs.bapPoints, fs.bapWidth = nil, nil
end

-- Width of the text itself (not its box). nil when unknown or secret.
local function TextWidth(fs)
    if not fs then return end
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
        or fs.GetStringWidth and fs:GetStringWidth()
    w = Safe(w)
    if type(w) == "number" and w > 0 then return w end
end

-- Anchor a text to the name row and keep it there if BBF/Blizzard moves it later.
-- The text box shrinks to the text, so alignment doesn't depend on justify: BBF gives
-- its name a fixed width, and the player's bbfName ignores later SetJustifyH calls.
-- maxWidth (optional function) caps it so a long name stops short of the level.
local function PinText(fs, point, rel, relPoint, x, y, justify, maxWidth)
    if not fs then return end
    SavePoints(fs)
    fs.bapLayout = { point, rel, relPoint, x, y, justify, maxWidth }
    local function Apply(self)
        local l = self.bapLayout
        if not l or self.bapApplying then return end
        self.bapApplying = true
        self:ClearAllPoints()
        self:SetPoint(l[1], l[2], l[3], l[4], l[5])
        if l[6] and self.SetJustifyH then self:SetJustifyH(l[6]) end
        local w = self.SetWidth and TextWidth(self)
        if w then
            local cap = l[7] and l[7]()
            if cap and w > cap then w = cap end
            self:SetWidth(math.ceil(w) + 1) -- +1: rounding slack, or the name gets an ellipsis
        end
        self.bapApplying = nil
    end
    fs.bapApply = Apply -- lets other code re-fit it (the build text changes the name's room)
    if not fs.bapPinHook then
        fs.bapPinHook = true
        hooksecurefunc(fs, "SetPoint", Apply)
        if fs.SetJustifyH then hooksecurefunc(fs, "SetJustifyH", Apply) end
        if fs.SetWidth then hooksecurefunc(fs, "SetWidth", Apply) end
        if fs.SetText then hooksecurefunc(fs, "SetText", Apply) end
        if fs.SetFont then hooksecurefunc(fs, "SetFont", Apply) end
    end
    Apply(fs)
end

-- Every region we pin, per unit, so handing a frame back restores all of them (no
-- hand-kept restore lists to forget one in). Pin() = PinText() + record.
local pinned = {} -- unit -> { [region] = true }
local function Pin(unit, fs, ...)
    if not fs then return end
    pinned[unit] = pinned[unit] or {}
    pinned[unit][fs] = true
    PinText(fs, ...)
end

-- Mirrored text (target/focus, box on the right): name and build hug the portrait and
-- the level goes to the outer edge, so the frame mirrors the player's.
local function Mirrored(unit)
    return db.mirrorTarget and UNITS[unit].side == "RIGHT"
end

-- The player's status icons: combat (crossed swords) and the resting Zzz. BBF's No Portrait
-- mode puts them where the portrait used to be, which is now our box: right on the face.
-- Blizzard shows only one at a time (PlayerFrame_UpdateStatus), so both share one slot
-- just after the name.
local function StatusIcons(unit)
    if unit ~= "player" then return end
    local f = PlayerFrame and PlayerFrame.PlayerFrameContent
    local c = f and f.PlayerFrameContentContextual
    if c then return c.AttackIcon, c.PlayerRestLoop end
end
local STATUS_ICON_ROOM = 18 -- icon (~15 px) + gaps, kept free after the name
-- The Zzz frame is scaled 0.5 by BBF (offsets are in its scale) and its art overhangs the
-- frame by 5 units per side. Tuned in game: 3 px closer to the name and 3 px up (the
-- small "z" sat below the name's baseline).
local REST_X, REST_Y = 2, 6
-- db.restIcon: "name" (just after the name, above) or "corner" (centered on the portrait box's
-- top-right corner, overlapping it). Jason likes both, so it's a setting.
local REST_MODES = { name = true, corner = true }
local REST_CORNER_X, REST_CORNER_Y = 0, 0 -- in the Zzz frame's 0.5 scale

-- Target/focus elite icon. BBF centers it on the health bar's top-right corner, which is now
-- where the name ends and our box begins (on the name and the model). It goes beside the
-- level instead, on the side facing the name ("14 [elite] ... Name"), like classic's elite
-- level. Room is kept free whether or not it shows (it changes per target).
local function EliteIcon(unit)
    return UNITS[unit].elite and Lookup(unit, "elite")
end
local function SkullIcon(unit)
    return UNITS[unit].skull and Lookup(unit, "skull")
end
local ELITE_ROOM = 17 -- icon (15) + gap
local ELITE_MODES = { top = true, bottom = true, center = true, level = true, hidden = true }
-- The name row only keeps room for the icon when it sits beside the level.
local function EliteInRow(unit)
    return EliteIcon(unit) and db.eliteIcon == "level"
end

-- "hidden" only fades the icon (alpha), and only while we hide it; BBF/Blizzard still
-- show/hide and re-atlas it per target as usual.
local function SetEliteHidden(elite, hide)
    if hide and not elite.bapHidden then
        elite.bapHidden = true
        elite:SetAlpha(0)
    elseif not hide and elite.bapHidden then
        elite.bapHidden = nil
        elite:SetAlpha(1)
    end
end
-- Tint the icon with the elite border color (gold/silver or the user's picks): desaturate
-- the atlas, then color it. The atlas is bronze, which clashed with the gold border. nil r
-- = untint (only if we tinted). BBF re-sets the atlas per target; SetAtlas keeps the tint.
local function TintElite(elite, r, g, b)
    if r then
        elite.bapTinted = true
        elite:SetDesaturated(true)
        elite:SetVertexColor(r, g, b)
    elseif elite.bapTinted then
        elite.bapTinted = nil
        elite:SetDesaturated(false)
        elite:SetVertexColor(1, 1, 1)
    end
end

-- Hand back everything pinned on this unit, and undo the elite icon's fade and tint.
local function RestorePins(unit)
    local elite = EliteIcon(unit)
    if elite then
        SetEliteHidden(elite, false)
        TintElite(elite, nil)
    end
    local set = pinned[unit]
    if not set then return end
    for fs in pairs(set) do RestorePoints(fs) end
    wipe(set)
end
local SKULL_WIDTH = 11 -- BBF sizes the "??" skull 11x15

-- The "??" skull replaces the level text (Blizzard hides one and shows the other per target),
-- so the elite icon sits beside whichever is shown. Re-run when the skull shows or hides.
local function PlaceElite(unit)
    local elite = EliteIcon(unit)
    local _, level = Lookup(unit, "texts")
    local skull = SkullIcon(unit)
    local hpPos = GetBarFrames(unit)
    if not (elite and level and hpPos and (hpPos.bapRow or 0) > 0) then return end -- name row active only
    local mode = ELITE_MODES[db.eliteIcon] and db.eliteIcon or "center"
    SetEliteHidden(elite, mode == "hidden")
    local sq = squares[unit]
    if (mode == "top" or mode == "bottom" or mode == "center") and sq then
        -- Centered on the box's outer corner (or bottom middle), straddling the border.
        local outer = UNITS[unit].side == "RIGHT" and "RIGHT" or "LEFT"
        local spot = mode == "center" and "BOTTOM" or (mode == "top" and "TOP" or "BOTTOM") .. outer
        Pin(unit, elite, "CENTER", sq.box, spot, 0, 0)
        return
    end
    local anchor = skull and skull:IsShown() and skull or level
    if Mirrored(unit) then
        Pin(unit, elite, "LEFT", anchor, "RIGHT", 2, 0)
    else
        Pin(unit, elite, "RIGHT", anchor, "LEFT", -2, 0)
    end
end

local function LayoutNameRow(unit, hpPos)
    local name, level, bbfName = Lookup(unit, "texts")
    if not (name or level or bbfName) then return end
    local row = hpPos.bapRow or 0
    local combat, rest = StatusIcons(unit)
    local elite = EliteIcon(unit)
    local skull = SkullIcon(unit)
    if row <= 0 then
        RestorePins(unit) -- player/target/focus/ToT: only name-row regions are pinned on them
        return
    end
    local y = row / 2
    -- Room for the name: the row minus the level and a small gap.
    local function nameMax()
        local w = Safe(hpPos:GetWidth())
        if type(w) ~= "number" then return end
        local lw = level and level:IsShown() and TextWidth(level)
            or skull and skull:IsShown() and SKULL_WIDTH
        local bt = buildTexts[unit]
        local bw = bt and bt.bapInline and bt:IsShown() and TextWidth(bt)
        return math.max(w - 2 - (lw and lw + 4 or 0) - (bw and bw + 6 or 0) - (combat and STATUS_ICON_ROOM or 0)
            - (EliteInRow(unit) and ELITE_ROOM or 0), 10)
    end
    if Mirrored(unit) then
        Pin(unit, name,    "RIGHT", hpPos, "TOPRIGHT", -1, y, "RIGHT", nameMax)
        Pin(unit, bbfName, "RIGHT", hpPos, "TOPRIGHT", -1, y, "RIGHT", nameMax)
        Pin(unit, level,   "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT")
    else
        Pin(unit, name,    "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT", nameMax)
        Pin(unit, bbfName, "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT", nameMax)
        Pin(unit, level,   "RIGHT", hpPos, "TOPRIGHT", -1, y, "RIGHT")
    end
    -- BBF puts the skull where the portrait was (now our box's corner): it goes in the level's spot.
    if skull then
        if Mirrored(unit) then
            Pin(unit, skull, "LEFT", hpPos, "TOPLEFT", 1, y)
        else
            Pin(unit, skull, "RIGHT", hpPos, "TOPRIGHT", -1, y)
        end
    end
    if elite and level then
        PlaceElite(unit)
        if skull and not skull.bapEliteHook then
            skull.bapEliteHook = true
            hooksecurefunc(skull, "Show", function() PlaceElite(unit) end)
            hooksecurefunc(skull, "Hide", function() PlaceElite(unit) end)
            hooksecurefunc(skull, "SetShown", function() PlaceElite(unit) end)
        end
    end
    -- Status icons just after the name (whichever name text BBF shows), room reserved in nameMax.
    local shown = bbfName and bbfName:IsShown() and bbfName or name
    if shown then Pin(unit, combat, "LEFT", shown, "RIGHT", 3, 0) end
    -- The first layout runs before the box exists: the name's spot until the next one.
    local sq = squares[unit]
    if db.restIcon == "corner" and sq then
        Pin(unit, rest, "CENTER", sq.box, "TOPRIGHT", REST_CORNER_X, REST_CORNER_Y)
    elseif shown then
        Pin(unit, rest, "LEFT", shown, "RIGHT", REST_X, REST_Y)
    end
end

-- Party icons (square style). BBF's No Portrait mode put the role icon on our box's top-right
-- corner (over the box/bar border) and the disconnect icon over box and bar. Role, then
-- leader/guide, go just left of the name ("[role][crown] Name"); the disconnect icon goes in
-- the middle of the box, which is empty for an offline member. BBF centers the name in a
-- fixed-width box, so its box is fitted to the text first (kept at BBF's anchor and width
-- cap), or "left of the name" would be the box's edge. Pinned, so BBF re-anchoring them
-- (its party updates) doesn't move them back.
local function PartyNameText(unit)
    local bbfName, name = Lookup(unit, "partyName")
    if bbfName and bbfName:IsShown() then return bbfName end
    return name
end

local function LayoutPartyIcons(unit)
    local sq = squares[unit]
    if not (UNITS[unit].icons and sq) or InCombatLockdown() then return end
    local role, leader, guide, disconnect = Lookup(unit, "icons")
    Pin(unit, disconnect, "CENTER", sq.box, "CENTER", 0, 0)
    local name = PartyNameText(unit)
    if not name then return end
    if not name.bapLayout then -- fit the name's box to its text, in place
        local point, rel, relPoint, x, y = name:GetPoint(1)
        if not point or AnySecret(x, y) then return end
        Pin(unit, name, point, rel, relPoint, x, y, nil, function() return name.bapWidth end)
    end
    if role then
        Pin(unit, role, "RIGHT", name, "LEFT", -2, 0)
        Pin(unit, leader, "RIGHT", role, "LEFT", -1, 0)
        Pin(unit, guide, "RIGHT", role, "LEFT", -1, 0)
    end
end

ns.Pin = Pin
ns.Mirrored = Mirrored
ns.EliteIcon = EliteIcon
ns.EliteInRow = EliteInRow
ns.ELITE_ROOM = ELITE_ROOM
ns.TintElite = TintElite
ns.RestorePins = RestorePins
ns.REST_MODES = REST_MODES
ns.LayoutNameRow = LayoutNameRow
ns.LayoutPartyIcons = LayoutPartyIcons
