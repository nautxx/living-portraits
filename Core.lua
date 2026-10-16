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
local CORNERS  = "Interface\\AddOns\\" .. ADDON_NAME .. "\\media\\corners"
-- vignette.tga is the soft round edge (fades in over the last 12% of the radius, clear
-- outside the circle); corners.tga covers only what's outside the circle. Both are sized
-- like the model. The corners follow circleBg: with a clear background, dark corners
-- would show as a square, so they fade out with it.

-- Bump when a default changes in a way saved settings should pick up (see MigrateSettings).
local SETTINGS_VERSION = 10

local defaults = {
    enabled  = true,
    style    = "square", -- "square" (needs BBF No Portrait / Pixel Border) or "circle"
    zoom     = 1,     -- 0..1, 1 = head & shoulders
    circleBg    = 1,  -- circle: opacity of the dark background inside the ring (0 = clear)
    squareBg    = 0,  -- square: opacity of the dark background behind the model (0 = none)
    squareGap   = 1,  -- px between the box and the bars (1 = their borders share one line)
    barSpacing  = 0,  -- px between health and mana (0 = their borders share one line)
    -- Square: px added to the health+mana stack; the box spans health top to mana bottom,
    -- so a taller stack means a bigger box that stays aligned with the bars.
    stackExtra  = { large = 10, small = 6 },
    hpShare     = 0.66, -- square: health bar's share of the stack (mana gets the rest)
    -- Square: px at the top of the box for the name + level row (health starts below it).
    -- Groups: large = player/target/focus, tot = target-of-target/focus-target, party.
    nameRow     = { large = 12, tot = 9, party = 0 },
    alignMana   = true, -- square: line the mana bar's edge up with the health bar on the box side
    growBars    = true, -- new target: health and mana grow from empty to their value
    growTime    = 0.35, -- seconds the grow takes (/bap growtime)
    vignette = true,
    calibrate = false, -- circle: tint the edge red to line it up with the ring (/bap calibrate)
    -- Circle: per-frame nudge (px) of the portrait inside its ring. Measured in game with
    -- /bap calibrate (Blizzard's portrait textures aren't exactly centered on their rings).
    offsets = {
        player = { -0.5, 0.6 },
        target = { 0.6, 0.3 },
        focus  = { 0.6, 0.3 }, -- same frame design as target
        tot    = { -1.3, 2.2 },
        party  = { 0, 0 },     -- not measured yet
    },
    bgR = 0.05, bgG = 0.05, bgB = 0.07,
    -- inset (circle style): model square as a fraction of the portrait. 0.84 keeps the
    --        square's corners under the ring's outer edge; the crisp circle edge follows it.
    -- cam:   camera distance (lower = closer = bigger face)
    sizes = {
        large  = { inset = 0.80, cam = 0.85 },
        small  = { inset = 0.80, cam = 0.85 },
        square = { inset = 1,    cam = 0.9 },
    },
    units = {
        player = true,
        target = true, focus = true,
        targettarget = true, focustarget = true,
        party1 = true, party2 = true, party3 = true, party4 = true,
    },
}

-- Every supported unit: its layout groups and how to find its Blizzard frames.
-- **Add new units here.**
--   size    "large" | "small": camera and inset sizes (db.sizes)
--   offset  db.offsets key: circle centering nudge
--   row     db.nameRow key: square name-row height (ToT and party share "small" but differ here)
--   side    which side of the bars the square box goes on (where the round portrait was)
--   frame() the unit frame. Square boxes are parented here, never via the portrait:
--           BBF's No Portrait mode moves portraits/containers into a hidden frame.
-- The rest take that unit frame and return nil when a part is missing:
--   portrait(f) the 2D portrait texture
--   ring(f)     the ring art around it. Layers are placed relative to the frame that owns
--               it: on target/focus the ring (TargetFrameContainer, LOW strata, level ~501)
--               and the portrait (an unnamed BACKGROUND-strata frame) live in different frames.
--   bars(f)     health bar, mana bar (BBF frames them in No Portrait / Pixel Border mode)
--   texts(f)    Blizzard's name, the level, BBF's replacement name (bbfName). BBF lays
--               bbfName out on its own, so both names get pinned. Optional.
local function RingTex(t) return type(t) == "table" and t.GetDrawLayer and t.GetParent and t or nil end
local function AsText(x) return type(x) == "table" and x.SetPoint and x or nil end

