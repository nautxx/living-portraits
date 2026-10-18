local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local PARTY = ns.PARTY
local UNITS = ns.UNITS
local Lookup = ns.Lookup
local UnitFrameOf = ns.UnitFrameOf
local AsText = ns.AsText
local Safe = ns.Safe

-- Name texts ------------------------------------------------------------------
-- Camelot characters have a surname: UnitName returns (name, surname) and Blizzard's
-- frames show both. Our frames' name texts are rewritten in a post-hook on SetText, so it
-- follows every name update by Blizzard or BBF: the text they set (kept as bapRawText), minus
-- the surname with hideSurname, plus the class after it with classText "name" (classText.lua).
-- Only those parts change, so BBF's formatting (colors, prefixes) stays; turning a setting off
-- writes the text back from bapRawText.
local SURNAME_UNITS = { "player", "target", "focus", "targettarget", "focustarget", unpack(PARTY) }
local ClassSuffix = ns.ClassSuffix

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

-- What the name text should show for Blizzard's/BBF's text `raw`.
local function Compose(fs, raw)
    local text, unit = raw, fs.bapNameUnit
    local surname = db.hideSurname and SurnameOf(unit)
    if surname then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        local i, j = text:find(sep .. surname, 1, true)
        if i then text = text:sub(1, i - 1) .. text:sub(j + 1) end
    end
    local class = ClassSuffix(unit)
    if class and text ~= "" then text = text .. " " .. class end
    return text
end

local function OnNameText(fs)
    if fs.bapNaming or not db then return end
    local text = Safe(fs:GetText())
    if type(text) ~= "string" then return end
    fs.bapRawText = text
    local shown = Compose(fs, text)
    if shown ~= text then SetNameText(fs, shown) end
end

-- Hook a name text once; the hook then follows every name change by itself.
local function HookName(fs, unit)
    if not fs or fs.bapNameHook or not fs.SetText then return end
    fs.bapNameHook, fs.bapNameUnit = true, unit
    hooksecurefunc(fs, "SetText", OnNameText)
    OnNameText(fs) -- its current text
end

-- Re-apply the settings to one name text (after a setting change or a refresh).
local function ApplyName(fs)
    local raw = fs and fs.bapRawText
    if not raw then return end
    local shown = Compose(fs, raw)
    if Safe(fs:GetText()) ~= shown then SetNameText(fs, shown) end
end

-- From the ticker: hook name texts as they appear (BBF creates bbfName after us). With
-- `apply` (after a refresh or a toggle): also re-apply the settings to every name now.
local function UpdateSurnames(apply)
    if not db then return end
    for _, unit in ipairs(SURNAME_UNITS) do
        local a, b = NameTextsOf(unit)
        HookName(a, unit); HookName(b, unit)
        if apply then ApplyName(a); ApplyName(b) end
    end
end

ns.UpdateSurnames = UpdateSurnames
