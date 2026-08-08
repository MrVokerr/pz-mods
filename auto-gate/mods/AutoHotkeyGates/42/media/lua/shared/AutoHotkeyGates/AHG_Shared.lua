-- Automatic / Hotkey Gates - shared core
-- Loaded on client, server and singleplayer. Holds config access, gate
-- detection, gate-group helpers, ModData markers and lock helpers.

AHG = AHG or {}
AHG.Module = "AutoHotkeyGates"
AHG.SystemName = "autoHotkeyGates"
AHG.Version = 1

-- ModData keys written onto every tile piece of a registered gate.
AHG.MD = {
    Registered = "AHG_Registered",
    GateId = "AHG_GateId",
    Tag = "AHG_Tag",
    AnchorX = "AHG_AnchorX",
    AnchorY = "AHG_AnchorY",
    AnchorZ = "AHG_AnchorZ",
    AnchorIndex = "AHG_AnchorIndex",
}

-- Fallbacks used when SandboxVars are unavailable (e.g. main menu).
AHG.Defaults = {
    TriggerRange = 7,
    CooldownSeconds = 1.0,
    RequireVehicleGates = true,
    OperateFromVehicleOnly = false,
    BypassLocks = true,
    RelockOnClose = true,
    AutoCloseSeconds = 10,
    AutoCloseSafetyCheck = true,
    MinAccessLevelToRegister = 2,
    MaxRegisteredGates = 0,
    EnforcePermissionHook = true,
    EnableHotkey = true,
    EnableVehicleRadial = true,
    EnableContextMenu = true,
    ShowHaloMessages = true,
    DebugLogging = false,
}

function AHG.opt(name)
    local sv = SandboxVars and SandboxVars.AutoHotkeyGates
    if sv and sv[name] ~= nil then return sv[name] end
    return AHG.Defaults[name]
end

function AHG.noise(msg)
    if AHG.opt("DebugLogging") then
        print("[AHG] " .. tostring(msg))
    end
end

function AHG.text(key, ...)
    if getText then return getText(key, ...) end
    return tostring(key)
end

-- ---------------------------------------------------------------------------
-- Command dispatch (MP client -> server; SP calls the handler directly)
-- ---------------------------------------------------------------------------

function AHG.sendCommand(playerObj, command, args)
    args = args or {}
    -- Connected client / listen-server host UI: go over the network.
    if isClient() then
        sendClientCommand(playerObj, AHG.Module, command, args)
        return
    end
    -- Pure singleplayer (isClient and isServer both false): call server handler
    -- directly in-process. Dedicated-server process never runs this path.
    if AHG.ServerHandle then
        AHG.ServerHandle(command, playerObj, args)
    else
        print("[AHG] ERROR: ServerHandle missing for command " .. tostring(command))
    end
end

-- ---------------------------------------------------------------------------
-- Object helpers
-- ---------------------------------------------------------------------------

function AHG.isDoorLike(obj)
    if not obj then return false end
    if instanceof(obj, "IsoDoor") then return true end
    if instanceof(obj, "IsoThumpable") and obj.isDoor and obj:isDoor() then return true end
    return false
end

function AHG.getObjectIndex(obj)
    if not obj then return -1 end
    local ok, idx = pcall(function() return obj:getObjectIndex() end)
    if ok and idx then return idx end
    local sq = obj:getSquare()
    if not sq then return -1 end
    for i = 0, sq:getObjects():size() - 1 do
        if sq:getObjects():get(i) == obj then return i end
    end
    return -1
end

function AHG.getSquare(x, y, z)
    -- Use == nil: ground floor is z=0, which is valid and must not be treated as missing.
    if x == nil or y == nil or z == nil then return nil end
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(x, y, z)
end

function AHG.getObjectAt(x, y, z, index)
    local sq = AHG.getSquare(x, y, z)
    if not sq then return nil end
    -- index 0 is the first object on a square; `if index and` would reject it.
    if index ~= nil and index >= 0 and index < sq:getObjects():size() then
        return sq:getObjects():get(index)
    end
    return nil
end

