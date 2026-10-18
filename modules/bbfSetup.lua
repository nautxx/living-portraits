local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local PREFIX = ns.PREFIX

-- BBF setup -----------------------------------------------------------------
-- The box style needs BBF's No Portrait + Pixel Border mode on every frame. "Turn on Pixel
-- Border mode" writes just those switches (BBF_MODE) into BBF's saved settings (never its files),
-- on top of the user's own BBF look, after a full backup for Undo; BBF reads them when it loads,
-- hence the UI reload. A whole look (a BBF base profile plus more settings) is a profile instead
-- (modules/profiles.lua: Starter, Naut), which uses WriteBBF and BaseProfile from here.
local BBF_MODE = {
    -- No portraits, pixel borders, on every frame (BBF.HasNoPortrait checks these).
    noPortraitModes = true, noPortraitPixelBorder = true,
    noPortraitPartyOnly = false, -- otherwise only the party frames lose their portraits
    noPortraitSkipPlayer = false, noPortraitSkipTarget = false, noPortraitSkipFocus = false,
    -- Classic Frames wins over No Portrait (BBF builds it first, and its own No Portrait / Pixel
    -- Border checkboxes turn it off), so it must go: left on, the frames stay classic.
    classicFrames = false,
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
    WriteBBF(nil, BBF_MODE)
    ShowReloadPopup()
    return "Turned on BetterBlizzFrames' Pixel Border mode for every frame. Reload the UI to apply it."
end

-- Undo Pixel Border mode and/or a loaded profile (modules/profiles.lua): BBF's settings and our own
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
        local welcomed = db.welcomed
        for k in pairs(db) do db[k] = nil end
        for k, v in pairs(lp) do db[k] = Copy(v) end
        db.welcomed = welcomed
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

ns.BBF_MODE = BBF_MODE
ns.DeepCopy = Copy
ns.BaseProfile = BaseProfile
ns.BBFLoaded = BBFLoaded
ns.WriteBBF = WriteBBF
ns.ShowReloadPopup = ShowReloadPopup
ns.ApplyBBFSetup = ApplyBBFSetup
ns.UndoBBFSetup = UndoBBFSetup
-- First run --------------------------------------------------------------------
-- A good starting point on a fresh install: BBF isn't set up, so the box style can't show (circle
-- portraits). Once per account, offer a profile (modules/profiles.lua, loaded after this file):
-- Starter (BBF's own Starter + Pixel Border mode) or Naut (Jason's look); without BBF, recommend
-- it. Not shown when Pixel Border mode is already on. db.welcomed is set when shown, whatever
-- the answer.
local function CheckFirstRun()
    if not db or db.welcomed then return end
    if BBFLoaded() and ns.BBFHidesPortrait("player") then
        db.welcomed = true -- already set up
        return
    end
    db.welcomed = true
    if not BBFLoaded() then
        print(PREFIX .. "works best with BetterBlizzFrames: with its Pixel Border mode the portraits sit in a box "
            .. "beside the bars. Without it they go in the round portrait.")
        return
    end
    if not (StaticPopupDialogs and StaticPopup_Show) then
        print(PREFIX .. "Load a profile for the box portraits: /lp profile starter (or naut).")
        return
    end
    StaticPopupDialogs.LIVING_PORTRAITS_WELCOME = StaticPopupDialogs.LIVING_PORTRAITS_WELCOME or {
        text = "Welcome to Living Portraits!\n\nThe box portraits need BetterBlizzFrames set up. Pick a starting "
            .. "point. It overwrites all of your BetterBlizzFrames settings and reloads the UI:\n\n"
            .. "Starter: BetterBlizzFrames' Starter profile with Pixel Border mode.\n"
            .. "Naut: the author's full look.\n\nUndo: Options > AddOns > Living Portraits > Profiles.",
        button1 = "Starter",
        button2 = LATER or "Not now",
        button3 = "Naut",
        OnAccept = function() print(PREFIX .. ns.LoadProfile("Starter")) end,
        OnAlt = function() print(PREFIX .. ns.LoadProfile("Naut")) end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopup_Show("LIVING_PORTRAITS_WELCOME")
end

ns.CheckOldAddon = CheckOldAddon
ns.CheckFirstRun = CheckFirstRun
