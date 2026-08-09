-- Automatic / Hotkey Gates - hotkey handler
-- Pressing the Operate Gate keybind triggers the nearest registered gate.
-- Works on foot and while seated in a vehicle.
--
-- B42 changed Events.OnKeyPressed to fire on key RELEASE (it used to fire on
-- press in B41). Events.OnKeyStartPressed is the new down-edge, single-shot
-- event ("has the key been pressed, not continuous"). Using the old event
-- here made a single tap flicker the gate: one toggle fired near the press
-- and a second fired on release, opening then instantly closing it.
--
-- The guard against re-firing is an edge-triggered down/up state machine
-- (not a plain time debounce), and the state lives on the shared AHG table
-- rather than a local closure variable. If this file is ever executed more
-- than once in the same Lua VM (mod reload, duplicate load, etc.), a plain
-- local debounce would give each registration its own private timer and
-- neither would see the other's press - letting two triggers slip through
-- a moment apart (the exact open-then-instant-close symptom). Sharing the
-- state means every registration, however many exist, agrees on whether the
-- key is currently "down" and only the genuine first press can fire.
require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_Client"

local DEBOUNCE_MS = 150
local STUCK_MS = 2000 -- failsafe: recover if a release event is ever missed (alt-tab, focus loss)

AHG.__hotkeyState = AHG.__hotkeyState or { down = false, downSinceMs = 0, lastFireMs = 0 }

local function isTextInputActive()
    local focused = false
    pcall(function()
        -- B42 chat focus flag (see ISChat.lua).
        if ISChat and ISChat.focused then
            focused = true
        end
    end)
    return focused
end

local function isOperateGateKey(key)
    if not key or key == 0 then return false end
    local core = getCore()
    if not core then return false end
    local bound = core:getKey("AHG_OperateGate")
    return bound ~= nil and bound ~= 0 and key == bound
end

local function onOperateGateKeyDown(key)
    if not isOperateGateKey(key) then return end

    local state = AHG.__hotkeyState
    local now = AHG.nowMs()

    if state.down then
        if now - state.downSinceMs < STUCK_MS then return end
        -- Release was missed (e.g. lost window focus); recover instead of
        -- staying stuck forever.
    end

    if now - state.lastFireMs < DEBOUNCE_MS then return end

    state.down = true
    state.downSinceMs = now
    state.lastFireMs = now

    if isGamePaused and isGamePaused() then return end
    if isTextInputActive() then return end

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() then return end

    if not AHG.opt("EnableHotkey") then
        AHG.Client.showNotifyKey(playerObj, "IGUI_AHG_HotkeyDisabled")
        return
    end

    AHG.Client.operateNearest(0, "hotkey")
end

-- Release edge. On B42 this is exactly what OnKeyPressed now fires on, which
-- is the signal we need to clear the down-flag for the next press. On the
-- B41 fallback (OnKeyStartPressed unavailable) OnKeyPressed fires on press
-- instead, so this simply clears the flag again right after it was set -
-- harmless, and DEBOUNCE_MS still protects that path.
local function onOperateGateKeyUp(key)
    if not isOperateGateKey(key) then return end
    AHG.__hotkeyState.down = false
end

if not AHG.__hotkeyHandlerInstalled then
    AHG.__hotkeyHandlerInstalled = true
    if Events.OnKeyStartPressed then
        Events.OnKeyStartPressed.Add(onOperateGateKeyDown)
    else
        Events.OnKeyPressed.Add(onOperateGateKeyDown)
    end
    Events.OnKeyPressed.Add(onOperateGateKeyUp)
end
