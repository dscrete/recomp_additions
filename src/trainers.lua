return function(mod, ctx)
  local function reputation()
    return ctx.getTable("reputation")
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

  function ctx.trainerMemory(npcId)
    if not npcId then return nil end
    local all = ctx.getTable("trainer_memory")
    local rec = all[npcId]
    if type(rec) ~= "table" then
      rec = { engagements = 0, battles = 0 }
      all[npcId] = rec
      ctx.putTable("trainer_memory", all)
    end
    return rec, all
  end

  function ctx.trainerArc(npcId)
    if not npcId then return nil end
    local arcs = ctx.getTable("trainer_arcs")
    local rec = arcs[npcId]
    if type(rec) ~= "table" then
      rec = { stage = 0, encounters = 0 }
      arcs[npcId] = rec
      ctx.putTable("trainer_arcs", arcs)
    end
    return rec, arcs
  end

  function ctx.getHeat()
    return math.max(0, tonumber(mod.save:get("rocket_heat", 0)) or 0)
  end

  function ctx.addHeat(amount)
    if not ctx.feature("rocket_heat") then return ctx.getHeat() end
    local heat = ctx.clamp(ctx.getHeat() + (amount or 1), 0, 100)
    mod.save:set("rocket_heat", heat)
    return heat
  end

  mod.hooks:wrap("trainer.party", function(next, trainerClass, partyIndex, party)
    local base = next(trainerClass, partyIndex, party)
    if not ctx.feature() or type(base) ~= "table" then return base end

    local bonus = ctx.hasMutation("HARDENED_TRAINERS") and 1 or 0
    if ctx.feature("trainer_memory") and ctx.runtime.currentTrainerNpc then
      local rec = ctx.trainerMemory(ctx.runtime.currentTrainerNpc)
      if rec and (tonumber(rec.battles) or 0) >= 2 then bonus = bonus + 1 end
    end
    if bonus <= 0 then return base end

    local out = ctx.cloneArray(base)
    for _, mon in ipairs(out) do
      if type(mon) == "table" and mon.level then
        mon.level = ctx.clamp((tonumber(mon.level) or 1) + bonus, 1, 100)
      end
    end
    return out
  end)

  -- Future dialogue/content stages a bet first. The low-level trainer hook only
  -- applies the already-agreed battle scope; it never interrupts every trainer.
  mod.hooks:wrap("trainer.before_battle", function(next, game, context, continue)
    if not ctx.feature() or type(context) ~= "table" or not context.npcId then
      return next()
    end
    local bets = ctx.getTable("battle_bets")
    local bet = bets[context.npcId]
    if type(bet) ~= "table" or bet.active == false then return next() end
    if type(bet.playerPartyIndices) == "table" and #bet.playerPartyIndices > 0 then
      bet.startedAt = ctx.runtime.steps
      bets[context.npcId] = bet
      ctx.putTable("battle_bets", bets)
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
      rec.engagements = (tonumber(rec.engagements) or 0) + 1
      rec.trainerClass = ev.trainerClass
      rec.partyIndex = ev.partyIndex
      rec.lastMap = ctx.runtime.currentMap
      all[npcId] = rec
      ctx.putTable("trainer_memory", all)

      local arc, arcs = ctx.trainerArc(npcId)
      arc.encounters = (tonumber(arc.encounters) or 0) + 1
      arc.firstMap = arc.firstMap or ctx.runtime.currentMap
      arc.lastMap = ctx.runtime.currentMap
      arcs[npcId] = arc
      ctx.putTable("trainer_arcs", arcs)
    end

    local classes = ctx.getTable("trainer_class_counts")
    local classKey = tostring(ev.trainerClass or "UNKNOWN")
    classes[classKey] = (classes[classKey] or 0) + 1
    ctx.putTable("trainer_class_counts", classes)

    if ctx.feature("rocket_heat") and ctx.containsText(classKey, "ROCKET") then
      ctx.addHeat(ctx.hasMutation("ROCKET_NERVES") and 3 or 2)
    end
  end)

  mod.events:on("battle.started", function(ev)
    ctx.bumpReputation("battles", 1)
    ctx.runtime.battle = {
      kind = ev.kind,
      trainerId = ev.trainerId,
      trainerNpc = ctx.runtime.currentTrainerNpc,
      trainerClass = ctx.runtime.currentTrainerClass,
      turns = 0,
      anomaly = ctx.runtime.lastWildAnomaly,
    }
    ctx.runtime.lastWildAnomaly = nil
  end)

  mod.events:on("battle.turn_ended", function()
    if ctx.runtime.battle then
      ctx.runtime.battle.turns = (ctx.runtime.battle.turns or 0) + 1
    end
  end)

  mod.events:on("battle.ended", function(ev)
    local battle = ctx.runtime.battle
    if battle and battle.trainerNpc and ctx.feature("trainer_memory") then
      local rec, all = ctx.trainerMemory(battle.trainerNpc)
      rec.battles = (tonumber(rec.battles) or 0) + 1
      rec.lastResult = ev.result
      rec.lastTurns = battle.turns
      all[battle.trainerNpc] = rec
      ctx.putTable("trainer_memory", all)

      local bets = ctx.getTable("battle_bets")
      local bet = bets[battle.trainerNpc]
      if type(bet) == "table" and bet.active ~= false then
        bet.active = false
        bet.result = ev.result
        bet.finishedAt = ctx.runtime.steps
        bets[battle.trainerNpc] = bet
        ctx.putTable("battle_bets", bets)
      end
    end
    if battle and battle.anomaly then mod.save:set("last_anomaly", battle.anomaly) end

    ctx.runtime.battle = nil
    ctx.runtime.currentTrainerNpc = nil
    ctx.runtime.currentTrainerClass = nil
    ctx.runtime.currentTrainerParty = nil
  end)
end
