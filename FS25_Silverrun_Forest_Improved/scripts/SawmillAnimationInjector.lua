-- =============================================================================
-- FS25_Silverrun_Forest_Improved
-- SawmillAnimationInjector.lua
--
-- Finds the preplaced old sawmill of Silverrun Forest at runtime and
--   1) switches the existing pond wood trigger to automatic log collection
--      (calls WoodUnloadTrigger:processWood, the same function the manual
--      "sell" activation uses, so prices, storage limits and the existing
--      log lift animation behave exactly like vanilla),
--   4) turns the yellow wood chipper next to the pond into a real chipper: logs
--      become WOODCHIPS in the sawmill storage (the map's heap spawner puts them
--      on the chip heap) instead of WOOD, optionally fully automatic like FS22,
--   2) drives the shader based roller/belt animations of the conveyors and
--      couples them to the production state,
--   3) restores the FS22 log lift: logs leave the pond one by one and a trunk
--      model travels over the chain, up the ramp into the hall. FS25 ignores the
--      map's <animation> block, so the clip keyframes (taken from the map's
--      sawmillOldAnimation.i3d.anim) are played by this script.
--
-- No map file is changed. Everything happens on the runtime instance.
-- =============================================================================

SawmillAnimationInjector = {}
SawmillAnimationInjector.MOD_NAME = g_currentModName
SawmillAnimationInjector.MOD_DIR = g_currentModDirectory
SawmillAnimationInjector.CONFIG_FILE = "xml/custom_sawmill_extension.xml"
SawmillAnimationInjector.SEARCH_INTERVAL = 2000   -- ms between searches for the sawmill
SawmillAnimationInjector.MAX_SEARCH_TIME = 120000 -- give up after 2 minutes
SawmillAnimationInjector.LOG_PREFIX = "[SilverrunForestImproved] "

local function logInfo(fmt, ...)
    print(SawmillAnimationInjector.LOG_PREFIX .. string.format(fmt, ...))
end

local function logWarning(fmt, ...)
    Logging.warning(SawmillAnimationInjector.LOG_PREFIX .. string.format(fmt, ...))
end

local function parseVector3(str)
    if str == nil then
        return nil
    end
    local values = {}
    for part in string.gmatch(str, "%S+") do
        local v = tonumber(part)
        if v == nil then
            return nil
        end
        table.insert(values, v)
    end
    if #values ~= 3 then
        return nil
    end
    return values
end

local function endsWith(str, suffix)
    if str == nil or suffix == nil then
        return false
    end
    str = string.gsub(str, "\\", "/")
    return suffix == "" or string.sub(str, -string.len(suffix)) == suffix
end

