-- Automatic / Hotkey Gates - hotkey handler
-- Pressing the Operate Gate keybind triggers the nearest registered gate.
-- Works on foot and while seated in a vehicle.

require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_Client"

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

local function onKeyPressed(key)
    if not key or key == 0 then return end
    local core = getCore()
    if not core then return end
    local bound = core:getKey("AHG_OperateGate")
    if not bound or bound == 0 or key ~= bound then return end

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

Events.OnKeyPressed.Add(onKeyPressed)