function AHG.getSpriteName(obj)
    if not obj then return nil end
    local spr = obj:getSprite()
    if spr and spr:getName() then return spr:getName() end
    return nil
end

function AHG.getObjectName(obj)
    if not obj then return nil end
    local ok, name = pcall(function() return obj:getName() end)
    if ok then return name end
    return nil
end

function AHG.findDoorLikeOnSquare(square, gateId, fallbackIndex)
    if not square then return nil end

    if gateId then
        for i = 0, square:getObjects():size() - 1 do
            local obj = square:getObjects():get(i)
            if AHG.isDoorLike(obj) and obj:hasModData() then
                if obj:getModData()[AHG.MD.GateId] == gateId then
                    return obj
                end
            end
        end
    end

    -- fallbackIndex 0 is valid; do not use truthiness checks on it.
    if fallbackIndex ~= nil and fallbackIndex >= 0 and fallbackIndex < square:getObjects():size() then
        local obj = square:getObjects():get(fallbackIndex)
        if AHG.isDoorLike(obj) then return obj end
    end

    for i = 0, square:getObjects():size() - 1 do
        local obj = square:getObjects():get(i)
        if AHG.isDoorLike(obj) then return obj end
    end

    return nil
end

-- Context menus may pass a Lua array or a Java ArrayList depending on build/path.
function AHG.forEachWorldObject(worldobjects, fn)
    if not worldobjects or not fn then return end
    if worldobjects.size and worldobjects.get then
        for i = 0, worldobjects:size() - 1 do
            fn(worldobjects:get(i))
        end
        return
    end
    for i = 1, #worldobjects do
        fn(worldobjects[i])
    end
end

function AHG.findDoorLikeFromWorldObjects(worldobjects)
    if not worldobjects then return nil end
    local found = nil
    AHG.forEachWorldObject(worldobjects, function(obj)
        if found then return end
        if AHG.isDoorLike(obj) then
            found = obj
            return
        end
        local square = obj and obj:getSquare()
        found = AHG.findDoorLikeOnSquare(square)
    end)
    return found
end

function AHG.isOpen(obj)
    if not obj then return false end
    local isOpen = false
    pcall(function() isOpen = obj:IsOpen() end)
    return isOpen
end

-- True if any piece of a multi-tile gate/door assembly is open.
function AHG.isGroupOpen(group)
    if not group then return false end
    for i = 1, #group do
        if AHG.isOpen(group[i]) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Gate group detection (multi-tile gates / garage doors)
-- IMPORTANT (B42): IsoDoor.getDoubleDoorObject(obj, i) throws
-- ArrayIndexOutOfBoundsException when obj is NOT a double-door piece.
-- Always guard with getDoubleDoorIndex / getGarageDoorIndex first.
-- Do not call buildUtil.getDoubleDoorObjects on arbitrary doors.
-- ---------------------------------------------------------------------------

local function appendUnique(list, candidate)
    if not candidate then return end
    for i = 1, #list do
        if list[i] == candidate then return end
    end
    table.insert(list, candidate)
end

function AHG.getDoubleDoorIndexSafe(obj)
    local idx = -1
    if not obj or not IsoDoor or not IsoDoor.getDoubleDoorIndex then return -1 end
    pcall(function() idx = IsoDoor.getDoubleDoorIndex(obj) end)
    if type(idx) ~= "number" then return -1 end
    return idx
end

function AHG.getGarageDoorIndexSafe(obj)
    local idx = -1
    if not obj or not IsoDoor or not IsoDoor.getGarageDoorIndex then return -1 end
    pcall(function() idx = IsoDoor.getGarageDoorIndex(obj) end)
    if type(idx) ~= "number" then return -1 end
    return idx
end