local function TargetMain(f)
    local c = f.TargetFrameContent
    return c and c.TargetFrameContentMain
end

-- Target and focus share one frame design.
local function TargetUnit(frameName, offset)
    return {
        size = "large", offset = offset, row = "large", side = "RIGHT",
        frame    = function() return _G[frameName] end,
        portrait = function(f) local c = f.TargetFrameContainer; return c and c.Portrait end,
        ring     = function(f) local c = f.TargetFrameContainer; return c and RingTex(c.FrameTexture) end,
        bars     = function(f)
            local m = TargetMain(f)
            return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar, m and m.ManaBar
        end,
        texts    = function(f)
            local m = TargetMain(f)
            return AsText(m and m.Name), AsText(m and m.LevelText), AsText(f.bbfName)
        end,
    }
end

-- Target-of-target / focus-target (no level text).
local function ToTUnit(parentName)
    return {
        size = "small", offset = "tot", row = "tot", side = "LEFT",
        frame    = function() local p = _G[parentName]; return p and p.totFrame end,
        portrait = function(f) return f.Portrait end,
        ring     = function(f) return RingTex(f.FrameTexture) end,
        bars     = function(f) return f.HealthBar, f.ManaBar end,
        texts    = function(f) return AsText(f.Name), nil, AsText(f.bbfName) end,
    }
end

local function PartyUnit(i)
    return {
        size = "small", offset = "party", row = "party", side = "LEFT",
        frame    = function() return PartyFrame and PartyFrame["MemberFrame" .. i] end,
        portrait = function(f) return f.Portrait end,
        ring     = function(f) return RingTex(f.Texture) end,
        bars     = function(f) return f.HealthBarContainer and f.HealthBarContainer.HealthBar, f.ManaBar end,
    }
end

local UNITS = {
    player = {
        size = "large", offset = "player", row = "large", side = "LEFT",
        frame    = function() return PlayerFrame end,
        portrait = function(f) local c = f.PlayerFrameContainer; return c and c.PlayerPortrait end,
        ring     = function(f) local c = f.PlayerFrameContainer; return c and RingTex(c.FrameTexture) end,
        bars     = function(f)
            local m = f.PlayerFrameContent and f.PlayerFrameContent.PlayerFrameContentMain
            return m and m.HealthBarsContainer and m.HealthBarsContainer.HealthBar, m and m.ManaBarArea and m.ManaBarArea.ManaBar
        end,
        texts    = function(f)
            local name = AsText(f.name) or AsText(f.Name) or AsText(PlayerName)
            return name, AsText(PlayerLevelText), AsText(f.bbfName)
        end,
    },
    target       = TargetUnit("TargetFrame", "target"),
    focus        = TargetUnit("FocusFrame", "focus"),
    targettarget = ToTUnit("TargetFrame"),
    focustarget  = ToTUnit("FocusFrame"),
}
for i, unit in ipairs(PARTY) do UNITS[unit] = PartyUnit(i) end

-- Fixed iteration order (ipairs, and no table changes mid-traversal while refreshing).
local UNIT_LIST = { "player", "target", "targettarget", "focus", "focustarget", unpack(PARTY) }

local function UnitFrameOf(unit)
    local u = UNITS[unit]
    return u and u.frame()
end

-- Call one of the unit's frame lookups (portrait, ring, bars, texts) on its unit frame.
local function Lookup(unit, key)
    local u = UNITS[unit]
    local f = u and u[key] and u.frame()
    if f then return u[key](f) end
end

-- Slash-command groups -> units
local GROUPS = {
    player = { "player" }, target = { "target" }, focus = { "focus" },
    tot = { "targettarget", "focustarget" },
    party = PARTY,
}

local db
local layers = {}    -- unit -> layer record
-- unit -> GUID and visible/connected code at the last refresh, so the ticker only refreshes on change
local lastGuid, lastCode = {}, {}
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

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- GUID ("none" without a unit) and a visibility/connection code. Two plain values, so the
-- ticker can compare them without building a string per unit every tick.
local function UnitState(unit)
    if not UnitExists(unit) then return "none", 0 end
    local guid = Safe(UnitGUID(unit)) or "?"
    local hidden = Safe(UnitIsVisible(unit)) == false and 1 or 0
    local offline = Safe(UnitIsConnected(unit)) == false and 2 or 0
    return guid, hidden + offline
