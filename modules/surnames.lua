local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local PARTY = ns.PARTY
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local UnitFrameOf = ns.UnitFrameOf
local AsText = ns.AsText
local Safe = ns.Safe

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

ns.UpdateSurnames = UpdateSurnames