function AHG.getGateGroup(obj)
    local result = {}
    if not AHG.isDoorLike(obj) then return result end
    table.insert(result, obj)

    -- Double doors / double gates (indices 1..4 only).
    if AHG.getDoubleDoorIndexSafe(obj) ~= -1 then
        for i = 1, 4 do
            local piece = nil
            pcall(function() piece = IsoDoor.getDoubleDoorObject(obj, i) end)
            appendUnique(result, piece)
        end
    end

    -- Garage door segments.
    if AHG.getGarageDoorIndexSafe(obj) ~= -1 then
        local prev = nil
        pcall(function() prev = IsoDoor.getGarageDoorPrev(obj) end)
        while prev do
            appendUnique(result, prev)
            local nextPrev = nil
            pcall(function() nextPrev = IsoDoor.getGarageDoorPrev(prev) end)
            prev = nextPrev
        end
        local nxt = nil
        pcall(function() nxt = IsoDoor.getGarageDoorNext(obj) end)
        while nxt do
            appendUnique(result, nxt)
            local nextNxt = nil
            pcall(function() nextNxt = IsoDoor.getGarageDoorNext(nxt) end)
            nxt = nextNxt
        end
    end

    return result
end

-- A "vehicle gate" is any door assembly spanning more than one tile:
-- double gates, double doors and garage doors.
function AHG.isVehicleGate(obj)
    if not AHG.isDoorLike(obj) then return false end
    if AHG.getGarageDoorIndexSafe(obj) ~= -1 then return true end
    if AHG.getDoubleDoorIndexSafe(obj) ~= -1 then return true end
    return #AHG.getGateGroup(obj) >= 2
end

function AHG.isEligibleGate(obj)
    if not AHG.isDoorLike(obj) then return false end
    if AHG.opt("RequireVehicleGates") then
        return AHG.isVehicleGate(obj)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- ModData markers
-- ---------------------------------------------------------------------------

function AHG.isRegisteredObject(obj)
    if not AHG.isDoorLike(obj) or not obj:hasModData() then return false end
    local md = obj:getModData()
    return md[AHG.MD.Registered] == true and md[AHG.MD.GateId] ~= nil
end

function AHG.getGateIdFromObject(obj)
    if not obj or not obj:hasModData() then return nil end
    return obj:getModData()[AHG.MD.GateId]
end

function AHG.getTagFromObject(obj)
    if not obj or not obj:hasModData() then return nil end
    return obj:getModData()[AHG.MD.Tag]
end

function AHG.makeGateId(obj)
    return tostring(obj:getX()) .. "," .. tostring(obj:getY()) .. "," .. tostring(obj:getZ())
        .. ":" .. tostring(AHG.getObjectIndex(obj)) .. ":" .. tostring(ZombRand(100000000))
end

function AHG.markObject(obj, record)
    if not obj or not record then return end
    local md = obj:getModData()
    md[AHG.MD.Registered] = true
    md[AHG.MD.GateId] = record.gateId
    md[AHG.MD.Tag] = record.tag or ""
    md[AHG.MD.AnchorX] = record.x
    md[AHG.MD.AnchorY] = record.y
    md[AHG.MD.AnchorZ] = record.z
    md[AHG.MD.AnchorIndex] = record.objectIndex or -1
    if isServer() then
        pcall(function() obj:transmitModData() end)
    end
end

function AHG.clearObjectMarker(obj)
    if not obj or not obj:hasModData() then return end
    local md = obj:getModData()
    md[AHG.MD.Registered] = nil
    md[AHG.MD.GateId] = nil
    md[AHG.MD.Tag] = nil
    md[AHG.MD.AnchorX] = nil
    md[AHG.MD.AnchorY] = nil
    md[AHG.MD.AnchorZ] = nil
    md[AHG.MD.AnchorIndex] = nil
    if isServer() then
        pcall(function() obj:transmitModData() end)
    end
end

-- ---------------------------------------------------------------------------
-- Distance
-- ---------------------------------------------------------------------------

function AHG.distSq(ax, ay, az, bx, by, bz)
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    local dz = (tonumber(az) or 0) - (tonumber(bz) or 0)
    return dx * dx + dy * dy + (dz * dz * 100)
end

function AHG.isPlayerNear(playerObj, x, y, z, maxDist)
    if not playerObj then return false end
    local d2 = AHG.distSq(playerObj:getX(), playerObj:getY(), playerObj:getZ(), x, y, z)
    return d2 <= (maxDist * maxDist)
end

