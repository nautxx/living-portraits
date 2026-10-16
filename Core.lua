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
--
-- Square style (when BBF's No Portrait / Pixel Border mode is on): a square box with
-- BBF's 1px black border sits beside the health/mana bars and the model fills it exactly.
-- No masking needed. Falls back to the circle style when BBF still shows portraits.

local ADDON_NAME, ns = ...

local PARTY = { "party1", "party2", "party3", "party4" }
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local VIGNETTE = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\vignette"
local VIGNETTE_EDGE = 0.72 -- radius of the crisp circle edge baked into vignette.tga (fraction of the texture)

-- Bump when a default changes in a way saved settings should pick up (see MigrateSettings).
local SETTINGS_VERSION = 6

local defaults = {
    enabled  = true,
    style    = "square", -- "square" (needs BBF No Portrait / Pixel Border) or "circle"
    zoom     = 1,     -- 0..1, 1 = head & shoulders
    squareGap   = 3,  -- px between the box and the bars
    -- Square: px added to the health+mana stack; the box spans health top to mana bottom,
    -- so a taller stack means a bigger box that stays aligned with the bars.
    stackExtra  = { large = 10, small = 6 },
    hpShare     = 0.66, -- square: health bar's share of the stack (mana gets the rest)
    -- Square: px at the top of the box for the name + level row (health starts below it).
    nameRow     = { large = 12, small = 0 },
    alignMana   = true, -- square: line the mana bar's edge up with the health bar on the box side
    vignette = true,
    bgR = 0.05, bgG = 0.05, bgB = 0.07,
    -- inset (circle style): model square as a fraction of the portrait. 0.84 keeps the
    --        square's corners under the ring's outer edge; the crisp circle edge follows it.
    -- cam:   camera distance (lower = closer = bigger face)
    sizes = {
        large  = { inset = 0.84, cam = 0.85 },
        small  = { inset = 0.84, cam = 0.85 },
        square = { inset = 1,    cam = 0.9 },
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

-- Square style: the health/mana bars BBF frames in No Portrait / Pixel Border mode.
local function TargetBars(frame)
    local m = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
    return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar, m and m.ManaBar
end
local BARS = {
    player = function()
        local m = PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
        return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar, m and m.ManaBarArea and m.ManaBarArea.ManaBar
    end,
    target       = function() return TargetBars(TargetFrame) end,
    focus        = function() return TargetBars(FocusFrame) end,
    targettarget = function() local f = TargetFrame and TargetFrame.totFrame; return f and f.HealthBar, f and f.ManaBar end,
    focustarget  = function() local f = FocusFrame and FocusFrame.totFrame;   return f and f.HealthBar, f and f.ManaBar end,
}
for i, unit in ipairs(PARTY) do
    BARS[unit] = function()
        local f = PartyFrame and PartyFrame["MemberFrame" .. i]
        return f and f.HealthBarContainer and f.HealthBarContainer.HealthBar, f and f.ManaBar
    end
end
-- The unit frame itself. Square boxes are parented here, never via the portrait:
-- BBF's No Portrait mode moves portraits/containers into a hidden frame.
local UNIT_FRAMES = {
    player       = function() return PlayerFrame end,
    target       = function() return TargetFrame end,
    focus        = function() return FocusFrame end,
    targettarget = function() return TargetFrame and TargetFrame.totFrame end,
    focustarget  = function() return FocusFrame and FocusFrame.totFrame end,
}
for i, unit in ipairs(PARTY) do
    UNIT_FRAMES[unit] = function() return PartyFrame and PartyFrame["MemberFrame" .. i] end
end

-- Which side of the bars the box goes on (where the round portrait used to be).
local SQUARE_SIDE = { target = "RIGHT", focus = "RIGHT" } -- everything else: LEFT

-- Name and level text for the name row (large frames only).
local function AsText(x) return type(x) == "table" and x.SetPoint and x or nil end
-- Returns Blizzard's name, the level, and BBF's replacement name (bbfName). BBF lays
-- bbfName out on its own for these frames, so both names get pinned.
local function TargetTexts(frame)
    local m = frame and frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
    return AsText(m and m.Name), AsText(m and m.LevelText), AsText(frame and frame.bbfName)
end
local NAME_TEXTS = {
    player = function()
        local name = PlayerFrame and (AsText(PlayerFrame.name) or AsText(PlayerFrame.Name))
        return name or AsText(PlayerName), AsText(PlayerLevelText), AsText(PlayerFrame and PlayerFrame.bbfName)
    end,
    target = function() return TargetTexts(TargetFrame) end,
    focus  = function() return TargetTexts(FocusFrame) end,
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
local lastScale = {} -- unit -> unit frame's effective scale at the last refresh

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

-- Saved settings keep old values over new defaults, so reset what changed between versions.
local function MigrateSettings()
    local version = db.version or 1
    if version < 2 then
        db.inset, db.bgInset = nil, nil -- v1 single-size settings
        db.sizes = nil                  -- v2: model fills the circle (inset 0.82 -> 1.0)
    end
    if version < 6 then
        db.manaExtra = nil              -- v6: extra height is split between health and mana
    end
    if version < 5 then
        db.squareExtra = nil            -- v5: box no longer grows upward; mana bars grow instead
    end
    if version < 4 then
        db.sizes = nil                  -- v3/v4: crisp circle edge (inset 0.72 -> 0.84), square size added
    end
    db.version = SETTINGS_VERSION
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

-- Square style -------------------------------------------------------------

-- BBF's bar frames for the unit: the pixel-border position frames when present.
local function GetBarFrames(unit)
    local getter = BARS[unit]
    if not getter then return end
    local hp, mana = getter()
    if not hp then return end
    if mana and not mana:IsShown() then mana = nil end -- BBF can hide the mana bar
    return hp.BBFPositionFrame or hp, mana and (mana.BBFPositionFrame or mana), mana, hp
end

local function SetPixelPoint(region, point, rel, relPoint, x, y)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(region, point, rel, relPoint, x, y)
    else
        region:SetPoint(point, rel, relPoint, x, y)
    end
end

-- Same recipe as BBF's pixel border: four 1px black edges just outside the frame.
local function CreatePixelBorder(frame)
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER", nil, 4)
        t:SetColorTexture(0, 0, 0, 1)
        if PixelUtil and PixelUtil.SetHeight then
            if i % 2 == 1 then PixelUtil.SetHeight(t, 1, 1) else PixelUtil.SetWidth(t, 1, 1) end
        elseif i % 2 == 1 then t:SetHeight(1) else t:SetWidth(1) end
        edges[i] = t
    end
    local top, right, bottom, left = edges[1], edges[2], edges[3], edges[4]
    SetPixelPoint(top,    "BOTTOMLEFT",  frame, "TOPLEFT",     -1, 0)
    SetPixelPoint(top,    "BOTTOMRIGHT", frame, "TOPRIGHT",     1, 0)
    SetPixelPoint(bottom, "TOPLEFT",     frame, "BOTTOMLEFT",  -1, 0)
    SetPixelPoint(bottom, "TOPRIGHT",    frame, "BOTTOMRIGHT",  1, 0)
    SetPixelPoint(left,   "TOPRIGHT",    frame, "TOPLEFT",      0, 1)
    SetPixelPoint(left,   "BOTTOMRIGHT", frame, "BOTTOMLEFT",   0, -1)
    SetPixelPoint(right,  "TOPLEFT",     frame, "TOPRIGHT",     0, 1)
    SetPixelPoint(right,  "BOTTOMLEFT",  frame, "BOTTOMRIGHT",  0, -1)
    return edges
end

local squares = {} -- unit -> square record

local function CreateSquare(unit, unitFrame)
    local box = CreateFrame("Frame", nil, unitFrame)
    box:Hide()
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    CreatePixelBorder(box)
    local model = CreateFrame("PlayerModel", nil, box)
    model:SetAllPoints(box)
    model:SetScript("OnModelLoaded", function(self) ApplyCamera(self, "square") end)
    local sq = { unit = unit, box = box, bg = bg, model = model, unitFrame = unitFrame }
    -- Mirror Blizzard's portrait fading (party out of range) even though BBF hid the portrait.
    local portrait = PORTRAITS[unit] and PORTRAITS[unit]()
    if portrait then
        box:SetAlpha(Safe(portrait:GetAlpha()) or 1)
        hooksecurefunc(portrait, "SetAlpha", function(_, alpha) box:SetAlpha(Safe(alpha) or 1) end)
    end
    squares[unit] = sq
    return sq
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
    bar.bapDX = 0
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

local function LayoutBars(unit, hpPos, manaPos, manaBar, hpBar)
    if not (hpBar and manaPos and manaBar) or InCombatLockdown() then return end
    Remember(hpBar, hpPos)
    Remember(manaBar, manaPos)
    if not (hpBar.bapOrig and manaBar.bapOrig) then return end

    -- Heights: grow the stack, reserve the name row at the top, and split the rest
    -- hpShare / rest (measured on BBF's frames).
    local size = SIZE_OF[unit]
    local row = db.nameRow[size] or 0
    local total = hpPos.bapBaseH + manaPos.bapBaseH + (db.stackExtra[size] or 0)
    local bars = total - row
    local hpH = math.floor(bars * db.hpShare + 0.5)
    local dhHp = hpH - hpPos.bapBaseH
    local dhMana = (bars - hpH) - manaPos.bapBaseH

    SetBarLayout(hpBar, hpPos, dhHp, 0, -row) -- health starts below the name row
    hpPos.bapRow = row

    -- The mana bar moves down by however much the health bar grew, unless it's anchored
    -- to the health bar itself (it follows automatically, e.g. target-of-target).
    local follows = manaBar.bapOrig[2] == hpBar
    local dy = follows and 0 or -(dhHp + row)

    if db.alignMana then
        local a, b
        if SQUARE_SIDE[unit] == "RIGHT" then a, b = hpPos:GetRight(), manaPos:GetRight()
        else a, b = hpPos:GetLeft(), manaPos:GetLeft() end
        if a and b and math.abs(a - b) >= 0.5 then
            manaBar.bapDX = manaBar.bapDX + (a - b) * hpPos:GetEffectiveScale() / manaBar:GetEffectiveScale()
        end
    else
        manaBar.bapDX = 0
    end
    SetBarLayout(manaBar, manaPos, dhMana, manaBar.bapDX, dy)
end

-- Move each bar text vertically to the middle of its bar (BBF's offsets were tuned for the
-- original thin bars). Horizontal placement is left to BBF.
local function CenterTexts(holder, keys, pos)
    if not holder then return end
    local _, posY = pos:GetCenter()
    if not posY then return end
    for _, key in ipairs(keys) do
        local fs = holder[key]
        if type(fs) == "table" and fs.GetCenter and fs:GetNumPoints() == 1 then
            local _, fsY = fs:GetCenter()
            local point, rel, relPoint, x, y = fs:GetPoint(1)
            if fsY and point then
                if not fs.bapOrig then fs.bapOrig = { point, rel, relPoint, x or 0, y or 0 } end
                local ps = pos:GetEffectiveScale() or 1
                local fsScale = fs.GetEffectiveScale and fs:GetEffectiveScale() or ps
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
    bar:SetPoint(o[1], o[2], o[3], o[4], o[5])
    bar.bapDX = 0
end

-- Name row: name and level on one line above the health bar, inside the box's height.
-- Player: name left, level right. Target/focus (box on the right): mirrored.
local function SavePoints(fs)
    if fs.bapPoints then return end
    local pts = {}
    for i = 1, fs:GetNumPoints() do pts[i] = { fs:GetPoint(i) } end
    fs.bapPoints = pts
    fs.bapJustify = fs.GetJustifyH and fs:GetJustifyH()
end

local function RestorePoints(fs)
    if not (fs and fs.bapPoints) then return end
    fs.bapLayout = nil
    fs:ClearAllPoints()
    for _, pt in ipairs(fs.bapPoints) do fs:SetPoint(unpack(pt)) end
    if fs.bapJustify then fs:SetJustifyH(fs.bapJustify) end
    fs.bapPoints = nil
end

-- Anchor a text to the name row and keep it there if BBF/Blizzard moves it later.
local function PinText(fs, point, rel, relPoint, x, y, justify)
    if not fs then return end
    SavePoints(fs)
    fs.bapLayout = { point, rel, relPoint, x, y, justify }
    local function Apply(self)
        local l = self.bapLayout
        if not l or self.bapApplying then return end
        self.bapApplying = true
        self:ClearAllPoints()
        self:SetPoint(l[1], l[2], l[3], l[4], l[5])
        if l[6] and self.SetJustifyH then self:SetJustifyH(l[6]) end
        self.bapApplying = nil
    end
    if not fs.bapPinHook then
        fs.bapPinHook = true
        hooksecurefunc(fs, "SetPoint", Apply)
        if fs.SetJustifyH then hooksecurefunc(fs, "SetJustifyH", Apply) end
    end
    Apply(fs)
end

local function LayoutNameRow(unit, hpPos)
    local getter = NAME_TEXTS[unit]
    if not getter then return end
    local name, level, bbfName = getter()
    local row = hpPos.bapRow or 0
    if row <= 0 then
        RestorePoints(name); RestorePoints(level); RestorePoints(bbfName)
        return
    end
    local y = row / 2
    if SQUARE_SIDE[unit] == "RIGHT" then
        PinText(name,    "RIGHT", hpPos, "TOPRIGHT", -1, y, "RIGHT")
        PinText(bbfName, "RIGHT", hpPos, "TOPRIGHT", -1, y, "RIGHT")
        PinText(level,   "LEFT",  hpPos, "TOPLEFT",   1, y, nil)
    else
        PinText(name,    "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT")
        PinText(bbfName, "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT")
        PinText(level,   "RIGHT", hpPos, "TOPRIGHT", -1, y, nil)
    end
end

-- Put the bars and texts back exactly as BBF/Blizzard had them.
local function RestoreBars(unit)
    if InCombatLockdown() then return end
    local hpPos, manaPos, manaBar, hpBar = GetBarFrames(unit)
    if not hpBar then return end
    RestoreBar(hpBar, hpPos)
    RestoreBar(manaBar, manaPos)
    RestoreTexts(hpBar, HP_TEXT_KEYS)
    RestoreTexts(hpBar:GetParent(), HP_TEXT_KEYS)
    RestoreTexts(manaBar, MANA_TEXT_KEYS)
    hpPos.bapRow = nil
    local getter = NAME_TEXTS[unit]
    if getter then
        local name, level, bbfName = getter()
        RestorePoints(name); RestorePoints(level); RestorePoints(bbfName)
    end
end

-- Anchor the box beside the bars; height spans the health bar top to the mana bar bottom.
-- Returns false if the bars haven't been laid out yet.
local function PlaceSquare(sq, hpPos, manaPos)
    local box = sq.box
    local bottomRef = manaPos or hpPos
    local top, bottom = hpPos:GetTop(), bottomRef:GetBottom()
    if not top or not bottom then return false end
    local row = hpPos.bapRow or 0 -- the name row sits above the health bar, inside the box
    local scale = hpPos:GetEffectiveScale() / box:GetEffectiveScale()
    local size = (top + row - bottom) * scale
    if size <= 0 then return false end

    box:ClearAllPoints()
    if SQUARE_SIDE[sq.unit] == "RIGHT" then
        box:SetPoint("TOPLEFT", hpPos, "TOPRIGHT", db.squareGap, row)
    else
        box:SetPoint("TOPRIGHT", hpPos, "TOPLEFT", -db.squareGap, row)
    end
    box:SetSize(size, size)
    box:SetFrameStrata(hpPos:GetFrameStrata())
    box:SetFrameLevel(hpPos:GetFrameLevel())
    return true
end

local function DeactivateSquare(unit)
    if squares[unit] then squares[unit].box:Hide() end
end

local function ActivateSquare(unit, unitFrame, hpPos, manaPos)
    local sq = squares[unit] or CreateSquare(unit, unitFrame)
    if not PlaceSquare(sq, hpPos, manaPos) then
        sq.box:Hide()
        return false
    end
    sq.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, 1)
    sq.model:ClearModel()
    sq.model:SetUnit(unit)
    ApplyCamera(sq.model, "square")
    sq.box:Show()
    return true
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
    vignette:SetPoint("CENTER", portrait, "CENTER")
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
    -- Remember the scale: the 3D camera framing is computed for the current size, so a
    -- scale change (Edit Mode, UI scale) needs a refresh. See Tick().
    local uf = UNIT_FRAMES[unit] and UNIT_FRAMES[unit]()
    lastScale[unit] = uf and uf:GetEffectiveScale()
    local function HideAll()
        if p then Deactivate(p) end
        DeactivateSquare(unit)
        RestoreBars(unit)
    end

    local unitFrame = UNIT_FRAMES[unit] and UNIT_FRAMES[unit]()
    if not db.units[unit] or not db.enabled or not unitFrame or not unitFrame:IsVisible()
       or not UnitExists(unit)
       or Safe(UnitIsVisible(unit)) == false or Safe(UnitIsConnected(unit)) == false then
        HideAll()
        lastState[unit] = UnitState(unit)
        return
    end

    -- Square style: where BBF has removed the round portrait.
    if BBFHidesPortrait(unit) then
        if p then Deactivate(p) end
        local hpPos, manaPos, manaBar, hpBar = GetBarFrames(unit)
        if db.style == "square" and hpPos then
            LayoutBars(unit, hpPos, manaPos, manaBar, hpBar)
            if not ActivateSquare(unit, unitFrame, hpPos, manaPos) then
                C_Timer.After(0.5, function() Refresh(unit) end) -- bars not laid out yet
                return
            end
            -- Once the resized bars have been laid out: re-measure the box, center the texts.
            C_Timer.After(0, function()
                PlaceSquare(squares[unit], hpPos, manaPos)
                CenterBarTexts(hpPos, manaPos, manaBar, hpBar)
                if not InCombatLockdown() then LayoutNameRow(unit, hpPos) end
            end)
        else
            DeactivateSquare(unit)
            RestoreBars(unit)
        end
        lastState[unit] = UnitState(unit)
        return
    end

    -- Circle style
    DeactivateSquare(unit)
    RestoreBars(unit)
    p = p or CreateLayers(unit)
    if not p or not p.container:IsVisible() then
        if p then Deactivate(p) end
        lastState[unit] = UnitState(unit)
        return
    end
    local w, h = p.portrait:GetSize()
    local s = db.sizes[p.size]
    p.model:SetSize(w * s.inset, h * s.inset)
    -- Scale the vignette so its circle edge lands on the model's straight edges.
    -- Capped at the portrait size so its dark band never spills past the ring.
    local vscale = math.min(s.inset / VIGNETTE_EDGE, 1)
    p.vignette:SetSize(w * vscale, h * vscale)
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

-- Catches changes with no reliable event: ToT swaps, party range/visibility, and frame
-- scale changes (Edit Mode / UI scale) that leave the 3D camera framed for the old size.
local function ScaleChanged(unit)
    local uf = UNIT_FRAMES[unit] and UNIT_FRAMES[unit]()
    local scale = uf and uf:GetEffectiveScale()
    local last = lastScale[unit]
    return scale and last and math.abs(scale - last) > 0.001
end

local function Tick()
    if not (db and db.enabled) then return end
    for unit in pairs(PORTRAITS) do
        if db.units[unit] and (lastState[unit] ~= UnitState(unit) or ScaleChanged(unit)) then
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
        MigrateSettings()
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
        self:RegisterEvent("UI_SCALE_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        if EditModeManagerFrame then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() C_Timer.After(0.1, RefreshAll) end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- small delay so BBF finishes resizing portraits first
        C_Timer.After(0.5, RefreshAll)
        if not ns.ticker then ns.ticker = C_Timer.NewTicker(0.5, Tick) end
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        C_Timer.After(0.1, RefreshAll)
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
        .. "  style=" .. db.style .. "  zoom=" .. db.zoom .. "  vignette=" .. tostring(db.vignette)
        .. "  units=" .. (#on > 0 and table.concat(on, ",") or "none"))
    local Q = db.sizes.square
    print(("  circle large: inset=%.2f cam=%.2f   small: inset=%.2f cam=%.2f"):format(L.inset, L.cam, S.inset, S.cam))
    print(("  square: cam=%.2f gap=%d alignmana=%s split=%.2f  extend: large=%d small=%d"):format(
        Q.cam, db.squareGap, tostring(db.alignMana), db.hpShare, db.stackExtra.large, db.stackExtra.small))
end

local function PrintHelp()
    print("  /bap toggle  |  /bap vignette  |  /bap zoom 0-1  |  /bap reset")
    print("  /bap style square|circle  |  /bap extend 0-30 [large|small]  |  /bap split 0.4-0.85")
    print("  /bap namerow 0-24 [large|small]  |  /bap gap 0-20  |  /bap alignmana")
    print("  /bap inset 0.3-1.2 [large|small]  |  /bap cam 0.3-2 [large|small|square]")
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
    elseif cmd == "style" and (arg == "square" or arg == "circle") then
        db.style = arg
    elseif cmd == "extend" and val then
        val = math.max(0, math.min(30, val))
        for name in pairs(db.stackExtra) do
            if not size or size == name then db.stackExtra[name] = val end
        end
    elseif cmd == "namerow" and val then
        val = math.max(0, math.min(24, val))
        for name in pairs(db.nameRow) do
            if not size or size == name then db.nameRow[name] = val end
        end
    elseif cmd == "split" and val then
        db.hpShare = math.max(0.4, math.min(0.85, val))
    elseif cmd == "alignmana" then
        db.alignMana = not db.alignMana
    elseif cmd == "gap" and val then
        db.squareGap = math.max(0, math.min(20, val))
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
        wipe(db); CopyDefaults(defaults, db); db.version = SETTINGS_VERSION
    else
        PrintStatus()
        PrintHelp()
        return
    end
    RefreshAll()
    PrintStatus()
end
