-- Profiles: a whole look in one click, Living Portraits' settings and BetterBlizzFrames' together
-- (one profile recreates the same frames on another PC). Built-in profiles (PROFILES, Jason's
-- "Naut" first) and export/import strings to share your own. Loading one replaces both addons'
-- settings after a backup; Undo (modules/bbfSetup.lua) puts both back.
-- Strings are LibSerialize + LibDeflate, the libraries BBF ships (and uses for its own import
-- codes), so export/import needs BBF loaded. Nothing in a string is ever run as code: our own
-- settings are checked key by key against the defaults, BBF's are written like BBF's importer does.

local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local defaults = ns.defaults
local SETTINGS_VERSION = ns.SETTINGS_VERSION
local Copy = ns.DeepCopy
local BaseProfile = ns.BaseProfile
local BBFLoaded = ns.BBFLoaded
local WriteBBF = ns.WriteBBF
local ShowReloadPopup = ns.ShowReloadPopup

-- One entry per built-in profile; the panel shows a button each, named after it, in this order.
-- To add one (a friend's config): name (button, /lp profile <name>), desc (tooltip), class
-- (optional, e.g. "PALADIN": the button name in that class's color), then either `string` = their export string (/lp export: both addons' settings,
-- the easy way to add a friend), or lp = our settings that differ from the defaults (the rest are
-- defaults), bbfBase = one of BBF's built-in profiles to start from (optional), bbf = BBF settings
-- on top.
-- Jason's BBF unit frame look, on top of Bodify and Pixel Border mode (BBF_MODE). Picked from a
-- diff of his saved BBF settings; the fonts and textures named here all ship with BBF (its
-- LibSharedMedia and media folder), so it looks the same on any install.
local NAUT_LOOK = {
    -- Fonts: names/levels, bar numbers, party, action bars and their cooldowns (BBF's Fonts
    -- section, all on except "One font for all text ingame").
    changeUnitFrameFont = true, unitFrameFont = "2002", unitFrameFontSize = 8, unitFrameFontOutline = "",
    unitFrameFontColor = false, unitFrameFontColorLvl = true, unitFrameFontColorRGB = { 0.953, 1, 0.969, 1 },
    changeUnitFrameValueFont = true, unitFrameValueFont = "Arial Narrow", unitFrameValueFontSize = 7,
    unitFrameValueFontOutline = "OUTLINE", unitFrameValueFontColor = true,
    changePartyFrameFont = true, partyFrameFont = "2002",
    changeActionBarFont = true, actionBarFont = "2002", changeActionBarCDFont = true, actionBarCDFont = "2002",
    changeAllFontsIngame = false,
    -- Textures (BBF's UnitFrame Textures section, all on): health, mana, cast bar, the background
    -- behind the bars, XP/reputation bar; smooth bar changes.
    changeUnitFrameHealthbarTexture = true, unitFrameHealthbarTexture = "Solid",
    changeUnitFrameManabarTexture = true, unitFrameManabarTexture = "Blizzard Retail Bar Crop 2",
    changeUnitFrameManaBarTextureKeepFancy = true, addUnitFrameBgTexture = true,
    changeUnitFrameCastbarTexture = true, unitFrameCastbarTexture = "Solid",
    changeXpBarTexture = true, xpBarTexture = "Solid",
    smoothHealthbars = true, smoothManabars = true,
    -- Class colors on health bars and target names.
    classColorFrames = true, classColorTargetNames = true,
    -- Combo points under the player frame (our class resource moves and restyles that bar).
    foreverComboPoints = true, instantComboPoints = true, enableLegacyComboPoints = false,
    -- Target-of-target and focus-target placement that fits the taller box layout.
    targetToTScale = 0.97, targetToTXPos = -1, targetToTYPos = 17,
    focusToTScale = 0.97, focusToTXPos = -1, focusToTYPos = 17,
    -- Clutter that would sit on or around the portrait box and name row.
    hideTargetReputationColor = true, hideFocusReputationColor = true, hideCombatGlow = true,
    hideHitIndicator = true, hidePetHitIndicator = true, hidePvpIcon = true, hidePrestigeBadge = true,
    hideGroupIndicator = true, hidePlayerLeaderIcon = true, hideTargetLeaderIcon = true,
    hideFocusLeaderIcon = true, hidePlayerGuideIcon = true,
}

-- Starter's BBF changes on top of BBF's Starter profile and Pixel Border mode, saved from Jason's
-- in-game setup (2026-10-18): health/mana texture switches on (BBF's own Pixel Border checkbox
-- turns these on; no texture named = LSM's default bar) and realm names kept.
local STARTER_LOOK = {
    changeUnitFrameHealthbarTexture = true, changeUnitFrameManabarTexture = true,
    removeRealmNames = false,
}

local function Merge(...)
    local t = {}
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do t[k] = v end
    end
    return t
end

local PROFILES = {
    {
        name = "Starter",
        desc = "A clean starting point: square box portraits with the elite border, full names, no talent builds and Blizzard's bar text, on BetterBlizzFrames' own Starter profile with Pixel Border mode.",
        lp = {
            eliteBorder = true, tallPortraits = { player = false, target = false, party = false },
            hideSurname = false, showBuild = false, barText = "default",
        },
        bbfBase = "Starter",
        bbf = Merge(ns.BBF_MODE, STARTER_LOOK),
    },
    {
        name = "Naut",
        class = "PALADIN",
        desc = "Jason's setup: tall box portraits with bar text and class resource circles, and BetterBlizzFrames' Bodify profile with Pixel Border mode and his unit frame look (fonts, textures, class colors, combo points, target-of-target placement, less clutter).",
        lp = {
            barText = "max", barTextStyle = "shadow", eliteIcon = "bottom", eliteBorder = false,
            restIcon = "corner", resourceAlign = "right", resourceRadius = 5,
        },
        bbfBase = "Bodify",
        bbf = Merge(ns.BBF_MODE, NAUT_LOOK),
    },
    {
        -- Saved from Jason's in-game setup (2026-10-18): BBF was exactly its Forever profile.
        name = "BlizzFrames",
        desc = "Living portraits in the round portrait, on BetterBlizzFrames' Forever profile (its Classic Frames look): bigger player, target and focus models, Blizzard's bar text, full names and no talent builds.",
        lp = {
            style = "circle", sizes = { large = { inset = 0.9 } }, barText = "default",
            eliteBorder = true, tallPortraits = { player = false, target = false, party = false },
            hideSurname = false, showBuild = false,
        },
        bbfBase = "Forever",
    },
}

local STRING_PREFIX = "!LP1!" -- format 1
local LP_SKIP = { bbfBackup = true, bbfBackupFull = true, lpBackup = true, welcomed = true } -- never exported or imported

local function FindProfile(name)
    name = name and name:lower()
    for _, p in ipairs(PROFILES) do
        if p.name:lower() == name then return p end
    end
end

-- BBF's serializer and compressor, or nil without BBF.
local function Libs()
    if not LibStub then return end
    local deflate = LibStub:GetLibrary("LibDeflate", true)
    local serialize = LibStub:GetLibrary("LibSerialize", true) or LibStub:GetLibrary("LibSerialize-BB", true)
    if deflate and serialize then return deflate, serialize end
end

-- Our settings without the Undo backups.
local function LPSettings()
    local t = {}
    for k, v in pairs(db) do
        if not LP_SKIP[k] then t[k] = Copy(v) end
    end
    return t
end

-- Keep only values that match the defaults' shape: known keys, same types, tables checked inside
-- (units and other keyed tables keep their known keys). Anything else in an imported string goes.
local function Sanitize(src, def)
    local out = {}
    for k, v in pairs(src) do
        local d = def[k]
        if type(d) == "table" and type(v) == "table" then
            out[k] = Sanitize(v, d)
        elseif d ~= nil and type(v) == type(d) then
            out[k] = v
        end
    end
    return out
end

-- Replace our settings with `lp` (backup first, once), then migrate and fill in defaults.
local function ApplyLP(lp)
    if not db.lpBackup then db.lpBackup = LPSettings() end
    local keep = { bbfBackup = db.bbfBackup, bbfBackupFull = db.bbfBackupFull, lpBackup = db.lpBackup, welcomed = db.welcomed }
    local version = type(lp.version) == "number" and lp.version or SETTINGS_VERSION
    local clean = Sanitize(lp, defaults)
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(clean) do db[k] = Copy(v) end
    for k, v in pairs(keep) do db[k] = v end
    db.version = math.min(version, SETTINGS_VERSION)
    ns.LoadSettings() -- every file keeps the same table
end

-- Both return a line for chat.
local Import -- below

local function LoadProfile(name)
    local p = FindProfile(name)
    if not p then return "No profile named " .. tostring(name) .. "." end
    if p.string then return (Import(p.string, p.name)) end
    ApplyLP(p.lp)
    local bbfNote = ""
    if BBFLoaded() then
        local base = p.bbfBase and BaseProfile(p.bbfBase)
        WriteBBF(base, p.bbf)
        if p.bbfBase and not base then bbfNote = " (BetterBlizzFrames' " .. p.bbfBase .. " profile wasn't found)" end
        ShowReloadPopup()
        return "Loaded the " .. p.name .. " profile" .. bbfNote .. ". Reload the UI to apply it."
    end
    ns.RefreshAll()
    return "Loaded the " .. p.name .. " profile (Living Portraits only: BetterBlizzFrames isn't loaded)."
end

local function ExportString()
    local deflate, serialize = Libs()
    if not deflate then return nil, "Export needs BetterBlizzFrames loaded." end
    local data = { format = 1, lp = LPSettings(), bbf = BBFLoaded() and Copy(BetterBlizzFramesDB) or nil }
    return STRING_PREFIX .. deflate:EncodeForPrint(deflate:CompressDeflate(serialize:Serialize(data)))
end

-- name: a built-in profile stored as an export string (for the chat line).
function Import(str, name)
    local deflate, serialize = Libs()
    if not deflate then return "Import needs BetterBlizzFrames loaded." end
    str = type(str) == "string" and str:gsub("%s", "") or ""
    if str:sub(1, #STRING_PREFIX) ~= STRING_PREFIX then return "That isn't a Living Portraits profile string." end
    local compressed = deflate:DecodeForPrint(str:sub(#STRING_PREFIX + 1))
    local serialized = compressed and deflate:DecompressDeflate(compressed)
    if not serialized then return "That profile string is damaged (copy all of it)." end
    local ok, data = serialize:Deserialize(serialized)
    if not (ok and type(data) == "table" and data.format == 1 and type(data.lp) == "table") then
        return "That profile string is damaged or from a newer Living Portraits."
    end
    ApplyLP(data.lp)
    local what = name and ("Loaded the " .. name .. " profile") or "Imported the profile"
    if type(data.bbf) == "table" and BBFLoaded() then
        WriteBBF(data.bbf)
        ShowReloadPopup()
        return what .. ". Reload the UI to apply it."
    end
    ns.RefreshAll()
    return what .. " (Living Portraits only)."
end

-- Dialogs ---------------------------------------------------------------------
-- Blizzard's popup edit box is shared between dialogs and keeps the last length limit set on it,
-- so ours lift it (0 = no limit) for these long strings.
local function EditBoxOf(dialog)
    return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

local function Dialogs()
    if not StaticPopupDialogs then return false end
    StaticPopupDialogs.LIVING_PORTRAITS_LOAD_PROFILE = StaticPopupDialogs.LIVING_PORTRAITS_LOAD_PROFILE or {
        text = "Load the %s profile? It replaces your Living Portraits and BetterBlizzFrames settings (Undo puts them back).",
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        OnAccept = function(_, name) print(ns.PREFIX .. LoadProfile(name)) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopupDialogs.LIVING_PORTRAITS_EXPORT = StaticPopupDialogs.LIVING_PORTRAITS_EXPORT or {
        text = "Your Living Portraits + BetterBlizzFrames profile. Copy it with Ctrl+C (Cmd+C on a Mac) to share.",
        hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
        button1 = CLOSE or "Close",
        OnShow = function(self, str)
            local eb = EditBoxOf(self)
            eb:SetMaxLetters(0)
            eb:SetText(str or "")
            eb:HighlightText()
            eb:SetFocus()
        end,
        EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopupDialogs.LIVING_PORTRAITS_IMPORT = StaticPopupDialogs.LIVING_PORTRAITS_IMPORT or {
        text = "Paste a Living Portraits profile string. It replaces your Living Portraits and BetterBlizzFrames settings (Undo puts them back).",
        hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        OnShow = function(self)
            local eb = EditBoxOf(self)
            eb:SetMaxLetters(0)
            eb:SetText("")
            eb:SetFocus()
        end,
        OnAccept = function(self) print(ns.PREFIX .. Import(EditBoxOf(self):GetText())) end,
        EditBoxOnEnterPressed = function(eb)
            local dialog = eb:GetParent()
            print(ns.PREFIX .. Import(eb:GetText()))
            dialog:Hide()
        end,
        EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    return StaticPopup_Show ~= nil
end

-- Panel and slash entry points. Each returns a chat line, or nil when a dialog took over.
local function AskLoadProfile(name)
    local p = FindProfile(name)
    if not p then return "No profile named " .. tostring(name) .. "." end
    if not Dialogs() then return LoadProfile(p.name) end
    StaticPopup_Show("LIVING_PORTRAITS_LOAD_PROFILE", p.name, nil, p.name)
end

local function ShowExport()
    local str, err = ExportString()
    if not str then return err end
    if not Dialogs() then return str end
    StaticPopup_Show("LIVING_PORTRAITS_EXPORT", nil, nil, str)
end

local function ShowImport()
    if not Libs() then return "Import needs BetterBlizzFrames loaded." end
    if not Dialogs() then return "The import dialog isn't available on this client." end
    StaticPopup_Show("LIVING_PORTRAITS_IMPORT")
end

ns.PROFILES = PROFILES
ns.LoadProfile = LoadProfile
ns.AskLoadProfile = AskLoadProfile
ns.ExportString = ExportString
ns.ImportProfile = Import
ns.ShowExport = ShowExport
ns.ShowImport = ShowImport
