local _, ns = ...

local PARTY = { "party1", "party2", "party3", "party4" }

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

ns.PARTY = PARTY
ns.UNITS = UNITS
ns.UNIT_LIST = UNIT_LIST
ns.GROUPS = GROUPS
ns.UnitFrameOf = UnitFrameOf
ns.Lookup = Lookup
ns.AsText = AsText
