-- Class name on the player, target and focus (players only), in the class's color: for people
-- who don't use BBF's class-colored health bars and still want to see the class at a glance.
-- db.classText picks where (players asked for a choice):
--   "build": in the talent build text, before the points ("Warrior 2/8/0"): on its own line above
--            the name with tall portraits, else next to the level (talentBuild.lua places it).
--   "level": on the build line, on the level's side (above the level); without that line
--            (tall portraits off) it joins the build text like "build".
--   "name":  after the name ("Naut Warrior"), added in the name text rewrite (surnames.lua), so
--            the name's fitted width, its cap and the status icons after it all follow.
--   "off".
-- The build line only exists in the box style with a name row; elsewhere (circle style) "build"
-- and "level" fall back to "name", so the class always shows somewhere once it's on.

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UNITS = ns.UNITS
local Safe = ns.Safe
local BBFHidesPortrait = ns.BBFHidesPortrait

local CLASS_UNITS = { player = true, target = true, focus = true }
local CLASS_TEXT_MODES = { off = true, build = true, name = true, level = true }

-- The talent build's line (and the class text's) exists only where the box style draws the
-- unit's name row.
local function BuildLineVisible(unit)
    return db and db.enabled and db.units[unit] and db.style == "square"
        and (db.nameRow[UNITS[unit].row] or 0) > 0 and BBFHidesPortrait(unit) and true or false
end

-- The unit's class name in its class color, for players; nil otherwise (NPCs, secret values).
local function ClassLabel(unit)
    if not Safe(UnitIsPlayer(unit)) then return end
    local name, file = UnitClass(unit)
    name, file = Safe(name), Safe(file)
    if type(name) ~= "string" or name == "" then return end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if c and type(c.colorStr) == "string" then return "|c" .. c.colorStr .. name .. "|r" end
    return name
end

-- Where the class goes for this unit right now: "build", "level", "name", or nil (off, other
-- frames). "build"/"level" without a build line become "name".
local function ClassTextMode(unit)
    if not (db and CLASS_UNITS[unit]) then return end
    local mode = db.classText
    if not CLASS_TEXT_MODES[mode] or mode == "off" then return end
    if mode ~= "name" and not BuildLineVisible(unit) then return "name" end
    return mode
end

-- For the name text rewrite: the class to add after the name, or nil.
local function ClassSuffix(unit)
    if ClassTextMode(unit) == "name" then return ClassLabel(unit) end
end

ns.CLASS_TEXT_MODES = CLASS_TEXT_MODES
ns.BuildLineVisible = BuildLineVisible
ns.ClassLabel = ClassLabel
ns.ClassTextMode = ClassTextMode
ns.ClassSuffix = ClassSuffix
