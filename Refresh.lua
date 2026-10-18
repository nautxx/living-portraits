-- Refresh (show/hide each unit's portrait), the ticker and events. Loaded after the
-- modules so it can use all of them.

local ADDON_NAME, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local UNITS = ns.UNITS
local UNIT_LIST = ns.UNIT_LIST
local PARTY = ns.PARTY
local UnitFrameOf = ns.UnitFrameOf
local Safe = ns.Safe
local BBFHidesPortrait = ns.BBFHidesPortrait
local retryDelay = ns.retryDelay
local QueueRefresh = ns.QueueRefresh
local QueueRefreshAll = ns.QueueRefreshAll
local layers = ns.layers
local Deactivate = ns.Deactivate
local CreateLayers = ns.CreateLayers
local RefreshCircle = ns.RefreshCircle
local LayeringOK = ns.LayeringOK
local ApplyLayering = ns.ApplyLayering
local DeactivateSquare = ns.DeactivateSquare
local RestoreBars = ns.RestoreBars
local RefreshSquare = ns.RefreshSquare
local HookGrowUpdates = ns.HookGrowUpdates
local UpdateBuild = ns.UpdateBuild
local OnTalentsChanged = ns.OnTalentsChanged
local OnInspectReady = ns.OnInspectReady
local UpdateBarTexts = ns.UpdateBarTexts
local UpdateSurnames = ns.UpdateSurnames
local UpdateClassResource = ns.UpdateClassResource
local CheckResourceBar = ns.CheckResourceBar
local CheckOldAddon = ns.CheckOldAddon

-- unit -> GUID and visible/connected code at the last refresh, so the ticker only refreshes on change
local lastGuid, lastCode = {}, {}
local lastScale = {} -- unit -> unit frame's effective scale at the last refresh

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

local function HideAll(p, unit)
    if p then Deactivate(p) end
    DeactivateSquare(unit)
end

local function Refresh(unit)
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

-- Talent build, bar text, surnames and class resource, after every RefreshAll.
local function AfterRefreshAll()
    UpdateBuild()
    UpdateBarTexts()
    UpdateSurnames(true)
    UpdateClassResource()
end

local function RefreshAll()
    for _, unit in ipairs(UNIT_LIST) do Refresh(unit) end
    AfterRefreshAll()
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
    CheckResourceBar() -- BBF's combo point bar, once BBF creates it
end

-- Events --------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        ns.LoadSettings()
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
        ns.BuildOptions()
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

ns.Refresh = Refresh
ns.RefreshAll = RefreshAll
