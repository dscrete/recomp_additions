return function(mod, ctx)
  function ctx.unlockExhibit(id)
    local exhibits = ctx.getTable("museum_exhibits")
    exhibits[id] = true
    ctx.putTable("museum_exhibits", exhibits)
  end

  function ctx.exhibitCount()
    local n = 0
    for _, unlocked in pairs(ctx.getTable("museum_exhibits")) do
      if unlocked then n = n + 1 end
    end
    return n
  end

  function ctx.registerLegend(def)
    assert(type(def) == "table" and type(def.id) == "string")
    ctx.legendDefs[def.id] = def
  end

  function ctx.activateLegend(id, stage)
    local legends = ctx.getTable("urban_legends")
    local rec = legends[id]
    if type(rec) ~= "table" then rec = { stage = 0, discovered = false } end
    rec.stage = math.max(tonumber(rec.stage) or 0, tonumber(stage) or 1)
    rec.discovered = true
    rec.lastStep = ctx.runtime.steps
    legends[id] = rec
    ctx.putTable("urban_legends", legends)
    return rec
  end

  -- The state machine is ready now. A physical cursed bag item is intentionally
  -- not registered yet because the public hook catalog has no discard intercept.
  function ctx.touchCurse(action)
    local curse = mod.save:get("curse_state", {})
    if type(curse) ~= "table" then curse = {} end
    curse.touches = (tonumber(curse.touches) or 0) + 1
    curse.lastAction = action or "unknown"
    curse.stage = math.min(5, math.floor(curse.touches / 3))
    mod.save:set("curse_state", curse)
    return curse
  end

  function ctx.registerTraveler(def)
    assert(type(def) == "table" and type(def.id) == "string")
    ctx.travelerDefs[def.id] = def
  end

  function ctx.travelerState(id)
    return ctx.getTable("traveler_state")[id]
  end

  function ctx.updateTravelers()
    local states = ctx.getTable("traveler_state")
    local changed = false
    for id, def in pairs(ctx.travelerDefs) do
      if type(def.maps) == "table" and #def.maps > 0 then
        local state = states[id]
        if type(state) ~= "table" then state = {} end
        if not state.mapId or ctx.runtime.steps >= (tonumber(state.nextMove) or 0) then
          state.mapId = ctx.pick(def.maps)
          state.nextMove = ctx.runtime.steps + (tonumber(def.interval) or 640)
          states[id] = state
          changed = true
        end
      end
    end
    if changed then ctx.putTable("traveler_state", states) end
  end

  function ctx.registerBoss(def)
    assert(type(def) == "table" and type(def.id) == "string")
    ctx.bossDefs[def.id] = def
  end

  function ctx.recordBossResult(id, result)
    local bosses = ctx.getTable("boss_progress")
    local rec = bosses[id]
    if type(rec) ~= "table" then rec = { attempts = 0, wins = 0 } end
    rec.attempts = (tonumber(rec.attempts) or 0) + 1
    rec.lastResult = result
    if result == "win" or result == "won" or result == "victory" then
      rec.wins = (tonumber(rec.wins) or 0) + 1
    end
    bosses[id] = rec
    ctx.putTable("boss_progress", bosses)
    return rec
  end

  -- Baseline content identities. Concrete NPCs/maps/trainers can be attached later.
  ctx.registerLegend({ id = "REFLECTION", text = "Some televisions seem to reflect too much." })
  ctx.registerLegend({ id = "STATIC", text = "Travelers report hearing static where there is no radio." })
  ctx.registerLegend({ id = "EMPTY_ROUTE", text = "A route occasionally feels much quieter than it should." })

  ctx.registerTraveler({
    id = "CON_ARTIST",
    maps = { "PEWTER_CITY", "CERULEAN_CITY", "CELADON_CITY", "FUCHSIA_CITY" },
    interval = 720,
  })

  for i = 1, 4 do
    ctx.registerBoss({ id = "BOOTLEG_LEAGUE_" .. i, order = i })
  end
end
