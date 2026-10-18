local _, ns = ...
local db -- LivingPortraitsDB, set when it loads (Core.lua)
ns.OnLoad(function(saved) db = saved end)
local Safe = ns.Safe
local IsSecret = ns.IsSecret
local AnySecret = ns.AnySecret
local Lookup = ns.Lookup

-- New target: health and mana grow from empty to their value.
-- Blizzard's bars can't be animated directly: Blizzard re-sets them (immediately) as it
-- updates, which cancelled the engine's own interpolation. So for a moment we draw our
-- own copy of each bar on top and hide Blizzard's fill (alpha only, restored after).
-- The copy shows the bar's real value but its width grows from 0 to the bar's width,
-- so the visible fill is value x progress. Values can be "secret" and tainted code can't
-- do math on them (nor feed them to C_CurveUtil curves), but StatusBar:SetValue and
-- SetMinMaxValues accept them, so the lerp happens in geometry instead.
-- Starts from a post-hook on TargetFrame:Update(), which Blizzard calls on a target
-- change (also login and UNIT_TARGETABLE_CHANGED) right after setting the new values;
-- our own PLAYER_TARGET_CHANGED handler can run before Blizzard's.
local growDebug = false
local function GrowTrace(...) if growDebug then print("|cff00c0fflp grow|r", ...) end end

local grows = {} -- bar -> { ov, fill, alpha, t }
local growDriver -- created on first grow

local function EndGrow(bar)
    local g = grows[bar]
    if not g then return end
    -- Remove first: if anything below errors, the grow must not re-run (and error) every frame.
    grows[bar] = nil
    g.ov:Hide()
    -- Restore Blizzard's fill unless something else set its alpha meanwhile. In PvP the
    -- alpha can read back as a secret value that can't be compared: restore it then too,
    -- or the bar stays invisible.
    local alpha = Safe(g.fill:GetAlpha())
    if alpha == nil or alpha == 0 then g.fill:SetAlpha(g.alpha) end
    GrowTrace("done", bar.bapGrowName)
end

-- The grow compares and does math on what the bar and its fill report (orientation, reverse
-- fill, texture, draw layer, masks). In instances and PvP any of these can come back secret,
-- and comparing a secret errors (tainted code). The grow is cosmetic: skip or end it then.
-- The bar's own values are checked once at the start; the fill's in CopyBarStyle, which
-- reads them every frame anyway.
local function BarReadable(bar)
    return not AnySecret(bar:GetWidth(), bar.GetOrientation and bar:GetOrientation(),
        bar.GetReverseFill and bar:GetReverseFill())
end

-- Copy the fill's current look (BBF/Blizzard texture, class color, desaturation) onto
-- the overlay. BBF class colors are a desaturated fill with a tint, sometimes set on the
-- fill texture itself, so read the fill rather than the bar. Re-run every frame: BBF can
-- recolor or retexture right after Blizzard's update.
-- Returns false (copying nothing) when any of the fill's values is secret.
local function CopyBarStyle(ov, fill)
    local atlas, tex = fill:GetAtlas(), fill:GetTexture()
    local layer, sub = fill:GetDrawLayer()
    local desat, blend = fill:GetDesaturation(), fill:GetBlendMode()
    local n = fill.GetNumMaskTextures and fill:GetNumMaskTextures() or 0
    if AnySecret(atlas, tex, layer, sub, desat, blend, n) then return false end
    for i = 1, n do
        if IsSecret(fill:GetMaskTexture(i)) then return false end
    end
    local asset = atlas or tex or "Interface\\Buttons\\WHITE8X8"
    local ovFill = ov:GetStatusBarTexture()
    if ov.bapAsset ~= asset or not ovFill then
        ov:SetStatusBarTexture(asset)
        ov.bapAsset = asset
        if ov:GetStatusBarTexture() ~= ovFill then ov.bapMasks = nil end -- new texture, no masks yet
        ovFill = ov:GetStatusBarTexture()
    end
    ovFill:SetDrawLayer(layer, math.min(7, (sub or 0) + 1))
    ovFill:SetDesaturation(desat or 0)
    ovFill:SetBlendMode(blend or "BLEND")
    -- RGB only: the fill's alpha is 0 while we hide it, and copying that hid the overlay.
    local r, g, b = fill:GetVertexColor()
    pcall(ovFill.SetVertexColor, ovFill, r, g, b)
    -- Same masks as the fill (Blizzard's bar shape, BBF's no-portrait mask). Unmasked, the
    -- overlay reached past the fill's clipped end. This runs every frame, so only rebuild
    -- (and allocate) when the fill's masks actually changed.
    local have = ov.bapMasks -- array of the fill's masks (false for empty slots)
    local same = have and #have == n
    for i = 1, same and n or 0 do
        if (fill:GetMaskTexture(i) or false) ~= have[i] then same = false; break end
    end
    if same then return true end
    if have then
        for _, m in ipairs(have) do if m then ovFill:RemoveMaskTexture(m) end end
    end
    have = {}
    for i = 1, n do
        local m = fill:GetMaskTexture(i) or false
        if m then ovFill:AddMaskTexture(m) end
        have[i] = m
    end
    ov.bapMasks = have
    return true
