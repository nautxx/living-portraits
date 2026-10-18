-- Living Portraits (a BetterBlizzFrames companion)
-- Replaces the flat 2D unit-frame portrait with a live 3D model (idle "breathing"
-- animation, like the character screen). Companion to BetterBlizzFrames; never edits BBF.
--
-- Two styles: the box (modules/box.lua) when BBF's No Portrait / Pixel Border mode is on,
-- else the circle inside Blizzard's round portrait (modules/circle.lua).
--
-- Files share the addon namespace `ns`. Core.lua loads first: settings, shared helpers,
-- shared state and refresh scheduling. Each file keeps its own locals and puts on `ns`
-- what other files use. The .toc order is the load order: a file copies an earlier file's
-- exports into locals at the top, and calls into later files go through `ns` at call time.

local _, ns = ...
ns.PREFIX = "Living|cff00c0ffPortraits|r " -- chat prefix

-- Bump when a default changes in a way saved settings should pick up (see MigrateSettings).
local SETTINGS_VERSION = 13

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
    -- Class name in class color on the player, target and focus (players): "off", "build" (in the
    -- talent build text), "level" (above the level), "name" (after the name) (/lp classtext).
    classText   = "off",
    eliteBorder = false, -- square: target/focus box border gold for elite/boss, silver for rare (/lp eliteborder)
    eliteColor  = "ffffc71a", -- square: elite/boss border color, ARGB hex like the settings swatch (/lp elitecolor)
    rareColor   = "ffc7ccdb", -- square: rare/rare elite border color (/lp rarecolor)
    -- Square: where the target/focus elite icon goes: "top"/"bottom" (outer corner of the
    -- portrait box), "center" (bottom center of the box), "level" (beside the level), "hidden".
    eliteIcon   = "bottom",
    -- Square: the box grows upward by a line (the talent build's, above the name), per group:
    -- player, target (target + focus), party. ToT stays square (/lp tall [group]).
    tallPortraits = { player = true, target = true, party = true },
    hideSurname = true, -- first names only on our frames (/lp surname)
    mirrorTarget = true, -- square: target/focus text mirrors the player's (/lp mirror)
    restIcon    = "corner", -- square: resting Zzz on the portrait box's top-right corner, or "name" (after it) (/lp resticon)
    -- Health/mana text on player, target, focus and party bars, left-aligned and always shown:
    -- "default" (Blizzard/BBF's text), "max" = "350 (462)", "percent" = "350 (76%)" (/lp bartext).
    barText     = "max",
    -- Its look: "shadow" (default), "outline_shadow", "outline", "thick", "thick_shadow" (/lp bartextstyle).
    barTextStyle = "shadow",
    -- Square: the player's class resource (rogue/druid combo points, warlock shards, mage arcane
    -- charges, paladin holy charges) under the bars: "pixel" (our circles, bordered like the box)
    -- "bbf" (rogue/druid: BBF's own combo point art there) or "none" (hidden) (/lp resource).
    resource       = "pixel",
    resourceAlign  = "right",  -- under the mana bar: "left", "center" or "right" (/lp resourcealign)
    resourceRadius = 5,        -- circle radius in px inside the border (/lp resourcesize)
    -- A filled circle's color per resource, ARGB hex (/lp resourcecolor [combo|shards|arcane|holy] RRGGBB).
    resourceColors = { combo = "ffe62e2e", shards = "ffa15cff", arcane = "ff4db8ff", holy = "ffffd633" },
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

-- Saved settings ------------------------------------------------------------
-- db is nil until ADDON_LOADED. Every file keeps its own `db` local, set from here:
--   local db; ns.OnLoad(function(saved) db = saved end)
-- /lp reset wipes the table in place, so those references stay valid.
local db
local onLoad = {}
function ns.OnLoad(fn) onLoad[#onLoad + 1] = fn end

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

-- BBF's No Portrait mode is on for the unit. BBF.HasNoPortrait ignores Classic Frames, but with
-- that on BBF draws its classic round portrait instead (it builds Classic Frames first).
local function BBFHidesPortrait(unit)
    local bdb = BetterBlizzFramesDB
    if type(bdb) == "table" and bdb.classicFrames then return false end
    return BBF and BBF.HasNoPortrait and BBF.HasNoPortrait(unit)
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

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
    if version < 12 then
        -- v12: drop keys from removed experiments (model facing/shift, mirror angle, build row).
        db.shift, db.facing, db.mirrorAngle, db.mirrorShift, db.buildRow = nil, nil, nil, nil, nil
    end
    if version < 13 then
        -- v13: Jason's settings became the defaults. Every install saved the old defaults on its
        -- first load, so move a key only while it still holds the old default (a value someone
        -- picked stays). Also drop the class resource's dev-build keys (comboPoints and co.).
        local OLD = {
            barText = "default", barTextStyle = "outline_shadow", eliteIcon = "center", eliteBorder = true,
            restIcon = "name", resourceAlign = "center", resourceRadius = 6,
        }
        for key, old in pairs(OLD) do
            if db[key] == old then db[key] = defaults[key] end
        end
        db.comboPoints, db.comboAlign, db.comboRadius, db.comboColor = nil, nil, nil, nil
    end
    db.version = SETTINGS_VERSION
end

-- ADDON_LOADED: load, migrate and fill in the saved settings, then hand them to every file.
function ns.LoadSettings()
    LivingPortraitsDB = LivingPortraitsDB or {}
    db = LivingPortraitsDB
    MigrateSettings()
    CopyDefaults(defaults, db)
    for _, fn in ipairs(onLoad) do fn(db) end
end

local function ApplyCamera(model, size)
    model:SetPortraitZoom(db.zoom)
    model:SetCamDistanceScale(db.sizes[size].cam)
    model:SetPosition(0, 0, 0)
end

-- Shared state --------------------------------------------------------------
ns.layers = {}     -- unit -> circle layer record (modules/circle.lua)
ns.squares = {}    -- unit -> box record (modules/box.lua)
ns.buildTexts = {} -- unit -> talent build FontString ("2/8/0"), created on first use (modules/talentBuild.lua)

-- Refresh scheduling --------------------------------------------------------
-- Refresh and RefreshAll themselves are in Refresh.lua (loaded last).

-- Coalesce refresh requests per unit into one refresh on the next frame. Every Refresh
-- reloads the 3D model (ClearModel + SetUnit), and one target change fires several events
-- (PLAYER_TARGET_CHANGED, UNIT_TARGET, UNIT_PORTRAIT_UPDATE) that each asked for one.
local queued = {} -- unit -> true
local flushQueued = false
local function FlushRefreshes()
    flushQueued = false
    for _, unit in ipairs(ns.UNIT_LIST) do -- Units.lua, loaded after this file
        if queued[unit] then
            queued[unit] = nil
            ns.Refresh(unit)
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
        ns.Refresh(unit)
    end)
end

-- Coalesce bursts of refresh requests (BBF re-layouts often call several functions).
local refreshQueued = false
local function QueueRefreshAll()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        ns.RefreshAll()
    end)
end

ns.SETTINGS_VERSION = SETTINGS_VERSION
ns.defaults = defaults
ns.CopyDefaults = CopyDefaults
ns.IsSecret = IsSecret
ns.Safe = Safe
ns.AnySecret = AnySecret
ns.BBFHidesPortrait = BBFHidesPortrait
ns.Clamp = Clamp
ns.ApplyCamera = ApplyCamera
ns.QueueRefresh = QueueRefresh
ns.QueueRefreshAll = QueueRefreshAll
ns.RetryRefresh = RetryRefresh
ns.retryDelay = retryDelay
