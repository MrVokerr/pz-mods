-- Automatic / Hotkey Gates - server-authoritative gate registry
-- Persists registered gates as GlobalObjects, marks all tile pieces with
-- ModData, and performs open/close (with lock bypass/restore and auto-close).

if isClient() then return end

require "Map/SGlobalObjectSystem"
require "AutoHotkeyGates/AHG_Shared"
require "AutoHotkeyGates/AHG_GlobalObject"

SAHGSystem = SGlobalObjectSystem:derive("SAHGSystem")

local REMOVAL_VERIFY_TICKS = 20
local AUTOCLOSE_RETRY_MS = 3000
local TICK_THROTTLE = 30

function SAHGSystem:new()
    local o = SGlobalObjectSystem.new(self, AHG.SystemName)
    o:rebuildIndex()
    return o
end

function SAHGSystem:initSystem()
    SGlobalObjectSystem.initSystem(self)
    self.system:setModDataKeys({})
    self.system:setObjectModDataKeys({
        "version",
        "gateId",
        "tag",
        "registeredBy",
        "registeredAt",
        "objectIndex",
        "spriteName",
        "objectName",
        "north",
        "savedLockKey",
        "savedLockIso",
        "savedLockPadlock",
        "hasSavedLock",
    })
    self.gateIndex = {}
    self.pendingRemovalChecks = self.pendingRemovalChecks or {}
    -- Runtime only: gateId -> epoch ms when the gate should auto-close.
    self.autoClose = self.autoClose or {}
end

function SAHGSystem:newLuaObject(globalObject)
    return SAHGGlobalObject:new(self, globalObject)
end

function SAHGSystem:isValidIsoObject(isoObject)
    return AHG.isRegisteredObject(isoObject)
end

-- ---------------------------------------------------------------------------
-- Index / lookup
-- ---------------------------------------------------------------------------

function SAHGSystem:rebuildIndex()
    self.gateIndex = {}
    for i = 1, self:getLuaObjectCount() do
        local luaObject = self:getLuaObjectByIndex(i)
        if luaObject and luaObject.gateId and luaObject.gateId ~= "" then
            self.gateIndex[luaObject.gateId] = luaObject
        end
    end
end

function SAHGSystem:getByGateId(gateId)
    if not gateId then return nil end
    if not self.gateIndex then self:rebuildIndex() end
    return self.gateIndex[gateId]
end

function SAHGSystem:getGateForObject(gateObj)
    if not gateObj then return nil end

    if gateObj:hasModData() then
        local record = self:getByGateId(gateObj:getModData()[AHG.MD.GateId])
        if record then return record end
    end

    -- Check every piece of the group; the anchor may be on another tile.
    local group = AHG.getGateGroup(gateObj)
    for i = 1, #group do
        local record = self:getLuaObjectAt(group[i]:getX(), group[i]:getY(), group[i]:getZ())
        if record then return record end
    end

    return nil
end

function SAHGSystem:resolveGateObjectWithStatus(record)
    if not record then return nil, "no_record" end
    local sq = record:getSquare()
    if not sq then return nil, "square_unavailable" end
    local gateObj = AHG.findDoorLikeOnSquare(sq, record.gateId, record.objectIndex)
    if AHG.isDoorLike(gateObj) then return gateObj, "ok" end
    return nil, "gate_missing"
end

function SAHGSystem:resolveGateObject(record)
    local gateObj = self:resolveGateObjectWithStatus(record)
    return gateObj
end

function SAHGSystem:getRegisteredCount()
    return self:getLuaObjectCount()
end

-- ---------------------------------------------------------------------------
-- Anchor selection: pick a stable endpoint piece of the multi-tile gate so
-- the record survives which half the admin happened to click.
-- ---------------------------------------------------------------------------

