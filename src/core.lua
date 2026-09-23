local PERSONALITIES = {
  "BRAVE", "CAUTIOUS", "SHOW-OFF", "CURIOUS", "STUBBORN",
  "LUCKY", "SLEEPY", "MISCHIEVOUS", "LOYAL", "DRAMATIC",
}

local MOOD_DEFS = {
  QUIET = {
    weight = 5,
    modifiers = { director_weight = -0.20, anomaly_rate = -1, rumor_weight = -0.15 },
  },
  LUCKY = {
    weight = 3,
    modifiers = { director_weight = 0.10, anomaly_rate = -1, favorable_weight = 0.25 },
  },
  RESTLESS = {
    weight = 3,
    modifiers = { director_weight = 0.20, anomaly_rate = 2, rumor_weight = 0.20 },
  },
  STRANGE = {
    weight = 2,
    modifiers = { director_weight = 0.10, anomaly_rate = 1, strange_weight = 0.35 },
  },
}

local MUTATION_DEFS = {
  HARDENED_TRAINERS = { category = "TRAINERS", weight = 3 },
  WILD_SURGE = { category = "WILD", weight = 3 },
  NIGHT_OWLS = { category = "TIME", weight = 2 },
  GOSSIP_CHAIN = { category = "WORLD", weight = 2 },
  ROCKET_NERVES = { category = "ROCKET", weight = 2 },
  ODD_SPECIMENS = { category = "WILD", weight = 2 },
}