-- ---------------------------------------------------------------------------
-- Access levels (registration rights)
-- ---------------------------------------------------------------------------

local ACCESS_RANK = {
    admin = 5, moderator = 4, overseer = 3, gm = 2, observer = 1,
}

-- MinAccessLevelToRegister enum: 1=Admin, 2=Moderator+, 3=Overseer+, 4=GM+
local ENUM_TO_RANK = { 5, 4, 3, 2 }

function AHG.accessRank(levelStr)
    if not levelStr then return 0 end
    return ACCESS_RANK[string.lower(tostring(levelStr))] or 0
end

-- B42 prefers Role objects (player:getRole():getName()). Fall back to the
-- older getAccessLevel string and the client-only globals isAdmin/getAccessLevel.
function AHG.getPlayerAccessLevel(playerObj)
    if not playerObj then return "" end

    local level = ""
    pcall(function()
        if playerObj.getRole then
            local role = playerObj:getRole()
            if role and role.getName then
                level = tostring(role:getName() or "")
            end
        end
    end)

    if level == "" or string.lower(level) == "none" then
        pcall(function()
            if playerObj.getAccessLevel then
                level = tostring(playerObj:getAccessLevel() or "")
            end
        end)
    end

    -- Local client staff checks (vanilla AdminContextMenu pattern).
    if (level == "" or string.lower(level) == "none") and isClient() then
        pcall(function()
            if isAdmin and isAdmin() then
                level = "admin"
            elseif getAccessLevel then
                level = tostring(getAccessLevel() or "")
            end
        end)
    end

    return level or ""
end

function AHG.playerCanRegister(playerObj)
    if not playerObj then return false end
    -- Solo worlds have no access levels; the world owner can always register.
    if not isClient() and not isServer() then return true end
    local required = ENUM_TO_RANK[tonumber(AHG.opt("MinAccessLevelToRegister")) or 1] or 5
    return AHG.accessRank(AHG.getPlayerAccessLevel(playerObj)) >= required
end

-- ---------------------------------------------------------------------------
-- Lock helpers (capture / clear / restore across a gate group)
-- ---------------------------------------------------------------------------

function AHG.pieceLockState(obj)
    local key, iso, pad = false, false, false
    if not obj then return key, iso, pad end
    pcall(function() if obj.isLockedByKey then key = obj:isLockedByKey() or false end end)
    pcall(function() if obj.isLocked then iso = obj:isLocked() or false end end)
    pcall(function() if obj.isLockedByPadlock then pad = obj:isLockedByPadlock() or false end end)
    return key, iso, pad
end

function AHG.isGroupLocked(group)
    if not group then return false end
    for i = 1, #group do
        local key, iso, pad = AHG.pieceLockState(group[i])
        if key or iso or pad then return true end
    end
    return false
end

function AHG.setPieceLocks(obj, key, iso, pad)
    if not obj then return end
    pcall(function() if obj.setLockedByKey then obj:setLockedByKey(key) end end)
    pcall(function() if obj.setIsLocked then obj:setIsLocked(iso) end end)
    pcall(function() if obj.setLockedByPadlock then obj:setLockedByPadlock(pad) end end)
end

-- Sync lock / open-state / sprite to clients after a remote toggle.
-- B42: ToggleDoor usually networks itself; ToggleDoorSilent does not, so we
-- must push sprite + iso state when the silent path was used.
function AHG.syncPiece(obj)
    if not obj then return end
    pcall(function()
        if instanceof(obj, "IsoThumpable") and obj.sync then
            obj:sync()
        end
        if obj.syncIsoObject then
            obj:syncIsoObject(false, 0, nil, nil)
        end
        if isServer() and obj.transmitUpdatedSpriteToClients then
            obj:transmitUpdatedSpriteToClients()
        end
    end)
end

-- Timestamp helper (B42+). Falls back to wall-clock ms via getTimeInMillis.
function AHG.nowMs()
    if getTimestampMs then
        local ok, t = pcall(getTimestampMs)
        if ok and t then return t end
    end
    if getTimeInMillis then
        local ok, t = pcall(getTimeInMillis)
        if ok and t then return t end
    end
    return 0
end
