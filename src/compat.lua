-- Inter-mod compatibility adapters.
--
-- Kanto Expansion owns semantic systems, not another mod's renderer/spawner.
-- Adapters therefore use the other mod's exported seams and restore them on
-- quit instead of patching files or replacing engine globals.
return function(mod, ctx)
  local BATTLE_ART_ID = "BATTLE_ART_VOXEL_FORK"
  local WILDS_ID = "overworld_wild_spawns"

  -- Battle Art --------------------------------------------------------------
  local battleInstalled, dayNight, originalHours, wrappedHours = false, nil, nil, nil

  local function installBattleArt()
    if battleInstalled or mod.generation ~= 1 then return battleInstalled end
    local other = mod.find(BATTLE_ART_ID)
    local exports = other and other.exports
    local lib = exports and exports.lib
    if type(lib) ~= "table" or type(lib.require) ~= "function" then return false end

    local ok, candidate = pcall(lib.require, "DayNight")
    if not ok or type(candidate) ~= "table" or type(candidate.hours) ~= "function" then return false end

    dayNight, originalHours = candidate, candidate.hours
    wrappedHours = function()
      if ctx.feature("night_cycle") then
        local hour = ctx.currentHour()
        if type(hour) == "number" then return hour % 24 end
      end
      return originalHours()
    end
    candidate.hours = wrappedHours
    battleInstalled = true
    mod.log:info("Battle Art SYNC clock is following Kanto Expansion time")
    return true
  end

  local function uninstallBattleArt()
    if battleInstalled and dayNight and originalHours and dayNight.hours == wrappedHours then
      dayNight.hours = originalHours
    end
    battleInstalled, dayNight, originalHours, wrappedHours = false, nil, nil, nil
  end

  -- Wilds of Kanto ----------------------------------------------------------
  -- Wilds chooses visible species directly from its encounter tables and then
  -- starts a battle with that species. That deliberately bypasses the engine's
  -- encounter.species hook, so route ecology/night/rumor/anomaly rules would
  -- otherwise differ between classic encounters and Pokemon visible on-map.
  local wildsInstalled = false
  local wildsPick, wildsWater, originalPick, wrappedPick
  local originalWaterPick, wrappedWaterPick
  local wildsLogic
  local originalTrySpawn, wrappedTrySpawn
  local originalTrySpawnWater, wrappedTrySpawnWater
  local originalStartBattle, wrappedStartBattle
  local currentSpawnContext

  local function applyExternalRule(out, mapId, ruleBook, ecology)
    local mapRules = ruleBook and ruleBook[mapId]
    if type(mapRules) ~= "table" then return out end
    local rule = mapRules[out.species]
    if type(rule) ~= "table" then return out end
    local chance = tonumber(rule.chance) or 25
    if ecology then
      local pressure = ctx.ecologyPressure(mapId, out.species)
      local threshold = tonumber(rule.threshold) or 0
      if pressure < threshold then return out end
      local cap = math.max(threshold + 1, tonumber(rule.cap) or 20)
      local scale = ctx.clamp((pressure - threshold) / math.max(1, cap - threshold), 0, 1)
      chance = chance * (0.5 + scale * 0.5)
    end
    if rule.condition and not ctx.checkCondition(rule.condition, {
      encounter = out, hook = { mapId = mapId, source = "WILDS" },
    }) then return out end
    if not ctx.chance(chance, "wilds_rules") then return out end
    out.species = rule.replacement or out.species
    if out.speciesId ~= nil then out.speciesId = out.species end
    return out
  end

  local function transformWildsEncounter(enc, kind)
    if not ctx.feature() or type(enc) ~= "table" then return enc end
    local mapId = wildsLogic and wildsLogic.activeMapId or ctx.runtime.currentMap
    if not mapId then return enc end
    local out = ctx.cloneTable(enc)

    if ctx.feature("rumors") then
      for _, rumor in ipairs(ctx.activeRumors(mapId)) do
        if rumor.replacementSpecies
          and (not rumor.mapId or rumor.mapId == mapId)
          and ctx.chance(tonumber(rumor.encounterChance) or 8, "wilds_rumors") then
          out.species = rumor.replacementSpecies
          if out.speciesId ~= nil then out.speciesId = out.species end
          break
        end
      end
    end

    if ctx.feature("night_cycle") and ctx.currentTod() == "NIGHT" then
      out = applyExternalRule(out, mapId, ctx.nightRules, false)
    end
    if ctx.feature("ecology") then out = applyExternalRule(out, mapId, ctx.ecologyRules, true) end

    if ctx.hasMutation("WILD_SURGE") then
      if out.level ~= nil then out.level = ctx.clamp((tonumber(out.level) or 1) + 1, 1, 100) end
      if out.levelMin ~= nil then out.levelMin = ctx.clamp((tonumber(out.levelMin) or 1) + 1, 1, 100) end
      if out.levelMax ~= nil then out.levelMax = ctx.clamp((tonumber(out.levelMax) or 1) + 1, 1, 100) end
    end

    -- Wilds picks visible Pokemon well before battle. Capture anomaly metadata
    -- on that particular spawn instead of leaving ctx.runtime.lastWildAnomaly
    -- global, which could otherwise be consumed by the wrong visible Pokemon.
    if currentSpawnContext then
      local beforeLevel = tonumber(out.level)
      local previous = ctx.runtime.lastWildAnomaly
      out = ctx.rollAnomaly(out, { mapId = mapId, kind = kind, source = "WILDS" })
      local rolled = ctx.runtime.lastWildAnomaly
      ctx.runtime.lastWildAnomaly = previous
      if rolled and rolled ~= previous then
        currentSpawnContext.anomaly = ctx.cloneTable(rolled)
        -- rollAnomaly counts immediate classic encounters. A visible anomaly is
        -- only counted when the player actually engages it.
        ctx.addCounter("wild_anomalies", -1)
      end
      local afterLevel = tonumber(out.level)
      if beforeLevel and afterLevel and afterLevel ~= beforeLevel then
        local delta = afterLevel - beforeLevel
        if out.levelMin ~= nil then out.levelMin = ctx.clamp((tonumber(out.levelMin) or 1) + delta, 1, 100) end
        if out.levelMax ~= nil then out.levelMax = ctx.clamp((tonumber(out.levelMax) or 1) + delta, 1, 100) end
      end
    end

    if out.speciesId ~= nil then out.speciesId = out.species end
    return out
  end

  local function finishSpawn(record, entity, spawnContext)
    if type(record) == "table" and spawnContext and spawnContext.anomaly then
      record._kxAnomaly = spawnContext.anomaly
      if type(entity) == "table" then entity._kxAnomaly = spawnContext.anomaly end
    end
  end

  local function installWilds()
    if wildsInstalled or mod.generation ~= 1 then return wildsInstalled end
    local other = mod.find(WILDS_ID)
    local exports = other and other.exports
    local lib = exports and exports.lib
    if type(lib) ~= "table" or type(lib.require) ~= "function" then return false end

    local okPick, picker = pcall(lib.require, "encounter_pick")
    if not okPick or type(picker) ~= "table" or type(picker.pick) ~= "function" then return false end
    local okWater, water = pcall(lib.require, "water_spawn")
    if not okWater or type(water) ~= "table" then water = nil end

    wildsLogic = exports.logic
    if type(wildsLogic) ~= "table" then return false end

    wildsPick, originalPick = picker, picker.pick
    wrappedPick = function(encDef, rng, kind)
      return transformWildsEncounter(originalPick(encDef, rng, kind), kind or "grass")
    end
    picker.pick = wrappedPick

    if water and type(water.pickForZone) == "function" then
      wildsWater, originalWaterPick = water, water.pickForZone
      wrappedWaterPick = function(zonePools, zone, opts)
        return transformWildsEncounter(originalWaterPick(zonePools, zone, opts), "water")
      end
      water.pickForZone = wrappedWaterPick
    end

    if type(wildsLogic.trySpawn) == "function" then
      originalTrySpawn = wildsLogic.trySpawn
      wrappedTrySpawn = function(self, game, opts)
        local previous = currentSpawnContext
        local spawnContext = {}
        currentSpawnContext = spawnContext
        local record, err, entity = originalTrySpawn(self, game, opts)
        currentSpawnContext = previous
        finishSpawn(record, entity, spawnContext)
        return record, err, entity
      end
      wildsLogic.trySpawn = wrappedTrySpawn
    end

    if type(wildsLogic.trySpawnWater) == "function" then
      originalTrySpawnWater = wildsLogic.trySpawnWater
      wrappedTrySpawnWater = function(self, game, opts)
        local previous = currentSpawnContext
        local spawnContext = {}
        currentSpawnContext = spawnContext
        local record, err, entity = originalTrySpawnWater(self, game, opts)
        currentSpawnContext = previous
        finishSpawn(record, entity, spawnContext)
        return record, err, entity
      end
      wildsLogic.trySpawnWater = wrappedTrySpawnWater
    end

    if type(wildsLogic._startBattle) == "function" then
      originalStartBattle = wildsLogic._startBattle
      wrappedStartBattle = function(self, record)
        local previous = ctx.runtime.lastWildAnomaly
        local anomaly = type(record) == "table" and record._kxAnomaly or nil
        ctx.runtime.lastWildAnomaly = anomaly
        if anomaly then ctx.addCounter("wild_anomalies", 1) end
        local result = originalStartBattle(self, record)
        if result == false then
          if anomaly then ctx.addCounter("wild_anomalies", -1) end
          ctx.runtime.lastWildAnomaly = previous
        end
        return result
      end
      wildsLogic._startBattle = wrappedStartBattle
    end

    wildsInstalled = true
    mod.log:info("Wilds of Kanto visible encounters are using Kanto Expansion arbitration")
    return true
  end

  local function uninstallWilds()
    if wildsPick and originalPick and wildsPick.pick == wrappedPick then wildsPick.pick = originalPick end
    if wildsWater and originalWaterPick and wildsWater.pickForZone == wrappedWaterPick then
      wildsWater.pickForZone = originalWaterPick
    end
    if wildsLogic and originalTrySpawn and wildsLogic.trySpawn == wrappedTrySpawn then
      wildsLogic.trySpawn = originalTrySpawn
    end
    if wildsLogic and originalTrySpawnWater and wildsLogic.trySpawnWater == wrappedTrySpawnWater then
      wildsLogic.trySpawnWater = originalTrySpawnWater
    end
    if wildsLogic and originalStartBattle and wildsLogic._startBattle == wrappedStartBattle then
      wildsLogic._startBattle = originalStartBattle
    end
    wildsInstalled = false
    wildsPick, wildsWater, originalPick, wrappedPick = nil, nil, nil, nil
    originalWaterPick, wrappedWaterPick = nil, nil
    originalTrySpawn, wrappedTrySpawn = nil, nil
    originalTrySpawnWater, wrappedTrySpawnWater = nil, nil
    originalStartBattle, wrappedStartBattle = nil, nil
    wildsLogic, currentSpawnContext = nil, nil
  end

  -- optional_dependencies guarantees supported peers load first when present.
  -- mods.loaded keeps the adapters resilient to future priority changes.
  installBattleArt()
  installWilds()
  mod.events:on("mods.loaded", function()
    installBattleArt()
    installWilds()
  end)

  mod.hooks:wrap("core.quit_to_launcher", function(next, ...)
    uninstallWilds()
    uninstallBattleArt()
    return next(...)
  end)
end
