-- Living Portraits (a BetterBlizzFrames companion)
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
local SETTINGS_VERSION = 11

local defaults = {
    enabled  = true,
    style    = "square", -- "square" (needs BBF No Portrait / Pixel Border) or "circle"
    zoom     = 1,     -- 0..1, 1 = head & shoulders
    circleBg    = 0,  -- circle: opacity of the dark background inside the ring (0 = clear)
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
    growTime    = 0.35, -- seconds the grow takes (/lp growtime)
    showBuild   = true, -- square: talent build ("2/8/0") on the player, target and focus (/lp build)
    eliteBorder = true, -- square: target/focus box border gold for elite/boss, silver for rare (/lp eliteborder)
    eliteColor  = "ffffc71a", -- square: elite/boss border color, ARGB hex like the settings swatch (/lp elitecolor)
    rareColor   = "ffc7ccdb", -- square: rare/rare elite border color (/lp rarecolor)
    -- Square: where the target/focus elite icon goes: "top"/"bottom" (outer corner of the
    -- portrait box), "center" (bottom center of the box), "level" (beside the level), "hidden".
    eliteIcon   = "center",
    -- Square: the box grows upward by a line (the talent build's, above the name), per group:
    -- player, target (target + focus), party. ToT stays square (/lp tall [group]).
    tallPortraits = { player = true, target = true, party = true },
    hideSurname = true, -- first names only on our frames (/lp surname)
    mirrorTarget = true, -- square: target/focus text mirrors the player's (/lp mirror)
    borderColor = "ff000000", -- square: box + bar border color, ARGB hex like the settings swatch (/lp bordercolor)
    borderAlpha = 1,      -- square: border opacity (/lp borderalpha)
    borderSize  = 1,      -- square: border thickness: 1 thin, 2 medium, 3 heavy (/lp bordersize)
    vignette = true,
    calibrate = false, -- circle: tint the edge red to line it up with the ring (/lp calibrate)
    -- Circle: per-frame nudge (px) of the portrait inside its ring. Measured in game with
    -- /lp calibrate (Blizzard's portrait textures aren't exactly centered on their rings).
    offsets = {
        player = { -0.5, 0.6 },
        target = { 0.6, 0.3 },
        focus  = { 0.6, 0.3 }, -- same frame design as target
        tot    = { -1.3, 0 },
        party  = { 0, 0 },     -- not measured yet
    },
    bgR = 0.05, bgG = 0.05, bgB = 0.07,
    -- inset (circle style): model square as a fraction of the portrait. 0.84 keeps the
    --        square's corners under the ring's outer edge; the crisp circle edge follows it.
    -- cam:   camera distance (lower = closer = bigger face)
    sizes = {
        large  = { inset = 0.80, cam = 0.85 },
        small  = { inset = 0.80, cam = 0.85 },
        square = { inset = 1,    cam = 0.85 },
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
        -- Elite/rare marker: BBF's No Portrait mode turns Blizzard's portrait dragon into a
        -- 15px icon (nameplate elite atlas).
        elite    = function(f) local c = f.TargetFrameContainer; return c and c.BossPortraitFrameTexture end,
        -- "??" level skull: shown instead of the level text for units far above you.
        skull    = function(f)
            local c = f.TargetFrameContent and f.TargetFrameContent.TargetFrameContentContextual
            return c and c.HighLevelTexture
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
        icons    = function(f)
            local o = f.PartyMemberOverlay
            if o then return o.RoleIcon, o.LeaderIcon, o.GuideIcon, o.Disconnect end
        end,
        -- Not `texts`: party has no name row, and LayoutNameRow would hand those back to BBF.
        partyName = function(f) return AsText(f.bbfName), AsText(f.Name) end,
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
local BuildOptions -- the settings panel, defined with it below
local CheckOldAddon -- warns when the pre-rename addon is still enabled, defined below
local buildTexts = {} -- unit -> talent build FontString ("2/8/0"), created on first use
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
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Safe(v)
    if IsSecret(v) then return nil end
    return v
end

local function AnySecret(...)
    for i = 1, select("#", ...) do
        if IsSecret((select(i, ...))) then return true end
    end
    return false
end

local function BBFHidesPortrait(unit)
    return BBF and BBF.HasNoPortrait and BBF.HasNoPortrait(unit)
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- GUID ("none" without a unit) and a visibility/connection code. Two plain values, so the
-- ticker can compare them without building a string per unit every tick.
-- The code includes the unit frame's own visibility: a refresh while the frame was hidden
-- (party frames during a dungeon's loading screen or as the group forms) only hides the
-- square box, and nothing else re-runs it when the frame shows (the circle style has a
-- container OnShow hook, the square style doesn't).
local function UnitState(unit)
    if not UnitExists(unit) then return "none", 0 end
    local guid = Safe(UnitGUID(unit)) or "?"
    local hidden = Safe(UnitIsVisible(unit)) == false and 1 or 0
    local offline = Safe(UnitIsConnected(unit)) == false and 2 or 0
    local uf = UnitFrameOf(unit)
    local frameHidden = not (uf and uf:IsVisible()) and 4 or 0
    return guid, hidden + offline + frameHidden
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
    if version < 11 and type(db.tallPortraits) == "boolean" then
        -- v11: tall per group. Keep the old switch for player/target/focus; party is new (off).
        -- Only for the old boolean: a fresh install (no saved value) gets the defaults.
        local on = db.tallPortraits ~= false
        db.tallPortraits = { player = on, target = on, party = false }
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

local squares = {} -- unit -> square record

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
    if shown then
        Pin(unit, combat, "LEFT", shown, "RIGHT", 3, 0)
        Pin(unit, rest, "LEFT", shown, "RIGHT", REST_X, REST_Y)
    end
end

-- Put the bars and texts back exactly as BBF/Blizzard had them.
-- Border color (square style): our box border and BBF's health/mana borders get the
-- same color and opacity. BBF colors its edges once (black, when it creates them) and
-- keeps them on the bar (bar.BBFBlackBorder), so recoloring them at runtime sticks.
-- Edges are top, right, bottom, left. With the defaults, borders share pixel lines (box
-- and bars at squareGap 1, health and mana at barSpacing 0); below full opacity a shared
-- line would draw twice and show darker, so the duplicate edge is hidden.
local EDGE_RIGHT, EDGE_LEFT, EDGE_TOP = 2, 4, 1

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

-- Elite/rare on target and focus: the box and bar borders turn gold (elite, boss) or silver (rare,
-- rare elite), like classic's dragon around the portrait. The small elite icon alone was too
-- easy to miss. Both colors are settings. nil for normal units, other frames, or a secret
-- classification.
local ELITE_COLOR_KEY = { elite = "eliteColor", worldboss = "eliteColor", rare = "rareColor", rareelite = "rareColor" }
local function EliteColor(unit)
    if not (db.eliteBorder and UNITS[unit].elite and UnitExists(unit)) then return end
    local key = ELITE_COLOR_KEY[Safe(UnitClassification(unit)) or ""]
    if key then return HexRGB(db[key], defaults[key]) end
end

local function ApplyBorders(unit, manaBar, hpBar)
    local r, g, b, a = BorderRGBA()
    local er, eg, eb = EliteColor(unit) -- elite/rare: box and bars all get its color
    if er then r, g, b = er, eg, eb end
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
    -- The elite icon matches the border (here, not in the name row: this also runs in combat).
    local elite = EliteIcon(unit)
    if elite then TintElite(elite, er, eg, eb) end
end

-- BBF's look: black, 1px, every edge shown.
local function RestoreBorders(manaBar, hpBar)
    LayoutEdges(hpBar and hpBar.BBFBlackBorder, hpBar and hpBar.BBFPositionFrame, 1, true)
    LayoutEdges(manaBar and manaBar.BBFBlackBorder, manaBar and manaBar.BBFPositionFrame, 1, true)
    ColorEdges(hpBar and hpBar.BBFBlackBorder, 0, 0, 0, 1)
    ColorEdges(manaBar and manaBar.BBFBlackBorder, 0, 0, 0, 1)
end

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

-- Anchor the box beside the bars; height spans the health bar top to the mana bar bottom.
-- Returns false if the bars haven't been laid out yet.
-- Tall portraits (player, target and focus): px for the talent build's own line above the name
-- row. It grows the box upward, so the box becomes a taller rectangle while the bars keep
-- their size and spot. Reserved even with no build to show (NPC targets): bars can't be
-- re-laid out in combat, so the layout can't change per target. Off: square box, and the
-- build sits next to the level.
-- Party (no name row, no build) just gets the same taller box beside the name above its bars.
local BUILD_LINE = 9
local TALL_GROUP = {
    player = "player", target = "target", focus = "target",
    party1 = "party", party2 = "party", party3 = "party", party4 = "party",
}
local function BuildLine(unit)
    local group = TALL_GROUP[unit]
    if not (group and db.tallPortraits[group]) then return 0 end -- independent of showBuild
    return BUILD_LINE
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
    local extra = (row > 0 or not UNITS[sq.unit].texts) and BuildLine(sq.unit) or 0
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

-- One pending retry per unit: each Refresh that failed used to start its own retry chain,
-- and the ticker kept starting more while positions stayed secret (PvP), piling up into
-- hundreds of refreshes per tick (mouse lag).
-- Retries back off (0.5s, 1s, 2s, then every 4s) while positions stay secret, since each
-- one re-lays out the bars and names; a successful placement resets the delay.
local retryPending, retryDelay = {}, {}
local function RetryRefresh(unit)
    if retryPending[unit] then return end
    retryPending[unit] = true
    local delay = retryDelay[unit] or 0.5
    retryDelay[unit] = math.min(delay * 2, 4)
    C_Timer.After(delay, function()
        retryPending[unit] = nil
        Refresh(unit)
    end)
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
    if StateChanged(unit) then retryDelay[unit] = nil end -- new unit: retry quickly again
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
    elseif not unitFrame or not unitFrame:IsVisible() or not UnitExists(unit) then
        -- Transient (no target yet, frame hidden): just hide the portrait and keep our
        -- bar/name layout pinned, so a target switch can't leave BBF's layout behind.
        HideAll(p, unit)
    elseif BBFHidesPortrait(unit) then
        if p then Deactivate(p) end
        -- Out of view range (not zoned in yet) or offline: no model, but the same layout as
        -- everyone else, or this frame's bars wouldn't line up with the others.
        local away = Safe(UnitIsVisible(unit)) == false or Safe(UnitIsConnected(unit)) == false
        RefreshSquare(unit, unitFrame, away) -- on failure it schedules its own retry; the ticker leaves it alone
    elseif Safe(UnitIsVisible(unit)) == false or Safe(UnitIsConnected(unit)) == false then
        HideAll(p, unit) -- circle: Blizzard's 2D portrait stands in until they're in range
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

local AfterRefreshAll -- talent build and surnames, defined with them below

local function RefreshAll()
    for _, unit in ipairs(UNIT_LIST) do Refresh(unit) end
    if AfterRefreshAll then AfterRefreshAll() end
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
local function GrowTrace(...) if growDebug then print("|cff00c0fflp grow|r", ...) end end

local grows = {} -- bar -> { ov, fill, alpha, t }
local growDriver -- created on first grow

local function EndGrow(bar)
    local g = grows[bar]
    if not g then return end
    -- Remove first: if anything below errors, the grow must not re-run (and error) every frame.
    grows[bar] = nil
    g.ov:Hide()
    -- Restore Blizzard's fill unless something else set its alpha meanwhile. In PvP the
    -- alpha can read back as a secret value that can't be compared: restore it then too,
    -- or the bar stays invisible.
    local alpha = Safe(g.fill:GetAlpha())
    if alpha == nil or alpha == 0 then g.fill:SetAlpha(g.alpha) end
    GrowTrace("done", bar.bapGrowName)
end

-- The grow compares and does math on what the bar and its fill report (orientation, reverse
-- fill, texture, draw layer, masks). In instances and PvP any of these can come back secret,
-- and comparing a secret errors (tainted code). The grow is cosmetic: skip or end it then.
-- The bar's own values are checked once at the start; the fill's in CopyBarStyle, which
-- reads them every frame anyway.
local function BarReadable(bar)
    return not AnySecret(bar:GetWidth(), bar.GetOrientation and bar:GetOrientation(),
        bar.GetReverseFill and bar:GetReverseFill())
end

-- Copy the fill's current look (BBF/Blizzard texture, class color, desaturation) onto
-- the overlay. BBF class colors are a desaturated fill with a tint, sometimes set on the
-- fill texture itself, so read the fill rather than the bar. Re-run every frame: BBF can
-- recolor or retexture right after Blizzard's update.
-- Returns false (copying nothing) when any of the fill's values is secret.
local function CopyBarStyle(ov, fill)
    local atlas, tex = fill:GetAtlas(), fill:GetTexture()
    local layer, sub = fill:GetDrawLayer()
    local desat, blend = fill:GetDesaturation(), fill:GetBlendMode()
    local n = fill.GetNumMaskTextures and fill:GetNumMaskTextures() or 0
    if AnySecret(atlas, tex, layer, sub, desat, blend, n) then return false end
    for i = 1, n do
        if IsSecret(fill:GetMaskTexture(i)) then return false end
    end
    local asset = atlas or tex or "Interface\\Buttons\\WHITE8X8"
    local ovFill = ov:GetStatusBarTexture()
    if ov.bapAsset ~= asset or not ovFill then
        ov:SetStatusBarTexture(asset)
        ov.bapAsset = asset
        if ov:GetStatusBarTexture() ~= ovFill then ov.bapMasks = nil end -- new texture, no masks yet
        ovFill = ov:GetStatusBarTexture()
    end
    ovFill:SetDrawLayer(layer, math.min(7, (sub or 0) + 1))
    ovFill:SetDesaturation(desat or 0)
    ovFill:SetBlendMode(blend or "BLEND")
    -- RGB only: the fill's alpha is 0 while we hide it, and copying that hid the overlay.
    local r, g, b = fill:GetVertexColor()
    pcall(ovFill.SetVertexColor, ovFill, r, g, b)
    -- Same masks as the fill (Blizzard's bar shape, BBF's no-portrait mask). Unmasked, the
    -- overlay reached past the fill's clipped end. This runs every frame, so only rebuild
    -- (and allocate) when the fill's masks actually changed.
    local have = ov.bapMasks -- array of the fill's masks (false for empty slots)
    local same = have and #have == n
    for i = 1, same and n or 0 do
        if (fill:GetMaskTexture(i) or false) ~= have[i] then same = false; break end
    end
    if same then return true end
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
    return true
end

local function GrowStep(_, elapsed)
    local duration = math.max(0.05, db.growTime)
    for bar, g in pairs(grows) do
        g.t = g.t + elapsed
        local p = math.min(1, g.t / duration)
        local w = Safe(bar:GetWidth()) -- secret in PvP: stop and show Blizzard's fill
        if p >= 1 or not w or not bar:IsVisible() or not CopyBarStyle(g.ov, g.fill) then
            EndGrow(bar)
        else
            local e = 1 - (1 - p) ^ 3 -- ease-out cubic
            -- Follow the live bar: health/power changing mid-grow shows up right away.
            g.ov:SetMinMaxValues(bar:GetMinMaxValues())
            g.ov:SetValue(bar:GetValue())
            g.ov:SetWidth(math.max(0.01, w * e))
        end
    end
    if not next(grows) then growDriver:SetScript("OnUpdate", nil) end
end

local function StartGrow(bar, name)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not (fill and bar:IsVisible()) or not BarReadable(bar)
        or (bar.GetOrientation and bar:GetOrientation() == "VERTICAL") then
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
    if not CopyBarStyle(ov, fill) then
        EndGrow(bar) -- secret fill (instance/PvP): leave Blizzard's bar alone
        GrowTrace(name, "skip: secret fill")
        return
    end
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

local function GrowBars(unit)
    if not (db and db.growBars and UnitExists(unit)) then
        GrowTrace("skip: grow", db and db.growBars, unit, UnitExists(unit))
        return
    end
    local hpBar, manaBar = Lookup(unit, "bars")
    if hpBar then StartGrow(hpBar, unit .. " health") end
    if manaBar then StartGrow(manaBar, unit .. " mana") end
end

-- Target and focus share Blizzard's frame code: Update() runs on a new target (target
-- frame) or a new focus (focus frame), after the new values are set. Target-of-target is
-- left out on purpose: it changes many times a second in fights, so a grow would flicker.
local function HookGrowUpdates()
    for _, f in ipairs({ { TargetFrame, "target" }, { FocusFrame, "focus" } }) do
        local frame, unit = f[1], f[2]
        if frame and type(frame.Update) == "function" then
            hooksecurefunc(frame, "Update", function() GrowBars(unit) end)
        end
    end
end

-- Talent build on the player, target and focus -------------------------------------
-- Points per talent tree ("2/8/0") in the square style's name area: on its own line above
-- the name with tall portraits (BuildLine), else just left of the level. Your own build is
-- read directly (cached until your talents change); other players need an inspect
-- (server round trip, ~30 yd range, shared throttle), so results are cached per GUID for
-- the session and requests are spaced out. NPCs and players we can't inspect show
-- nothing rather than a guess.
local BUILD_UNITS = { "player", "target", "focus" }
local builds = {}         -- GUID -> "2/8/0"
local ownBuild            -- your build, cleared when your talents change
local inspectGUID         -- GUID of our pending inspect
local inspectAt = 0       -- GetTime() of our last NotifyInspect
local INSPECT_GAP = 1.5   -- seconds between our inspects
local INSPECT_TIMEOUT = 4 -- give up waiting for a reply after this long
local NO_REPLY_WAIT = 30  -- a player who didn't answer waits this long before we ask again
local noReply = {}        -- GUID -> GetTime() of an inspect that got no answer

-- Points per tree for a trait config, in the talent window's tree order. The game leaves
-- out trees with no points spent (Blizzard's own tree headers show "0" for those).
local function ReadBuild(configID)
    if not (configID and C_Traits and C_Traits.GetConfigInfo) then return end
    local info = C_Traits.GetConfigInfo(configID)
    local tree = info and info.treeIDs and info.treeIDs[1]
    local display = tree and C_Traits.GetGroupDisplayInfoByTreeID(tree)
    if not display or #display == 0 then return end
    local ids = {}
    for i, d in ipairs(display) do ids[i] = d.groupID end
    local spent = {}
    for _, g in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
        local c = g.currencyInfos and g.currencyInfos[1]
        local n = c and Safe(c.spent)
        if c and n == nil then return end -- secret: show nothing
        spent[g.traitNodeGroupID] = n or 0
    end
    local parts = {}
    for i, d in ipairs(display) do parts[i] = tostring(spent[d.groupID] or 0) end
    return table.concat(parts, "/")
end

local function OwnBuild()
    if not ownBuild and C_ClassTalents then -- not ready right after login: retried by the ticker
        ownBuild = ReadBuild(C_ClassTalents.GetActiveConfigID())
    end
    return ownBuild
end

-- The build shows only where the square style draws the unit's name row.
local function BuildVisible(unit)
    return db and db.enabled and db.showBuild and db.units[unit] and db.style == "square"
        and (db.nameRow[UNITS[unit].row] or 0) > 0 and BBFHidesPortrait(unit)
end

-- One inspect at a time (target and focus share it): a second request would replace the
-- pending one and its answer would be ignored. No answer in time: that player waits
-- NO_REPLY_WAIT so the other frame gets a turn.
local function RequestInspect(guid, unit)
    if not (NotifyInspect and guid) or InCombatLockdown() then return end
    local now = GetTime()
    if inspectGUID then
        if now - inspectAt < INSPECT_TIMEOUT then return end -- still waiting for its reply
        noReply[inspectGUID], inspectGUID = now, nil
    end
    if noReply[guid] and now - noReply[guid] < NO_REPLY_WAIT then return end
    if now - inspectAt < INSPECT_GAP then return end -- the ticker asks again shortly
    if CanInspect and not CanInspect(unit) then return end -- out of range, enemy, ...
    if InspectFrame and InspectFrame:IsShown() then return end -- Blizzard's inspect owns it
    inspectGUID, inspectAt = guid, GetTime()
    NotifyInspect(unit)
end

local function BuildFor(unit)
    if unit == "player" or Safe(UnitIsUnit(unit, "player")) then return OwnBuild() end
    if not Safe(UnitIsPlayer(unit)) then return end
    local guid = Safe(UnitGUID(unit))
    if guid and not builds[guid] then RequestInspect(guid, unit) end
    return guid and builds[guid]
end

local function CreateBuildText(unit, level)
    local uf = UnitFrameOf(unit)
    if not uf then return end
    local fs = uf:CreateFontString(nil, "OVERLAY")
    local font, size, flags = level:GetFont()
    if font then
        fs:SetFont(font, math.max((size or 10) - 2, 7), flags)
    elseif GameFontNormalSmall then
        fs:SetFontObject(GameFontNormalSmall)
    end
    fs:SetTextColor(0.7, 0.7, 0.7) -- muted: the name is the main information
    fs:Hide()
    return fs
end

local function UpdateBuildFor(unit)
    local text = BuildVisible(unit) and BuildFor(unit) or nil
    local fs = buildTexts[unit]
    if not text and not (fs and fs:IsShown()) then return end -- nothing to show or hide
    local name, level, bbfName = Lookup(unit, "texts")
    if not level then return end
    if text and not fs then
        fs = CreateBuildText(unit, level)
        buildTexts[unit] = fs
    end
    if not fs then return end
    -- Own line above the name (left-aligned with it), or next to the level.
    local hpPos = GetBarFrames(unit)
    local row, extra = hpPos and hpPos.bapRow or 0, BuildLine(unit)
    local above = row > 0 and extra > 0
    local mirror = Mirrored(unit)
    local eliteRow = EliteInRow(unit) and true or false -- the inline build steps past the elite icon
    if fs.bapText == text and fs.bapInline == not above and fs.bapRow == row and fs.bapExtra == extra
        and fs.bapMirror == mirror and fs.bapEliteRow == eliteRow then return end
    fs.bapText, fs.bapInline, fs.bapRow, fs.bapExtra, fs.bapMirror = text, not above, row, extra, mirror
    fs.bapEliteRow = eliteRow
    fs:ClearAllPoints()
    if above and mirror then -- above the name, on the portrait side
        fs:SetPoint("RIGHT", hpPos, "TOPRIGHT", -1, row + extra / 2)
        fs:SetJustifyH("RIGHT")
    elseif above then
        fs:SetPoint("LEFT", hpPos, "TOPLEFT", 1, row + extra / 2)
        fs:SetJustifyH("LEFT")
    elseif mirror then -- between the level (outer edge) and the name, past the elite icon
        fs:SetPoint("LEFT", level, "RIGHT", 4 + (eliteRow and ELITE_ROOM or 0), 0)
        fs:SetJustifyH("LEFT")
    else
        fs:SetPoint("RIGHT", level, "LEFT", -4 - (eliteRow and ELITE_ROOM or 0), 0)
        fs:SetJustifyH("RIGHT")
    end
    fs:SetText(text or "")
    fs:SetShown(text ~= nil)
    -- The name's room depends on an inline build text: re-fit the pinned names.
    for _, pinned in ipairs({ name, bbfName }) do
        if pinned and pinned.bapLayout and pinned.bapApply then pinned.bapApply(pinned) end
    end
end

local function UpdateBuild()
    for _, unit in ipairs(BUILD_UNITS) do UpdateBuildFor(unit) end
end

local function OnTalentsChanged()
    ownBuild = nil
    UpdateBuild()
end

local function OnInspectReady(guid)
    if not guid or guid ~= inspectGUID then return end -- someone else's inspect
    inspectGUID = nil
    local build = Constants and Constants.TraitConsts and ReadBuild(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)
    if build then builds[guid] = build end
    UpdateBuild()
end

-- Surnames ------------------------------------------------------------------
-- Camelot characters have a surname: UnitName returns (name, surname) and Blizzard's
-- frames show both. With hideSurname we strip it from the name texts on our frames, in
-- a post-hook on SetText so it follows every name update by Blizzard or BBF. Only the
-- surname is removed, so BBF's formatting (colors, prefixes) stays; the full text is kept
-- to put back when the setting is turned off.
local SURNAME_UNITS = { "player", "target", "focus", "targettarget", "focustarget", unpack(PARTY) }

local function NameTextsOf(unit)
    if UNITS[unit].texts then
        local name, _, bbfName = Lookup(unit, "texts")
        return name, bbfName
    end
    local f = UnitFrameOf(unit) -- party
    return f and AsText(f.Name)
end

local function SurnameOf(unit)
    local _, surname = UnitName(unit)
    surname = Safe(surname)
    if type(surname) == "string" and surname ~= "" then return surname end
end

local function SetNameText(fs, text)
    fs.bapNaming = true
    fs:SetText(text)
    fs.bapNaming = nil
end

local function StripSurname(fs)
    if fs.bapNaming or not (db and db.hideSurname) then return end
    local text, surname = Safe(fs:GetText()), SurnameOf(fs.bapNameUnit)
    if type(text) ~= "string" or not surname then return end
    local sep = Constants and Constants.CharacterNameSeparatorConsts
        and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
    local i, j = text:find(sep .. surname, 1, true)
    if not i then return end
    local short = text:sub(1, i - 1) .. text:sub(j + 1)
    fs.bapFullName, fs.bapShortName = text, short
    SetNameText(fs, short)
end

-- Hook a name text once; the hook then follows every name change by itself.
local function HookName(fs, unit)
    if not fs or fs.bapNameHook or not fs.SetText then return end
    fs.bapNameHook, fs.bapNameUnit = true, unit
    hooksecurefunc(fs, "SetText", StripSurname)
    StripSurname(fs) -- its current text
end

-- Strip (setting on) or put back (setting off) on one name text.
local function ApplySurname(fs)
    if not fs then return end
    if db.hideSurname then
        StripSurname(fs)
    elseif fs.bapShortName then
        if Safe(fs:GetText()) == fs.bapShortName then SetNameText(fs, fs.bapFullName) end
        fs.bapFullName, fs.bapShortName = nil, nil
    end
end

-- From the ticker: hook name texts as they appear (BBF creates bbfName after us). With
-- `apply` (after a refresh or a toggle): also strip or restore every name now.
local function UpdateSurnames(apply)
    if not db then return end
    for _, unit in ipairs(SURNAME_UNITS) do
        local a, b = NameTextsOf(unit)
        HookName(a, unit); HookName(b, unit)
        if apply then ApplySurname(a); ApplySurname(b) end
    end
end

AfterRefreshAll = function()
    UpdateBuild()
    UpdateSurnames(true)
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
    UpdateBuild() -- retries until there's a build (inspect range and throttle, talents loading)
    UpdateSurnames() -- hooks name texts as they appear (BBF creates its own later)
end

-- Events --------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        LivingPortraitsDB = LivingPortraitsDB or {}
        db = LivingPortraitsDB
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
        self:RegisterEvent("INSPECT_READY")
        self:RegisterEvent("TRAIT_CONFIG_UPDATED")
        HookBBF()
        HookGrowUpdates()
        -- Edit Mode's small/large focus frame re-anchors the focus-target (see ClearTot).
        if FocusFrame and type(FocusFrame.SetSmallSize) == "function" then
            hooksecurefunc(FocusFrame, "SetSmallSize", QueueRefreshAll)
        end
        BuildOptions()
        if EditModeManagerFrame then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() C_Timer.After(0.1, RefreshAll) end)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- small delay so BBF finishes resizing portraits first
        C_Timer.After(0.5, RefreshAll)
        if not ns.ticker then ns.ticker = C_Timer.NewTicker(0.5, Tick) end
        CheckOldAddon()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        C_Timer.After(0.1, RefreshAll)
    elseif event == "PLAYER_TARGET_CHANGED" then
        QueueRefresh("target"); QueueRefresh("targettarget")
        UpdateBuild()
    elseif event == "INSPECT_READY" then
        OnInspectReady(arg1)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        OnTalentsChanged() -- your own build (player frame, or targeting yourself)
    elseif event == "PLAYER_FOCUS_CHANGED" then
        QueueRefresh("focus"); QueueRefresh("focustarget")
        UpdateBuild()
    elseif event == "GROUP_ROSTER_UPDATE" then
        for _, unit in ipairs(PARTY) do QueueRefresh(unit) end
    elseif event == "UNIT_TARGET" then
        if arg1 == "target" then QueueRefresh("targettarget")
        elseif arg1 == "focus" then QueueRefresh("focustarget") end
    elseif arg1 and UNITS[arg1] then
        QueueRefresh(arg1)
    end
end)

-- BBF setup -----------------------------------------------------------------
-- The square style needs BBF's No Portrait + Pixel Border mode on every frame. We write
-- those switches into BBF's saved settings (never its files) and keep a backup for Undo.
-- BBF reads them when it loads, so a UI reload applies them. The rest of BBF stays as is.
local BBF_SETUP = {
    noPortraitModes = true, noPortraitPixelBorder = true,
    noPortraitPartyOnly = false, -- otherwise only the party frames lose their portraits
    noPortraitSkipPlayer = false, noPortraitSkipTarget = false, noPortraitSkipFocus = false,
}
local NO_VALUE = "<nil>" -- backup marker: BBF had never saved this key

local function ShowReloadPopup()
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    StaticPopupDialogs.LIVING_PORTRAITS_RELOAD = StaticPopupDialogs.LIVING_PORTRAITS_RELOAD or {
        text = "Living Portraits changed your BetterBlizzFrames settings. Reload the UI to apply them?",
        button1 = RELOADUI or "Reload UI",
        button2 = LATER or "Later",
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("LIVING_PORTRAITS_RELOAD")
end

local function BBFSetupOn()
    local bdb = BetterBlizzFramesDB
    if type(bdb) ~= "table" then return false end
    for k, v in pairs(BBF_SETUP) do
        if (bdb[k] or false) ~= v then return false end
    end
    return true
end

-- Both return a line for chat.
local function ApplyBBFSetup()
    local bdb = BetterBlizzFramesDB
    if not BBF or type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    if BBFSetupOn() then return "BBF's Pixel Border mode is already on." end
    if not db.bbfBackup then -- keep the first backup: it holds the settings from before us
        local backup = {}
        for k in pairs(BBF_SETUP) do
            if bdb[k] == nil then backup[k] = NO_VALUE else backup[k] = bdb[k] end
        end
        db.bbfBackup = backup
    end
    for k, v in pairs(BBF_SETUP) do bdb[k] = v end
    ShowReloadPopup()
    return "Turned on BBF's No Portrait + Pixel Border mode. Reload the UI to apply it."
end

local function UndoBBFSetup()
    local bdb, backup = BetterBlizzFramesDB, db.bbfBackup
    if not backup then return "Nothing to undo." end
    if type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    for k, v in pairs(backup) do
        if v == NO_VALUE then bdb[k] = nil else bdb[k] = v end
    end
    db.bbfBackup = nil
    ShowReloadPopup()
    return "Put back your previous BBF settings. Reload the UI to apply them."
end

-- Settings panel ------------------------------------------------------------
-- Options > AddOns > Living Portraits. Proxy settings read and write db directly,
-- so the panel and /lp always agree (slash changes call NotifyOptions).
local PREFIX = "Living|cff00c0ffPortraits|r "
local optionVars = {} -- registered setting variables, refreshed by NotifyOptions
local optionsCategory

local function NotifyOptions()
    if not (Settings and Settings.NotifyUpdate) then return end
    for _, var in ipairs(optionVars) do Settings.NotifyUpdate(var) end
end

local function FormatDecimal(v) return ("%.2f"):format(v) end
local function FormatWhole(v) return ("%d"):format(math.floor(v + 0.5)) end
local function FormatPercent(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end

-- get/set for db[k1][k2]..., and the matching default.
local function Path(keys)
    local last = keys[#keys]
    local function Parent()
        local t = db
        for i = 1, #keys - 1 do t = t[keys[i]] end
        return t
    end
    local d = defaults
    for _, k in ipairs(keys) do d = d[k] end
    return function() return Parent()[last] end, function(v) Parent()[last] = v end, d
end

BuildOptions = function()
    if optionsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory and SettingsPanel) then return end
    local category = -- Styled like BBF's own entry (plain first word, cyan second). The list sorts on the raw
    -- name, so it must not start with a color code.
    Settings.RegisterVerticalLayoutCategory("Living|cff00c0ffPortraits|r")
    local layout = SettingsPanel:GetLayout(category)

    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end
    local function Register(var, name, default, get, set)
        var = "LivingPortraits_" .. var
        optionVars[#optionVars + 1] = var
        return Settings.RegisterProxySetting(category, var, nil, name, default, get, function(v)
            set(v)
            QueueRefreshAll()
        end)
    end
    local function Check(keys, name, tooltip)
        local get, set, default = Path(keys)
        Settings.CreateCheckbox(category, Register(table.concat(keys, "_"), name, default, get, set), tooltip)
    end
    -- step >= 1 means whole numbers.
    local function Slider(keys, name, tooltip, lo, hi, step, format)
        local get, set, default = Path(keys)
        local whole = step >= 1
        local setting = Register(table.concat(keys, "_"), name, default, get, function(v)
            set(whole and math.floor(v + 0.5) or v)
        end)
        local options = Settings.CreateSliderOptions(lo, hi, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right,
            format or (whole and FormatWhole or FormatDecimal))
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    Header("General")
    Check({ "enabled" }, "Enable", "Show living portraits.")
    Check({ "hideSurname" }, "Hide Surnames", "Show only first names on the player, target, focus, target-of-target and party frames.")
    local styleGet, styleSet, styleDefault = Path({ "style" })
    Settings.CreateDropdown(category, Register("style", "Style", styleDefault, styleGet, styleSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("square", "Box")
        c:Add("circle", "Circle")
        return c:GetData()
    end, "Box: the portrait in a bordered box beside the bars (needs BBF's Pixel Border mode, below). Circle: inside the round portrait. Frames where BBF still shows portraits always use the circle.")
    for _, g in ipairs({ { "player", "Player Portrait", "player frame" },
                         { "target", "Target Portrait", "target frame" },
                         { "focus", "Focus Portrait", "focus frame" },
                         { "tot", "Target of Target Portrait", "target-of-target and focus-target frames" },
                         { "party", "Party Portraits", "party frames" } }) do
        local list = GROUPS[g[1]]
        Settings.CreateCheckbox(category, Register("unit_" .. g[1], g[2], true,
            function() return db.units[list[1]] end,
            function(v) for _, unit in ipairs(list) do db.units[unit] = v end end),
            "Living portrait on the " .. g[3] .. ".")
    end

    Header("Camera")
    Slider({ "zoom" }, "Zoom", "1 = head and shoulders; lower shows more of the body. Both styles.", 0, 1, 0.05)

    Header("Target bars")
    Check({ "growBars" }, "Grow on new target", "Health and mana grow from empty when you pick a new target or focus.")
    Slider({ "growTime" }, "Grow time", "Seconds the grow takes.", 0.1, 2, 0.05,
        function(v) return ("%.2fs"):format(v) end)

    Header("BetterBlizzFrames")
    layout:AddInitializer(CreateSettingsButtonInitializer("Pixel Border mode", "Turn on",
        function() print(PREFIX .. ApplyBBFSetup()) end,
        "Turns on BBF's No Portrait + Pixel Border mode on every frame, which the box style needs. Your other BBF settings stay as they are. Reloads the UI.", true))
    layout:AddInitializer(CreateSettingsButtonInitializer("Undo Pixel Border mode", "Undo",
        function() print(PREFIX .. UndoBBFSetup()) end,
        "Puts back the BBF settings you had before turning it on here. Reloads the UI.", true))

    -- Each style's settings on its own page under the main entry (falls back to sections on
    -- the main page if the client has no subcategories). Each style's camera distance lives
    -- there: square boxes share one distance, circle portraits use large/small.
    local main = category
    local function Page(name)
        if Settings.RegisterVerticalLayoutSubcategory then
            category, layout = Settings.RegisterVerticalLayoutSubcategory(main, name)
            layout = layout or SettingsPanel:GetLayout(category)
        else
            Header(name)
        end
    end

    Page("Box Style")
    Header("Camera")
    Slider({ "sizes", "square", "cam" }, "Distance", "All box portraits. Lower = closer, bigger face.", 0.3, 2, 0.05)
    Slider({ "squareBg" }, "Background", "Dark background behind the model.", 0, 1, 0.05, FormatPercent)

    Header("Size and layout")
    local TALL_TIP = "The portrait grows into a taller rectangle. Player, target and focus: with a line above the name for the talent build (off: square, build next to the level)."
    Check({ "tallPortraits", "player" }, "Tall portraits: player", TALL_TIP)
    Check({ "tallPortraits", "target" }, "Tall portraits: target & focus", TALL_TIP)
    Check({ "tallPortraits", "party" }, "Tall portraits: party", TALL_TIP)
    Slider({ "stackExtra", "large" }, "Extra height: large frames", "Player, target and focus. Makes the health + mana stack taller; the box grows with it.", 0, 30, 1)
    Slider({ "stackExtra", "small" }, "Extra height: small frames", "Target of target and party. Makes the health + mana stack taller; the box grows with it.", 0, 30, 1)
    Slider({ "nameRow", "large" }, "Name row: large frames", "Height of the name + level row inside the box (0 = off).", 0, 24, 1)
    Slider({ "nameRow", "tot" }, "Name row: target of target", "Height of the name row inside the box (0 = off).", 0, 24, 1)
    Slider({ "nameRow", "party" }, "Name row: party", "Height of the name row inside the box (0 = off).", 0, 24, 1)
    Slider({ "hpShare" }, "Health share", "Health bar's share of the stack; mana gets the rest.", 0.4, 0.85, 0.01, FormatPercent)
    Slider({ "squareGap" }, "Gap to bars", "Space between the box and the bars (1 = borders share one line).", 0, 20, 1)
    Slider({ "barSpacing" }, "Bar spacing", "Space between health and mana (0 = borders share one line).", 0, 10, 1)
    Check({ "alignMana" }, "Align mana bar", "Line the mana bar up with the health bar next to the box.")

    Header("Borders")
    local colorGet, colorSet, colorDefault = Path({ "borderColor" })
    Settings.CreateColorSwatch(category, Register("borderColor", "Border Color", colorDefault, colorGet, colorSet),
        "Color of the 1px lines around the portrait box and the health and mana bars.")
    local sizeGet, sizeSet, sizeDefault = Path({ "borderSize" })
    Settings.CreateDropdown(category, Register("borderSize", "Border Thickness", sizeDefault, sizeGet, sizeSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add(1, "Thin")
        c:Add(2, "Medium")
        c:Add(3, "Heavy")
        return c:GetData()
    end, "Thickness of the lines around the portrait box and the bars.")
    Slider({ "borderAlpha" }, "Border Opacity", "Opacity of the 1px lines around the portrait box and the bars.", 0, 1, 0.05, FormatPercent)

    Header("Text")
    Check({ "showBuild" }, "Show Talent Build", "Points per talent tree (like 2/8/0) on the player, target and focus frames. Other players need to be within inspect range (about 30 yards); NPCs show nothing.")
    Check({ "mirrorTarget" }, "Mirror Target Text", "Target and focus: name and talent build next to the portrait, level on the outer edge, mirroring the player frame.")

    Header("Elite and rare")
    Check({ "eliteBorder" }, "Elite Border", "Target and focus: the portrait and bar borders turn gold for elites and bosses, silver for rares.")
    for _, c in ipairs({ { "eliteColor", "Elite Border Color", "Border color for elite and boss targets." },
                         { "rareColor", "Rare Border Color", "Border color for rare and rare elite targets." } }) do
        local get, set, default = Path({ c[1] })
        Settings.CreateColorSwatch(category, Register(c[1], c[2], default, get, set), c[3])
    end
    local eliteGet, eliteSet, eliteDefault = Path({ "eliteIcon" })
    Settings.CreateDropdown(category, Register("eliteIcon", "Elite Icon", eliteDefault, eliteGet, eliteSet), function()
        local c = Settings.CreateControlTextContainer()
        c:Add("top", "Portrait top corner")
        c:Add("bottom", "Portrait bottom corner")
        c:Add("center", "Portrait bottom center")
        c:Add("level", "Next to level")
        c:Add("hidden", "Hidden")
        return c:GetData()
    end, "Target and focus: where the small elite/rare icon goes. The corners are on the portrait's outer side.")

    Page("Circle Style")
    Header("Camera")
    Slider({ "sizes", "large", "cam" }, "Distance: large frames", "Player, target and focus. Lower = closer, bigger face.", 0.3, 2, 0.05)
    Slider({ "sizes", "small", "cam" }, "Distance: small frames", "Target of target and party. Lower = closer, bigger face.", 0.3, 2, 0.05)
    Header("Portrait")
    Slider({ "circleBg" }, "Background", "Dark background inside the ring (0 = clear).", 0, 1, 0.05, FormatPercent)
    Check({ "vignette" }, "Round edge", "The circle edge that hides the model's square corners.")
    Slider({ "sizes", "large", "inset" }, "Model size: large frames", "Model size relative to the portrait.", 0.3, 1.2, 0.01)
    Slider({ "sizes", "small", "inset" }, "Model size: small frames", "Model size relative to the portrait.", 0.3, 1.2, 0.01)

    category, layout = main, SettingsPanel:GetLayout(main)
    Settings.RegisterAddOnCategory(category)
    optionsCategory = category
end

local function OpenOptions()
    if optionsCategory and Settings.OpenToCategory then
        Settings.OpenToCategory(optionsCategory:GetID())
        return true
    end
end

-- Old install ---------------------------------------------------------------
-- Until v0.2.1 this addon was "BBF_AnimatedPortraits". If that folder is still installed
-- and enabled, both addons draw models and lay out the bars on the same frames. Offer to
-- disable it (Blizzard's own pattern: DisableAddOn, then reload), once per session.
local OLD_ADDON = "BBF_AnimatedPortraits"
local oldAddonWarned = false

CheckOldAddon = function()
    local api = C_AddOns
    if oldAddonWarned or not (api and api.IsAddOnLoaded and api.IsAddOnLoaded(OLD_ADDON)) then return end
    oldAddonWarned = true
    print(PREFIX .. "replaces BBF Animated Portraits, which is still enabled. Disable it, then delete the "
        .. OLD_ADDON .. " folder from your AddOns.")
    if not (StaticPopupDialogs and StaticPopup_Show and api.DisableAddOn) then return end
    StaticPopupDialogs.LIVING_PORTRAITS_OLD_ADDON = StaticPopupDialogs.LIVING_PORTRAITS_OLD_ADDON or {
        text = "LivingPortraits is the new name of BBF Animated Portraits, but the old version is still enabled. "
            .. "Running both breaks your unit frames.\n\nDisable the old version and reload?",
        button1 = DISABLE or "Disable",
        button2 = IGNORE_DIALOG or "Ignore",
        OnAccept = function()
            api.DisableAddOn(OLD_ADDON)
            ReloadUI()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("LIVING_PORTRAITS_OLD_ADDON")
end

-- Slash command: /lp --------------------------------------------------------

local function PrintStatus()
    local on = {}
    for name, list in pairs(GROUPS) do
        if db.units[list[1]] then on[#on + 1] = name end
    end
    table.sort(on)
    local L, S = db.sizes.large, db.sizes.small
    print("Living|cff00c0ffPortraits|r  enabled=" .. tostring(db.enabled)
        .. "  style=" .. db.style .. "  zoom=" .. db.zoom .. "  vignette=" .. tostring(db.vignette)
        .. "  grow=" .. tostring(db.growBars) .. (" (%.2fs)"):format(db.growTime) .. "  units=" .. (#on > 0 and table.concat(on, ",") or "none"))
    local Q = db.sizes.square
    print(("  circle large: inset=%.2f cam=%.2f   small: inset=%.2f cam=%.2f"):format(L.inset, L.cam, S.inset, S.cam))
    print(("  box: cam=%.2f bg=%.2f gap=%d alignmana=%s split=%.2f  extend: large=%d small=%d"):format(
        Q.cam, db.squareBg, db.squareGap, tostring(db.alignMana), db.hpShare, db.stackExtra.large, db.stackExtra.small))
    print(("  name rows: large=%d tot=%d party=%d   build=%s tall=%s hidesurnames=%s"):format(db.nameRow.large,
        db.nameRow.tot, db.nameRow.party, tostring(db.showBuild), ("player=%s target=%s party=%s"):format(tostring(db.tallPortraits.player),
        tostring(db.tallPortraits.target), tostring(db.tallPortraits.party)), tostring(db.hideSurname)))
end

local function PrintHelp()
    print("  /lp options  |  /lp bbfsetup (turn on BBF's Pixel Border mode)  |  /lp bbfundo")
    print("  /lp toggle  |  /lp vignette  |  /lp zoom 0-1  |  /lp grow  |  /lp growtime 0.1-2  |  /lp reset")
    print("  /lp style box|circle  |  /lp bg 0-1  |  /lp extend 0-30 [large|small]  |  /lp split 0.4-0.85")
    print("  /lp namerow 0-24 [large|tot|party]  |  /lp gap 0-20  |  /lp barspacing 0-10  |  /lp alignmana  |  /lp build  |  /lp tall [player|target|party]  |  /lp surname  |  /lp mirror  |  /lp eliteborder  |  /lp eliteicon top|bottom|center|level|hidden")
    print("  /lp elitecolor RRGGBB  |  /lp rarecolor RRGGBB")
    print("  /lp bordercolor RRGGBB  |  /lp borderalpha 0-1  |  /lp bordersize thin|medium|heavy")
    print("  /lp inset 0.3-1.2 [large|small]  |  /lp cam 0.3-2 [large|small|box]")
    print("  /lp unit player|target|focus|tot|party  |  /lp refresh  |  /lp debug [unit]")
    print("  circle: /lp circlebg 0-1  |  /lp vignette  |  /lp calibrate  |  /lp offset player|target|focus|tot|party x y")
end

-- Set a per-group value (tbl[group], or tbl[group][key]); no group given = all of them.
local function SetEach(tbl, only, value, key)
    for name in pairs(tbl) do
        if not only or only == name then
            if key then tbl[name][key] = value else tbl[name] = value end
        end
    end
end

-- /lp debug [unit]: print the square layout's real geometry, for bug reports.
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
    print(("|cff00c0ffLP debug|r %s  style=%s  bbfNoPortrait=%s"):format(unit, db.style, tostring(BBFHidesPortrait(unit))))
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

-- On/off settings: command -> db key.
local SLASH_TOGGLES = {
    toggle = "enabled", vignette = "vignette", grow = "growBars", alignmana = "alignMana",
    build = "showBuild", surname = "hideSurname", mirror = "mirrorTarget", eliteborder = "eliteBorder",
}
-- Number settings: command -> { db key, min, max }.
local SLASH_NUMBERS = {
    growtime = { "growTime", 0.1, 2 }, split = { "hpShare", 0.4, 0.85 }, zoom = { "zoom", 0, 1 },
    circlebg = { "circleBg", 0, 1 }, bg = { "squareBg", 0, 1 },
    gap = { "squareGap", 0, 20 }, barspacing = { "barSpacing", 0, 10 }, borderalpha = { "borderAlpha", 0, 1 },
    bordersize = { "borderSize", 1, 3 },
}

SLASH_LIVINGPORTRAITS1 = "/lp"
SLASH_LIVINGPORTRAITS2 = "/livingportraits"
SLASH_LIVINGPORTRAITS3 = "/bap" -- the name before Living Portraits
SlashCmdList.LIVINGPORTRAITS = function(msg)
    local args = {}
    for word in (msg or ""):lower():gmatch("%S+") do args[#args + 1] = word end
    local cmd, arg, size = args[1], args[2], args[3]
    local val = tonumber(arg)
    if size == "box" then size = "square" end -- the box style's camera (stored as "square")
    if size and not db.sizes[size] then size = nil end

    if cmd == "options" or cmd == "config" then
        if not OpenOptions() then print("  The settings panel isn't available on this client.") end
        return
    elseif cmd == "bbfsetup" then
        print("  " .. ApplyBBFSetup())
        return
    elseif cmd == "bbfundo" then
        print("  " .. UndoBBFSetup())
        return
    elseif cmd == "debug" then
        DebugUnit(arg or "target")
        return
    elseif cmd == "refresh" then
        RefreshAll()
        return
    elseif cmd == "grow" and arg == "debug" then
        growDebug = not growDebug
        print("  grow debug " .. (growDebug and "on: change targets and watch chat." or "off."))
        return
    elseif cmd == "eliteicon" then
        local modes = { top = "top", bottom = "bottom", center = "center", level = "level", hidden = "hidden", off = "hidden" }
        if not modes[arg or ""] then
            print("  /lp eliteicon top|bottom|center|level|hidden  (now " .. tostring(db.eliteIcon) .. ")")
            return
        end
        db.eliteIcon = modes[arg]
    elseif cmd == "tall" then
        -- No group: player + target/focus together (party has its own switch).
        local t = db.tallPortraits
        local group = arg == "focus" and "target" or arg
        if group == "player" or group == "target" or group == "party" then
            t[group] = not t[group]
        elseif not arg then
            local on = not (t.player and t.target)
            t.player, t.target = on, on
        else
            print("  /lp tall [player|target|party]")
            return
        end
        print(("  tall: player=%s target=%s party=%s"):format(tostring(t.player), tostring(t.target), tostring(t.party)))
    elseif SLASH_TOGGLES[cmd] then
        local key = SLASH_TOGGLES[cmd]
        db[key] = not db[key]
    elseif SLASH_NUMBERS[cmd] and val then
        local n = SLASH_NUMBERS[cmd]
        db[n[1]] = Clamp(val, n[2], n[3])
    elseif cmd == "calibrate" then
        db.calibrate = not db.calibrate
        print(db.calibrate and "  Calibrate on: nudge with /lp offset <player|target|focus|tot|party> x y, then /lp calibrate to finish."
            or "  Calibrate off.")
    elseif cmd == "offset" and arg and db.offsets[arg] then
        local x, y = tonumber(args[3]), tonumber(args[4])
        if x and y then db.offsets[arg] = { Clamp(x, -10, 10), Clamp(y, -10, 10) } end
        print(("  offset %s = %s, %s"):format(arg, tostring(db.offsets[arg][1]), tostring(db.offsets[arg][2])))
    elseif cmd == "style" and (arg == "box" or arg == "square" or arg == "circle") then
        if arg == "box" then arg = "square" end -- shown as "Box", stored as "square" (older name)
        db.style = arg
    elseif cmd == "extend" and val then
        SetEach(db.stackExtra, size, Clamp(val, 0, 30))
    elseif cmd == "namerow" and val then
        SetEach(db.nameRow, args[3], Clamp(val, 0, 24))
    elseif cmd == "bordersize" and BORDER_SIZES[arg] then
        db.borderSize = BORDER_SIZES[arg]
    elseif cmd == "bordercolor" and arg and arg:match("^%x%x%x%x%x%x$") then
        db.borderColor = "ff" .. arg
    elseif (cmd == "elitecolor" or cmd == "rarecolor") and arg and arg:match("^%x%x%x%x%x%x$") then
        db[cmd == "elitecolor" and "eliteColor" or "rareColor"] = "ff" .. arg
    elseif cmd == "inset" and val then
        SetEach(db.sizes, size, Clamp(val, 0.3, 1.2), "inset")
    elseif cmd == "cam" and val then
        SetEach(db.sizes, size, Clamp(val, 0.3, 2), "cam")
    elseif cmd == "unit" and arg and GROUPS[arg] then
        local list = GROUPS[arg]
        local newValue = not db.units[list[1]]
        for _, unit in ipairs(list) do db.units[unit] = newValue end
    elseif cmd == "reset" then
        local backup = db.bbfBackup -- keep BBF's Undo
        wipe(db); CopyDefaults(defaults, db); db.version = SETTINGS_VERSION
        db.bbfBackup = backup
    else
        PrintStatus()
        PrintHelp()
        return
    end
    RefreshAll() -- also re-applies the talent build and surnames
    NotifyOptions()
    PrintStatus()
end