function SAHGSystem:getStableGateAnchor(gateObj)
    if not AHG.isDoorLike(gateObj) then return gateObj end

    local group = AHG.getGateGroup(gateObj)
    if #group <= 1 then return gateObj end

    local minXObj, maxXObj, minYObj, maxYObj
    local minX, maxX, minY, maxY

    for i = 1, #group do
        local obj = group[i]
        if AHG.isDoorLike(obj) then
            local x, y = obj:getX(), obj:getY()
            if not minX or x < minX then minX, minXObj = x, obj end
            if not maxX or x > maxX then maxX, maxXObj = x, obj end
            if not minY or y < minY then minY, minYObj = y, obj end
            if not maxY or y > maxY then maxY, maxYObj = y, obj end
        end
    end

    local xRange = (maxX or gateObj:getX()) - (minX or gateObj:getX())
    local yRange = (maxY or gateObj:getY()) - (minY or gateObj:getY())

    local endpointA, endpointB
    if math.abs(xRange) >= math.abs(yRange) then
        endpointA, endpointB = minXObj, maxXObj
    else
        endpointA, endpointB = minYObj, maxYObj
    end

    if endpointA and endpointB and endpointA ~= endpointB then
        local dA = AHG.distSq(gateObj:getX(), gateObj:getY(), gateObj:getZ(),
            endpointA:getX(), endpointA:getY(), endpointA:getZ())
        local dB = AHG.distSq(gateObj:getX(), gateObj:getY(), gateObj:getZ(),
            endpointB:getX(), endpointB:getY(), endpointB:getZ())
        if dA <= dB then return endpointA end
        return endpointB
    end

    return gateObj
end

-- ---------------------------------------------------------------------------
-- Markers
-- ---------------------------------------------------------------------------

function SAHGSystem:markRelatedObjectsForGate(record, anchorObj)
    if not record then return 0 end
    local gateObj = anchorObj or self:resolveGateObject(record)
    if not AHG.isDoorLike(gateObj) then return 0 end

    local group = AHG.getGateGroup(gateObj)
    local count = 0
    for i = 1, #group do
        if AHG.isDoorLike(group[i]) then
            AHG.markObject(group[i], record)
            count = count + 1
        end
    end
    return count
end

function SAHGSystem:getMarkedObjectsForGate(gateId)
    local result = {}
    if not gateId then return result end

    local anchor = self:getByGateId(gateId)
    if not anchor or anchor.x == nil or anchor.y == nil or anchor.z == nil then return result end

    local cell = getCell()
    if not cell then return result end

    -- Gate pieces sit on adjacent squares; scan a small local radius.
    for dx = -4, 4 do
        for dy = -4, 4 do
            local sq = cell:getGridSquare(anchor.x + dx, anchor.y + dy, anchor.z)
            if sq then
                for j = 0, sq:getObjects():size() - 1 do
                    local obj = sq:getObjects():get(j)
                    if obj and obj:hasModData() and obj:getModData()[AHG.MD.GateId] == gateId then
                        table.insert(result, obj)
                    end
                end
            end
        end
    end

    return result
end

function SAHGSystem:clearMarkersForGate(record)
    if not record or not record.gateId then return 0 end
    local objects = self:getMarkedObjectsForGate(record.gateId)
    for i = 1, #objects do
        AHG.clearObjectMarker(objects[i])
    end
    return #objects
end

-- ---------------------------------------------------------------------------
-- Register / unregister
-- ---------------------------------------------------------------------------

