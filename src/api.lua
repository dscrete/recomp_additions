return function(mod, ctx)
  mod.exports = {
    api = 1,

    status = function(game)
      return {
        mapId = ctx.runtime.currentMap,
        steps = ctx.runtime.steps,
        mood = ctx.worldMood(),
        tod = ctx.currentTodFromSteps(),
        rocketHeat = ctx.getHeat(),
        rumor = ctx.currentRumor(),
        tip = mod.save:get("current_tip"),
        bulletin = mod.save:get("current_bulletin"),
        mutations = ctx.ensureRunMutations(),
        reputation = ctx.reputation(),
        superstition = ctx.superstition(game or ctx.runtime.game),
        observation = ctx.playerObservation(),
        exhibits = ctx.exhibitCount(),
      }
    end,

    pokemonRecord = function(mon) return ctx.ensureMonRecord(mon) end,
    awardPokemonTitle = function(mon, id) return ctx.awardTitle(mon, id) end,
    trainerMemory = function(npcId) return (ctx.trainerMemory(npcId)) end,

    registerRumor = function(def)
      assert(type(def) == "table", "rumor definition must be a table")
      ctx.rumorDefs[#ctx.rumorDefs + 1] = def
      return def.id
    end,
    activateRumor = function(id)
      for _, def in ipairs(ctx.rumorDefs) do
        if def.id == id then return ctx.activateRumor(def) end
      end
      return nil, "unknown rumor"
    end,

    registerDirectorEvent = function(def) return ctx.registerDirectorEvent(def) end,

    registerEcologyRule = function(mapId, species, def)
      assert(type(mapId) == "string" and type(species) == "string" and type(def) == "table")
      ctx.ecologyRules[mapId] = ctx.ecologyRules[mapId] or {}
      ctx.ecologyRules[mapId][species] = def
    end,
    ecologyPressure = function(mapId, species) return ctx.ecologyPressure(mapId, species) end,

    registerNightRule = function(mapId, species, def)
      assert(type(mapId) == "string" and type(species) == "string" and type(def) == "table")
      ctx.nightRules[mapId] = ctx.nightRules[mapId] or {}
      ctx.nightRules[mapId][species] = def
    end,

    registerBulletin = function(def)
      if type(def) == "string" then def = { text = def } end
      assert(type(def) == "table")
      ctx.bulletinDefs[#ctx.bulletinDefs + 1] = def
    end,

    registerLegend = function(def) return ctx.registerLegend(def) end,
    activateLegend = function(id, stage) return ctx.activateLegend(id, stage) end,

    registerTraveler = function(def) return ctx.registerTraveler(def) end,
    travelerState = function(id) return ctx.travelerState(id) end,

    unlockExhibit = function(id) return ctx.unlockExhibit(id) end,

    setBattleBet = function(npcId, def)
      assert(type(npcId) == "string" and type(def) == "table")
      local bets = ctx.getTable("battle_bets")
      def.active = def.active ~= false
      bets[npcId] = def
      ctx.putTable("battle_bets", bets)
    end,

    advanceTrainerArc = function(npcId, stage)
      local rec, arcs = ctx.trainerArc(npcId)
      if not rec then return nil end
      rec.stage = math.max(tonumber(rec.stage) or 0, tonumber(stage) or (rec.stage + 1))
      arcs[npcId] = rec
      ctx.putTable("trainer_arcs", arcs)
      return rec
    end,

    registerBoss = function(def) return ctx.registerBoss(def) end,
    recordBossResult = function(id, result) return ctx.recordBossResult(id, result) end,
    touchCurse = function(action) return ctx.touchCurse(action) end,
    rocketHeat = function() return ctx.getHeat() end,
    addRocketHeat = function(amount) return ctx.addHeat(amount) end,
    playerObservation = function() return ctx.playerObservation() end,
    superstition = function(game) return ctx.superstition(game or ctx.runtime.game) end,
  }
end
