-- Final system-level contracts that sit above the feature modules.
--
-- This module deliberately contains no authored route/NPC/story content. It
-- hardens extension semantics that multiple future content packs need: readable
-- personality state, condition-only achievements, composable anomaly traits,
-- recoverable battle-bet settlement, curse stage effects, community-memory
-- propagation, and generic Bootleg League queries.
return function(mod, ctx)
  -- Pokemon personalities ---------------------------------------------------
  -- Existing battle/world events already feed personalitySignal(). Definitions
  -- convert those raw observations into a read-only expression score/tier. No
  -- personality changes battle math; content decides how/where to express it.
  local personalityProfiles = {
    BRAVE = {
      KO = 2.0, SWITCHED_IN = 1.0, FAINTED = 0.5, BATTLE_FINISHED = 0.5,
    },
    CAUTIOUS = {
      FAINTED = 2.0, SWITCHED_IN = 0.5, BATTLE_FINISHED = 0.5,
    },
    ["SHOW-OFF"] = {
      CRITICAL_HIT = 2.5, KO = 1.5, LEVEL_UP = 0.5,
    },
    CURIOUS = {
      MOVE_USED = 0.08, MAP_VISIT = 0.6, EVOLVED = 2.0, LEVEL_UP = 0.4,
    },
    STUBBORN = {
      MOVE_USED = 0.12, FAINTED = 1.5, KO = 0.8,
    },
    LUCKY = {
      CRITICAL_HIT = 2.0, KO = 0.6, LEVEL_UP = 0.4,
    },
    SLEEPY = {
      BATTLE_FINISHED = 0.8, LEVEL_UP = 0.3, FAINTED = 0.5,
    },
    MISCHIEVOUS = {
      CRITICAL_HIT = 1.5, KO = 1.2, SWITCHED_IN = 0.4,
    },
    LOYAL = {
      SWITCHED_IN = 1.5, BATTLE_FINISHED = 1.0, MAP_VISIT = 0.25,
    },
    DRAMATIC = {
      CRITICAL_HIT = 2.0, FAINTED = 2.0, KO = 1.0, EVOLVED = 2.0,
    },
  }

  for id, weights in pairs(personalityProfiles) do
    ctx.registerPersonality(id, {
      signalWeights = weights,
      thresholds = { 3, 8, 16 },
    })
  end

  function ctx.personalityExpression(mon)
    local rec = ctx.ensureMonRecord(mon)
    if not rec or not rec.personality then return nil end
    local def = ctx.personalityDefs[rec.personality] or {}
    local weights = type(def.signalWeights) == "table" and def.signalWeights or {}
    local score, dominantSignal, dominantValue = 0, nil, -math.huge
    for signal, count in pairs(rec.personalitySignals or {}) do
      local contribution = (tonumber(count) or 0) * (tonumber(weights[signal]) or 0)
      score = score + contribution
      if contribution > dominantValue then
        dominantValue = contribution
        dominantSignal = signal
      end
    end
    local thresholds = type(def.thresholds) == "table" and def.thresholds or { 3, 8, 16 }
    local tier = 0
    for i, threshold in ipairs(thresholds) do
      if score >= (tonumber(threshold) or math.huge) then tier = i end
    end
    return {
      id = rec.personality,
      score = score,
      tier = tier,
      dominantSignal = dominantSignal,
      signals = rec.personalitySignals,
    }
  end

  -- Feed non-battle lifecycle signals into the same personality registry.
  mod.events:on("pokemon.level_up", function(ev)
    ctx.personalitySignal(ev.mon, "LEVEL_UP", 1)
  end)
  mod.events:on("pokemon.evolved", function(ev)
    ctx.personalitySignal(ev.mon, "EVOLVED", 1)
  end)
  mod.events:on("pokemon.caught", function(ev)
    ctx.personalitySignal(ev.mon, "CAUGHT", 1)
  end)
  mod.events:on("pokemon.received", function(ev)
    ctx.personalitySignal(ev.mon, "RECEIVED", 1)
  end)
  mod.events:on("map.entered", function(ev)
    local game = ctx.runtime.game
    local party = game and game.save and game.save.party or {}
    for _, mon in ipairs(party) do ctx.personalitySignal(mon, "MAP_VISIT", 1) end
  end)
  mod.events:on("battle.ended", function()
    local game = ctx.runtime.game
    local party = game and game.save and game.save.party or {}
    for _, mon in ipairs(party) do ctx.personalitySignal(mon, "BATTLE_FINISHED", 1) end
  end)

  -- Achievement rules ------------------------------------------------------
  -- pokemon.lua originally required a metric even when a title supplied a
  -- condition. Allow metric-only, condition-only, or combined definitions.
  function ctx.evaluateTitles(mon)
    local rec = ctx.ensureMonRecord(mon)
    if not rec then return {} end
    local ids = {}
    for id in pairs(ctx.titleDefs) do ids[#ids + 1] = id end
    table.sort(ids)

    local awarded = {}
    for _, id in ipairs(ids) do
      local def = ctx.titleDefs[id]
      if not rec.titles[id] and (def.metric ~= nil or def.condition ~= nil) then
        local ok = true
        if def.metric ~= nil then
          ok = (tonumber(rec.stats[def.metric]) or 0) >= (tonumber(def.threshold) or 1)
        end
        if ok and def.condition ~= nil then
          ok = ctx.checkCondition(def.condition, {
            mon = mon, record = rec, game = ctx.runtime.game,
            mapId = ctx.runtime.currentMap,
          })
        end
        if ok and ctx.awardTitle(mon, id, def.metric or "condition") then
          awarded[#awarded + 1] = id
        end
      end
    end
    return awarded
  end

  -- Definition-driven mutations -------------------------------------------
  -- Keep stock behavior unchanged while publishing standardized modifier keys
  -- so future content can consume mutations without checking string IDs.
  ctx.registerMutation("HARDENED_TRAINERS", {
    category = "TRAINERS", weight = 3, modifiers = { trainer_level = 1 },
  })
  ctx.registerMutation("WILD_SURGE", {
    category = "WILD", weight = 3, modifiers = { wild_level = 1 },
  })
  ctx.registerMutation("NIGHT_OWLS", {
    category = "TIME", weight = 2, modifiers = { night_anomaly_rate = 2 },
  })
  ctx.registerMutation("GOSSIP_CHAIN", {
    category = "WORLD", weight = 2, modifiers = { rumor_spread = 20, director_cooldown = -30 },
  })
  ctx.registerMutation("ROCKET_NERVES", {
    category = "ROCKET", weight = 2, modifiers = { rocket_heat_gain = 1 },
  })
  ctx.registerMutation("ODD_SPECIMENS", {
    category = "WILD", weight = 2, modifiers = { anomaly_rate = 2, strange_weight = 1 },
  })

  -- Composable wild anomalies ---------------------------------------------
  -- Preserve the complete encounter payload (important for visible-water
  -- records) and allow anomaly definitions to opt into additional compatible
  -- traits. Stock LEVEL_SURGE remains a single-trait anomaly.
  local function anomalyCompatible(candidate, selected)
    local incompatible = {}
    for _, id in ipairs(candidate.incompatible or {}) do incompatible[id] = true end
    for _, row in ipairs(selected) do
      if candidate.exclusiveGroup and row.def.exclusiveGroup == candidate.exclusiveGroup then
        return false
      end
      if incompatible[row.id] then return false end
      for _, id in ipairs(row.def.incompatible or {}) do
        if id == candidate.id then return false end
      end
    end
    return true
  end

  function ctx.rollAnomaly(enc, hookCtx)
    if not ctx.feature("wild_anomalies") or type(enc) ~= "table"
      or not ctx.chance(ctx.anomalyRate(), "anomaly_gate") then
      return enc
    end

    local ids = {}
    for id in pairs(ctx.anomalyDefs) do ids[#ids + 1] = id end
    table.sort(ids)
    local eligible = {}
    for _, id in ipairs(ids) do
      local def = ctx.anomalyDefs[id]
      local ok = not def.condition or ctx.checkCondition(def.condition, {
        encounter = enc, hook = hookCtx,
      })
      if ok then eligible[#eligible + 1] = { value = { id = id, def = def }, weight = tonumber(def.weight) or 1 } end
    end

    local primary = ctx.weightedPick(eligible, "anomaly_pick")
    if not primary then return enc end
    local selected = { primary }
    local maxTraits = ctx.clamp(tonumber(primary.def.maxTraits) or 1, 1, 3)
    local stackChance = ctx.clamp(tonumber(primary.def.stackChance) or 0, 0, 100)

    while #selected < maxTraits and stackChance > 0
      and ctx.chance(stackChance, "anomaly_stack") do
      local choices = {}
      for _, row in ipairs(eligible) do
        local already = false
        for _, chosen in ipairs(selected) do if chosen.id == row.value.id then already = true break end end
        if not already and anomalyCompatible(row.value.def, selected) then
          choices[#choices + 1] = row
        end
      end
      local extra = ctx.weightedPick(choices, "anomaly_stack_pick")
      if not extra then break end
      selected[#selected + 1] = extra
      stackChance = ctx.clamp(tonumber(extra.def.stackChance) or stackChance * 0.5, 0, 100)
    end

    local out = ctx.cloneTable(enc)
    local traits = {}
    for _, row in ipairs(selected) do
      local applied = true
      if type(row.def.applyEncounter) == "function" then
        local ok, value = pcall(row.def.applyEncounter, out, hookCtx)
        applied = ok
        if ok and type(value) == "table" then out = value end
      end
      if applied then traits[#traits + 1] = row.id end
    end
    if #traits == 0 then return enc end

    local anomaly = {
      id = "A" .. tostring(ctx.runtime.steps) .. ":" .. tostring(ctx.nextRandom(9999, "anomaly_ids")),
      mapId = hookCtx and hookCtx.mapId,
      species = out.species,
      level = out.level,
      traits = traits,
      atStep = ctx.runtime.steps,
      source = hookCtx and hookCtx.source or "CLASSIC",
    }
    ctx.runtime.lastWildAnomaly = anomaly
    ctx.addCounter("wild_anomalies", 1)
    return out
  end

  -- Battle-bet contracts ---------------------------------------------------
  -- Add validation/reservation/refund hooks and make failed settlement
  -- recoverable instead of permanently marking the contract resolved.
  local baseCreateBet = ctx.createBattleBet
  function ctx.createBattleBet(npcId, def)
    local bet = baseCreateBet(npcId, def)
    if not bet then return bet end
    bet.contractVersion = tonumber(bet.contractVersion) or 1
    bet.settlementAttempts = tonumber(bet.settlementAttempts) or 0
    local bets = ctx.getTable("battle_bets")
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  function ctx.acceptBattleBet(npcId, env)
    local bets = ctx.getTable("battle_bets")
    local bet = bets[npcId]
    if type(bet) ~= "table" then return nil, "no bet" end
    if bet.state ~= "PROPOSED" and bet.state ~= "ACCEPTED" then return nil, "bet not open" end

    env = type(env) == "table" and env or {}
    env.bet, env.npcId, env.game = bet, npcId, env.game or ctx.runtime.game
    if bet.validate then
      local ok
      if type(bet.validate) == "function" then
        local success, value = pcall(bet.validate, env)
        ok = success and value ~= false
      else
        ok = ctx.checkCondition(bet.validate, env)
      end
      if not ok then return nil, "bet validation failed" end
    end

    if not bet.reservationApplied and (bet.reserveEffects or bet.onAccept) then
      local ok, err = ctx.runEffects(bet.reserveEffects or bet.onAccept, env)
      if not ok then
        bet.reservationStatus = "FAILED"
        bet.reservationError = tostring(err)
        bets[npcId] = bet
        ctx.putTable("battle_bets", bets)
        return nil, err
      end
      bet.reservationApplied = true
      bet.reservationStatus = "APPLIED"
    end

    bet.state = "ACCEPTED"
    bet.acceptedAt = bet.acceptedAt or ctx.runtime.steps
    bet.active = true
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  function ctx.cancelBattleBet(npcId, reason, env)
    local bets = ctx.getTable("battle_bets")
    local bet = bets[npcId]
    if type(bet) ~= "table" then return nil end
    if bet.state == "RESOLVED" then return bet end

    env = type(env) == "table" and env or {}
    env.bet, env.npcId, env.game = bet, npcId, env.game or ctx.runtime.game
    if bet.reservationApplied and not bet.refundApplied and (bet.refundEffects or bet.onCancel) then
      local ok, err = ctx.runEffects(bet.refundEffects or bet.onCancel, env)
      bet.refundStatus = ok and "APPLIED" or "FAILED"
      bet.refundError = ok and nil or tostring(err)
      if ok then bet.refundApplied = true end
    end

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
    return text == "win" or text == "won" or text == "victory"
      or text:find("player_win", 1, true) ~= nil
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
    if bet.state ~= "IN_BATTLE" and bet.state ~= "ACCEPTED"
      and bet.state ~= "SETTLEMENT_FAILED" then
      return nil, "bet not active"
    end

    result = result or bet.result
    bet.result = result
    bet.finishedAt = bet.finishedAt or ctx.runtime.steps
    bet.settlementAttempts = (tonumber(bet.settlementAttempts) or 0) + 1

    local effects
    if playerWon(result) then effects = bet.onWin or bet.winEffects
    elseif playerLost(result) then effects = bet.onLoss or bet.lossEffects
    else effects = bet.onOther or bet.otherEffects end

    local effectEnv = type(env) == "table" and env or {}
    effectEnv.bet, effectEnv.npcId, effectEnv.game = bet, npcId, effectEnv.game or ctx.runtime.game
    local ok, err = ctx.runEffects(effects, effectEnv)
    if not ok then
      bet.state = "SETTLEMENT_FAILED"
      bet.active = false
      bet.settled = false
      bet.settlementStatus = "FAILED"
      bet.settlementError = tostring(err)
      bets[npcId] = bet
      ctx.putTable("battle_bets", bets)
      return bet, err
    end

    bet.state = "RESOLVED"
    bet.active = false
    bet.settled = true
    bet.settlementStatus = "APPLIED"
    bet.settlementError = nil
    bets[npcId] = bet
    ctx.putTable("battle_bets", bets)
    return bet
  end

  function ctx.retryBattleBetSettlement(npcId, env)
    local bet = ctx.battleBet(npcId)
    if type(bet) ~= "table" or bet.state ~= "SETTLEMENT_FAILED" then
      return nil, "settlement is not pending"
    end
    return ctx.settleBattleBet(npcId, bet.result, env)
  end

  mod.events:on("battle.started", function()
    local npcId = ctx.runtime.currentTrainerNpc
    if not npcId then return end
    local bets = ctx.getTable("battle_bets")
    local bet = bets[npcId]
    if type(bet) ~= "table" or bet.state ~= "IN_BATTLE" then return end
    if not bet.battleToken then
      bet.battleToken = tostring(ctx.runtime.steps) .. ":" .. tostring(ctx.nextRandom(999999, "battle_bets"))
      bets[npcId] = bet
      ctx.putTable("battle_bets", bets)
    end
  end)

  -- Curse definitions ------------------------------------------------------
  -- Content can declare stageEffects without writing a callback. The generic
  -- effect registry is used so curse behavior stays data-driven.
  local baseRegisterCurse = ctx.registerCurse
  function ctx.registerCurse(def)
    if type(def) == "table" and type(def.stageEffects) == "table" and def.onStage == nil then
      local stageEffects = def.stageEffects
      def.onStage = function(stage, rec, action)
        local effects = stageEffects[stage] or stageEffects[tostring(stage)]
        if effects then
          return ctx.runEffects(effects, {
            curse = rec, stage = stage, action = action,
            game = ctx.runtime.game, mapId = ctx.runtime.currentMap,
          })
        end
        return true
      end
    end
    return baseRegisterCurse(def)
  end

  -- Community-memory propagation ------------------------------------------
  function ctx.spreadCommunityMemory(fromMap, toMap, opts)
    if not fromMap or not toMap or fromMap == toMap then return nil end
    opts = type(opts) == "table" and opts or {}
    local all = ctx.getTable("community_memories")
    local source = type(all[fromMap]) == "table" and all[fromMap] or {}
    local target = type(all[toMap]) == "table" and all[toMap] or {}
    if #source == 0 then return nil end

    local known = {}
    for _, fact in ipairs(target) do if fact.id then known[fact.id] = true end end
    local candidates = {}
    for _, fact in ipairs(source) do
      if not known[fact.id] and (tonumber(fact.confidence) or 0) >= (tonumber(opts.minConfidence) or 0.25) then
        candidates[#candidates + 1] = fact
      end
    end
    local fact = ctx.pick(candidates, "community_memory_spread")
    if not fact then return nil end
    local chance = ctx.clamp(tonumber(opts.chance) or 35, 0, 100)
    if not ctx.chance(chance * (tonumber(fact.confidence) or 1), "community_memory_spread") then return nil end

    local copy = ctx.cloneTable(fact)
    copy.confidence = ctx.clamp((tonumber(copy.confidence) or 1) * (tonumber(opts.retention) or 0.78), 0, 1)
    copy.learnedFrom = fromMap
    copy.spreadAt = ctx.runtime.steps
    target[#target + 1] = copy
    while #target > 16 do table.remove(target, 1) end
    all[toMap] = target
    ctx.putTable("community_memories", all)
    return copy
  end

  -- Bootleg League generic queries ----------------------------------------
  function ctx.currentLeagueBoss()
    local state = ctx.leagueState()
    if state.status ~= "ACTIVE" then return nil end
    local found
    for id, def in pairs(ctx.bossDefs) do
      if (tonumber(def.order) or 0) == state.currentIndex then
        if not found or tostring(id) < tostring(found.id) then found = { id = id, def = def } end
      end
    end
    return found and found.id or nil, found and found.def or nil
  end

  function ctx.leagueEligible(context)
    local id, def = ctx.currentLeagueBoss()
    if not id or not def then return false, id, def end
    if def.condition and not ctx.checkCondition(def.condition, {
      game = ctx.runtime.game,
      mapId = ctx.runtime.currentMap,
      league = ctx.leagueState(),
      boss = def,
      context = context,
    }) then return false, id, def end
    return true, id, def
  end

  -- API additions ----------------------------------------------------------
  -- api.lua has already created mod.exports before this module runs.
  local api = mod.exports
  if type(api) == "table" then
    api.personalityExpression = function(mon) return ctx.personalityExpression(mon) end
    api.mutationModifier = function(key, base) return ctx.mutationModifier(key, base) end
    api.retryBattleBetSettlement = function(npcId, env)
      return ctx.retryBattleBetSettlement(npcId, env)
    end
    api.spreadCommunityMemory = function(fromMap, toMap, opts)
      return ctx.spreadCommunityMemory(fromMap, toMap, opts)
    end
    api.currentLeagueBoss = function() return ctx.currentLeagueBoss() end
    api.leagueEligible = function(context) return ctx.leagueEligible(context) end
  end
end
