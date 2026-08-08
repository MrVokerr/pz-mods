-- Automatic / Hotkey Gates - per-gate persistent record (server side)

if isClient() then return end

require "Map/SGlobalObject"
require "AutoHotkeyGates/AHG_Shared"

SAHGGlobalObject = SGlobalObject:derive("SAHGGlobalObject")

function SAHGGlobalObject:new(luaSystem, globalObject)
    return SGlobalObject.new(self, luaSystem, globalObject)
end

function SAHGGlobalObject:initNew()
    self.version = AHG.Version
    self.gateId = self.gateId or ""
    self.tag = self.tag or ""
    self.registeredBy = self.registeredBy or "unknown"
    if not self.registeredAt then
        local hours = 0
        pcall(function() hours = getGameTime():getWorldAgeHours() end)
        self.registeredAt = hours
    end
    self.objectIndex = self.objectIndex or -1
    self.spriteName = self.spriteName or ""
    self.objectName = self.objectName or ""
    self.north = self.north or false
    -- Lock memory: captured when a locked gate is opened via bypass,
    -- restored when the gate closes again.
    self.savedLockKey = self.savedLockKey or false
    self.savedLockIso = self.savedLockIso or false
    self.savedLockPadlock = self.savedLockPadlock or false
    self.hasSavedLock = self.hasSavedLock or false
end

function SAHGGlobalObject:stateFromIsoObject(isoObject)
    self:initNew()
    local md = isoObject:getModData()
    self.gateId = md[AHG.MD.GateId] or self.gateId
    self.tag = md[AHG.MD.Tag] or self.tag
    self.objectIndex = tonumber(md[AHG.MD.AnchorIndex]) or AHG.getObjectIndex(isoObject)
    self.spriteName = AHG.getSpriteName(isoObject) or self.spriteName
    self.objectName = AHG.getObjectName(isoObject) or self.objectName
    self.north = isoObject.getNorth and isoObject:getNorth() or false
    AHG.markObject(isoObject, self)
end

function SAHGGlobalObject:stateToIsoObject(isoObject)
    self:initNew()
    AHG.markObject(isoObject, self)
end

function SAHGGlobalObject:aboutToRemoveFromSystem()
    local objects = self.luaSystem:getMarkedObjectsForGate(self.gateId)
    for i = 1, #objects do
        AHG.clearObjectMarker(objects[i])
    end
end