end

local function MarkState(unit)
    lastGuid[unit], lastCode[unit] = UnitState(unit)
end

local function StateChanged(unit)
    local guid, code = UnitState(unit)
    return guid ~= lastGuid[unit] or code ~= lastCode[unit]
end

-- Saved settings keep old values over new defaults, so reset what changed between versions.
local function MigrateSettings()
    local version = db.version or 1
    if version < 2 then
        db.inset, db.bgInset = nil, nil -- v1 single-size settings
        db.sizes = nil                  -- v2: model fills the circle (inset 0.82 -> 1.0)
    end
    if version < 4 then
        db.sizes = nil                  -- v3/v4: crisp circle edge (inset 0.72 -> 0.84), square size added
    end
    if version < 5 then
        db.squareExtra = nil            -- v5: box no longer grows upward; mana bars grow instead
    end
    if version < 6 then
        db.manaExtra = nil              -- v6: extra height is split between health and mana
    end
    if version < 7 then
        db.nameRow = nil                -- v7: separate name rows for ToT and party
    end
    if version < 8 then
        db.squareGap = nil              -- v8: box and bars share a border line (3 -> 1)
    end
    if version < 9 then
        db.sizes = nil                  -- v9: circle inset 0.84 -> 0.80 with a soft edge
    end
    if version < 10 then
        db.offsets = nil                -- v10: measured centering offsets
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

-- Coalesce refresh requests per unit into one refresh on the next frame. Every Refresh
-- reloads the 3D model (ClearModel + SetUnit), and one target change fires several events
-- (PLAYER_TARGET_CHANGED, UNIT_TARGET, UNIT_PORTRAIT_UPDATE) that each asked for one.
local queued = {} -- unit -> true
local flushQueued = false
local function FlushRefreshes()
    flushQueued = false
    for _, unit in ipairs(UNIT_LIST) do
        if queued[unit] then
            queued[unit] = nil
            Refresh(unit)
        end
    end
end
local function QueueRefresh(unit)
    queued[unit] = true
    if not flushQueued then
        flushQueued = true
        C_Timer.After(0, FlushRefreshes)
    end
end

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

-- Square style -------------------------------------------------------------

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
    local portrait = Lookup(unit, "portrait")
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
        if manaPos ~= manaBar then manaPos:SetWidth(hpPos:GetWidth() * toMana) end
        local a, b
        if UNITS[unit].side == "RIGHT" then a, b = hpPos:GetRight(), manaPos:GetRight()
        else a, b = hpPos:GetLeft(), manaPos:GetLeft() end
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
    local hpBottom, manaTop = hpPos:GetBottom(), manaPos:GetTop()
    if hpBottom and manaTop then
        local shift = ((hpBottom - 1 - db.barSpacing) - manaTop) * toMana
        if math.abs(shift) >= 0.25 then
            manaBar.bapDY = manaBar.bapDY + shift
            SetBarLayout(manaBar, manaPos, dhMana, manaBar.bapDX, dy + manaBar.bapDY)
        end
    end
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
    if pos and pos ~= bar and pos.bapBaseW then pos:SetWidth(pos.bapBaseW) end
    bar:SetPoint(o[1], o[2], o[3], o[4], o[5])
    bar.bapDX = 0
    bar.bapDY = 0
end

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

local function LayoutNameRow(unit, hpPos)
    local name, level, bbfName = Lookup(unit, "texts")
    if not (name or level or bbfName) then return end
    local row = hpPos.bapRow or 0
    if row <= 0 then
        RestorePoints(name); RestorePoints(level); RestorePoints(bbfName)
        return
    end
    local y = row / 2
    -- Room for the name: the row minus the level and a small gap.
    local function nameMax()
        local w = Safe(hpPos:GetWidth())
        if type(w) ~= "number" then return end
        local lw = level and level:IsShown() and TextWidth(level)
        return math.max(w - 2 - (lw and lw + 4 or 0), 10)
    end
    PinText(name,    "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT", nameMax)
    PinText(bbfName, "LEFT",  hpPos, "TOPLEFT",   1, y, "LEFT", nameMax)
    PinText(level,   "RIGHT", hpPos, "TOPRIGHT", -1, y, "RIGHT")
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
    local name, level, bbfName = Lookup(unit, "texts")
    RestorePoints(name); RestorePoints(level); RestorePoints(bbfName)
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
    if UNITS[sq.unit].side == "RIGHT" then
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
    sq.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, db.squareBg)
    sq.bg:SetShown(db.squareBg > 0)
    sq.box:Show() -- show first, then load (see circle Refresh)
    sq.model:ClearModel()
    sq.model:SetUnit(unit)
    ApplyCamera(sq.model, "square")
    return true
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

