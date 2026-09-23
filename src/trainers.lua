return function(mod, ctx)
  -- Reputation --------------------------------------------------------------
  local function reputation()
    local rep = ctx.getTable("reputation")
    rep.facets = type(rep.facets) == "table" and rep.facets or {}
    rep.history = type(rep.history) == "table" and rep.history or {}
    return rep
  end

  function ctx.reputation()
    return reputation()
  end

  function ctx.bumpReputation(field, amount)
    local rep = reputation()
    rep[field] = (tonumber(rep[field]) or 0) + (amount or 1)
    ctx.putTable("reputation", rep)
    return rep[field]
  end

  function ctx.adjustReputationFacet(facet, amount, source)
    local rep = reputation()
    facet = tostring(facet or "general")
    rep.facets[facet] = ctx.clamp((tonumber(rep.facets[facet]) or 0) + (tonumber(amount) or 0), -100, 100)
    rep.history[#rep.history + 1] = {
      facet = facet, amount = tonumber(amount) or 0, source = source or "unknown",
      step = ctx.runtime.steps, mapId = ctx.runtime.currentMap,
    }
    while #rep.history > 20 do table.remove(rep.history, 1) end
    ctx.putTable("reputation", rep)
    return rep.facets[facet]
  end

  function ctx.reputationFacet(facet)
    return tonumber(reputation().facets[tostring(facet)]) or 0
  end

  -- Community/NPC memory is intentionally fact-based rather than a single
  -- reputation score. Content can publish witnessed facts and NPCs can inherit
  -- them later with reduced confidence.
  function ctx.publishCommunityMemory(mapId, fact)
    if not mapId or type(fact) ~= "table" then return nil end
    local all = ctx.getTable("community_memories")
    local rows = type(all[mapId]) == "table" and all[mapId] or {}
    local entry = ctx.cloneTable(fact)
    entry.id = entry.id or ("FACT_" .. tostring(ctx.nextRandom(999999, "memory")))
    entry.step = entry.step or ctx.runtime.steps
    entry.confidence = ctx.clamp(tonumber(entry.confidence) or 1, 0, 1)
    rows[#rows + 1] = entry
    while #rows > 16 do table.remove(rows, 1) end
    all[mapId] = rows
    ctx.putTable("community_memories", all)
    return entry
  end

  function ctx.rememberNpc(npcId, fact)
    if not npcId or type(fact) ~= "table" then return nil end
    local all = ctx.getTable("npc_memories")
    local rows = type(all[npcId]) == "table" and all[npcId] or {}
    local entry = ctx.cloneTable(fact)
    entry.step = entry.step or ctx.runtime.steps
    rows[#rows + 1] = entry
    while #rows > 12 do table.remove(rows, 1) end
    all[npcId] = rows
    ctx.putTable("npc_memories", all)
    return entry
  end

  function ctx.npcMemories(npcId)
    return ctx.getTable("npc_memories")[npcId] or {}
  end

  -- Trainer memory / grudges / archaeology ---------------------------------
  local function normalizeTrainerRecord(rec)
    rec = type(rec) == "table" and rec or {}
    rec.engagements = tonumber(rec.engagements) or 0
    rec.battles = tonumber(rec.battles) or 0
    rec.resentment = tonumber(rec.resentment) or 0
    rec.respect = tonumber(rec.respect) or 0
    rec.embarrassment = tonumber(rec.embarrassment) or 0
    rec.confidence = tonumber(rec.confidence) or 0
    rec.history = type(rec.history) == "table" and rec.history or {}
    return rec
  end

  function ctx.trainerMemory(npcId)
    if not npcId then return nil end
    local all = ctx.getTable("trainer_memory")
    local rec = normalizeTrainerRecord(all[npcId])
    all[npcId] = rec
    ctx.putTable("trainer_memory", all)
    return rec, all
  end

  local function decayTrainerMemory(rec)
    local last = tonumber(rec.lastMemoryStep) or ctx.runtime.steps
    local elapsed = math.max(0, ctx.runtime.steps - last)
    if elapsed < 512 then return rec end
    local resentmentDecay = math.floor(elapsed / 1024)
    local embarrassmentDecay = math.floor(elapsed / 768)
    rec.resentment = math.max(0, (tonumber(rec.resentment) or 0) - resentmentDecay)
    rec.embarrassment = math.max(0, (tonumber(rec.embarrassment) or 0) - embarrassmentDecay)
    if rec.confidence > 0 then rec.confidence = math.max(0, rec.confidence - math.floor(elapsed / 1536)) end
    if rec.confidence < 0 then rec.confidence = math.min(0, rec.confidence + math.floor(elapsed / 1536)) end
    rec.lastMemoryStep = ctx.runtime.steps
    return rec
  end

  function ctx.grudgeState(npcId)
    local rec = ctx.trainerMemory(npcId)
    if not rec then return { score = 0, tier = 0, respectTier = 0 } end
    decayTrainerMemory(rec)
    local score = math.max(0,
      (tonumber(rec.resentment) or 0)
      + (tonumber(rec.embarrassment) or 0) * 0.5
      - (tonumber(rec.respect) or 0) * 0.20)
    local tier = 0
    if score >= 3 then tier = 1 end
    if score >= 7 then tier = 2 end
    if score >= 12 then tier = 3 end
    if score >= 20 then tier = 4 end
    local respect = tonumber(rec.respect) or 0
    local respectTier = respect >= 12 and 3 or (respect >= 6 and 2 or (respect >= 3 and 1 or 0))
    return { score = score, tier = tier, respectTier = respectTier, record = rec }
  end

  function ctx.trainerArc(npcId)
    if not npcId then return nil end
    local arcs = ctx.getTable("trainer_arcs")
    local rec = arcs[npcId]
    if type(rec) ~= "table" then
      rec = { stage = 0, encounters = 0, snapshots = {} }
      arcs[npcId] = rec
      ctx.putTable("trainer_arcs", arcs)
    end
    rec.snapshots = type(rec.snapshots) == "table" and rec.snapshots or {}
    return rec, arcs
  end

  local function addTrainerSnapshot(npcId, snapshot)
    if not npcId then return end
    local arc, arcs = ctx.trainerArc(npcId)
    arc.snapshots[#arc.snapshots + 1] = snapshot
    while #arc.snapshots > 16 do table.remove(arc.snapshots, 1) end
    arc.firstMap = arc.firstMap or snapshot.mapId
    arc.lastMap = snapshot.mapId or arc.lastMap
    arcs[npcId] = arc
    ctx.putTable("trainer_arcs", arcs)
  end

  -- Rocket Heat -------------------------------------------------------------
  local function heatState()
    local state = mod.save:get("rocket_heat_state", {})
    if type(state) ~= "table" then state = {} end
    if state.value == nil then state.value = tonumber(mod.save:get("rocket_heat", 0)) or 0 end
    state.value = math.max(0, tonumber(state.value) or 0)
    state.lastStep = tonumber(state.lastStep) or ctx.runtime.steps
    state.regional = type(state.regional) == "table" and state.regional or {}
    state.history = type(state.history) == "table" and state.history or {}
    return state
  end

  local function decayHeat(state)
    local elapsed = math.max(0, ctx.runtime.steps - (tonumber(state.lastStep) or ctx.runtime.steps))
    if elapsed >= 384 then
      local decay = math.floor(elapsed / 384)
      state.value = math.max(0, state.value - decay)
      for mapId, value in pairs(state.regional) do
        state.regional[mapId] = math.max(0, (tonumber(value) or 0) - math.floor(elapsed / 256))
      end
      state.lastStep = ctx.runtime.steps
    end
    return state
  end

  local function saveHeat(state)
    mod.save:set("rocket_heat_state", state)
    mod.save:set("rocket_heat", math.floor((tonumber(state.value) or 0) + 0.5))
    return state
  end

  function ctx.getHeat(mapId)
    local state = decayHeat(heatState())
    saveHeat(state)
    if mapId then return tonumber(state.regional[mapId]) or 0 end
    return state.value
  end

  function ctx.rocketHeatTier(mapId)
    local value = ctx.getHeat(mapId)
    if value >= 25 then return "HUNTED", 4 end
    if value >= 15 then return "WANTED", 3 end
    if value >= 8 then return "WATCHED", 2 end
    if value >= 3 then return "NOTICED", 1 end
    return "COLD", 0
  end

  function ctx.addHeat(amount, source, mapId)
    if not ctx.feature("rocket_heat") then return ctx.getHeat() end
    local state = decayHeat(heatState())
    amount = tonumber(amount) or 1
    state.value = ctx.clamp(state.value + amount, 0, 100)
    mapId = mapId or ctx.runtime.currentMap
    if mapId then state.regional[mapId] = ctx.clamp((tonumber(state.regional[mapId]) or 0) + amount, 0, 100) end
    state.history[#state.history + 1] = {
      amount = amount, source = source or "unknown", mapId = mapId, step = ctx.runtime.steps,
    }
    while #state.history > 16 do table.remove(state.history, 1) end
    saveHeat(state)
    return state.value
  end

  -- Battle bet contracts ----------------------------------------------------
  function ctx.battleBet(npcId)
    return ctx.getTable("battle_bets")[npcId]
  end

  function ctx.createBattleBet(npcId, def)
    assert(type(npcId) == "string" and type(def) == "table")
    local bets = ctx.getTable("battle_bets")
    local bet = ctx.cloneTable(def)
    bet.id = bet.id or (npcId .. ":" .. tostring(ctx.runtime.steps))
    bet.npcId = npcId
    bet.state = bet.state or "PROPOSED"
    bet.createdAt = ctx.runtime.steps
    bet.settled = false
    bet.active = bet.state ~= "CANCELLED" and bet.state ~= "RESOLVED"
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  function ctx.acceptBattleBet(npcId)
    local bets = ctx.getTable("battle_bets")
    local bet = bets[npcId]
    if type(bet) ~= "table" then return nil, "no bet" end
    if bet.state ~= "PROPOSED" and bet.state ~= "ACCEPTED" then return nil, "bet not open" end
    bet.state = "ACCEPTED"
    bet.acceptedAt = bet.acceptedAt or ctx.runtime.steps
    bet.active = true
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  function ctx.cancelBattleBet(npcId, reason)
    local bets = ctx.getTable("battle_bets")
    local bet = bets[npcId]
    if type(bet) ~= "table" then return nil end
    if bet.state == "RESOLVED" then return bet end
    bet.state = "CANCELLED"
    bet.active = false
    bet.cancelledAt = ctx.runtime.steps
    bet.cancelReason = reason or "cancelled"
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  local function playerWon(result)
    local text = tostring(result or ""):lower()
    return text == "win" or text == "won" or text == "victory" or text:find("player_win", 1, true) ~= nil
  end

  local function playerLost(result)
    local text = tostring(result or ""):lower()
    return text == "loss" or text == "lost" or text == "lose" or text == "blackout"
      or text:find("player_loss", 1, true) ~= nil
  end

  function ctx.settleBattleBet(npcId, result, env)
    local bets = ctx.getTable("battle_bets")
    local bet = bets[npcId]
    if type(bet) ~= "table" then return nil, "no bet" end
    if bet.settled or bet.state == "RESOLVED" then return bet end
    if bet.state ~= "IN_BATTLE" and bet.state ~= "ACCEPTED" then return nil, "bet not active" end

    bet.result = result
    bet.finishedAt = ctx.runtime.steps
    bet.state = "RESOLVED"
    bet.active = false
    bet.settled = true
    local effects
    if playerWon(result) then effects = bet.onWin or bet.winEffects
    elseif playerLost(result) then effects = bet.onLoss or bet.lossEffects
    else effects = bet.onOther or bet.otherEffects end

    local effectEnv = type(env) == "table" and env or {}
    effectEnv.bet = bet
    effectEnv.npcId = npcId
    local ok, err = ctx.runEffects(effects, effectEnv)
    bet.settlementStatus = ok and "APPLIED" or "FAILED"
    bet.settlementError = ok and nil or tostring(err)
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  -- Trainer hooks -----------------------------------------------------------
  mod.hooks:wrap("trainer.party", function(next, trainerClass, partyIndex, party)
    local base = next(trainerClass, partyIndex, party)
    if not ctx.feature() or type(base) ~= "table" then return base end

    local bonus = ctx.hasMutation("HARDENED_TRAINERS") and 1 or 0
    if ctx.feature("trainer_memory") and ctx.runtime.currentTrainerNpc then
      local grudge = ctx.grudgeState(ctx.runtime.currentTrainerNpc)
      if grudge.tier >= 2 then bonus = bonus + 1 end
      if grudge.tier >= 4 then bonus = bonus + 1 end
    end
    bonus = ctx.clamp(bonus, 0, 3)
    if bonus <= 0 then return base end

    local out = ctx.cloneArray(base)
    for _, mon in ipairs(out) do
      if type(mon) == "table" and mon.level then
        mon.level = ctx.clamp((tonumber(mon.level) or 1) + bonus, 1, 100)
      end
    end
    return out
  end)

  mod.hooks:wrap("trainer.before_battle", function(next, game, context, continue)
    if not ctx.feature() or type(context) ~= "table" or not context.npcId then return next() end
    local bet = ctx.battleBet(context.npcId)
    if type(bet) ~= "table" or bet.active == false or bet.state ~= "ACCEPTED" then return next() end

    bet.state = "IN_BATTLE"
    bet.startedAt = ctx.runtime.steps
    local bets = ctx.getTable("battle_bets")
    bets[context.npcId] = bet
    ctx.putTable("battle_bets", bets)

    if type(bet.playerPartyIndices) == "table" and #bet.playerPartyIndices > 0 then
      continue({ playerPartyIndices = bet.playerPartyIndices })
      return true
    end
    return next()
  end)

  mod.events:on("world.trainer_engaged", function(ev)
    local npcId = ev.npc and ev.npc.id
    ctx.runtime.currentTrainerNpc = npcId
    ctx.runtime.currentTrainerClass = ev.trainerClass
    ctx.runtime.currentTrainerParty = ev.partyIndex

    if ctx.feature("trainer_memory") and npcId then
      local rec, all = ctx.trainerMemory(npcId)
      decayTrainerMemory(rec)
      rec.engagements = rec.engagements + 1
      rec.trainerClass = ev.trainerClass
      rec.partyIndex = ev.partyIndex
      rec.lastMap = ctx.runtime.currentMap
      rec.lastMemoryStep = ctx.runtime.steps
      all[npcId] = rec
      ctx.putTable("trainer_memory", all)

      local arc, arcs = ctx.trainerArc(npcId)
      arc.encounters = (tonumber(arc.encounters) or 0) + 1
      arc.firstMap = arc.firstMap or ctx.runtime.currentMap
      arc.lastMap = ctx.runtime.currentMap
      arcs[npcId] = arc
      ctx.putTable("trainer_arcs", arcs)
      addTrainerSnapshot(npcId, {
        kind = "ENGAGED", step = ctx.runtime.steps, mapId = ctx.runtime.currentMap,
        trainerClass = ev.trainerClass, partyIndex = ev.partyIndex,
      })
    end

    local classes = ctx.getTable("trainer_class_counts")
    local classKey = tostring(ev.trainerClass or "UNKNOWN")
    classes[classKey] = (classes[classKey] or 0) + 1
    ctx.putTable("trainer_class_counts", classes)

    if ctx.feature("rocket_heat") and ctx.containsText(classKey, "ROCKET") then
      ctx.addHeat(ctx.hasMutation("ROCKET_NERVES") and 3 or 2, "rocket_engagement", ctx.runtime.currentMap)
    end
  end)

  mod.events:on("battle.started", function(ev)
    ctx.bumpReputation("battles", 1)
    local token = "B" .. tostring(ctx.runtime.steps) .. ":" .. tostring(ctx.nextRandom(9999, "battle_ids"))
    ctx.runtime.battle = {
      id = token,
      kind = ev.kind,
      trainerId = ev.trainerId,
      trainerNpc = ctx.runtime.currentTrainerNpc,
      trainerClass = ctx.runtime.currentTrainerClass,
      turns = 0,
      anomaly = ctx.runtime.lastWildAnomaly,
    }
    ctx.runtime.lastWildAnomaly = nil

    local npcId = ctx.runtime.currentTrainerNpc
    local bet = npcId and ctx.battleBet(npcId) or nil
    if bet and bet.state == "IN_BATTLE" then
      bet.battleId = token
      local bets = ctx.getTable("battle_bets")
      bets[npcId] = bet
      ctx.putTable("battle_bets", bets)
    end
  end)

  mod.events:on("battle.turn_ended", function()
    if ctx.runtime.battle then ctx.runtime.battle.turns = (ctx.runtime.battle.turns or 0) + 1 end
  end)

  mod.events:on("battle.ended", function(ev)
    local battle = ctx.runtime.battle
    if battle and battle.trainerNpc and ctx.feature("trainer_memory") then
      local npcId = battle.trainerNpc
      local rec, all = ctx.trainerMemory(npcId)
      rec.battles = rec.battles + 1
      rec.lastResult = ev.result
      rec.lastTurns = battle.turns
      rec.lastMemoryStep = ctx.runtime.steps

      if playerWon(ev.result) then
        rec.resentment = rec.resentment + 1
        rec.respect = rec.respect + 1
        rec.confidence = rec.confidence - 1
        if (tonumber(battle.turns) or 99) <= 3 then rec.embarrassment = rec.embarrassment + 2 end
      elseif playerLost(ev.result) then
        rec.confidence = rec.confidence + 2
        rec.resentment = math.max(0, rec.resentment - 1)
        rec.respect = rec.respect + 0.5
      end

      rec.history[#rec.history + 1] = {
        step = ctx.runtime.steps, mapId = ctx.runtime.currentMap,
        result = ev.result, turns = battle.turns,
        resentment = rec.resentment, respect = rec.respect,
        embarrassment = rec.embarrassment, confidence = rec.confidence,
      }
      while #rec.history > 12 do table.remove(rec.history, 1) end
      all[npcId] = rec
      ctx.putTable("trainer_memory", all)

      addTrainerSnapshot(npcId, {
        kind = "BATTLE", step = ctx.runtime.steps, mapId = ctx.runtime.currentMap,
        trainerClass = battle.trainerClass, result = ev.result, turns = battle.turns,
      })

      ctx.settleBattleBet(npcId, ev.result, { battle = battle, event = ev })
    end

    if battle and battle.anomaly then mod.save:set("last_anomaly", battle.anomaly) end

    if playerWon(ev.result) then
      ctx.adjustReputationFacet("competence", 0.5, "battle_win")
      ctx.adjustMoodPressure(1, "battle_win")
    elseif playerLost(ev.result) then
      ctx.adjustReputationFacet("competence", -0.25, "battle_loss")
      ctx.adjustMoodPressure(-2, "battle_loss")
    end

    ctx.runtime.battle = nil
    ctx.runtime.currentTrainerNpc = nil
    ctx.runtime.currentTrainerClass = nil
    ctx.runtime.currentTrainerParty = nil
  end)
end