return function(mod)
  local ctx = {
    MON_FIELD = "gen1Expansion",
    SCREEN_ID = "Gen1ExpansionStatus",
    CURRENT_SCHEMA = 4,
    personalities = PERSONALITIES,
    moodDefs = MOOD_DEFS,
    mutationDefs = MUTATION_DEFS,
    runtime = {
      game = nil,
      currentMap = nil,
      steps = 0,
      currentTrainerNpc = nil,
      currentTrainerClass = nil,
      currentTrainerParty = nil,
      battle = nil,
      lastWildAnomaly = nil,
    },
    rumorDefs = {},
    directorDefs = {},
    ecologyRules = {},
    nightRules = {},
    legendDefs = {},
    travelerDefs = {},
    bulletinDefs = {},
    bossDefs = {},
    anomalyDefs = {},
    titleDefs = {},
    observationDefs = {},
    superstitionDefs = {},
    curseDefs = {},
    conditionDefs = {},
    effectDefs = {},
    migrations = {},
  }

  function ctx.feature(key)
    return mod.options:get("enabled") ~= false and (key == nil or mod.options:get(key) ~= false)
  end

  function ctx.clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
  end

  function ctx.cloneArray(rows)
    local out = {}
    for i, row in ipairs(rows or {}) do
      if type(row) == "table" then
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        out[i] = copy
      else
        out[i] = row
      end
    end
    return out
  end

  function ctx.cloneTable(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
      out[k] = type(v) == "table" and ctx.cloneTable(v) or v
    end
    return out
  end

  function ctx.containsText(value, needle)
    return type(value) == "string" and string.find(value, needle, 1, true) ~= nil
  end

  function ctx.speciesOf(mon)
    if type(mon) ~= "table" then return nil end
    return mon.species or mon.speciesId or mon.id
  end

  function ctx.monFromBattler(value)
    if type(value) ~= "table" then return nil end
    if type(value.mon) == "table" then return value.mon end
    if value.species or value.speciesId then return value end
    return nil
  end

  function ctx.isPlayerBattler(value)
    if type(value) ~= "table" then return false end
    return value.isPlayer == true or value.side == "player" or value.owner == "player"
  end

  function ctx.truncate(text, n)
    text = tostring(text or "")
    if #text <= n then return text end
    return string.sub(text, 1, math.max(1, n - 3)) .. "..."
  end

  function ctx.getTable(key)
    local value = mod.save:get(key, {})
    if type(value) ~= "table" then value = {} end
    return value
  end

  function ctx.putTable(key, value)
    mod.save:set(key, value)
    return value
  end

  function ctx.addCounter(key, amount)
    local n = tonumber(mod.save:get(key, 0)) or 0
    n = n + (amount or 1)
    mod.save:set(key, n)
    return n
  end

  function ctx.appendHistory(key, entry, limit)
    local rows = ctx.getTable(key)
    rows[#rows + 1] = entry
    limit = math.max(1, tonumber(limit) or 24)
    while #rows > limit do table.remove(rows, 1) end
    ctx.putTable(key, rows)
    return rows
  end

  -- Explicit schema migrations. Feature modules can register more work for the
  -- same target version; all callbacks for each version are executed in order.
  function ctx.registerMigration(version, fn)
    version = math.max(1, math.floor(tonumber(version) or 1))
    assert(type(fn) == "function", "migration must be a function")
    ctx.migrations[version] = ctx.migrations[version] or {}
    ctx.migrations[version][#ctx.migrations[version] + 1] = fn
  end

  function ctx.runMigrations()
    local current = math.max(0, math.floor(tonumber(mod.save:get("schema_version", 0)) or 0))
    if current >= ctx.CURRENT_SCHEMA then return current end
    for version = current + 1, ctx.CURRENT_SCHEMA do
      for _, fn in ipairs(ctx.migrations[version] or {}) do
        local ok, err = pcall(fn, version)
        if not ok then
          mod.log:error("Kanto Expansion migration %d failed: %s", version, tostring(err))
          return version - 1, err
        end
      end
      mod.save:set("schema_version", version)
    end
    return ctx.CURRENT_SCHEMA
  end

  ctx.registerMigration(1, function()
    local streams = mod.save:get("rng_streams")
    if type(streams) ~= "table" then
      streams = {}
      local legacy = tonumber(mod.save:get("rng_state"))
      if legacy then streams.default = math.max(1, legacy % 2147483647) end
      mod.save:set("rng_streams", streams)
    end
  end)

  ctx.registerMigration(2, function()
    if type(mod.save:get("mood_state")) ~= "table" then
      local oldMood = mod.save:get("world_mood")
      local oldExpires = tonumber(mod.save:get("mood_expires", 0)) or 0
      if oldMood then
        mod.save:set("mood_state", {
          id = oldMood,
          intensity = 1,
          pressure = 0,
          startedAt = 0,
          expiresAt = oldExpires,
          causes = {},
        })
      end
    end
  end)

  ctx.registerMigration(3, function()
    if mod.save:get("run_seed") == nil then
      local old = tonumber(mod.save:get("rng_state"))
      mod.save:set("run_seed", math.max(1, math.floor(old or (os.time() % 2147483647))))
    end
  end)

  ctx.registerMigration(4, function()
    local active = mod.save:get("run_mutations")
    if type(active) ~= "table" then mod.save:set("run_mutations", {}) end
    if mod.save:get("mutation_version") == nil then mod.save:set("mutation_version", 1) end
  end)

  function ctx.runSeed()
    local seed = tonumber(mod.save:get("run_seed"))
    if seed and seed > 0 then return math.floor(seed) end
    seed = math.max(1, math.floor((os.time() or 1) % 2147483647))
    mod.save:set("run_seed", seed)
    return seed
  end

  local function streamHash(name)
    local h = 5381
    name = tostring(name or "default")
    for i = 1, #name do h = (h * 33 + string.byte(name, i)) % 2147483647 end
    return h
  end

  -- Park-Miller RNG using Schrage's method, avoiding large floating-point
  -- products. Streams isolate subsystems so adding a rumor roll cannot change
  -- the next mutation, ecology result or Director event.
  function ctx.nextRandom(max, stream)
    max = math.max(1, math.floor(max or 1))
    stream = tostring(stream or "default")
    local streams = ctx.getTable("rng_streams")
    local state = tonumber(streams[stream])
    if not state or state <= 0 then
      state = ((ctx.runSeed() + streamHash(stream) * 97) % 2147483646) + 1
    end
    local hi = math.floor(state / 44488)
    local lo = state % 44488
    local test = 48271 * lo - 3399 * hi
    if test <= 0 then test = test + 2147483647 end
    streams[stream] = test
    ctx.putTable("rng_streams", streams)
    return (test % max) + 1
  end

  function ctx.chance(percent, stream)
    percent = ctx.clamp(tonumber(percent) or 0, 0, 100)
    if percent <= 0 then return false end
    return ctx.nextRandom(10000, stream) <= math.floor(percent * 100)
  end

  function ctx.pick(rows, stream)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    return rows[ctx.nextRandom(#rows, stream)]
  end

  function ctx.weightedPick(rows, stream)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local total = 0
    for _, row in ipairs(rows) do total = total + math.max(0, tonumber(row.weight) or 0) end
    if total <= 0 then return nil end
    local roll = ctx.nextRandom(math.max(1, math.floor(total * 100)), stream) / 100
    for _, row in ipairs(rows) do
      roll = roll - math.max(0, tonumber(row.weight) or 0)
      if roll <= 0 then return row.value or row.def or row end
    end
    return rows[#rows].value or rows[#rows].def or rows[#rows]
  end

  function ctx.registerCondition(id, fn)
    assert(type(id) == "string" and type(fn) == "function")
    ctx.conditionDefs[id] = fn
  end

  function ctx.checkCondition(spec, env)
    if spec == nil then return true end
    if type(spec) == "boolean" then return spec end
    if type(spec) == "function" then
      local ok, value = pcall(spec, env)
      return ok and value ~= false
    end
    if type(spec) == "string" then
      local fn = ctx.conditionDefs[spec]
      if not fn then return false end
      local ok, value = pcall(fn, env or {})
      return ok and value ~= false
    end
    if type(spec) ~= "table" then return false end
    if spec.all then
      for _, child in ipairs(spec.all) do if not ctx.checkCondition(child, env) then return false end end
      return true
    end
    if spec.any then
      for _, child in ipairs(spec.any) do if ctx.checkCondition(child, env) then return true end end
      return false
    end
    if spec["not"] then return not ctx.checkCondition(spec["not"], env) end
    local id = spec.id or spec.condition
    local fn = id and ctx.conditionDefs[id] or nil
    if not fn then return false end
    local ok, value = pcall(fn, env or {}, spec)
    return ok and value ~= false
  end

  function ctx.registerEffect(id, fn)
    assert(type(id) == "string" and type(fn) == "function")
    ctx.effectDefs[id] = fn
  end

  function ctx.runEffect(spec, env)
    if type(spec) == "function" then return pcall(spec, env or {}) end
    if type(spec) == "string" then spec = { id = spec } end
    if type(spec) ~= "table" then return false, "invalid effect" end
    local fn = ctx.effectDefs[spec.id or spec.effect]
    if not fn then return false, "unknown effect" end
    return pcall(fn, env or {}, spec)
  end

  function ctx.runEffects(specs, env)
    if specs == nil then return true end
    if specs.id or specs.effect then specs = { specs } end
    for _, spec in ipairs(specs) do
      local ok, result = ctx.runEffect(spec, env)
      if not ok then return false, result end
    end
    return true
  end

  function ctx.hasMutation(id)
    local active = ctx.getTable("run_mutations")
    for _, value in ipairs(active) do if value == id then return true end end
    return false
  end

  function ctx.registerMutation(id, def)
    assert(type(id) == "string" and type(def) == "table")
    def.id = id
    ctx.mutationDefs[id] = def
  end

  local function mutationCompatible(def, selected)
    local incompatible = {}
    for _, id in ipairs(def.incompatible or {}) do incompatible[id] = true end
    for _, selectedId in ipairs(selected) do
      local other = ctx.mutationDefs[selectedId]
      if incompatible[selectedId] then return false end
      if other then
        for _, id in ipairs(other.incompatible or {}) do if id == def.id then return false end end
      end
    end
    return true
  end

  function ctx.ensureRunMutations()
    if not ctx.feature("anti_randomizer") then return {} end
    local active = ctx.getTable("run_mutations")
    if #active > 0 then return active end

    local pool = {}
    for id, def in pairs(ctx.mutationDefs) do
      if def.enabled ~= false then pool[#pool + 1] = { id = id, def = def } end
    end
    table.sort(pool, function(a, b) return a.id < b.id end)

    while #active < 3 and #pool > 0 do
      local weighted = {}
      for _, row in ipairs(pool) do
        if mutationCompatible(row.def, active) then
          weighted[#weighted + 1] = { value = row, weight = tonumber(row.def.weight) or 1 }
        end
      end
      local selected = ctx.weightedPick(weighted, "mutations")
      if not selected then break end
      active[#active + 1] = selected.id
      for i = #pool, 1, -1 do if pool[i].id == selected.id then table.remove(pool, i) end end
    end
    ctx.putTable("run_mutations", active)
    return active
  end

  function ctx.mutationModifier(key, base)
    local value = tonumber(base) or 0
    for _, id in ipairs(ctx.ensureRunMutations()) do
      local def = ctx.mutationDefs[id]
      local modifiers = def and def.modifiers
      if modifiers and modifiers[key] ~= nil then value = value + (tonumber(modifiers[key]) or 0) end
    end
    return value
  end

  function ctx.adjustMoodPressure(amount, source)
    if not ctx.feature("luck") then return 0 end
    local state = mod.save:get("mood_state", {})
    if type(state) ~= "table" then state = {} end
    state.pressure = ctx.clamp((tonumber(state.pressure) or 0) + (tonumber(amount) or 0), -100, 100)
    state.causes = type(state.causes) == "table" and state.causes or {}
    state.causes[#state.causes + 1] = {
      source = source or "unknown", amount = tonumber(amount) or 0, step = ctx.runtime.steps,
    }
    while #state.causes > 12 do table.remove(state.causes, 1) end
    mod.save:set("mood_state", state)
    return state.pressure
  end

  local function chooseMood(pressure)
    local weighted = {}
    for id, def in pairs(ctx.moodDefs) do
      local weight = tonumber(def.weight) or 1
      if id == "LUCKY" then weight = weight + math.max(0, pressure) / 15 end
      if id == "RESTLESS" then weight = weight + math.max(0, -pressure) / 18 end
      if id == "STRANGE" and ctx.hasMutation("ODD_SPECIMENS") then weight = weight + 1.5 end
      weighted[#weighted + 1] = { value = id, weight = math.max(0.1, weight) }
    end
    return ctx.weightedPick(weighted, "moods") or "QUIET"
  end

  function ctx.worldMoodState()
    if not ctx.feature("luck") then
      return { id = "QUIET", intensity = 1, pressure = 0, expiresAt = math.huge, causes = {} }
    end
    local state = mod.save:get("mood_state", {})
    if type(state) ~= "table" then state = {} end
    local expired = not state.id or ctx.runtime.steps >= (tonumber(state.expiresAt) or 0)
    if expired then
      local pressure = tonumber(state.pressure) or 0
      local id = chooseMood(pressure)
      state.id = id
      state.intensity = ctx.clamp(1 + math.floor(math.abs(pressure) / 35), 1, 3)
      state.startedAt = ctx.runtime.steps
      state.expiresAt = ctx.runtime.steps + 512 + ctx.nextRandom(384, "moods")
      state.pressure = pressure * 0.45
      state.causes = type(state.causes) == "table" and state.causes or {}
      mod.save:set("mood_state", state)
      mod.save:set("world_mood", id)
      mod.save:set("mood_expires", state.expiresAt)
    end
    return state
  end

  function ctx.worldMood()
    return ctx.worldMoodState().id or "QUIET"
  end

  function ctx.moodModifier(key)
    local state = ctx.worldMoodState()
    local def = ctx.moodDefs[state.id] or ctx.moodDefs.QUIET
    local base = tonumber(def.modifiers and def.modifiers[key]) or 0
    return base * math.max(1, tonumber(state.intensity) or 1)
  end

  -- Shared semantic time-of-day. Gen 1 has no native clock, so the expansion
  -- owns a 24-hour Kanto clock. Later generations keep their native clock.
  function ctx.currentHour()
    if not ctx.feature("night_cycle") then return 12 end

    if mod.generation ~= 1 then
      local game = ctx.runtime.game
      local world = game and game.world
      local hour = world and (world.hour or world.clockHour)
      return tonumber(hour)
    end

    local source = mod.options:get("night_time_source") or "REAL_TIME"
    if source == "REAL_TIME" then
      local now = os.date("*t")
      return ((tonumber(now.hour) or 12)
        + (tonumber(now.min) or 0) / 60
        + (tonumber(now.sec) or 0) / 3600) % 24
    end
    if source == "FIXED_DAY" then return 12 end
    if source == "FIXED_NIGHT" then return 0 end

    local length = math.max(256, tonumber(mod.options:get("night_cycle_preset")) or 1024)
    local cycleSteps = length * 2
    return ((ctx.runtime.steps % cycleSteps) / cycleSteps * 24 + 6) % 24
  end

  function ctx.currentTod()
    if not ctx.feature("night_cycle") then return "DAY" end

    if mod.generation ~= 1 then
      local game = ctx.runtime.game
      local world = game and game.world
      local native = world and (world.tod or world.daytime)
      if native == "NITE" then return "NIGHT" end
      if native == "MORN" then return "MORNING" end
      return native or "DAY"
    end

    local hour = ctx.currentHour() or 12
    return (hour >= 18 or hour < 6) and "NIGHT" or "DAY"
  end

  ctx.currentTodFromSteps = ctx.currentTod

  function ctx.timeInRange(startHour, endHour)
    local hour = ctx.currentHour() or 12
    startHour, endHour = tonumber(startHour) or 0, tonumber(endHour) or 24
    if startHour <= endHour then return hour >= startHour and hour < endHour end
    return hour >= startHour or hour < endHour
  end

  function ctx.registerDirectorEvent(def)
    assert(type(def) == "table" and type(def.run) == "function",
      "director event requires a run function")
    def.id = def.id or ("director_" .. tostring(#ctx.directorDefs + 1))
    def.category = def.category or "WORLD"
    def.cost = math.max(1, tonumber(def.cost) or 20)
    def.cooldown = math.max(0, tonumber(def.cooldown) or 180)
    ctx.directorDefs[#ctx.directorDefs + 1] = def
    return def.id
  end

  local function directorBudget()
    local state = mod.save:get("director_budget", {})
    if type(state) ~= "table" then state = {} end
    local last = tonumber(state.lastStep) or ctx.runtime.steps
    local delta = math.max(0, ctx.runtime.steps - last)
    state.value = ctx.clamp((tonumber(state.value) or 70) + delta / 8, 0, 100)
    state.lastStep = ctx.runtime.steps
    mod.save:set("director_budget", state)
    return state
  end

  function ctx.reserveDirectorEvent(id, constraints)
    mod.save:set("director_reservation", {
      id = id,
      constraints = type(constraints) == "table" and constraints or {},
      createdAt = ctx.runtime.steps,
    })
  end

  function ctx.suppressDirectorCategory(category, duration)
    local suppressed = ctx.getTable("director_suppressed")
    suppressed[tostring(category)] = ctx.runtime.steps + math.max(0, tonumber(duration) or 0)
    ctx.putTable("director_suppressed", suppressed)
  end

  local function directorEventById(id)
    for _, def in ipairs(ctx.directorDefs) do if def.id == id then return def end end
  end

  local function directorEligible(def, reason)
    local suppressed = ctx.getTable("director_suppressed")
    if ctx.runtime.steps < (tonumber(suppressed[def.category]) or -1) then return false end

    local cooldowns = ctx.getTable("director_event_cooldowns")
    if ctx.runtime.steps < (tonumber(cooldowns[def.id]) or -1) then return false end

    if type(def.reasons) == "table" then
      local allowed = false
      for _, value in ipairs(def.reasons) do if value == reason then allowed = true break end end
      if not allowed then return false end
    end
    if def.condition and not ctx.checkCondition(def.condition, {
      game = ctx.runtime.game, mapId = ctx.runtime.currentMap, reason = reason,
    }) then return false end
    if type(def.eligible) == "function" then
      local success, result = pcall(def.eligible, ctx.runtime.game, ctx.runtime.currentMap, reason)
      if not success or result == false then return false end
    end
    return true
  end

  local function reservationMatches(reservation, reason)
    if type(reservation) ~= "table" or not reservation.id then return false end
    local c = type(reservation.constraints) == "table" and reservation.constraints or {}
    if c.reason and c.reason ~= reason then return false end
    if c.mapId and c.mapId ~= ctx.runtime.currentMap then return false end
    if c.tod and c.tod ~= ctx.currentTod() then return false end
    if c.afterStep and ctx.runtime.steps < tonumber(c.afterStep) then return false end
    return true
  end

  local function runDirectorDef(def, reason, budget)
    local ok, result = pcall(def.run, ctx.runtime.game, ctx.runtime.currentMap, reason)
    if not ok or result == false then return false end

    budget.value = math.max(0, budget.value - (tonumber(def.cost) or 20))
    mod.save:set("director_budget", budget)
    mod.save:set("last_director_step", ctx.runtime.steps)
    mod.save:set("last_director_event", def.id)

    local cooldowns = ctx.getTable("director_event_cooldowns")
    cooldowns[def.id] = ctx.runtime.steps + (tonumber(def.cooldown) or 180)
    ctx.putTable("director_event_cooldowns", cooldowns)

    local history = ctx.getTable("director_history")
    history[#history + 1] = {
      id = def.id, category = def.category, step = ctx.runtime.steps,
      mapId = ctx.runtime.currentMap, reason = reason,
    }
    while #history > 10 do table.remove(history, 1) end
    ctx.putTable("director_history", history)
    return true
  end

  function ctx.directorStatus()
    local budget = directorBudget()
    return {
      budget = budget.value,
      lastEvent = mod.save:get("last_director_event"),
      history = ctx.getTable("director_history"),
      reservation = mod.save:get("director_reservation"),
    }
  end

  function ctx.runDirector(reason)
    if not ctx.feature("director") then return false end
    local globalCooldown = ctx.hasMutation("GOSSIP_CHAIN") and 150 or 180
    local last = tonumber(mod.save:get("last_director_step", -999999)) or -999999
    if ctx.runtime.steps - last < globalCooldown then return false end

    local chance = reason == "map" and 35 or 18
    chance = ctx.clamp(chance * (1 + ctx.moodModifier("director_weight")), 2, 80)
    if not ctx.chance(chance, "director_gate") then return false end

    local budget = directorBudget()
    local reservation = mod.save:get("director_reservation")
    if reservationMatches(reservation, reason) then
      local reserved = directorEventById(reservation.id)
      if reserved and directorEligible(reserved, reason) and reserved.cost <= budget.value then
        if runDirectorDef(reserved, reason, budget) then
          mod.save:set("director_reservation", nil)
          return true
        end
      end
    end

    local history = ctx.getTable("director_history")
    local recentCategory = history[#history] and history[#history].category or nil
    local eligible = {}
    for _, def in ipairs(ctx.directorDefs) do
      if def.cost <= budget.value and directorEligible(def, reason) then
        local weight = math.max(0.1, tonumber(def.weight) or 1)
        if def.category == recentCategory then weight = weight * 0.45 end
        if def.category == "RUMOR" then weight = weight * (1 + ctx.moodModifier("rumor_weight")) end
        if def.category == "STRANGE" then weight = weight * (1 + ctx.moodModifier("strange_weight")) end
        eligible[#eligible + 1] = { value = def, weight = math.max(0.1, weight) }
      end
    end
    local selected = ctx.weightedPick(eligible, "director_pick")
    if not selected then return false end
    return runDirectorDef(selected, reason, budget)
  end

  mod.events:on("game.ready", function(ev)
    ctx.runtime.game = ev.game
    ctx.runMigrations()
    if type(ctx.reconcilePokemonIdentity) == "function" then
      pcall(ctx.reconcilePokemonIdentity, ev.game)
    end
  end)

  mod.events:on("save.loaded", function()
    ctx.runMigrations()
    if type(ctx.reconcilePokemonIdentity) == "function" then
      pcall(ctx.reconcilePokemonIdentity, ctx.runtime.game)
    end
  end)

  return ctx
end
