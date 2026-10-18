-- Box style: BBF's health/mana bars (layout, text centering) and pixel border helpers.

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local Safe = ns.Safe
local IsSecret = ns.IsSecret
local Clamp = ns.Clamp

-- BBF's bar frames for the unit: the pixel-border position frames when present.
local function GetBarFrames(unit)
    local hp, mana = Lookup(unit, "bars")
    if not hp then return end
    local manaPos = mana and (mana.BBFPositionFrame or mana)
    -- Units with no power (most NPCs): Blizzard hides the mana bar, but BBF keeps its empty
    -- slot (border + background) on screen, so lay that out like a normal mana bar. If BBF
    -- hides the slot too (its "hide mana" option), there's no mana row at all.
    if mana and not mana:IsShown() and not (manaPos ~= mana and manaPos:IsVisible()) then
        manaPos = nil
    end
    return hp.BBFPositionFrame or hp, manaPos, mana, hp
end

local function SetPixelPoint(region, point, rel, relPoint, x, y)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(region, point, rel, relPoint, x, y)
    else
        region:SetPoint(point, rel, relPoint, x, y)
    end
end

-- Same recipe as BBF's pixel border: four 1px black edges just outside the frame.
-- Border thickness in UI units: thin 1, medium 2, heavy 3 (/lp bordersize).
local BORDER_SIZES = { thin = 1, medium = 2, heavy = 3 }
local function BorderSize()
    return Clamp(math.floor((db and db.borderSize or 1) + 0.5), 1, 3)
end

-- Size and anchor a border's four edges (top, right, bottom, left) just outside frame.
-- Top and bottom span the corners and the sides fit between them, so each corner is drawn
-- once (drawn twice, corners looked darker at partial opacity). `bbf` reproduces BBF's
-- own geometry (1px, sides spanning the corners too), for handing its bars back.
local function LayoutEdges(edges, frame, size, bbf)
    if type(edges) ~= "table" or not frame then return end
    local top, right, bottom, left = edges[1], edges[2], edges[3], edges[4]
    if not (top and right and bottom and left) then return end
    for i, t in ipairs(edges) do
        if PixelUtil and PixelUtil.SetHeight then
            if i % 2 == 1 then PixelUtil.SetHeight(t, size, size) else PixelUtil.SetWidth(t, size, size) end
        elseif i % 2 == 1 then t:SetHeight(size) else t:SetWidth(size) end
        t:ClearAllPoints()
    end
    local side = bbf and size or 0
    SetPixelPoint(top,    "BOTTOMLEFT",  frame, "TOPLEFT",     -size, 0)
    SetPixelPoint(top,    "BOTTOMRIGHT", frame, "TOPRIGHT",     size, 0)
    SetPixelPoint(bottom, "TOPLEFT",     frame, "BOTTOMLEFT",  -size, 0)
    SetPixelPoint(bottom, "TOPRIGHT",    frame, "BOTTOMRIGHT",  size, 0)
    SetPixelPoint(left,   "TOPRIGHT",    frame, "TOPLEFT",      0, side)
    SetPixelPoint(left,   "BOTTOMRIGHT", frame, "BOTTOMLEFT",   0, -side)
    SetPixelPoint(right,  "TOPLEFT",     frame, "TOPRIGHT",     0, side)
    SetPixelPoint(right,  "BOTTOMLEFT",  frame, "BOTTOMRIGHT",  0, -side)
end

local function CreatePixelBorder(frame)
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER", nil, 4)
        t:SetColorTexture(0, 0, 0, 1)
        edges[i] = t
    end
    LayoutEdges(edges, frame, BorderSize())
    return edges
end

-- Bar layout (square style) ------------------------------------------------
-- The health+mana stack grows by stackExtra[size] px, split hpShare / rest, so the box
-- (health top to mana bottom) gets bigger while staying aligned with the bars.
-- Blizzard's target/focus mana bar also sits ~8px left of the health bar (it followed the
-- old portrait's curve); alignMana lines its edge up with the health bar on the box side.
-- Everything is reversible: original anchors and heights are stored on first touch.
-- Out of combat only: moving or resizing unit-frame parts in combat is restricted.

local HP_TEXT_KEYS   = { "HealthBarText", "CenterText", "TextString", "LeftText", "RightText", "DeadText", "UnconsciousText" }
local MANA_TEXT_KEYS = { "ManaBarText", "CenterText", "TextString", "LeftText", "RightText" }

local function Remember(bar, pos)
    if bar.bapOrig then return end
    local point, rel, relPoint, x, y = bar:GetPoint(1)
    if not point then return end
    bar.bapOrig = { point, rel, relPoint, x or 0, y or 0 }
    bar.bapBaseH = bar:GetHeight()
    pos.bapBaseH = pos:GetHeight()
    pos.bapBaseW = pos:GetWidth()
    bar.bapDX = 0
    bar.bapDY = 0