-- Square style, where BBF has removed the round portrait. Returns false when the bars
-- haven't been laid out yet (retries shortly; the ticker keeps trying meanwhile).
local function RefreshSquare(unit, unitFrame)
    local hpPos, manaPos, manaBar, hpBar = GetBarFrames(unit)
    if db.style ~= "square" or not hpPos then
        DeactivateSquare(unit)
        RestoreBars(unit)
        return true
    end
    LayoutBars(unit, hpPos, manaPos, manaBar, hpBar)
    if not InCombatLockdown() then LayoutNameRow(unit, hpPos) end
    if not ActivateSquare(unit, unitFrame, hpPos, manaPos) then
        C_Timer.After(0.5, function() Refresh(unit) end) -- bars not laid out yet
        return false
    end
    -- Once the resized bars have been laid out: re-measure the box, center the texts.
    C_Timer.After(0, function()
        PlaceSquare(squares[unit], hpPos, manaPos)
        CenterBarTexts(hpPos, manaPos, manaBar, hpBar)
        if not InCombatLockdown() then LayoutNameRow(unit, hpPos) end
    end)
    return true
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

local function HideAll(p, unit)
    if p then Deactivate(p) end
    DeactivateSquare(unit)
end

Refresh = function(unit)
    lastGuid[unit] = nil
    if not db then return end
    local p = layers[unit]
    local unitFrame = UnitFrameOf(unit)
    -- Remember the scale: the 3D camera framing is computed for the current size, so a
    -- scale change (Edit Mode, UI scale) needs a refresh. See Tick().
    lastScale[unit] = unitFrame and unitFrame:GetEffectiveScale()

    if not db.units[unit] or not db.enabled then
        -- Turned off by the user: hand the bars, texts and names back to BBF.
        HideAll(p, unit)
        RestoreBars(unit)
    elseif not unitFrame or not unitFrame:IsVisible() or not UnitExists(unit)
       or Safe(UnitIsVisible(unit)) == false or Safe(UnitIsConnected(unit)) == false then
        -- Transient (no target yet, frame hidden, out of range): just hide the portrait and
        -- keep our bar/name layout pinned, so a target switch can't leave BBF's layout behind.
        HideAll(p, unit)
    elseif BBFHidesPortrait(unit) then
        if p then Deactivate(p) end
        if not RefreshSquare(unit, unitFrame) then return end
    else
        DeactivateSquare(unit)
        RestoreBars(unit)
        p = p or CreateLayers(unit)
        if p and p.container:IsVisible() then
            RefreshCircle(p, unit)
        elseif p then
            Deactivate(p)
        end
    end
    MarkState(unit)
end

local function RefreshAll()
    for _, unit in ipairs(UNIT_LIST) do Refresh(unit) end
end

-- Coalesce bursts of refresh requests (BBF re-layouts often call several functions).
local refreshQueued = false
local function QueueRefreshAll()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        RefreshAll()
    end)
end

-- BBF functions that rebuild its frame layout at runtime (font changes, name layout, bar
-- text, no-portrait settings). Re-apply ours right after any of them runs.
local BBF_RELAYOUT_FUNCS = {
    "SetCustomFonts", "ApplyNameLayout", "ApplyNameLayouts", "UpdateNoPortraitText",
    "UpdateUserTargetSettings", "noPortraitModes", "UpdatePlayerPixelBorderSize", "AllNameChanges",
}
local function HookBBF()
    if not BBF then return end
    for _, fn in ipairs(BBF_RELAYOUT_FUNCS) do
        if type(BBF[fn]) == "function" then hooksecurefunc(BBF, fn, QueueRefreshAll) end
    end
end

