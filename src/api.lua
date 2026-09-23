return function(mod, ctx)
  mod.exports = {
    api = 2,

    status = function(game)
      local heatTier = ctx.rocketHeatTier()
      return {
        schema = ctx.CURRENT_SCHEMA,
        seed = ctx.runSeed(),
        mapId = ctx.runtime.currentMap,
        steps = ctx.runtime.steps,
        mood = ctx.worldMood(),
        moodState = ctx.worldMoodState(),
        tod = ctx.currentTod(),
        hour = ctx.currentHour(),
        rocketHeat = ctx.getHeat(),
        rocketHeatTier = heatTier,
        rumor = ctx.currentRumor(),
        rumors = ctx.activeRumors(),
        tip = mod.save:get("current_tip"),
        bulletin = mod.save:get("current_bulletin"),
        mutations = ctx.ensureRunMutations(),
        reputation = ctx.reputation(),
        superstition = ctx.superstition(game or ctx.runtime.game),
        observation = ctx.playerObservation(),
        observations = ctx.playerObservations(),
        exhibits = ctx.exhibitCount(),
        director = ctx.directorStatus(),
      }
    end,

    time = {
      hour = function() return ctx.currentHour() end,
      period = function() return ctx.currentTod() end,
      fraction = function()
        local hour = ctx.currentHour()
        return hour and (hour % 24) / 24 or nil
      end,
      source = function()
        if mod.generation ~= 1 then return "NATIVE" end
        return mod.options:get("night_time_source") or "REAL_TIME"
      end,
      inRange = function(startHour, endHour) return ctx.timeInRange(startHour, endHour) end,
    },

    rng = {
      seed = function() return ctx.runSeed() end,
      next = function(stream, max) return ctx.nextRandom(max, stream) end,
      chance = function(stream, percent) return ctx.chance(percent, stream) end,
    },

    pokemonId = function(mon) return ctx.ensureMonUid(mon) end,
    pokemonRecord = function(mon) return ctx.ensureMonRecord(mon) end,
    reconcilePokemonIdentity = function(game) return ctx.reconcilePokemonIdentity(game or ctx.runtime.game) end,
    awardPokemonTitle = function(mon, id, reason) return ctx.awardTitle(mon, id, reason) end,
    registerPokemonTitle = function(id, def) return ctx.registerTitle(id, def) end,
    relationship = function(a, b) return ctx.relationship(a, b) end,
    adjustRelationship = function(a, b, axis, amount, reason)
      return ctx.adjustRelationship(a, b, axis, amount, reason)
    end,
    registerPersonality = function(id, def) return ctx.registerPersonality(id, def) end,

    trainerMemory = function(npcId) return (ctx.trainerMemory(npcId)) end,
    grudgeState = function(npcId) return ctx.grudgeState(npcId) end,
    trainerArc = function(npcId) return (ctx.trainerArc(npcId)) end,
    advanceTrainerArc = function(npcId, stage)
      local rec, arcs = ctx.trainerArc(npcId)
      if not rec then return nil end
      rec.stage = math.max(tonumber(rec.stage) or 0, tonumber(stage) or (rec.stage + 1))
      arcs[npcId] = rec
      ctx.putTable("trainer_arcs", arcs)
      return rec
    end,

    reputation = function() return ctx.reputation() end,
    reputationFacet = function(id) return ctx.reputationFacet(id) end,
    adjustReputationFacet = function(id, amount, source)
      return ctx.adjustReputationFacet(id, amount, source)
    end,
    publishCommunityMemory = function(mapId, fact) return ctx.publishCommunityMemory(mapId, fact) end,
    npcMemories = function(npcId) return ctx.npcMemories(npcId) end,

    registerRumor = function(def)
      assert(type(def) == "table", "rumor definition must be a table")
      ctx.rumorDefs[#ctx.rumorDefs + 1] = def
      return def.id
    end,
    activateRumor = function(id, opts)
      for _, def in ipairs(ctx.rumorDefs) do
        if def.id == id then return ctx.activateRumor(def, opts) end
      end
      return nil, "unknown rumor"
    end,
    activeRumors = function(mapId) return ctx.activeRumors(mapId) end,
    resolveRumor = function(id, resolution) return ctx.resolveRumor(id, resolution) end,

    registerDirectorEvent = function(def) return ctx.registerDirectorEvent(def) end,
    reserveDirectorEvent = function(id, constraints) return ctx.reserveDirectorEvent(id, constraints) end,
    suppressDirectorCategory = function(category, duration)
      return ctx.suppressDirectorCategory(category, duration)
    end,
    directorStatus = function() return ctx.directorStatus() end,

    registerEcologyRule = function(mapId, species, def)
      assert(type(mapId) == "string" and type(species) == "string" and type(def) == "table")
      ctx.ecologyRules[mapId] = ctx.ecologyRules[mapId] or {}
      ctx.ecologyRules[mapId][species] = def
      return def
    end,
    ecologyState = function(mapId, species) return ctx.ecologyState(mapId, species) end,
    ecologyPressure = function(mapId, species) return ctx.ecologyPressure(mapId, species) end,
    ecologyAbundance = function(mapId, species) return ctx.ecologyAbundance(mapId, species) end,
    recordEcologyEvent = function(mapId, species, kind, amount)
      return ctx.recordEcologyEvent(mapId, species, kind, amount)
    end,

    registerNightRule = function(mapId, species, def)
      assert(type(mapId) == "string" and type(species) == "string" and type(def) == "table")
      ctx.nightRules[mapId] = ctx.nightRules[mapId] or {}
      ctx.nightRules[mapId][species] = def
      return def
    end,

    registerAnomaly = function(id, def) return ctx.registerAnomaly(id, def) end,
    anomalyRate = function() return ctx.anomalyRate() end,

    registerBulletin = function(def)
      if type(def) == "string" then def = { text = def } end
      assert(type(def) == "table")
      ctx.bulletinDefs[#ctx.bulletinDefs + 1] = def
      return def.id
    end,
    postBulletin = function(boardId, def) return ctx.postBulletin(boardId, def) end,
    bulletins = function(boardId) return ctx.bulletins(boardId) end,

    issueAdvice = function(def) return ctx.issueAdvice(def) end,
    currentAdvice = function() return ctx.currentAdvice() end,
    disproveAdvice = function(id) return ctx.disproveAdvice(id) end,

    registerLegend = function(def) return ctx.registerLegend(def) end,
    activateLegend = function(id, stage, reason) return ctx.activateLegend(id, stage, reason) end,
    legendState = function(id) return ctx.legendState(id) end,
    addLegendClue = function(id, clueId, amount) return ctx.addLegendClue(id, clueId, amount) end,
    advanceLegend = function(id, trigger, env) return ctx.advanceLegend(id, trigger, env) end,
    resolveLegend = function(id, resolution) return ctx.resolveLegend(id, resolution) end,

    registerTraveler = function(def) return ctx.registerTraveler(def) end,
    travelerState = function(id) return ctx.travelerState(id) end,
    recordTravelerEncounter = function(id, outcome, details)
      return ctx.recordTravelerEncounter(id, outcome, details)
    end,

    unlockExhibit = function(id, meta) return ctx.unlockExhibit(id, meta) end,
    advanceExhibit = function(id, amount, meta) return ctx.advanceExhibit(id, amount, meta) end,
    exhibitState = function(id) return ctx.exhibitState(id) end,

    createBattleBet = function(npcId, def) return ctx.createBattleBet(npcId, def) end,
    acceptBattleBet = function(npcId) return ctx.acceptBattleBet(npcId) end,
    cancelBattleBet = function(npcId, reason) return ctx.cancelBattleBet(npcId, reason) end,
    battleBet = function(npcId) return ctx.battleBet(npcId) end,
    -- Compatibility with API 1: staging a bet meant it was already accepted.
    setBattleBet = function(npcId, def)
      ctx.createBattleBet(npcId, def)
      return ctx.acceptBattleBet(npcId)
    end,

    registerBoss = function(def) return ctx.registerBoss(def) end,
    recordBossResult = function(id, result) return ctx.recordBossResult(id, result) end,
    leagueState = function() return ctx.leagueState() end,
    startLeague = function() return ctx.startLeague() end,
    resetLeague = function(reason) return ctx.resetLeague(reason) end,

    registerCurse = function(def) return ctx.registerCurse(def) end,
    curseState = function(id) return ctx.curseState(id) end,
    touchCurse = function(action, id) return ctx.touchCurse(action, id) end,
    cleanseCurse = function(id, reason) return ctx.cleanseCurse(id, reason) end,

    rocketHeat = function(mapId) return ctx.getHeat(mapId) end,
    rocketHeatTier = function(mapId) return ctx.rocketHeatTier(mapId) end,
    addRocketHeat = function(amount, source, mapId) return ctx.addHeat(amount, source, mapId) end,

    registerObservation = function(def) return ctx.registerObservation(def) end,
    playerObservation = function() return ctx.playerObservation() end,
    playerObservations = function() return ctx.playerObservations() end,
    registerSuperstition = function(def) return ctx.registerSuperstition(def) end,
    superstition = function(game, context) return ctx.superstition(game or ctx.runtime.game, context) end,
    superstitions = function(game, context) return ctx.superstitions(game or ctx.runtime.game, context) end,

    registerMutation = function(id, def) return ctx.registerMutation(id, def) end,
    mutations = function() return ctx.ensureRunMutations() end,
    moodState = function() return ctx.worldMoodState() end,
    adjustMoodPressure = function(amount, source) return ctx.adjustMoodPressure(amount, source) end,

    registerCondition = function(id, fn) return ctx.registerCondition(id, fn) end,
    registerEffect = function(id, fn) return ctx.registerEffect(id, fn) end,
    checkCondition = function(spec, env) return ctx.checkCondition(spec, env) end,
    runEffects = function(specs, env) return ctx.runEffects(specs, env) end,
  }
end