end

-- Set a bar's height (bar carries the fill; BBF's posFrame carries border, background and
-- mask) and re-anchor it so its top edge stays put, then move it by (dx, dy).
local function SetBarLayout(bar, pos, dh, dx, dy)
    local o = bar.bapOrig
    bar:SetHeight(bar.bapBaseH + dh)
    if pos ~= bar then pos:SetHeight(pos.bapBaseH + dh) end
    local keepTop = 0
    if o[1]:find("BOTTOM") then keepTop = -dh
    elseif not o[1]:find("TOP") then keepTop = -dh / 2 end
    bar:SetPoint(o[1], o[2], o[3], o[4] + dx, o[5] + keepTop + dy)
end

-- Width of the border line that neighbors share (box and bars, health and mana). At full
-- opacity it's a 1px black line between them. Below that it would show the world through
-- a 1px slot (BBF's fills overhang their borders differently per frame, so some frames
-- covered it and some didn't), so the pieces close up and the faint line is drawn over
-- the bars instead.
local function SharedLine()
    return (db.borderAlpha or 1) >= 1 and BorderSize() or 0
end

local function BoxGap()
    if db.squareGap < 1 then return db.squareGap end
    return db.squareGap - 1 + SharedLine()
end

local function LayoutBars(unit, hpPos, manaPos, manaBar, hpBar)
    if not hpBar or InCombatLockdown() then return end
    Remember(hpBar, hpPos)
    if manaPos and manaBar then Remember(manaBar, manaPos) end
    if not hpBar.bapOrig then return end
    local hasMana = manaPos and manaBar and manaBar.bapOrig

    -- Heights: grow the stack, reserve the name row at the top, and split the rest
    -- hpShare / rest (measured on BBF's frames). Without a mana row, health takes it all.
    local size = UNITS[unit].size
    local row = db.nameRow[UNITS[unit].row] or 0
    -- Keep the box size even without a mana row: use mana's remembered base height.
    local manaSlot = manaPos or (manaBar and manaBar.BBFPositionFrame)
    local manaBase = (manaSlot and manaSlot.bapBaseH) or 0
    local total = hpPos.bapBaseH + manaBase + (db.stackExtra[size] or 0)
    local bars = total - row
    local hpH = hasMana and math.floor(bars * db.hpShare + 0.5) or bars
    local dhHp = hpH - hpPos.bapBaseH

    SetBarLayout(hpBar, hpPos, dhHp, 0, -row) -- health starts below the name row
    hpPos.bapRow = row
    if not hasMana then return end
    local dhMana = (bars - hpH) - manaPos.bapBaseH

    -- The mana bar moves down by however much the health bar grew, unless it's anchored
    -- to the health bar itself (it follows automatically, e.g. target-of-target).
    local follows = manaBar.bapOrig[2] == hpBar
    local dy = follows and 0 or -(dhHp + row)

    local toMana = hpPos:GetEffectiveScale() / manaBar:GetEffectiveScale()
    if db.alignMana then
        -- Same width as the health bar's border, edges lined up on the box side.
        local hpW = Safe(hpPos:GetWidth())
        if manaPos ~= manaBar and hpW then manaPos:SetWidth(hpW * toMana) end
        local a, b
        if UNITS[unit].side == "RIGHT" then a, b = Safe(hpPos:GetRight()), Safe(manaPos:GetRight())
        else a, b = Safe(hpPos:GetLeft()), Safe(manaPos:GetLeft()) end
        if a and b and math.abs(a - b) >= 0.25 then
            manaBar.bapDX = manaBar.bapDX + (a - b) * toMana
        end
    else
        manaBar.bapDX = 0
        if manaPos ~= manaBar and manaPos.bapBaseW then manaPos:SetWidth(manaPos.bapBaseW) end
    end
    SetBarLayout(manaBar, manaPos, dhMana, manaBar.bapDX, dy + manaBar.bapDY)

    -- Put mana directly under health, measured after layout so it's exact whatever offsets
    -- BBF uses: the borders share one line (barSpacing 0). BBF's ToT leaves a gap otherwise.
    local hpBottom, manaTop = Safe(hpPos:GetBottom()), Safe(manaPos:GetTop())
    if hpBottom and manaTop then
        local shift = ((hpBottom - SharedLine() - db.barSpacing) - manaTop) * toMana
        if math.abs(shift) >= 0.25 then
            manaBar.bapDY = manaBar.bapDY + shift
            SetBarLayout(manaBar, manaPos, dhMana, manaBar.bapDX, dy + manaBar.bapDY)
        end
    end
end

-- Move each bar text vertically to the middle of its bar (BBF's offsets were tuned for the
-- original thin bars). Horizontal placement is left to BBF.
-- In PvP a text showing secret health is secret too, and so is its position: skip it.
local function CenterTexts(holder, keys, pos)
    if not holder then return end
    local _, posY = pos:GetCenter()
    posY = Safe(posY)
    if not posY then return end
    for _, key in ipairs(keys) do
        local fs = holder[key]
        if type(fs) == "table" and fs.GetCenter and fs:GetNumPoints() == 1 then
            local _, fsY = fs:GetCenter()
            fsY = Safe(fsY)
            local point, rel, relPoint, x, y = fs:GetPoint(1)
            if fsY and point and not IsSecret(x) and not IsSecret(y) then
                if not fs.bapOrig then fs.bapOrig = { point, rel, relPoint, x or 0, y or 0 } end
                local ps = Safe(pos:GetEffectiveScale()) or 1
                local fsScale = fs.GetEffectiveScale and Safe(fs:GetEffectiveScale()) or ps
                local diff = (posY * ps - fsY * fsScale) / fsScale
                if math.abs(diff) >= 0.25 then
                    fs:SetPoint(point, rel, relPoint, x or 0, (y or 0) + diff)
                end
            end
        end
    end
end

local function CenterBarTexts(hpPos, manaPos, manaBar, hpBar)
    if InCombatLockdown() or not hpBar then return end
    local hpHolder = hpBar:GetParent()
    CenterTexts(hpBar, HP_TEXT_KEYS, hpPos)
    if hpHolder and hpHolder ~= hpBar then CenterTexts(hpHolder, HP_TEXT_KEYS, hpPos) end
    if manaBar and manaPos then CenterTexts(manaBar, MANA_TEXT_KEYS, manaPos) end
end

local function RestoreTexts(holder, keys)
    if not holder then return end
    for _, key in ipairs(keys) do
        local fs = holder[key]
        if type(fs) == "table" and fs.bapOrig then
            local o = fs.bapOrig
            fs:SetPoint(o[1], o[2], o[3], o[4], o[5])
            fs.bapOrig = nil
        end
    end
end

local function RestoreBar(bar, pos)
    if not (bar and bar.bapOrig) then return end
    local o = bar.bapOrig
    bar:SetHeight(bar.bapBaseH)
    if pos and pos ~= bar and pos.bapBaseH then pos:SetHeight(pos.bapBaseH) end
    if pos and pos ~= bar and pos.bapBaseW then pos:SetWidth(pos.bapBaseW) end
    bar:SetPoint(o[1], o[2], o[3], o[4], o[5])
    bar.bapDX = 0
    bar.bapDY = 0
end

-- Border color helpers (ApplyBorders is in box.lua).
-- ARGB hex (the settings color swatch's format) -> r, g, b.
local function HexRGB(hex, fallback)
    if type(hex) ~= "string" or #hex ~= 8 then hex = fallback end
    local function c(i) return (tonumber(hex:sub(i, i + 1), 16) or 0) / 255 end
    return c(3), c(5), c(7)
end

local function BorderRGBA()
    local r, g, b = HexRGB(db.borderColor, "ff000000")
    return r, g, b, db.borderAlpha or 1
end

local function ColorEdges(edges, r, g, b, a, hideA, hideB)
    if type(edges) ~= "table" then return end
    for i, t in ipairs(edges) do
        if t.SetColorTexture then
            t:SetColorTexture(r, g, b, a)
            t:SetShown(i ~= hideA and i ~= hideB)
        end
    end
end

-- BBF's look: black, 1px, every edge shown.
local function RestoreBorders(manaBar, hpBar)
    LayoutEdges(hpBar and hpBar.BBFBlackBorder, hpBar and hpBar.BBFPositionFrame, 1, true)
    LayoutEdges(manaBar and manaBar.BBFBlackBorder, manaBar and manaBar.BBFPositionFrame, 1, true)
    ColorEdges(hpBar and hpBar.BBFBlackBorder, 0, 0, 0, 1)
    ColorEdges(manaBar and manaBar.BBFBlackBorder, 0, 0, 0, 1)
end

ns.GetBarFrames = GetBarFrames
ns.BORDER_SIZES = BORDER_SIZES
ns.BorderSize = BorderSize
ns.LayoutEdges = LayoutEdges
ns.CreatePixelBorder = CreatePixelBorder
ns.HP_TEXT_KEYS = HP_TEXT_KEYS
ns.MANA_TEXT_KEYS = MANA_TEXT_KEYS
ns.BoxGap = BoxGap
ns.LayoutBars = LayoutBars
ns.CenterBarTexts = CenterBarTexts
ns.RestoreTexts = RestoreTexts
ns.RestoreBar = RestoreBar
ns.HexRGB = HexRGB
ns.BorderRGBA = BorderRGBA
ns.ColorEdges = ColorEdges
ns.RestoreBorders = RestoreBorders