function SAHGSystem:registerGate(playerObj, gateObj, tag)
    if not AHG.isDoorLike(gateObj) then return false, "IGUI_AHG_NoValidGateFound" end
    if AHG.isRegisteredObject(gateObj) then return false, "IGUI_AHG_AlreadyRegistered" end

    local anchor = self:getStableGateAnchor(gateObj) or gateObj
    if AHG.isRegisteredObject(anchor) then return false, "IGUI_AHG_AlreadyRegistered" end

    local existing = self:getLuaObjectAt(anchor:getX(), anchor:getY(), anchor:getZ())
    if existing then return false, "IGUI_AHG_AlreadyRegistered" end

    local record = self:newLuaObjectAt(anchor:getX(), anchor:getY(), anchor:getZ())
    record:initNew()
    record.gateId = AHG.makeGateId(anchor)
    record.tag = tostring(tag or "")
    record.registeredBy = playerObj and playerObj:getUsername() or "unknown"
    local worldAge = 0
    pcall(function() worldAge = getGameTime():getWorldAgeHours() end)
    record.registeredAt = worldAge
    record.objectIndex = AHG.getObjectIndex(anchor)
    record.spriteName = AHG.getSpriteName(anchor) or ""
    record.objectName = AHG.getObjectName(anchor) or ""
    record.north = anchor.getNorth and anchor:getNorth() or false

    local marked = self:markRelatedObjectsForGate(record, anchor)
    record:updateOnClient()
    self:rebuildIndex()

    AHG.noise("registered gateId=" .. tostring(record.gateId)
        .. " tag=" .. tostring(record.tag)
        .. " at " .. record.x .. "," .. record.y .. "," .. record.z
        .. " pieces=" .. tostring(marked))
    return true, record
end

function SAHGSystem:unregisterGate(playerObj, gateObj)
    local record = self:getGateForObject(gateObj)
    if not record then
        AHG.clearObjectMarker(gateObj)
        return false, "IGUI_AHG_NotRegistered"
    end
    self:removeGateRecord(record, "manual unregister by " .. tostring(playerObj and playerObj:getUsername()))
    return true, "IGUI_AHG_Unregistered"
end

function SAHGSystem:setGateTag(playerObj, gateObj, tag)
    local record = self:getGateForObject(gateObj)
    if not record then
        return false, "IGUI_AHG_NotRegistered"
    end

    record.tag = tostring(tag or "")
    local marked = self:markRelatedObjectsForGate(record, gateObj)
    record:updateOnClient()

    AHG.noise("set tag gateId=" .. tostring(record.gateId)
        .. " tag=" .. tostring(record.tag)
        .. " by=" .. tostring(playerObj and playerObj:getUsername())
        .. " marked=" .. tostring(marked))
    return true, record
end

function SAHGSystem:removeGateRecord(record, reason)
    if not record then return false end
    local gateId = record.gateId
    local cleared = self:clearMarkersForGate(record)
    self:removeLuaObject(record)
    self:rebuildIndex()
    if gateId then
        if self.pendingRemovalChecks then self.pendingRemovalChecks[gateId] = nil end
        if self.autoClose then self.autoClose[gateId] = nil end
        if self.openWatch then self.openWatch[gateId] = nil end
    end
    AHG.noise("removed gateId=" .. tostring(gateId) .. " reason=" .. tostring(reason) .. " cleared=" .. tostring(cleared))
    return true
end

-- ---------------------------------------------------------------------------
-- Operate: open / close with lock bypass and restore
-- ---------------------------------------------------------------------------

-- Match GateMotor / HydeCo / ASG: call ToggleDoor once on a single canonical
-- handle. Vanilla syncs the rest of a double-door / garage group from that.
-- Do NOT ToggleDoorSilent every leftover leaf - that desyncs assemblies and
-- can leave secondary pieces with a null sprite (which then permanently
-- broke our earlier "refuse if any piece has no sprite" guard).
function SAHGSystem:togglePiece(piece, playerObj)
    if not piece or not piece.ToggleDoor then return false end

    local before = AHG.isOpen(piece)
    local actor = AHG.findActorForToggle(piece:getX(), piece:getY(), piece:getZ(), playerObj)

    local ok = pcall(function()
        piece:ToggleDoor(actor)
    end)

    local after = AHG.isOpen(piece)
    if ok and after ~= before then
        AHG.noise("togglePiece ok before=" .. tostring(before) .. " after=" .. tostring(after)
            .. " @ " .. tostring(piece:getX()) .. "," .. tostring(piece:getY()))
        return true
    end

    -- ToggleDoor can refuse when the actor is missing / too far (vehicle fob).
    -- One silent flip on the SAME canonical piece only - never on every leaf.
    pcall(function()
        if piece.ToggleDoorSilent then
            piece:ToggleDoorSilent()
        elseif piece.ToggleDoor then
            piece:ToggleDoor(nil)
        end
    end)

    after = AHG.isOpen(piece)
    AHG.noise("togglePiece silent-fallback before=" .. tostring(before) .. " after=" .. tostring(after)
        .. " @ " .. tostring(piece:getX()) .. "," .. tostring(piece:getY()))
    return after ~= before
