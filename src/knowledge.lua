return function(mod, ctx)
  ctx.trainerNoteDefs = ctx.trainerNoteDefs or {}
  ctx.scheduleDefs = ctx.scheduleDefs or {}

  -- Trainer Pokedex notes ---------------------------------------------------
  function ctx.registerTrainerNote(classKey, def)
    assert(type(classKey) == "string" and type(def) == "table")
    ctx.trainerNoteDefs[classKey] = ctx.trainerNoteDefs[classKey] or {}
    def.id = def.id or (classKey .. "_NOTE_" .. tostring(#ctx.trainerNoteDefs[classKey] + 1))
    ctx.trainerNoteDefs[classKey][#ctx.trainerNoteDefs[classKey] + 1] = def
    return def.id
  end

  function ctx.trainerKnowledge(classKey)
    classKey = tostring(classKey or "UNKNOWN")
    local all = ctx.getTable("trainer_knowledge")
    local rec = all[classKey]
    if type(rec) ~= "table" then
      rec = {
        encounters = 0,
        maps = {},
        partyIndices = {},
        observations = {},
        history = {},
      }
      all[classKey] = rec
      ctx.putTable("trainer_knowledge", all)
    end
    rec.maps = type(rec.maps) == "table" and rec.maps or {}
    rec.partyIndices = type(rec.partyIndices) == "table" and rec.partyIndices or {}
    rec.observations = type(rec.observations) == "table" and rec.observations or {}
    rec.history = type(rec.history) == "table" and rec.history or {}
    return rec, all
  end

  function ctx.recordTrainerObservation(classKey, key, amount, detail)
    local rec, all = ctx.trainerKnowledge(classKey)
    key = tostring(key or "UNKNOWN")
    rec.observations[key] = (tonumber(rec.observations[key]) or 0) + (tonumber(amount) or 1)
    rec.history[#rec.history + 1] = {
      key = key,
      amount = tonumber(amount) or 1,
      detail = detail,
      step = ctx.runtime.steps,
      mapId = ctx.runtime.currentMap,
    }
    while #rec.history > 16 do table.remove(rec.history, 1) end
    all[tostring(classKey or "UNKNOWN")] = rec
    ctx.putTable("trainer_knowledge", all)
    return rec.observations[key]
  end

  function ctx.trainerNotes(classKey)
    classKey = tostring(classKey or "UNKNOWN")
    local rec = ctx.trainerKnowledge(classKey)
    local env = {
      classKey = classKey,
      knowledge = rec,
      game = ctx.runtime.game,
      mapId = ctx.runtime.currentMap,
    }
    local out = {}
    for _, def in ipairs(ctx.trainerNoteDefs[classKey] or {}) do
      local ok = (tonumber(rec.encounters) or 0) >= (tonumber(def.minEncounters) or 0)
      if ok and def.observation then
        ok = (tonumber(rec.observations[def.observation]) or 0) >= (tonumber(def.threshold) or 1)
      end
      if ok and def.condition then ok = ctx.checkCondition(def.condition, env) end
      if ok then
        out[#out + 1] = {
          id = def.id,
          text = type(def.text) == "function" and def.text(env) or def.text,
          confidence = ctx.clamp(tonumber(def.confidence) or math.min(1, (rec.encounters or 0) / 5), 0, 1),
          priority = tonumber(def.priority) or 0,
        }
      end
    end
    table.sort(out, function(a, b) return a.priority > b.priority end)
    return out
  end

  mod.events:on("world.trainer_engaged", function(ev)
    local classKey = tostring(ev.trainerClass or "UNKNOWN")
    local rec, all = ctx.trainerKnowledge(classKey)
    rec.encounters = (tonumber(rec.encounters) or 0) + 1
    rec.lastSeenAt = ctx.runtime.steps
    rec.lastMap = ctx.runtime.currentMap
    rec.maps[ctx.runtime.currentMap or "UNKNOWN"] = (rec.maps[ctx.runtime.currentMap or "UNKNOWN"] or 0) + 1
    if ev.partyIndex ~= nil then
      local key = tostring(ev.partyIndex)
      rec.partyIndices[key] = (rec.partyIndices[key] or 0) + 1
    end
    rec.history[#rec.history + 1] = {
      key = "ENCOUNTER",
      step = ctx.runtime.steps,
      mapId = ctx.runtime.currentMap,
      partyIndex = ev.partyIndex,
    }
    while #rec.history > 16 do table.remove(rec.history, 1) end
    all[classKey] = rec
    ctx.putTable("trainer_knowledge", all)
  end)

  -- Time/schedule registry --------------------------------------------------
  function ctx.registerSchedule(id, def)
    assert(type(id) == "string" and type(def) == "table")
    def.id = id
    ctx.scheduleDefs[id] = def
    return id
  end

  function ctx.scheduleActive(id, context)
    local def = ctx.scheduleDefs[id]
    if not def then return false end
    context = type(context) == "table" and context or {}
    local mapId = context.mapId or ctx.runtime.currentMap
    if def.mapId and def.mapId ~= mapId then return false end
    if type(def.maps) == "table" and #def.maps > 0 then
      local found = false
      for _, value in ipairs(def.maps) do if value == mapId then found = true break end end
      if not found then return false end
    end
    if def.tod and def.tod ~= ctx.currentTod() then return false end
    if def.startHour ~= nil or def.endHour ~= nil then
      if not ctx.timeInRange(def.startHour or 0, def.endHour or 24) then return false end
    end
    if def.condition and not ctx.checkCondition(def.condition, {
      game = ctx.runtime.game,
      mapId = mapId,
      schedule = def,
      context = context,
    }) then return false end
    return true
  end
end
