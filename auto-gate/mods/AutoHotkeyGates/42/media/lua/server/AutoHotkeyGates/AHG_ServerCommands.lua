-- Automatic / Hotkey Gates - server command handlers
-- Receives client intents (Register / Unregister / Trigger), validates them,
-- and answers with Notify halo messages. Also dispatches directly in SP.

if isClient() then return end

require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_System"
require "AutoHotkeyGates/AHG_Permissions"

local REGISTER_DISTANCE = 4

-- username -> epoch ms of the last accepted trigger
local lastTrigger = {}

local function notify(playerObj, key, arg1, arg2)
    if not playerObj then return end
    if isServer() then
        sendServerCommand(playerObj, AHG.Module, "Notify", { key = tostring(key), arg1 = arg1, arg2 = arg2 })
    elseif AHG.Client and AHG.Client.showNotifyKey then
        -- Singleplayer: no network round-trip, display directly.
        AHG.Client.showNotifyKey(playerObj, key, arg1, arg2)
    end
end

local function systemReady(playerObj)
    if SAHGSystem and SAHGSystem.instance then return true end
    notify(playerObj, "IGUI_AHG_GateNotLoaded")
    return false
end

local function getGateFromArgs(args)
    if not args then return nil end
    local obj = AHG.getObjectAt(args.x, args.y, args.z, args.index)
    if AHG.isDoorLike(obj) then return obj end
    local sq = AHG.getSquare(args.x, args.y, args.z)
    return AHG.findDoorLikeOnSquare(sq, args.gateId, args.index)
end

local Commands = {}

function Commands.Register(playerObj, args)
    if not systemReady(playerObj) then return end
    if not AHG.playerCanRegister(playerObj) then
        notify(playerObj, "IGUI_AHG_RegisterDenied")
        return
    end

    local gateObj = getGateFromArgs(args)
    if not gateObj then
        notify(playerObj, "IGUI_AHG_NoValidGateFound")
        return
    end

    if not AHG.isPlayerNear(playerObj, gateObj:getX(), gateObj:getY(), gateObj:getZ(), REGISTER_DISTANCE) then
        notify(playerObj, "IGUI_AHG_MoveCloserToGate")
        return
    end

    if not AHG.isEligibleGate(gateObj) then
        notify(playerObj, "IGUI_AHG_NotEligible")
        return
    end

    local cap = tonumber(AHG.opt("MaxRegisteredGates")) or 0
    if cap > 0 and SAHGSystem.instance:getRegisteredCount() >= cap then
        notify(playerObj, "IGUI_AHG_GateLimitReached", cap)
        return
    end

    local ok, result = SAHGSystem.instance:registerGate(playerObj, gateObj, args.tag)
    if ok then
        local tag = tostring(args.tag or "")
        if tag ~= "" then
            notify(playerObj, "IGUI_AHG_RegisteredWithTag", tag)
        else
            notify(playerObj, "IGUI_AHG_Registered")
        end
    else
        notify(playerObj, result)
    end
end

function Commands.Unregister(playerObj, args)
    if not systemReady(playerObj) then return end
    if not AHG.playerCanRegister(playerObj) then
        notify(playerObj, "IGUI_AHG_RegisterDenied")
        return
    end

    local gateObj = getGateFromArgs(args)
    if not gateObj then
        notify(playerObj, "IGUI_AHG_NoValidGateFound")
        return
    end

    if not AHG.isPlayerNear(playerObj, gateObj:getX(), gateObj:getY(), gateObj:getZ(), REGISTER_DISTANCE) then
        notify(playerObj, "IGUI_AHG_MoveCloserToGate")
        return
    end

    local ok, result = SAHGSystem.instance:unregisterGate(playerObj, gateObj)
    notify(playerObj, result)
end

function Commands.SetTag(playerObj, args)
    if not systemReady(playerObj) then return end
    if not AHG.playerCanRegister(playerObj) then
        notify(playerObj, "IGUI_AHG_RegisterDenied")
        return
    end

    local gateObj = getGateFromArgs(args)
    if not gateObj then
        notify(playerObj, "IGUI_AHG_NoValidGateFound")
        return
    end

    if not AHG.isPlayerNear(playerObj, gateObj:getX(), gateObj:getY(), gateObj:getZ(), REGISTER_DISTANCE) then
        notify(playerObj, "IGUI_AHG_MoveCloserToGate")
        return
    end

    local ok, result = SAHGSystem.instance:setGateTag(playerObj, gateObj, args and args.tag)
    if ok then
        local tag = tostring(args and args.tag or "")
        if tag ~= "" then
            notify(playerObj, "IGUI_AHG_TagUpdated", tag)
        else
            notify(playerObj, "IGUI_AHG_TagCleared")
        end
    else
        notify(playerObj, result)
    end
end

function Commands.Trigger(playerObj, args)
    if not playerObj or playerObj:isDead() then return end
    if not systemReady(playerObj) then return end
    args = args or {}

    -- Per-player cooldown so key spam cannot flicker the gate.
    local cooldownMs = (tonumber(AHG.opt("CooldownSeconds")) or 0) * 1000
    if cooldownMs > 0 then
        local username = playerObj:getUsername() or "?"
        local now = AHG.nowMs()
        local last = lastTrigger[username]
        if last and (now - last) < cooldownMs then
            AHG.noise("trigger ignored (cooldown) user=" .. username)
            return
        end
        lastTrigger[username] = now
    end

    if AHG.opt("OperateFromVehicleOnly") and not playerObj:getVehicle() and args.source ~= "context" then
        notify(playerObj, "IGUI_AHG_VehicleOnly")
        return
    end

    local record = SAHGSystem.instance:getByGateId(args and args.gateId)
    if not record then
        -- Fall back to the object the client pointed at (context menu path).
        local gateObj = getGateFromArgs(args)
        if gateObj then
            record = SAHGSystem.instance:getGateForObject(gateObj)
        end
    end
    if not record then
        notify(playerObj, "IGUI_AHG_NotRegistered")
        return
    end

    local range = tonumber(AHG.opt("TriggerRange")) or 15
    if not AHG.isPlayerNear(playerObj, record.x, record.y, record.z, range + 1) then
        notify(playerObj, "IGUI_AHG_GateOutOfRange")
        return
    end

    if AHG.opt("EnforcePermissionHook") then
        local allowed = false
        local ok, err = pcall(function()
            allowed = AHG.Permissions.canOperate(playerObj, record) == true
        end)
        if not ok then
            print("[AHG] ERROR in AHG.Permissions.canOperate: " .. tostring(err))
            allowed = false
        end
        if not allowed then
            notify(playerObj, "IGUI_AHG_AccessDenied")
            return
        end
    end

    local ok, result = SAHGSystem.instance:operateGate(playerObj, record)
    notify(playerObj, result)
end

-- Direct dispatch entry point: used by OnClientCommand in MP and called
-- straight from client lua in singleplayer (see AHG.sendCommand).
function AHG.ServerHandle(command, playerObj, args)
    local fn = Commands[command]
    if fn then
        fn(playerObj, args or {})
    else
        AHG.noise("unknown command " .. tostring(command))
    end
end

local function OnClientCommand(module, command, playerObj, args)
    if module ~= AHG.Module then return end
    AHG.ServerHandle(command, playerObj, args)
end

Events.OnClientCommand.Add(OnClientCommand)