end

function SAHGSystem:toggleGroup(group, playerObj, targetOpen)
    if not group or #group == 0 then return 0 end
    if AHG.isGroupOpen(group) == targetOpen then
        AHG.noise("toggleGroup already at targetOpen=" .. tostring(targetOpen))
        return 1
    end

    local handle = AHG.getCanonicalGateHandle(group)
    if not handle then return 0 end

    local toggled = self:togglePiece(handle, playerObj)

    -- Re-walk partners from the handle; stale leaf refs can lie after ToggleDoor.
    local fresh = AHG.getGateGroup(handle)
    if not fresh or #fresh == 0 then fresh = group end
    local success = AHG.isGroupOpen(fresh) == targetOpen

    AHG.noise("toggleGroup targetOpen=" .. tostring(targetOpen)
        .. " success=" .. tostring(success) .. " toggled=" .. tostring(toggled)
        .. " pieces=" .. tostring(#fresh))
    if success then return 1 end
    return 0
end

function SAHGSystem:captureAndUnlock(record, group)
    local anyKey, anyIso, anyPad = false, false, false
    for i = 1, #group do
        local key, iso, pad = AHG.pieceLockState(group[i])
        anyKey = anyKey or key
        anyIso = anyIso or iso
        anyPad = anyPad or pad
    end
    if not (anyKey or anyIso or anyPad) then return false end

    record.savedLockKey = anyKey
    record.savedLockIso = anyIso
    record.savedLockPadlock = anyPad
    record.hasSavedLock = true

    for i = 1, #group do
        AHG.setPieceLocks(group[i], false, false, false)
        AHG.syncPiece(group[i])
    end
    AHG.noise("lock bypass on gateId=" .. tostring(record.gateId)
        .. " key=" .. tostring(anyKey) .. " iso=" .. tostring(anyIso) .. " padlock=" .. tostring(anyPad))
    return true
end

function SAHGSystem:restoreLocks(record, group)
    if not record or not record.hasSavedLock then return end
    if AHG.opt("RelockOnClose") and group then
        for i = 1, #group do
            AHG.setPieceLocks(group[i], record.savedLockKey, record.savedLockIso, record.savedLockPadlock)
            AHG.syncPiece(group[i])
        end
        AHG.noise("restored locks on gateId=" .. tostring(record.gateId))
    end
    record.savedLockKey = false
    record.savedLockIso = false
    record.savedLockPadlock = false
    record.hasSavedLock = false
end

-- Garage / double-door toggles can replace IsoObjects. Re-resolve before
-- lock restore and ModData re-mark so later hotkeys still find the gate.
function SAHGSystem:refreshGateGroup(record, fallbackGroup)
    local gateObj = self:resolveGateObject(record)
    if gateObj then
        return gateObj, AHG.getGateGroup(gateObj)
    end
    return nil, fallbackGroup
end

function SAHGSystem:finishClose(record, group, gateObj)
    local freshObj, freshGroup = self:refreshGateGroup(record, group)
    gateObj = freshObj or gateObj
    group = freshGroup or group
    self:restoreLocks(record, group)
    self:disarmAutoClose(record.gateId)
    if gateObj then
        self:markRelatedObjectsForGate(record, gateObj)
    end
    record:updateOnClient()
end

function SAHGSystem:finishOpen(record, group, gateObj)
    local freshObj, freshGroup = self:refreshGateGroup(record, group)
    gateObj = freshObj or gateObj
    group = freshGroup or group
    self:armAutoClose(record)
    if gateObj then
        self:markRelatedObjectsForGate(record, gateObj)
    end
    record:updateOnClient()
end

function SAHGSystem:tryOpenGroup(record, group, playerObj)
    if AHG.isGroupLocked(group) then
        if not AHG.opt("BypassLocks") then
            return false, "IGUI_AHG_GateLocked"
        end
        self:captureAndUnlock(record, group)
    end

    local changed = self:toggleGroup(group, playerObj, true)
    if changed > 0 then return true, nil end

    -- Post-auto-close relock / stale refs: unlock hard, refresh, retry once.
    if AHG.opt("BypassLocks") then
        local freshObj, freshGroup = self:refreshGateGroup(record, group)
        group = freshGroup or group
        if not self:captureAndUnlock(record, group) then
            for i = 1, #group do
                AHG.setPieceLocks(group[i], false, false, false)
                AHG.syncPiece(group[i])
            end
        end
        changed = self:toggleGroup(group, playerObj, true)
        if changed > 0 then return true, nil end
    end

    self:restoreLocks(record, group)
    record:updateOnClient()
    return false, "IGUI_AHG_ToggleFailed"
end

function SAHGSystem:operateGate(playerObj, record)
    local gateObj, status = self:resolveGateObjectWithStatus(record)
    if not gateObj then
        if status == "square_unavailable" then return false, "IGUI_AHG_GateNotLoaded" end
        return false, "IGUI_AHG_GateMissing"
    end

    local group = AHG.getGateGroup(gateObj)
    local wantOpen = not AHG.isGroupOpen(group)
    local isGarage = AHG.isGarageGroup(group)

    if wantOpen then
        local ok, err = self:tryOpenGroup(record, group, playerObj)
        if not ok then return false, err end
        self:finishOpen(record, group, gateObj)
        if isGarage then return true, "IGUI_AHG_GarageDoorOpened" end
        return true, "IGUI_AHG_GateOpened"
    else
        local changed = self:toggleGroup(group, playerObj, false)
        if changed == 0 then
            -- Refresh once in case open-state refs were stale after a prior auto-close.
            local freshObj, freshGroup = self:refreshGateGroup(record, group)
            if freshObj then
                gateObj, group = freshObj, freshGroup
                isGarage = AHG.isGarageGroup(group)
                changed = self:toggleGroup(group, playerObj, false)
            end
        end
        if changed == 0 then
            return false, "IGUI_AHG_ToggleFailed"
        end
        self:finishClose(record, group, gateObj)
        if isGarage then return true, "IGUI_AHG_GarageDoorClosed" end
        return true, "IGUI_AHG_GateClosed"
    end
end

-- ---------------------------------------------------------------------------
-- Auto-close
-- ---------------------------------------------------------------------------

function SAHGSystem:armAutoClose(record)
    local secs = tonumber(AHG.opt("AutoCloseSeconds")) or 0
    if secs <= 0 or not record or not record.gateId then return end
    self.autoClose = self.autoClose or {}
    self.autoClose[record.gateId] = AHG.nowMs() + secs * 1000
    AHG.noise("auto-close armed gateId=" .. tostring(record.gateId) .. " in " .. tostring(secs) .. "s")
end

function SAHGSystem:disarmAutoClose(gateId)
    if not gateId or not self.autoClose then return end
    self.autoClose[gateId] = nil
end

-- True while any player, zombie, or vehicle occupies the gateway tiles.
function SAHGSystem:isGateBlocked(group)
    if not group then return false end
    for i = 1, #group do
        local piece = group[i]
        if piece then
            local sq = piece:getSquare()
            if sq then
                local moving = sq:getMovingObjects()
                if moving and moving:size() > 0 then return true end
            end
        end
    end

    local blocked = false
    pcall(function()
        local cell = getCell()
        if not cell or not cell.getVehicles then return end
        local vehicles = cell:getVehicles()
        if not vehicles or not vehicles.size then return end
        local size = vehicles:size()
        if type(size) ~= "number" or size <= 0 then return end
        for v = 0, size - 1 do
            local vehicle = nil
            pcall(function() vehicle = vehicles:get(v) end)
            if vehicle then
                for i = 1, #group do
                    local piece = group[i]
                    if piece
                        and math.abs(vehicle:getX() - piece:getX()) < 2.5
                        and math.abs(vehicle:getY() - piece:getY()) < 2.5
                        and math.floor(vehicle:getZ() + 0.5) == piece:getZ() then
                        blocked = true
                        return
                    end
                end
            end
        end
    end)
    return blocked
end

-- Watch registered gates for open/close transitions from ANY source
-- (mod hotkey, vanilla E interact, other mods). Arms auto-close when a
-- gate becomes open and no timer is already running; disarms when closed.
-- Also re-arms if the gate is open with no timer (missed the rising edge,
-- e.g. chunk load while already open, or a prior failed auto-close).
function SAHGSystem:watchManualOpens()
    local secs = tonumber(AHG.opt("AutoCloseSeconds")) or 0
    if secs <= 0 then return end

    self.openWatch = self.openWatch or {}
    self.autoClose = self.autoClose or {}

    for i = 1, self:getLuaObjectCount() do
        local record = self:getLuaObjectByIndex(i)
        if record and record.gateId and record.gateId ~= "" then
            local gateObj = self:resolveGateObject(record)
            if gateObj then
                local isOpen = AHG.isGroupOpen(AHG.getGateGroup(gateObj))
                local wasOpen = self.openWatch[record.gateId] == true
                local hasTimer = self.autoClose[record.gateId] ~= nil

                if isOpen and not wasOpen then
                    if not hasTimer then
                        self:armAutoClose(record)
                        AHG.noise("auto-close armed from open-watch (manual/E/other) gateId="
                            .. tostring(record.gateId))
                    end
                elseif isOpen and wasOpen and not hasTimer then
                    -- Missed rising edge or a previous close attempt cleared the
                    -- timer while the gate stayed open - keep trying.
                    self:armAutoClose(record)
                    AHG.noise("auto-close re-armed; open with no timer gateId="
                        .. tostring(record.gateId))
                elseif (not isOpen) and wasOpen then
                    if hasTimer then
                        self:disarmAutoClose(record.gateId)
                        AHG.noise("auto-close disarmed; gate closed externally gateId="
                            .. tostring(record.gateId))
                    end
                end

                self.openWatch[record.gateId] = isOpen
            end
        end
    end
end

function SAHGSystem:processAutoClose()
    -- NOTE: Kahlua does not expose the global `next`; use nil guards + pairs only.
    if not self.autoClose then return end
    local now = AHG.nowMs()

    for gateId, closeAt in pairs(self.autoClose) do
        if now >= closeAt then
            local record = self:getByGateId(gateId)
            if not record then
                self.autoClose[gateId] = nil
            else
                local gateObj = self:resolveGateObject(record)
                if not gateObj then
                    -- Area unloaded or gate destroyed; give up quietly.
                    self.autoClose[gateId] = nil
                else
                    local group = AHG.getGateGroup(gateObj)
                    if not AHG.isGroupOpen(group) then
                        -- Already closed (manual / other); still finish lock+marker cleanup.
                        self:finishClose(record, group, gateObj)
                        if self.openWatch then self.openWatch[gateId] = false end
                        AHG.noise("auto-close skipped; already closed gateId=" .. tostring(gateId))
                    elseif AHG.opt("AutoCloseSafetyCheck") and self:isGateBlocked(group) then
                        self.autoClose[gateId] = now + AUTOCLOSE_RETRY_MS
                        AHG.noise("auto-close postponed (blocked) gateId=" .. tostring(gateId))
                    else
                        -- GateMotor/HydeCo/ASG always pass a living player into
                        -- ToggleDoor. Auto-close has no triggering player, so
                        -- borrow the nearest online one (or any alive player).
                        local actor = AHG.findActorForToggle(record.x, record.y, record.z, nil)
                        if self:toggleGroup(group, actor, false) > 0 then
                            self:finishClose(record, group, gateObj)
                            if self.openWatch then self.openWatch[gateId] = false end
                            AHG.noise("auto-closed gateId=" .. tostring(gateId))
                        else
                            -- Retry shortly instead of giving up permanently.
                            self.autoClose[gateId] = now + AUTOCLOSE_RETRY_MS
                            AHG.noise("auto-close retry (toggle failed) gateId=" .. tostring(gateId))
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Cleanup when gate objects are destroyed / replaced
-- ---------------------------------------------------------------------------

function SAHGSystem:scheduleRemovalCheck(gateId)
    if not gateId or not self:getByGateId(gateId) then return end
    self.pendingRemovalChecks = self.pendingRemovalChecks or {}
    -- Multiple pieces of a gate can emit removal events in the same tick.
    self.pendingRemovalChecks[gateId] = REMOVAL_VERIFY_TICKS
end

-- Strict existence check for the removal-check flow: true only if a piece
-- still carries THIS gate's own marker. Deliberately does not use
-- resolveGateObject/AHG.findDoorLikeOnSquare - those fall back to "any
-- door-like object on the anchor square" (useful for Trigger/Toggle, where
-- being lenient about which exact piece moved is helpful), which would
-- wrongly report the gate as "still there" if an unrelated door, or a
-- leftover corrupted remnant of the destroyed gate, happens to occupy the
-- same square. That false positive is what let a destroyed gate's tag/
-- registration survive by re-marking whatever was left behind.
function SAHGSystem:gateStillExists(record)
    if not record or not record.gateId then return false end
    local pieces = self:getMarkedObjectsForGate(record.gateId)
    for i = 1, #pieces do
        if AHG.isDoorLike(pieces[i]) then return true end
    end
    return false
end

function SAHGSystem:processPendingRemovalChecks()
    if not self.pendingRemovalChecks then return end

    for gateId, ticks in pairs(self.pendingRemovalChecks) do
        ticks = (tonumber(ticks) or 0) - 1
        if ticks > 0 then
            self.pendingRemovalChecks[gateId] = ticks
        else
            self.pendingRemovalChecks[gateId] = nil
            local record = self:getByGateId(gateId)
            if record then
                local sq = record:getSquare()
                if not sq then
                    -- Chunk unavailable; never delete persistent data blindly.
                    AHG.noise("deferred cleanup skipped; square unavailable gateId=" .. tostring(gateId))
                elseif self:gateStillExists(record) then
                    local gateObj = self:resolveGateObject(record)
                    if gateObj then
                        self:markRelatedObjectsForGate(record, gateObj)
                    end
                    AHG.noise("deferred cleanup preserved gateId=" .. tostring(gateId))
                else
                    self:removeGateRecord(record, "gate object missing after deferred removal check")
                end
            end
        end
    end
end

function SAHGSystem:OnObjectAboutToBeRemoved(isoObject)
    if not isoObject or not isoObject:hasModData() then return end
    local gateId = isoObject:getModData()[AHG.MD.GateId]
    if gateId and self:getByGateId(gateId) then
        self:scheduleRemovalCheck(gateId)
        return
    end
    SGlobalObjectSystem.OnObjectAboutToBeRemoved(self, isoObject)
end

-- ---------------------------------------------------------------------------
-- Tick driver (throttled)
-- ---------------------------------------------------------------------------

local tickCounter = 0
local function AHG_ServerOnTick()
    tickCounter = tickCounter + 1
    if tickCounter < TICK_THROTTLE then return end
    tickCounter = 0
    local instance = SAHGSystem.instance
    if not instance then return end
    -- Isolate tick work so one failure cannot starve the other, and cannot
    -- spam the bottom-right error counter every frame forever.
    local ok, err = pcall(function() instance:processPendingRemovalChecks() end)
    if not ok then print("[AHG] ERROR in processPendingRemovalChecks: " .. tostring(err)) end
    ok, err = pcall(function() instance:watchManualOpens() end)
    if not ok then print("[AHG] ERROR in watchManualOpens: " .. tostring(err)) end
    ok, err = pcall(function() instance:processAutoClose() end)
    if not ok then print("[AHG] ERROR in processAutoClose: " .. tostring(err)) end
end

Events.OnTick.Add(AHG_ServerOnTick)

SGlobalObjectSystem.RegisterSystemClass(SAHGSystem)