-- New target: health and mana grow from empty to their value.
-- Blizzard's bars can't be animated directly: Blizzard re-sets them (immediately) as it
-- updates, which cancelled the engine's own interpolation. So for a moment we draw our
-- own copy of each bar on top and hide Blizzard's fill (alpha only, restored after).
-- The copy shows the bar's real value but its width grows from 0 to the bar's width,
-- so the visible fill is value x progress. Values can be "secret" and tainted code can't
-- do math on them (nor feed them to C_CurveUtil curves), but StatusBar:SetValue and
-- SetMinMaxValues accept them, so the lerp happens in geometry instead.
-- Starts from a post-hook on TargetFrame:Update(), which Blizzard calls on a target
-- change (also login and UNIT_TARGETABLE_CHANGED) right after setting the new values;
-- our own PLAYER_TARGET_CHANGED handler can run before Blizzard's.
local growDebug = false
local function GrowTrace(...) if growDebug then print("|cff00c0ffbap grow|r", ...) end end

local grows = {} -- bar -> { ov, fill, alpha, t }
local growDriver -- created on first grow

local function EndGrow(bar)
    local g = grows[bar]
    if not g then return end
    g.ov:Hide()
    -- Restore Blizzard's fill unless something else set its alpha meanwhile.
    if g.fill:GetAlpha() == 0 then g.fill:SetAlpha(g.alpha) end
    grows[bar] = nil
    GrowTrace("done", bar.bapGrowName)
end

-- Copy the fill's current look (BBF/Blizzard texture, class color, desaturation) onto
-- the overlay. BBF class colors are a desaturated fill with a tint, sometimes set on the
-- fill texture itself, so read the fill rather than the bar. Re-run every frame: BBF can
-- recolor or retexture right after Blizzard's update.
local function CopyBarStyle(ov, fill)
    local asset = fill:GetAtlas() or fill:GetTexture() or "Interface\\Buttons\\WHITE8X8"
    local ovFill = ov:GetStatusBarTexture()
    if ov.bapAsset ~= asset or not ovFill then
        ov:SetStatusBarTexture(asset)
        ov.bapAsset = asset
        if ov:GetStatusBarTexture() ~= ovFill then ov.bapMasks = nil end -- new texture, no masks yet
        ovFill = ov:GetStatusBarTexture()
    end
    local layer, sub = fill:GetDrawLayer()
    ovFill:SetDrawLayer(layer, math.min(7, (sub or 0) + 1))
    ovFill:SetDesaturation(fill:GetDesaturation() or 0)
    ovFill:SetBlendMode(fill:GetBlendMode() or "BLEND")
    -- RGB only: the fill's alpha is 0 while we hide it, and copying that hid the overlay.
    local r, g, b = fill:GetVertexColor()
    pcall(ovFill.SetVertexColor, ovFill, r, g, b)
    -- Same masks as the fill (Blizzard's bar shape, BBF's no-portrait mask). Unmasked, the
    -- overlay reached past the fill's clipped end. This runs every frame, so only rebuild
    -- (and allocate) when the fill's masks actually changed.
    local n = fill.GetNumMaskTextures and fill:GetNumMaskTextures() or 0
    local have = ov.bapMasks -- array of the fill's masks (false for empty slots)
    local same = have and #have == n
    for i = 1, same and n or 0 do
        if (fill:GetMaskTexture(i) or false) ~= have[i] then same = false; break end
    end
    if same then return end
    if have then
        for _, m in ipairs(have) do if m then ovFill:RemoveMaskTexture(m) end end
    end
    have = {}
    for i = 1, n do
        local m = fill:GetMaskTexture(i) or false
        if m then ovFill:AddMaskTexture(m) end
        have[i] = m
    end
    ov.bapMasks = have
end

local function GrowStep(_, elapsed)
    local duration = math.max(0.05, db.growTime)
    for bar, g in pairs(grows) do
        g.t = g.t + elapsed
        local p = math.min(1, g.t / duration)
        if p >= 1 or not bar:IsVisible() then
            EndGrow(bar)
        else
            local e = 1 - (1 - p) ^ 3 -- ease-out cubic
            -- Follow the live bar: health/power changing mid-grow shows up right away.
            g.ov:SetMinMaxValues(bar:GetMinMaxValues())
            g.ov:SetValue(bar:GetValue())
            g.ov:SetWidth(math.max(0.01, bar:GetWidth() * e))
            CopyBarStyle(g.ov, g.fill)
        end
    end
    if not next(grows) then growDriver:SetScript("OnUpdate", nil) end
end