-- -----------------------------------------------------------------------------
-- Config
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector:loadConfig()
    local cfg = {
        uniqueId = "sawmillOld",
        configFileSuffix = "sawmillOld/sawmillOldTriggers.xml",
        rotationNodes = {},
        scrollNodes = {},
        syncWithProduction = true,
        woodTriggerNodeName = "woodTrigger",
        autoCollect = true,
        intervalMs = 1000,
        chipper = {triggerNodeName = "woodTriggerCrusher", mode = "chips", autoChip = true, intervalMs = 1500, chipsScale = 1.0},
        logLift = {enabled = false, nodePrefix = "logAnimNode", nodeCount = 5, speedScale = 0.5, waitThreshold = 3400, keys = {}, duration = 0}
    }

    local path = Utils.getFilename(self.CONFIG_FILE, self.MOD_DIR)
    local xmlFile = loadXMLFile("silverrunSawmillExtension", path)
    if xmlFile == nil or xmlFile == 0 then
        logWarning("Config '%s' could not be loaded, using defaults (no log lift).", tostring(path))
        table.insert(cfg.rotationNodes, {shapeName = "satrtRot", parameter = "rotation", speed = 15, axis = 2})
        table.insert(cfg.rotationNodes, {shapeName = "middleRot", parameter = "rotation", speed = 15, axis = 2})
        table.insert(cfg.scrollNodes, {shapeName = "uvScroll", parameter = "offsetUV", speedScale = 1})
        return cfg
    end

    local base = "sawmillExtension.productionPoint"
    cfg.uniqueId = Utils.getNoNil(getXMLString(xmlFile, base .. "#uniqueId"), cfg.uniqueId)
    cfg.configFileSuffix = Utils.getNoNil(getXMLString(xmlFile, base .. "#configFileSuffix"), cfg.configFileSuffix)

    local i = 0
    while true do
        local key = string.format("%s.animationNodes.rotationNode(%d)", base, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        local axis = Utils.getNoNil(getXMLInt(xmlFile, key .. "#rotAxis"), 2)
        if axis < 1 or axis > 3 then
            logWarning("rotationNode %d: rotAxis %d invalid (1-3), using 2.", i, axis)
            axis = 2
        end
        table.insert(cfg.rotationNodes, {
            shapeName = getXMLString(xmlFile, key .. "#shapeName"),
            parameter = Utils.getNoNil(getXMLString(xmlFile, key .. "#shaderParameter"), "rotation"),
            speed = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#rotSpeed"), 8),
            axis = axis
        })
        i = i + 1
    end

    i = 0
    while true do
        local key = string.format("%s.animationNodes.scrollNode(%d)", base, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end
        table.insert(cfg.scrollNodes, {
            shapeName = getXMLString(xmlFile, key .. "#shapeName"),
            parameter = Utils.getNoNil(getXMLString(xmlFile, key .. "#shaderParameter"), "offsetUV"),
            speedScale = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#speedScale"), 1)
        })
        i = i + 1
    end

    cfg.syncWithProduction = Utils.getNoNil(getXMLBool(xmlFile, base .. ".animationNodes.syncWithProduction#value"), true)
    cfg.woodTriggerNodeName = Utils.getNoNil(getXMLString(xmlFile, base .. ".woodTrigger#triggerNodeName"), cfg.woodTriggerNodeName)
    cfg.autoCollect = Utils.getNoNil(getXMLBool(xmlFile, base .. ".woodTrigger#autoCollect"), true)
    cfg.intervalMs = math.max(250, Utils.getNoNil(getXMLInt(xmlFile, base .. ".woodTrigger#intervalMs"), 1000))

    local ch = cfg.chipper
    ch.triggerNodeName = Utils.getNoNil(getXMLString(xmlFile, base .. ".chipper#triggerNodeName"), ch.triggerNodeName)
    ch.mode = Utils.getNoNil(getXMLString(xmlFile, base .. ".chipper#mode"), ch.mode)
    ch.autoChip = Utils.getNoNil(getXMLBool(xmlFile, base .. ".chipper#autoChip"), ch.autoChip)
    ch.intervalMs = math.max(250, Utils.getNoNil(getXMLInt(xmlFile, base .. ".chipper#intervalMs"), ch.intervalMs))
    ch.chipsScale = math.max(0, Utils.getNoNil(getXMLFloat(xmlFile, base .. ".chipper#chipsScale"), ch.chipsScale))

    local liftKey = base .. ".logLift"
    if hasXMLProperty(xmlFile, liftKey) then
        local lift = cfg.logLift
        lift.enabled = Utils.getNoNil(getXMLBool(xmlFile, liftKey .. "#enabled"), true)
        lift.nodePrefix = Utils.getNoNil(getXMLString(xmlFile, liftKey .. "#nodePrefix"), lift.nodePrefix)
        lift.nodeCount = Utils.getNoNil(getXMLInt(xmlFile, liftKey .. "#nodeCount"), lift.nodeCount)
        lift.speedScale = math.max(0.05, Utils.getNoNil(getXMLFloat(xmlFile, liftKey .. "#transSpeed"), lift.speedScale))
        lift.waitThreshold = Utils.getNoNil(getXMLFloat(xmlFile, liftKey .. "#waitThresholdAnimTime"), lift.waitThreshold)

        local k = 0
        while true do
            local key = string.format("%s.key(%d)", liftKey, k)
            if not hasXMLProperty(xmlFile, key) then
                break
            end
            local t = getXMLFloat(xmlFile, key .. "#t")
            local pos = parseVector3(getXMLString(xmlFile, key .. "#pos"))
            local rot = parseVector3(getXMLString(xmlFile, key .. "#rot"))
            if t ~= nil and pos ~= nil and rot ~= nil then
                table.insert(lift.keys, {t = t, x = pos[1], y = pos[2], z = pos[3], rx = rot[1], ry = rot[2], rz = rot[3]})
            end
            k = k + 1
        end

        if #lift.keys >= 2 then
            lift.duration = lift.keys[#lift.keys].t
        else
            lift.enabled = false
            logWarning("logLift has less than 2 keyframes, log lift disabled.")
        end
    end

    delete(xmlFile)
    return cfg
end

-- -----------------------------------------------------------------------------
-- Lifecycle (mod event listener)
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector:loadMap(filename)
    self.disabled = false
    local ok, result = pcall(self.loadConfig, self)
    if not ok then
        self.disabled = true
        Logging.error(self.LOG_PREFIX .. "Config could not be loaded, mod disabled: " .. tostring(result))
        return
    end
    self.config = result
    self.placeable = nil
    self.productionPoint = nil
    self.woodTrigger = nil
    self.rotationShapes = {}
    self.scrollShapes = {}
    self.isInjected = false
    self.searchTimer = 0
    self.searchTime = 0
    self.collectTimer = 0
    self.chipTimer = 0
    self.chipperTrigger = nil
    self.chipperOriginalProcess = nil
    self.chipperOriginalText = nil
    self.lastRunningState = nil
    self.warnedFarm = false
    self.liftSlots = {}
    logInfo("Loaded. Waiting for sawmill '%s'.", tostring(self.config.uniqueId))
end

function SawmillAnimationInjector:deleteMap()
    -- restore original shader values so nothing leaks into a reloaded mission
    if self.isInjected and self.rotationShapes ~= nil then
        self:setAnimationsRunning(true, true)
        for _, slot in ipairs(self.liftSlots) do
            if entityExists(slot.node) then
                setVisibility(slot.node, false)
            end
        end
    end
    self:restoreChipper()
    self.placeable = nil
    self.productionPoint = nil
    self.woodTrigger = nil
    self.rotationShapes = {}
    self.scrollShapes = {}
    self.liftSlots = {}
    self.isInjected = false
end

function SawmillAnimationInjector:update(dt)
    if self.disabled or self.config == nil or g_currentMission == nil then
        return
    end
    local ok, err = pcall(self.updateInternal, self, dt)
    if not ok then
        self.disabled = true
        Logging.error(self.LOG_PREFIX .. "Runtime error, mod disabled for this session: " .. tostring(err))
    end
end

function SawmillAnimationInjector:updateInternal(dt)

    if not self.isInjected then
        if self.searchTime > self.MAX_SEARCH_TIME then
            return
        end
        self.searchTime = self.searchTime + dt
        self.searchTimer = self.searchTimer - dt
        if self.searchTimer <= 0 then
            self.searchTimer = self.SEARCH_INTERVAL
            self:tryInject()
            if not self.isInjected and self.searchTime > self.MAX_SEARCH_TIME then
                logWarning("Sawmill '%s' not found. Is FS25_silverrunForest the active map?", self.config.uniqueId)
            end
        end
        return
    end

    -- placeable was sold/removed
    if self.placeable == nil or self.placeable.isDeleted then
        self.isInjected = false
        self.searchTime = 0
        return
    end

    self:updateAnimations()
    self:updateLogLift(dt)
    self:updateAutoCollect(dt)
    self:updateAutoChip(dt)
end

-- -----------------------------------------------------------------------------
-- Finding and injecting
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector:findSawmill()
    local placeableSystem = g_currentMission.placeableSystem
    if placeableSystem == nil then
        return nil
    end

    local placeable = nil
    if placeableSystem.getPlaceableByUniqueId ~= nil then
        placeable = placeableSystem:getPlaceableByUniqueId(self.config.uniqueId)
    end

    if placeable == nil and type(placeableSystem.placeables) == "table" then
        for _, p in pairs(placeableSystem.placeables) do
            if endsWith(p.configFileName, self.config.configFileSuffix) then
                placeable = p
                break
            end
        end
    end

    if placeable ~= nil and not endsWith(placeable.configFileName, self.config.configFileSuffix) then
        logWarning("Placeable '%s' has unexpected config '%s', skipping.", self.config.uniqueId, tostring(placeable.configFileName))
        return nil
    end

    return placeable
end

function SawmillAnimationInjector:collectShapesByName(node, name, result)
    if getName(node) == name then
        table.insert(result, node)
    end
    for i = 0, getNumOfChildren(node) - 1 do
        self:collectShapesByName(getChildAt(node, i), name, result)
    end
end

function SawmillAnimationInjector:tryInject()
    local placeable = self:findSawmill()
    if placeable == nil or placeable.rootNode == nil then
        return
    end

    local spec = placeable.spec_productionPoint
    if spec == nil or spec.productionPoint == nil then
        logWarning("Sawmill found but has no production point spec.")
        self.searchTime = self.MAX_SEARCH_TIME + 1
        return
    end

    self.placeable = placeable
    self.productionPoint = spec.productionPoint

    -- 1) shader animated rollers / belts (part of the dynamically loaded conveyors)
    self.rotationShapes = {}
    for _, def in ipairs(self.config.rotationNodes) do
        local nodes = {}
        self:collectShapesByName(placeable.rootNode, def.shapeName, nodes)
        for _, node in ipairs(nodes) do
            if getHasShaderParameter(node, def.parameter) then
                local x, y, z, w = getShaderParameter(node, def.parameter)
                table.insert(self.rotationShapes, {node = node, def = def, orig = {x, y, z, w}})
            end
        end
    end

    self.scrollShapes = {}
    for _, def in ipairs(self.config.scrollNodes) do
        local nodes = {}
        self:collectShapesByName(placeable.rootNode, def.shapeName, nodes)
        for _, node in ipairs(nodes) do
            if getHasShaderParameter(node, def.parameter) then
                local x, y, z, w = getShaderParameter(node, def.parameter)
                table.insert(self.scrollShapes, {node = node, def = def, orig = {x, y, z, w}})
            end
        end
    end

    if #self.rotationShapes == 0 and #self.scrollShapes == 0 then
        -- conveyors are a dynamically loaded part; try again later if not there yet
        if self.searchTime < self.MAX_SEARCH_TIME then
            self.placeable = nil
            self.productionPoint = nil
            return
        end
        logWarning("No conveyor shapes found, animation upgrade disabled.")
    end

    -- 2) pond wood trigger
    self.woodTrigger = nil
    local unloadingStation = self.productionPoint.unloadingStation
    if unloadingStation ~= nil and type(unloadingStation.unloadTriggers) == "table" then
        for _, trigger in ipairs(unloadingStation.unloadTriggers) do
            if trigger.woodInTrigger ~= nil and trigger.processWood ~= nil
                and trigger.triggerNode ~= nil and trigger.triggerNode ~= 0
                and getName(trigger.triggerNode) == self.config.woodTriggerNodeName then
                self.woodTrigger = trigger
                break
            end
        end
    end

    if self.woodTrigger == nil then
        logWarning("Pond wood trigger '%s' not found, auto collection disabled.", self.config.woodTriggerNodeName)
    end

    -- 2b) yellow wood chipper
    self:setupChipper(unloadingStation)

    -- 3) log lift trunk models (logAnimNode1..n, already part of the map's placeable)
    self.liftSlots = {}
    local lift = self.config.logLift
    if lift.enabled then
        for n = 1, lift.nodeCount do
            local nodes = {}
            self:collectShapesByName(placeable.rootNode, lift.nodePrefix .. tostring(n), nodes)
            if nodes[1] ~= nil then
                setVisibility(nodes[1], false)
                table.insert(self.liftSlots, {node = nodes[1], active = false, time = 0, keyIndex = 1})
            end
        end
        if #self.liftSlots == 0 then
            logWarning("No log lift nodes '%s1..%d' found, log lift disabled.", lift.nodePrefix, lift.nodeCount)
        end
    end

    self.isInjected = true
    self.lastRunningState = nil
    logInfo("Injected into '%s': %d roller shapes, %d belt shapes, auto collect %s, log lift slots %d, chipper %s.",
        self.config.uniqueId, #self.rotationShapes, #self.scrollShapes,
        tostring(self.woodTrigger ~= nil and self.config.autoCollect), #self.liftSlots,
        self.chipperTrigger ~= nil and (self.config.chipper.mode .. (self.config.chipper.autoChip and ", automatic" or "")) or "unchanged")
end

-- -----------------------------------------------------------------------------
-- Animations
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector:getIsProductionRunning()
    local pp = self.productionPoint
    if pp == nil or type(pp.activeProductions) ~= "table" then
        return true
    end
    for _, production in ipairs(pp.activeProductions) do
        -- status RUNNING; fall back to "enabled" if the constant is unavailable
        if ProductionPoint.PROD_STATUS ~= nil and ProductionPoint.PROD_STATUS.RUNNING ~= nil then
            if production.status == ProductionPoint.PROD_STATUS.RUNNING then
                return true
            end
        else
            return true
        end
    end
    return false
end

function SawmillAnimationInjector:setAnimationsRunning(isRunning, restoreOriginal)
    for _, entry in ipairs(self.rotationShapes) do
        if entityExists(entry.node) then
            local o = entry.orig
            if restoreOriginal then
                setShaderParameter(entry.node, entry.def.parameter, o[1], o[2], o[3], o[4], false)
            elseif isRunning then
                local v = {0, 0, 0}
                v[entry.def.axis] = entry.def.speed
                setShaderParameter(entry.node, entry.def.parameter, v[1], v[2], v[3], o[4], false)
            else
                setShaderParameter(entry.node, entry.def.parameter, 0, 0, 0, o[4], false)
            end
        end
    end

    for _, entry in ipairs(self.scrollShapes) do
        if entityExists(entry.node) then
            local o = entry.orig
            if restoreOriginal then
                setShaderParameter(entry.node, entry.def.parameter, o[1], o[2], o[3], o[4], false)
            elseif isRunning then
                local s = entry.def.speedScale
                setShaderParameter(entry.node, entry.def.parameter, o[1], o[2], o[3] * s, o[4] * s, false)
            else
                -- keep static offset (x, y), stop scrolling speed (z, w)
                setShaderParameter(entry.node, entry.def.parameter, o[1], o[2], 0, 0, false)
            end
        end
    end
end

function SawmillAnimationInjector:updateAnimations()
    local running = true
    if self.config.syncWithProduction then
        running = self:getIsProductionRunning()
    end
    if running ~= self.lastRunningState then
        self.lastRunningState = running
        self:setAnimationsRunning(running, false)
    end
end

-- -----------------------------------------------------------------------------
-- Automatic pond collection (server only)
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector:getPayoutFarmId()
    local farmId = self.placeable:getOwnerFarmId()
    if farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID then
        return farmId
    end
    -- sawmill not owned: in singleplayer pay the player's farm (same as manual selling)
    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return FarmManager.SINGLEPLAYER_FARM_ID
    end
    if not self.warnedFarm then
        self.warnedFarm = true
        logInfo("Multiplayer: sawmill is not owned by a farm, auto collection paused until it is bought.")
    end
    return nil
end

-- -----------------------------------------------------------------------------
-- Log lift (keyframe playback of the map's FS22 clip)
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector:hasLogLift()
    return #self.liftSlots > 0
end

function SawmillAnimationInjector:applyLiftPose(slot)
    local keys = self.config.logLift.keys
    local t = slot.time
    local i = slot.keyIndex
    while i < #keys - 1 and keys[i + 1].t <= t do
        i = i + 1
    end
    slot.keyIndex = i

    local a = keys[i]
    local b = keys[i + 1]
    local alpha = 0
    if b.t > a.t then
        alpha = math.max(0, math.min(1, (t - a.t) / (b.t - a.t)))
    end

    setTranslation(slot.node, a.x + (b.x - a.x) * alpha, a.y + (b.y - a.y) * alpha, a.z + (b.z - a.z) * alpha)
    setRotation(slot.node, a.rx + (b.rx - a.rx) * alpha, a.ry + (b.ry - a.ry) * alpha, a.rz + (b.rz - a.rz) * alpha)
end

function SawmillAnimationInjector:startLiftLog()
    for _, slot in ipairs(self.liftSlots) do
        if not slot.active then
            slot.active = true
            slot.time = 0
            slot.keyIndex = 1
            self:applyLiftPose(slot)
            setVisibility(slot.node, true)
            return true
        end
    end
    return false
end

-- a new log may start when a model is free and the last started log has
-- travelled far enough (map value waitThresholdAnimTime)
function SawmillAnimationInjector:getCanStartLiftLog()
    local hasFree = false
    for _, slot in ipairs(self.liftSlots) do
        if not slot.active then
            hasFree = true
        elseif slot.time < self.config.logLift.waitThreshold then
            return false
        end
    end
    return hasFree
end

function SawmillAnimationInjector:updateLogLift(dt)
    local lift = self.config.logLift
    for _, slot in ipairs(self.liftSlots) do
        if slot.active then
            slot.time = slot.time + dt * lift.speedScale
            if slot.time >= lift.duration then
                slot.active = false
                setVisibility(slot.node, false)
            else
                self:applyLiftPose(slot)
            end
        end
    end
end

-- -----------------------------------------------------------------------------
-- Automatic pond collection (server only)
-- -----------------------------------------------------------------------------

-- sells exactly one log of the trigger; returns true if it was sold
function SawmillAnimationInjector:processSingleLog(trigger, farmId)
    local allLogs = trigger.woodInTrigger
    local nodeId = nil
    for id, _ in pairs(allLogs) do
        if entityExists(id) then
            nodeId = id
            break
        end
        allLogs[id] = nil
    end
    if nodeId == nil then
        return false
    end

    local single = {[nodeId] = nodeId}
    trigger.woodInTrigger = single
    trigger:processWood(farmId)
    trigger.woodInTrigger = allLogs

    -- anything that was added to the temporary table during the call goes back
    for id, value in pairs(single) do
        allLogs[id] = value
    end

    if not entityExists(nodeId) then
        allLogs[nodeId] = nil
        return true
    end
    return false
end

function SawmillAnimationInjector:updateAutoCollect(dt)
    local trigger = self.woodTrigger
    if trigger == nil or not self.config.autoCollect then
        return
    end
    if not g_currentMission:getIsServer() then
        return
    end
    -- processWood updates the local player's farm stats; skip if there is none
    if g_localPlayer == nil then
        return
    end

    self.collectTimer = self.collectTimer - dt
    if self.collectTimer > 0 then
        return
    end

    if next(trigger.woodInTrigger) == nil then
        self.collectTimer = self.config.intervalMs
        return
    end

    if self:hasLogLift() then
        -- one log after the other, paced by the lift animation
        if not self:getCanStartLiftLog() then
            return
        end
        local farmId = self:getPayoutFarmId()
        if farmId == nil then
            self.collectTimer = self.config.intervalMs
            return
        end
        if self:processSingleLog(trigger, farmId) then
            self:startLiftLog()
        else
            -- storage full or log gone, try again later
            self.collectTimer = self.config.intervalMs
        end
        return
    end

    self.collectTimer = self.config.intervalMs
    local farmId = self:getPayoutFarmId()
    if farmId == nil then
        return
    end
    trigger:processWood(farmId)
end

-- -----------------------------------------------------------------------------
-- Wood chipper (yellow crusher next to the pond)
-- -----------------------------------------------------------------------------

function SawmillAnimationInjector.getText(key, fallback)
    local env = g_i18n.modEnvironments ~= nil and g_i18n.modEnvironments[SawmillAnimationInjector.MOD_NAME] or nil
    local text
    if env ~= nil then
        text = env:getText(key)
    else
        text = g_i18n:getText(key)
    end
    if text == nil or text == "" or string.find(text, "Missing", 1, true) == 1 then
        return fallback
    end
    return text
end

function SawmillAnimationInjector:setupChipper(unloadingStation)
    local cfg = self.config.chipper
    self.chipperTrigger = nil
    if cfg.mode ~= "chips" or unloadingStation == nil or type(unloadingStation.unloadTriggers) ~= "table" then
        return
    end
    if FillType == nil or FillType.WOODCHIPS == nil or self.productionPoint.storage == nil then
        logWarning("Chipper: WOODCHIPS or sawmill storage not available, chipper unchanged.")
        return
    end

    local trigger = nil
    for _, t in ipairs(unloadingStation.unloadTriggers) do
        if t.woodInTrigger ~= nil and t.processWood ~= nil and t.triggerNode ~= nil and t.triggerNode ~= 0
            and getName(t.triggerNode) == cfg.triggerNodeName then
            trigger = t
            break
        end
    end
    if trigger == nil then
        logWarning("Chipper trigger '%s' not found, chipper unchanged.", cfg.triggerNodeName)
        return
    end

    -- instance override: the client keeps the original behaviour (it sends the event to the
    -- server), the server chips instead of selling. Manual activation and the network event
    -- both end up here.
    local injector = self
    local original = trigger.processWood
    self.chipperOriginalProcess = original
    trigger.processWood = function(trig, farmId, noEventSend)
        if not trig.isServer or injector.chipperTrigger ~= trig then
            return original(trig, farmId, noEventSend)
        end
        injector:chipWood(trig, farmId)
    end

    if trigger.activatable ~= nil then
        self.chipperOriginalText = trigger.activatable.activateText
        trigger.activatable.activateText = SawmillAnimationInjector.getText("silverrun_action_chipWood", "Chip wood")
    end

    self.chipperTrigger = trigger
end

function SawmillAnimationInjector:restoreChipper()
    local trigger = self.chipperTrigger
    if trigger ~= nil then
        if self.chipperOriginalProcess ~= nil then
            trigger.processWood = self.chipperOriginalProcess
        end
        if trigger.activatable ~= nil and self.chipperOriginalText ~= nil then
            trigger.activatable.activateText = self.chipperOriginalText
        end
    end
    self.chipperTrigger = nil
    self.chipperOriginalProcess = nil
    self.chipperOriginalText = nil
end

-- server: every log in the chipper becomes woodchips in the sawmill storage
function SawmillAnimationInjector:chipWood(trigger, farmId)
    local storage = self.productionPoint ~= nil and self.productionPoint.storage or nil
    if storage == nil then
        return
    end
    local fillType = FillType.WOODCHIPS
    local mission = g_currentMission
    local scale = self.config.chipper.chipsScale
    local totalChips, numLogs = 0, 0

    for nodeId, _ in pairs(trigger.woodInTrigger) do
        if entityExists(nodeId) and getHasClassId(nodeId, ClassIds.MESH_SPLIT_SHAPE) then
            local splitType = g_splitShapeManager:getSplitTypeByIndex(getSplitType(nodeId))
            local liters = getVolume(nodeId) * ((splitType ~= nil and splitType.volumeToLiter) or 1000)
            local perLiter = splitType ~= nil and splitType.woodChipsPerLiter or 1
            if perLiter == nil or perLiter <= 0 then
                perLiter = 1
            end
            local chips = liters * perLiter * scale

            local free = storage:getFreeCapacity(fillType)
            if free == nil or free < chips * 0.9 then
                break -- chip storage full, the log stays in the chipper
            end
            storage:setFillLevel(storage:getFillLevel(fillType) + math.min(chips, free), fillType)
            totalChips = totalChips + chips
            numLogs = numLogs + 1

            local treeObject = mission:getNodeObject(nodeId)
            if treeObject ~= nil then
                treeObject:delete()
            else
                delete(nodeId)
            end
            trigger.woodInTrigger[nodeId] = nil
        else
            trigger.woodInTrigger[nodeId] = nil
        end
    end

    if numLogs > 0 then
        logInfo("Chipper: %d log(s) -> %.0f l woodchips.", numLogs, totalChips)
    end
end

function SawmillAnimationInjector:updateAutoChip(dt)
    local trigger = self.chipperTrigger
    if trigger == nil or not self.config.chipper.autoChip or not g_currentMission:getIsServer() then
        return
    end
    self.chipTimer = self.chipTimer - dt
    if self.chipTimer > 0 then
        return
    end
    self.chipTimer = self.config.chipper.intervalMs
    if next(trigger.woodInTrigger) == nil then
        return
    end
    self:chipWood(trigger, self.placeable:getOwnerFarmId())
end

addModEventListener(SawmillAnimationInjector)
