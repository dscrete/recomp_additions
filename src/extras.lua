return function(mod, ctx)
  -- Museum -----------------------------------------------------------------
  function ctx.exhibitState(id)
    local exhibits = ctx.getTable("museum_exhibits")
    local rec = exhibits[id]
    if rec == true then
      rec = { unlocked = true, stage = 1, discoveries = 1 }
      exhibits[id] = rec
      ctx.putTable("museum_exhibits", exhibits)
    end
    return type(rec) == "table" and rec or nil
  end

  function ctx.unlockExhibit(id, meta)
    if not id then return nil end
    meta = type(meta) == "table" and meta or {}
    local exhibits = ctx.getTable("museum_exhibits")
    local rec = exhibits[id]
    if rec == true then rec = { unlocked = true, stage = 1, discoveries = 1 } end
    if type(rec) ~= "table" then
      rec = { unlocked = false, stage = 0, discoveries = 0, history = {} }
    end
    rec.unlocked = true
    rec.stage = math.max(1, tonumber(rec.stage) or 0, tonumber(meta.stage) or 0)
    rec.discoveries = (tonumber(rec.discoveries) or 0) + 1
    rec.firstUnlockedAt = rec.firstUnlockedAt or ctx.runtime.steps
    rec.lastUpdatedAt = ctx.runtime.steps
    rec.provenance = meta.provenance or rec.provenance
    rec.species = meta.species or rec.species or id
    rec.history = type(rec.history) == "table" and rec.history or {}
    rec.history[#rec.history + 1] = {
      step = ctx.runtime.steps,
      mapId = ctx.runtime.currentMap,
      source = meta.source or "discovery",
      stage = rec.stage,
    }
    while #rec.history > 12 do table.remove(rec.history, 1) end
    exhibits[id] = rec
    ctx.putTable("museum_exhibits", exhibits)
    return rec
  end

  function ctx.advanceExhibit(id, amount, meta)
    local rec = ctx.unlockExhibit(id, meta)
    if not rec then return nil end
    local exhibits = ctx.getTable("museum_exhibits")
    rec.stage = math.max(1, (tonumber(rec.stage) or 1) + (tonumber(amount) or 1))
    rec.lastUpdatedAt = ctx.runtime.steps
    exhibits[id] = rec
    ctx.putTable("museum_exhibits", exhibits)
    return rec
  end

  function ctx.exhibitCount()
    local n = 0
    for _, rec in pairs(ctx.getTable("museum_exhibits")) do
      if rec == true or (type(rec) == "table" and rec.unlocked ~= false) then n = n + 1 end
    end
    return n
  end

  ctx.registerMigration(4, function()
    local exhibits = ctx.getTable("museum_exhibits")
    local changed = false
    for id, rec in pairs(exhibits) do
      if rec == true then
        exhibits[id] = { unlocked = true, stage = 1, discoveries = 1, history = {} }
        changed = true
      end
    end
    if changed then ctx.putTable("museum_exhibits", exhibits) end
  end)

  -- Urban legends ----------------------------------------------------------
  function ctx.registerLegend(def)
    assert(type(def) == "table" and type(def.id) == "string")
    def.initialStage = tonumber(def.initialStage) or 0
    def.transitions = type(def.transitions) == "table" and def.transitions or {}
    ctx.legendDefs[def.id] = def
    return def.id
  end

  function ctx.legendState(id)
    local legends = ctx.getTable("urban_legends")
    local rec = legends[id]
    if type(rec) ~= "table" then
      rec = {
        stage = 0,
        status = "UNKNOWN",
        discovered = false,
        clues = {},
        history = {},
      }
    end
    return rec
  end

  local function saveLegend(id, rec)
    local legends = ctx.getTable("urban_legends")
    legends[id] = rec
    ctx.putTable("urban_legends", legends)
    return rec
  end

  function ctx.activateLegend(id, stage, reason)
    local def = ctx.legendDefs[id]
    if not def then return nil, "unknown legend" end
    local rec = ctx.legendState(id)
    rec.stage = math.max(tonumber(rec.stage) or 0, tonumber(stage) or 1)
    rec.discovered = true
    if rec.status == "UNKNOWN" then rec.status = "HEARD" end
    rec.lastStep = ctx.runtime.steps
    rec.history = type(rec.history) == "table" and rec.history or {}
    rec.history[#rec.history + 1] = {
      step = ctx.runtime.steps, stage = rec.stage,
      status = rec.status, reason = reason or "discovered", mapId = ctx.runtime.currentMap,
    }
    while #rec.history > 16 do table.remove(rec.history, 1) end
    return saveLegend(id, rec)
  end

  function ctx.addLegendClue(id, clueId, amount)
    local rec = ctx.activateLegend(id, 1, "clue")
    if not rec then return nil end
    rec.clues = type(rec.clues) == "table" and rec.clues or {}
    rec.clues[clueId] = (tonumber(rec.clues[clueId]) or 0) + (tonumber(amount) or 1)
    rec.status = rec.status == "HEARD" and "INVESTIGATING" or rec.status
    return saveLegend(id, rec)
  end

  function ctx.advanceLegend(id, trigger, env)
    local def = ctx.legendDefs[id]
    if not def then return nil, "unknown legend" end
    local rec = ctx.legendState(id)
    env = type(env) == "table" and env or {}
    env.legend = rec
    env.trigger = trigger
    env.mapId = env.mapId or ctx.runtime.currentMap

    for _, transition in ipairs(def.transitions or {}) do
      local from = transition.from
      local fromOk = from == nil or from == rec.stage or from == rec.status
      local triggerOk = transition.trigger == nil or transition.trigger == trigger
      if fromOk and triggerOk and ctx.checkCondition(transition.condition, env) then
        if transition.toStage ~= nil then rec.stage = tonumber(transition.toStage) or rec.stage end
        if transition.toStatus then rec.status = transition.toStatus end
        if transition.clue then
          rec.clues = type(rec.clues) == "table" and rec.clues or {}
          rec.clues[transition.clue] = (tonumber(rec.clues[transition.clue]) or 0) + 1
        end
        if transition.resolution then
          rec.resolution = transition.resolution
          rec.status = "RESOLVED"
        end
        rec.discovered = true
        rec.lastStep = ctx.runtime.steps
        rec.history = type(rec.history) == "table" and rec.history or {}
        rec.history[#rec.history + 1] = {
          step = ctx.runtime.steps, trigger = trigger, stage = rec.stage,
          status = rec.status, mapId = env.mapId,
        }
        while #rec.history > 16 do table.remove(rec.history, 1) end
        saveLegend(id, rec)
        if transition.effects then ctx.runEffects(transition.effects, env) end
        return rec, transition
      end
    end
    return rec, nil
  end

  function ctx.resolveLegend(id, resolution)
    local rec = ctx.legendState(id)
    rec.discovered = true
    rec.status = "RESOLVED"
    rec.resolution = resolution or "UNRESOLVED"
    rec.resolvedAt = ctx.runtime.steps
    return saveLegend(id, rec)
  end

  -- Curses -----------------------------------------------------------------
  function ctx.registerCurse(def)
    assert(type(def) == "table" and type(def.id) == "string")
    def.stages = type(def.stages) == "table" and def.stages or { 0, 3, 6, 9, 12, 15 }
    ctx.curseDefs[def.id] = def
    return def.id
  end

  function ctx.curseState(id)
    id = id or "UNKNOWN_OBJECT"
    local all = ctx.getTable("curses")
    local rec = all[id]
    if type(rec) ~= "table" then
      rec = { id = id, stage = 0, touches = 0, active = true, history = {} }
    end
    return rec
  end

  local function curseStage(def, touches)
    local stage = 0
    for i, threshold in ipairs(def.stages or {}) do
      if touches >= (tonumber(threshold) or math.huge) then stage = i - 1 end
    end
    return math.max(0, stage)
  end

  function ctx.touchCurse(action, id)
    id = id or "UNKNOWN_OBJECT"
    local def = ctx.curseDefs[id] or { id = id, stages = { 0, 3, 6, 9, 12, 15 } }
    local rec = ctx.curseState(id)
    if rec.active == false then return rec end
    local oldStage = tonumber(rec.stage) or 0
    rec.touches = (tonumber(rec.touches) or 0) + 1
    rec.lastAction = action or "unknown"
    rec.lastStep = ctx.runtime.steps
    rec.stage = curseStage(def, rec.touches)
    rec.history = type(rec.history) == "table" and rec.history or {}
    rec.history[#rec.history + 1] = {
      action = rec.lastAction, step = ctx.runtime.steps, stage = rec.stage,
    }
    while #rec.history > 12 do table.remove(rec.history, 1) end

    local all = ctx.getTable("curses")
    all[id] = rec
    ctx.putTable("curses", all)
    -- Backward-compatible single-curse mirror.
    if id == "UNKNOWN_OBJECT" then mod.save:set("curse_state", rec) end

    if rec.stage > oldStage and type(def.onStage) == "function" then
      pcall(def.onStage, rec.stage, rec, action)
    end
    return rec
  end

  function ctx.cleanseCurse(id, reason)
    id = id or "UNKNOWN_OBJECT"
    local rec = ctx.curseState(id)
    rec.active = false
    rec.cleansedAt = ctx.runtime.steps
    rec.cleansedBy = reason or "unknown"
    local all = ctx.getTable("curses")
    all[id] = rec
    ctx.putTable("curses", all)
    return rec
  end

  ctx.registerMigration(4, function()
    local legacy = mod.save:get("curse_state")
    local all = ctx.getTable("curses")
    if type(legacy) == "table" and type(all.UNKNOWN_OBJECT) ~= "table" then
      legacy.id = "UNKNOWN_OBJECT"
      legacy.active = legacy.active ~= false
      legacy.history = type(legacy.history) == "table" and legacy.history or {}
      all.UNKNOWN_OBJECT = legacy
      ctx.putTable("curses", all)
    end
  end)

  -- Travelers ---------------------------------------------------------------
  function ctx.registerTraveler(def)
    assert(type(def) == "table" and type(def.id) == "string")
    def.maps = type(def.maps) == "table" and def.maps or {}
    ctx.travelerDefs[def.id] = def
    return def.id
  end

  function ctx.travelerState(id)
    local state = ctx.getTable("traveler_state")[id]
    return type(state) == "table" and state or nil
  end

  local function pickDifferentMap(def, current)
    local choices = {}
    for _, mapId in ipairs(def.maps or {}) do if mapId ~= current then choices[#choices + 1] = mapId end end
    if #choices == 0 then choices = def.maps or {} end
    return ctx.pick(choices, "traveler:" .. tostring(def.id))
  end

  function ctx.updateTravelers()
    local states = ctx.getTable("traveler_state")
    local changed = false
    for id, def in pairs(ctx.travelerDefs) do
      if #def.maps > 0 then
        local state = states[id]
        if type(state) ~= "table" then
          state = {
            encounters = 0, suspicion = 0, history = {},
            aliasIndex = 1, inventoryState = {},
          }
        end
        if not state.mapId or ctx.runtime.steps >= (tonumber(state.nextMove) or 0) then
          local previous = state.mapId
          state.previousMap = previous
          state.mapId = pickDifferentMap(def, previous)
          state.movedAt = ctx.runtime.steps
          state.nextMove = ctx.runtime.steps + (tonumber(def.interval) or 640)
          state.history = type(state.history) == "table" and state.history or {}
          state.history[#state.history + 1] = {
            step = ctx.runtime.steps, from = previous, to = state.mapId,
          }
          while #state.history > 10 do table.remove(state.history, 1) end
          states[id] = state
          changed = true
        end
      end
    end
    if changed then ctx.putTable("traveler_state", states) end
  end

  function ctx.recordTravelerEncounter(id, outcome, details)
    local def = ctx.travelerDefs[id]
    if not def then return nil, "unknown traveler" end
    local states = ctx.getTable("traveler_state")
    local state = states[id] or { encounters = 0, suspicion = 0, history = {} }
    state.encounters = (tonumber(state.encounters) or 0) + 1
    state.lastOutcome = outcome
    state.lastEncounterAt = ctx.runtime.steps
    details = type(details) == "table" and details or {}
    state.suspicion = ctx.clamp((tonumber(state.suspicion) or 0) + (tonumber(details.suspicion) or 0), 0, 100)
    if details.aliasIndex then state.aliasIndex = details.aliasIndex end
    if details.inventoryState then state.inventoryState = details.inventoryState end
    state.history = type(state.history) == "table" and state.history or {}
    state.history[#state.history + 1] = {
      step = ctx.runtime.steps, mapId = state.mapId, outcome = outcome,
      suspicion = state.suspicion,
    }
    while #state.history > 10 do table.remove(state.history, 1) end
    states[id] = state
    ctx.putTable("traveler_state", states)
    return state
  end

  -- Bootleg League / generic gauntlet --------------------------------------
  function ctx.registerBoss(def)
    assert(type(def) == "table" and type(def.id) == "string")
    ctx.bossDefs[def.id] = def
    return def.id
  end

  function ctx.leagueState()
    local state = mod.save:get("bootleg_league", {})
    if type(state) ~= "table" then state = {} end
    state.status = state.status or "IDLE"
    state.currentIndex = tonumber(state.currentIndex) or 1
    state.attempts = tonumber(state.attempts) or 0
    state.wins = tonumber(state.wins) or 0
    state.history = type(state.history) == "table" and state.history or {}
    return state
  end

  function ctx.startLeague()
    local state = ctx.leagueState()
    if state.status ~= "ACTIVE" then
      state.status = "ACTIVE"
      state.currentIndex = 1
      state.attempts = state.attempts + 1
      state.runStartedAt = ctx.runtime.steps
      state.runWins = 0
      mod.save:set("bootleg_league", state)
    end
    return state
  end

  function ctx.resetLeague(reason)
    local state = ctx.leagueState()
    state.status = "IDLE"
    state.currentIndex = 1
    state.runWins = 0
    state.lastResetReason = reason or "manual"
    mod.save:set("bootleg_league", state)
    return state
  end

  function ctx.recordBossResult(id, result)
    local bosses = ctx.getTable("boss_progress")
    local rec = bosses[id]
    if type(rec) ~= "table" then rec = { attempts = 0, wins = 0, history = {} } end
    rec.attempts = (tonumber(rec.attempts) or 0) + 1
    rec.lastResult = result
    rec.lastStep = ctx.runtime.steps
    local won = result == "win" or result == "won" or result == "victory"
    if won then rec.wins = (tonumber(rec.wins) or 0) + 1 end
    rec.history = type(rec.history) == "table" and rec.history or {}
    rec.history[#rec.history + 1] = { step = ctx.runtime.steps, result = result }
    while #rec.history > 8 do table.remove(rec.history, 1) end
    bosses[id] = rec
    ctx.putTable("boss_progress", bosses)

    local state = ctx.leagueState()
    if state.status == "ACTIVE" then
      local expected
      for bossId, def in pairs(ctx.bossDefs) do
        if (tonumber(def.order) or 0) == state.currentIndex then expected = bossId break end
      end
      if expected == id then
        state.history[#state.history + 1] = { id = id, result = result, step = ctx.runtime.steps }
        while #state.history > 20 do table.remove(state.history, 1) end
        if won then
          state.runWins = (tonumber(state.runWins) or 0) + 1
          state.wins = (tonumber(state.wins) or 0) + 1
          state.currentIndex = state.currentIndex + 1
          local remaining = false
          for _, def in pairs(ctx.bossDefs) do
            if (tonumber(def.order) or 0) >= state.currentIndex then remaining = true break end
          end
          if not remaining then
            state.status = "COMPLETED"
            state.completedAt = ctx.runtime.steps
            state.completions = (tonumber(state.completions) or 0) + 1
          end
        else
          state.status = "FAILED"
          state.failedAt = ctx.runtime.steps
        end
        mod.save:set("bootleg_league", state)
      end
    end
    return rec
  end

  -- Baseline identities. Concrete NPCs/maps/trainers remain content-deferred.
  ctx.registerLegend({ id = "REFLECTION", text = "Some televisions seem to reflect too much." })
  ctx.registerLegend({ id = "STATIC", text = "Travelers report hearing static where there is no radio." })
  ctx.registerLegend({ id = "EMPTY_ROUTE", text = "A route occasionally feels much quieter than it should." })

  ctx.registerCurse({ id = "UNKNOWN_OBJECT", stages = { 0, 3, 6, 9, 12, 15 } })

  ctx.registerTraveler({
    id = "CON_ARTIST",
    maps = { "PEWTER_CITY", "CERULEAN_CITY", "CELADON_CITY", "FUCHSIA_CITY" },
    interval = 720,
  })

  for i = 1, 4 do ctx.registerBoss({ id = "BOOTLEG_LEAGUE_" .. i, order = i }) end
end