local function StartGrow(bar, name)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not (fill and bar:IsVisible()) or (bar.GetOrientation and bar:GetOrientation() == "VERTICAL") then
        GrowTrace(name, "skip: fill", not not fill, "visible", bar:IsVisible())
        return
    end
    local g = grows[bar]
    if not g then
        local ov = bar.bapGrowBar
        if not ov then
            ov = CreateFrame("StatusBar", nil, bar)
            bar.bapGrowBar, bar.bapGrowName = ov, name
        end
        g = { ov = ov, fill = fill, alpha = fill:GetAlpha() }
        grows[bar] = g
    end
    g.t = 0
    local ov = g.ov
    -- Same frame level and draw layer as Blizzard's fill, so the bar texts stay on top.
    ov:SetFrameStrata(bar:GetFrameStrata())
    ov:SetFrameLevel(bar:GetFrameLevel())
    CopyBarStyle(ov, fill)
    ov:SetAlpha(g.alpha)
    local reverse = bar.GetReverseFill and bar:GetReverseFill()
    ov:SetReverseFill(reverse and true or false)
    local side = reverse and "RIGHT" or "LEFT"
    ov:ClearAllPoints()
    ov:SetPoint("TOP" .. side, bar, "TOP" .. side)
    ov:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side)
    ov:SetWidth(0.01)
    ov:SetMinMaxValues(bar:GetMinMaxValues())
    ov:SetValue(bar:GetValue())
    ov:Show()
    fill:SetAlpha(0)
    growDriver = growDriver or CreateFrame("Frame")
    growDriver:SetScript("OnUpdate", GrowStep)
    GrowTrace(name, "start, value", Safe(bar:GetValue()) or "secret")
end

local function GrowTargetBars()
    if not (db and db.growBars and UnitExists("target")) then
        GrowTrace("skip: grow", db and db.growBars, "target", UnitExists("target"))
        return
    end
    local hpBar, manaBar = Lookup("target", "bars")
    if hpBar then StartGrow(hpBar, "health") end
    if manaBar then StartGrow(manaBar, "mana") end
end

local function HookTargetUpdate()
    if TargetFrame and type(TargetFrame.Update) == "function" then
        hooksecurefunc(TargetFrame, "Update", GrowTargetBars)
    end
end

-- Catches changes with no reliable event: ToT swaps, party range/visibility, and frame
-- scale changes (Edit Mode / UI scale) that leave the 3D camera framed for the old size.
local function ScaleChanged(unit)
    local uf = UnitFrameOf(unit)
    local scale = uf and uf:GetEffectiveScale()
    local last = lastScale[unit]
    return scale and last and math.abs(scale - last) > 0.001
end

