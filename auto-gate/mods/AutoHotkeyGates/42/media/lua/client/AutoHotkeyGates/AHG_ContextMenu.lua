-- Automatic / Hotkey Gates - world context menu
-- Players: Open/Close Gate on registered gates.
-- Staff: Register Automatic Gate... (with optional tag) / Unregister.

require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_Client"
require "ISUI/ISTextBox"

local function buildObjArgs(obj)
    return {
        x = obj:getX(),
        y = obj:getY(),
        z = obj:getZ(),
        index = AHG.getObjectIndex(obj),
        gateId = AHG.getGateIdFromObject(obj),
    }
end

function AHG.Client.onRegisterTagEntered(target, button, playerNum, gateArgs)
    if button.internal ~= "OK" then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    gateArgs.tag = button.parent.entry:getText() or ""
    AHG.sendCommand(playerObj, "Register", gateArgs)
end

function AHG.Client.onChangeTagEntered(target, button, playerNum, gateArgs)
    if button.internal ~= "OK" then return end
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    gateArgs.tag = button.parent.entry:getText() or ""
    AHG.sendCommand(playerObj, "SetTag", gateArgs)
end

local function onRegisterGate(gateObj, playerNum)
    local gateArgs = buildObjArgs(gateObj)
    local box = ISTextBox:new(0, 0, 300, 180,
        AHG.text("ContextMenu_AHG_EnterTag"), "",
        nil, AHG.Client.onRegisterTagEntered, playerNum, playerNum, gateArgs)
    box:initialise()
    box:addToUIManager()
end

local function onChangeTag(gateObj, playerNum)
    local gateArgs = buildObjArgs(gateObj)
    local current = AHG.getTagFromObject(gateObj) or ""
    local box = ISTextBox:new(0, 0, 300, 180,
        AHG.text("ContextMenu_AHG_EnterTag"), current,
        nil, AHG.Client.onChangeTagEntered, playerNum, playerNum, gateArgs)
    box:initialise()
    box:addToUIManager()
end

local function onUnregisterGate(gateObj, playerObj)
    AHG.sendCommand(playerObj, "Unregister", buildObjArgs(gateObj))
end

local function addWorldMenu(playerNum, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(function()
        local playerObj = getSpecificPlayer(playerNum)
        if not playerObj then return end

        local gateObj = AHG.findDoorLikeFromWorldObjects(worldobjects)
        if not gateObj then return end

        local registered = AHG.isRegisteredObject(gateObj)
        local canRegister = AHG.playerCanRegister(playerObj)

        if not registered and not canRegister then return end
        if not registered and canRegister and AHG.opt("RequireVehicleGates") and not AHG.isVehicleGate(gateObj) then
            return
        end

        local main = context:addOption(AHG.text("ContextMenu_AHG_Root"), nil, nil)
        local sub = context:getNew(context)
        context:addSubMenu(main, sub)

        if registered then
            local tag = AHG.getTagFromObject(gateObj) or ""
            local infoText
            if tag ~= "" then
                infoText = AHG.text("ContextMenu_AHG_InfoTag", tag)
            else
                infoText = AHG.text("ContextMenu_AHG_InfoNoTag")
            end
            sub:addOption(infoText, nil, nil).notAvailable = true

            if AHG.opt("EnableContextMenu") then
                sub:addOption(AHG.text("ContextMenu_AHG_Operate"), gateObj, AHG.Client.operateGateObject, playerObj)
            end

            if canRegister then
                sub:addOption(AHG.text("ContextMenu_AHG_ChangeTag"), gateObj, onChangeTag, playerNum)
                sub:addOption(AHG.text("ContextMenu_AHG_Unregister"), gateObj, onUnregisterGate, playerObj)
            end
        else
            local option = sub:addOption(AHG.text("ContextMenu_AHG_Register"), gateObj, onRegisterGate, playerNum)
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = AHG.text("ContextMenu_AHG_RegisterTooltip")
            option.toolTip = tip
        end
    end)
    if not ok then
        print("[AHG] ERROR in context menu: " .. tostring(err))
    end
end

Events.OnFillWorldObjectContextMenu.Add(addWorldMenu)