end

local function GrowStep(_, elapsed)
    local duration = math.max(0.05, db.growTime)
    for bar, g in pairs(grows) do
        g.t = g.t + elapsed
        local p = math.min(1, g.t / duration)
        local w = Safe(bar:GetWidth()) -- secret in PvP: stop and show Blizzard's fill
        if p >= 1 or not w or not bar:IsVisible() or not CopyBarStyle(g.ov, g.fill) then
            EndGrow(bar)
        else
            local e = 1 - (1 - p) ^ 3 -- ease-out cubic
            -- Follow the live bar: health/power changing mid-grow shows up right away.
            g.ov:SetMinMaxValues(bar:GetMinMaxValues())
            g.ov:SetValue(bar:GetValue())
            g.ov:SetWidth(math.max(0.01, w * e))
        end
    end
    if not next(grows) then growDriver:SetScript("OnUpdate", nil) end
end

local function StartGrow(bar, name)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not (fill and bar:IsVisible()) or not BarReadable(bar)
        or (bar.GetOrientation and bar:GetOrientation() == "VERTICAL") then
        GrowTrace(name, "skip: fill", not not fill, "visible", bar:IsVisible())
        return
    end
    local g = grows[bar]
    if not g then
        local ov = bar.bapGrowBar
        if not ov then
            ov = CreateFrame("StatusBar", nil, bar)
            bar.bapGrowBar, bar.bapGrowName = ov, name
        end
        g = { ov = ov, fill = fill, alpha = fill:GetAlpha() }
        grows[bar] = g
    end
    g.t = 0
    local ov = g.ov
    -- Same frame level and draw layer as Blizzard's fill, so the bar texts stay on top.
    ov:SetFrameStrata(bar:GetFrameStrata())
    ov:SetFrameLevel(bar:GetFrameLevel())
    if not CopyBarStyle(ov, fill) then
        EndGrow(bar) -- secret fill (instance/PvP): leave Blizzard's bar alone
        GrowTrace(name, "skip: secret fill")
        return
    end
    ov:SetAlpha(g.alpha)
    local reverse = bar.GetReverseFill and bar:GetReverseFill()
    ov:SetReverseFill(reverse and true or false)
    local side = reverse and "RIGHT" or "LEFT"
    ov:ClearAllPoints()
    ov:SetPoint("TOP" .. side, bar, "TOP" .. side)
    ov:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side)
    ov:SetWidth(0.01)
    ov:SetMinMaxValues(bar:GetMinMaxValues())
    ov:SetValue(bar:GetValue())
    ov:Show()
    fill:SetAlpha(0)
    growDriver = growDriver or CreateFrame("Frame")
    growDriver:SetScript("OnUpdate", GrowStep)
    GrowTrace(name, "start, value", Safe(bar:GetValue()) or "secret")
end

local function GrowBars(unit)
    if not (db and db.growBars and UnitExists(unit)) then
        GrowTrace("skip: grow", db and db.growBars, unit, UnitExists(unit))
        return
    end
    local hpBar, manaBar = Lookup(unit, "bars")
    if hpBar then StartGrow(hpBar, unit .. " health") end
    if manaBar then StartGrow(manaBar, unit .. " mana") end
end

-- Target and focus share Blizzard's frame code: Update() runs on a new target (target
-- frame) or a new focus (focus frame), after the new values are set. Target-of-target is
-- left out on purpose: it changes many times a second in fights, so a grow would flicker.
local function HookGrowUpdates()
    for _, f in ipairs({ { TargetFrame, "target" }, { FocusFrame, "focus" } }) do
        local frame, unit = f[1], f[2]
        if frame and type(frame.Update) == "function" then
            hooksecurefunc(frame, "Update", function() GrowBars(unit) end)
        end
    end
end

-- /lp grow debug
local function ToggleGrowDebug()
    growDebug = not growDebug
    return growDebug
end

ns.HookGrowUpdates = HookGrowUpdates
ns.ToggleGrowDebug = ToggleGrowDebug