local function Tick()
    if not (db and db.enabled) then return end
    for _, unit in ipairs(UNIT_LIST) do
        if db.units[unit] and (StateChanged(unit) or ScaleChanged(unit)) then
            Refresh(unit)
        end
        -- Safety net: if anything put the model above its container, fix the layering.
        local p = layers[unit]
        if p and p.active and not LayeringOK(p) then ApplyLayering(p) end
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
        HookBBF()
        HookTargetUpdate()
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
        QueueRefresh("target"); QueueRefresh("targettarget")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        QueueRefresh("focus"); QueueRefresh("focustarget")
    elseif event == "GROUP_ROSTER_UPDATE" then
        for _, unit in ipairs(PARTY) do QueueRefresh(unit) end
    elseif event == "UNIT_TARGET" then
        if arg1 == "target" then QueueRefresh("targettarget")
        elseif arg1 == "focus" then QueueRefresh("focustarget") end
    elseif arg1 and UNITS[arg1] then
        QueueRefresh(arg1)
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
        .. "  grow=" .. tostring(db.growBars) .. (" (%.2fs)"):format(db.growTime) .. "  units=" .. (#on > 0 and table.concat(on, ",") or "none"))
    local Q = db.sizes.square
    print(("  circle large: inset=%.2f cam=%.2f   small: inset=%.2f cam=%.2f"):format(L.inset, L.cam, S.inset, S.cam))
    print(("  square: cam=%.2f bg=%.2f gap=%d alignmana=%s split=%.2f  extend: large=%d small=%d"):format(
        Q.cam, db.squareBg, db.squareGap, tostring(db.alignMana), db.hpShare, db.stackExtra.large, db.stackExtra.small))
    print(("  name rows: large=%d tot=%d party=%d"):format(db.nameRow.large, db.nameRow.tot, db.nameRow.party))
end

local function PrintHelp()
    print("  /bap toggle  |  /bap vignette  |  /bap zoom 0-1  |  /bap grow  |  /bap growtime 0.1-2  |  /bap reset")
    print("  /bap style square|circle  |  /bap bg 0-1  |  /bap extend 0-30 [large|small]  |  /bap split 0.4-0.85")
    print("  /bap namerow 0-24 [large|tot|party]  |  /bap gap 0-20  |  /bap barspacing 0-10  |  /bap alignmana")
    print("  /bap inset 0.3-1.2 [large|small]  |  /bap cam 0.3-2 [large|small|square]")
    print("  /bap unit player|target|focus|tot|party  |  /bap refresh  |  /bap debug [unit]")
    print("  circle: /bap circlebg 0-1  |  /bap vignette  |  /bap calibrate  |  /bap offset player|target|focus|tot|party x y")
end

-- Set a per-group value (tbl[group], or tbl[group][key]); no group given = all of them.
local function SetEach(tbl, only, value, key)
    for name in pairs(tbl) do
        if not only or only == name then
            if key then tbl[name][key] = value else tbl[name] = value end
        end
    end
end

-- /bap debug [unit]: print the square layout's real geometry, for bug reports.
local function Fmt(v) return type(v) == "number" and ("%.1f"):format(v) or tostring(v) end
local function PointInfo(r)
    if not r or not r.GetPoint then return "nil" end
    local point, rel, relPoint, x, y = r:GetPoint(1)
    local relName = rel and (rel.GetName and rel:GetName()) or (rel and "anon") or "nil"
    return ("%s>%s.%s (%s,%s) n=%d shown=%s"):format(tostring(point), relName, tostring(relPoint),
        Fmt(x), Fmt(y), r:GetNumPoints() or 0, tostring(r:IsShown()))
end
local function T(...) return tostring((...)) end -- tolerates calls that return nothing

local function DebugCircle(unit)
    local p = layers[unit]
    if not p then print("  circle: not created"); return end
    local c, m, v = p.container, p.model, p.vignette
    local vl, vs = v:GetDrawLayer()
    local pl, ps = p.portrait:GetDrawLayer()
    print(("  circle: active=%s  container lvl=%s %s  model lvl=%s %s shown=%s size=%s"):format(
        T(p.active), Fmt(c:GetFrameLevel()), T(c:GetFrameStrata()),
        Fmt(m:GetFrameLevel()), T(m:GetFrameStrata()), T(m:IsShown()), Fmt(m:GetWidth())))
    print(("  vignette shown=%s visible=%s layer=%s/%s size=%s alpha=%s  portrait layer=%s/%s shown=%s size=%s"):format(
        T(v:IsShown()), T(v:IsVisible()), T(vl), T(vs), Fmt(v:GetWidth()), Fmt(v:GetAlpha()),
        T(pl), T(ps), T(p.portrait:IsShown()), Fmt(p.portrait:GetWidth())))
    print(("  bg lvl=%s shown=%s"):format(Fmt(p.bgFrame:GetFrameLevel()), T(p.bgFrame:IsShown())))
    local function Chain(label, fr)
        local parts, n = {}, 0
        while fr and n < 6 do
            local flat = fr.GetFlattensRenderLayers and fr:GetFlattensRenderLayers()
            parts[#parts + 1] = ("%s[%s %s%s]"):format(T(fr.GetName and fr:GetName() or "anon"), Fmt(fr:GetFrameLevel()),
                T(fr:GetFrameStrata()), flat and " FLAT" or "")
            fr = fr:GetParent(); n = n + 1
        end
        print("  " .. label .. ": " .. table.concat(parts, " > "))
    end
    Chain("model parents", m:GetParent())
    Chain("container parents", c:GetParent())
    Chain("ring frame", p.ringFrame)
end

local function DebugUnit(unit)
    local hpPos, manaPos, manaBar, hpBar = GetBarFrames(unit)
    print(("|cff00c0ffBAP debug|r %s  style=%s  bbfNoPortrait=%s"):format(unit, db.style, tostring(BBFHidesPortrait(unit))))
    DebugCircle(unit)
    if not hpPos then print("  no bars found"); return end
    print(("  hpPos top=%s bottom=%s h=%s row=%s"):format(Fmt(hpPos:GetTop()), Fmt(hpPos:GetBottom()), Fmt(hpPos:GetHeight()), Fmt(hpPos.bapRow)))
    print("  hpBar " .. PointInfo(hpBar) .. "  h=" .. Fmt(hpBar:GetHeight()) .. " base=" .. Fmt(hpBar.bapBaseH))
    if manaPos then
        print(("  manaPos top=%s bottom=%s h=%s"):format(Fmt(manaPos:GetTop()), Fmt(manaPos:GetBottom()), Fmt(manaPos:GetHeight())))
        print("  manaBar " .. PointInfo(manaBar))
    else print("  no mana row") end
    local sq = squares[unit]
    if sq then
        print(("  box top=%s bottom=%s size=%s shown=%s"):format(Fmt(sq.box:GetTop()), Fmt(sq.box:GetBottom()), Fmt(sq.box:GetHeight()), tostring(sq.box:IsShown())))
    end
    if UNITS[unit] and UNITS[unit].texts then
        local name, level, bbfName = Lookup(unit, "texts")
        print("  name " .. PointInfo(name))
        print("  bbfName " .. PointInfo(bbfName))
        print("  level " .. PointInfo(level))
        if level and level.GetTop then print(("  level top=%s  bbfName top=%s"):format(Fmt(level:GetTop()), Fmt(bbfName and bbfName:GetTop()))) end
    end
end

SLASH_BBFANIMPORTRAITS1 = "/bap"
SlashCmdList.BBFANIMPORTRAITS = function(msg)
    local args = {}
    for word in (msg or ""):lower():gmatch("%S+") do args[#args + 1] = word end
    local cmd, arg, size = args[1], args[2], args[3]
    local val = tonumber(arg)
    if size and not db.sizes[size] then size = nil end

    if cmd == "debug" then
        DebugUnit(arg or "target")
        return
    elseif cmd == "refresh" then
        RefreshAll()
        return
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
    elseif cmd == "vignette" then
        db.vignette = not db.vignette
    elseif cmd == "grow" and arg == "debug" then
        growDebug = not growDebug
        print("  grow debug " .. (growDebug and "on: change targets and watch chat." or "off."))
        return
    elseif cmd == "grow" then
        db.growBars = not db.growBars
    elseif cmd == "growtime" and val then
        db.growTime = Clamp(val, 0.1, 2)
    elseif cmd == "calibrate" then
        db.calibrate = not db.calibrate
        print(db.calibrate and "  Calibrate on: nudge with /bap offset <player|target|focus|tot|party> x y, then /bap calibrate to finish."
            or "  Calibrate off.")
    elseif cmd == "offset" and arg and db.offsets[arg] then
        local x, y = tonumber(args[3]), tonumber(args[4])
        if x and y then db.offsets[arg] = { Clamp(x, -10, 10), Clamp(y, -10, 10) } end
        print(("  offset %s = %s, %s"):format(arg, tostring(db.offsets[arg][1]), tostring(db.offsets[arg][2])))
    elseif cmd == "style" and (arg == "square" or arg == "circle") then
        db.style = arg
    elseif cmd == "extend" and val then
        SetEach(db.stackExtra, size, Clamp(val, 0, 30))
    elseif cmd == "namerow" and val then
        SetEach(db.nameRow, args[3], Clamp(val, 0, 24))
    elseif cmd == "split" and val then
        db.hpShare = Clamp(val, 0.4, 0.85)
    elseif cmd == "alignmana" then
        db.alignMana = not db.alignMana
    elseif cmd == "circlebg" and val then
        db.circleBg = Clamp(val, 0, 1)
    elseif cmd == "bg" and val then
        db.squareBg = Clamp(val, 0, 1)
    elseif cmd == "gap" and val then
        db.squareGap = Clamp(val, 0, 20)
    elseif cmd == "barspacing" and val then
        db.barSpacing = Clamp(val, 0, 10)
    elseif cmd == "zoom" and val then
        db.zoom = Clamp(val, 0, 1)
    elseif cmd == "inset" and val then
        SetEach(db.sizes, size, Clamp(val, 0.3, 1.2), "inset")
    elseif cmd == "cam" and val then
        SetEach(db.sizes, size, Clamp(val, 0.3, 2), "cam")
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
