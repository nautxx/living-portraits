local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local SETTINGS_VERSION = ns.SETTINGS_VERSION
local defaults = ns.defaults
local CopyDefaults = ns.CopyDefaults
local Clamp = ns.Clamp
local Safe = ns.Safe
local GROUPS = ns.GROUPS
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local BBFHidesPortrait = ns.BBFHidesPortrait
local layers = ns.layers
local squares = ns.squares
local GetBarFrames = ns.GetBarFrames
local BORDER_SIZES = ns.BORDER_SIZES
local RefreshAll = ns.RefreshAll
local ToggleGrowDebug = ns.ToggleGrowDebug
local BAR_TEXT_MODES = ns.BAR_TEXT_MODES
local BAR_TEXT_STYLES = ns.BAR_TEXT_STYLES
local UpdateBarTexts = ns.UpdateBarTexts
local ApplyBBFSetup = ns.ApplyBBFSetup
local UndoBBFSetup = ns.UndoBBFSetup
local OpenOptions = ns.OpenOptions
local NotifyOptions = ns.NotifyOptions

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
    print("  /lp elitecolor RRGGBB  |  /lp rarecolor RRGGBB  |  /lp bartext default|max|percent")
    print("  /lp bartextstyle outline_shadow|outline|shadow|thick|thick_shadow")
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
    for _, b in ipairs({ { "hp", hpBar }, { "mana", manaBar } }) do
        local bar, fs = b[2], b[2] and b[2].bapText
        if bar then
            local p = fs and fs:GetParent()
            print(("  bartext %s: method=%s hook=%s fs=%s shown=%s visible=%s alpha=%s text=%s parent=%s(vis=%s)"):format(
                b[1], T(bar.UpdateTextStringWithValues ~= nil), T(bar.bapTextHook), T(fs ~= nil),
                T(fs and fs:IsShown()), T(fs and fs:IsVisible()), Fmt(fs and fs:GetAlpha()),
                T(fs and Safe(fs:GetText())), T(p and (p:GetName() or "anon")), T(p and p:IsVisible())))
        end
    end
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
        local on = ToggleGrowDebug()
        print("  grow debug " .. (on and "on: change targets and watch chat." or "off."))
        return
    elseif cmd == "bartextstyle" then
        if not BAR_TEXT_STYLES[arg or ""] then
            print("  /lp bartextstyle outline_shadow|outline|shadow|thick|thick_shadow  (now " .. tostring(db.barTextStyle) .. ")")
            return
        end
        db.barTextStyle = arg
        UpdateBarTexts()
    elseif cmd == "bartext" then
        if not BAR_TEXT_MODES[arg or ""] then
            print("  /lp bartext default|max|percent  (now " .. tostring(db.barText) .. ")")
            return
        end
        db.barText = arg
        UpdateBarTexts(true)
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
