local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local PREFIX = ns.PREFIX

-- BBF setup -----------------------------------------------------------------
-- One click sets BBF up the way Living Portraits is designed and tested (Jason's own BBF):
-- BBF's built-in Bodify profile first (BBF's author's setup, which Jason's builds on: dark mode,
-- auras, cast bars and the rest), then BBF_SETUP on top: the No Portrait + Pixel Border mode the
-- box style needs and Jason's unit frame look. Same result as loading Bodify in BBF's profile
-- menu and then changing those settings, in one reload. We write BBF's saved settings (never its
-- files) after a full backup for Undo; BBF reads them when it loads, hence the UI reload.
-- BBF.ApplyProfile can't be used: it reloads right away, before we could add ours. Its decoder
-- (BBF.OldImportProfile) is what it uses too. Without the profile (renamed, older BBF), only
-- BBF_SETUP is applied and the rest of BBF stays as it is.
-- The fonts and textures named here all ship with BBF (its LibSharedMedia and media folder).
local BASE_PROFILE = "Bodify"
local BBF_SETUP = {
    -- Mode: no portraits, pixel borders, on every frame (BBF.HasNoPortrait checks these).
    noPortraitModes = true, noPortraitPixelBorder = true,
    noPortraitPartyOnly = false, -- otherwise only the party frames lose their portraits
    noPortraitSkipPlayer = false, noPortraitSkipTarget = false, noPortraitSkipFocus = false,
    -- Classic Frames wins over No Portrait (BBF builds it first, and its own No Portrait / Pixel
    -- Border checkboxes turn it off), so it must go: left on, the frames stay classic.
    classicFrames = false,
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
local NO_VALUE = "<nil>" -- marker in v0.8.0/0.8.1 backups (db.bbfBackup): BBF had never saved this key

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

-- Deep copy (BBF's settings nest: aura lists, colors). Never hand BBF our own tables.
local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

local function Replace(dst, src)
    for k in pairs(dst) do dst[k] = nil end
    for k, v in pairs(src) do dst[k] = Copy(v) end
end

-- One of BBF's built-in profiles, decoded, or nil (not found, or BBF changed how it stores them).
local function BaseProfile(name)
    if not (BBF and type(BBF.ProfileData) == "table" and type(BBF.OldImportProfile) == "function") then return end
    for _, p in ipairs(BBF.ProfileData) do
        if type(p) == "table" and p.name == name and type(p.importString) == "string" then
            local ok, data, err = pcall(BBF.OldImportProfile, p.importString, "fullProfile")
            if ok and not err and type(data) == "table" then return data end
            return
        end
    end
end

local function BBFLoaded()
    return BBF and type(BetterBlizzFramesDB) == "table"
end

-- Write BBF's settings: replace them with `base` (a decoded built-in profile, or a whole set from
-- an imported profile), then put `overlay`'s keys on top. Takes the Undo backup first, once:
-- it holds BBF as it was before us.
local function WriteBBF(base, overlay)
    local bdb = BetterBlizzFramesDB
    if not db.bbfBackupFull then db.bbfBackupFull = Copy(bdb) end
    if base then
        Replace(bdb, base)
        -- What BBF.ApplyProfile also sets after loading a profile (skips its "what's new" and
        -- bag bar prompts).
        bdb.skipUpdateMsg, bdb.hideBagsBarImportCheck = true, true
    end
    for k, v in pairs(overlay or {}) do bdb[k] = Copy(v) end
end

-- Both return a line for chat.
local function ApplyBBFSetup()
    if not BBFLoaded() then return "BetterBlizzFrames isn't loaded." end
    local base = BaseProfile(BASE_PROFILE)
    WriteBBF(base, BBF_SETUP)
    ShowReloadPopup()
    if base then
        return "Set up BetterBlizzFrames: loaded its " .. BASE_PROFILE .. " profile, then Pixel Border mode and "
            .. "the Living Portraits unit frame look. Reload the UI to apply it."
    end
    return "Set up BetterBlizzFrames (" .. BASE_PROFILE .. " profile not found: only Pixel Border mode and the "
        .. "Living Portraits unit frame look). Reload the UI to apply it."
end

-- Undo the BBF setup and/or a loaded profile (modules/profiles.lua): BBF's settings and our own
-- go back to how they were before the first one.
local function UndoBBFSetup()
    local bdb, full, keys, lp = BetterBlizzFramesDB, db.bbfBackupFull, db.bbfBackup, db.lpBackup
    if not (full or keys or lp) then return "Nothing to undo." end
    if (full or keys) and type(bdb) ~= "table" then return "BetterBlizzFrames isn't loaded." end
    if full then Replace(bdb, full) end
    -- v0.8.0/0.8.1 backups held only the keys their setup changed, from before it ran.
    if keys then
        for k, v in pairs(keys) do
            if v == NO_VALUE then bdb[k] = nil else bdb[k] = Copy(v) end
        end
    end
    db.bbfBackupFull, db.bbfBackup, db.lpBackup = nil, nil, nil
    if lp then
        for k in pairs(db) do db[k] = nil end
        for k, v in pairs(lp) do db[k] = Copy(v) end
        ns.LoadSettings() -- migrate and fill in defaults; every file keeps the same table
    end
    if full or keys then ShowReloadPopup() else ns.RefreshAll() end
    return "Put back your previous settings." .. ((full or keys) and " Reload the UI to apply them." or "")
end

-- Old install ---------------------------------------------------------------
-- Until v0.2.1 this addon was "BBF_AnimatedPortraits". If that folder is still installed
-- and enabled, both addons draw models and lay out the bars on the same frames. Offer to
-- disable it (Blizzard's own pattern: DisableAddOn, then reload), once per session.
local OLD_ADDON = "BBF_AnimatedPortraits"
local oldAddonWarned = false

local function CheckOldAddon()
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

ns.BBF_SETUP = BBF_SETUP
ns.DeepCopy = Copy
ns.BaseProfile = BaseProfile
ns.BBFLoaded = BBFLoaded
ns.WriteBBF = WriteBBF
ns.ShowReloadPopup = ShowReloadPopup
ns.ApplyBBFSetup = ApplyBBFSetup
ns.UndoBBFSetup = UndoBBFSetup
ns.CheckOldAddon = CheckOldAddon
