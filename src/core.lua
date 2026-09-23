local PERSONALITIES = {
  "BRAVE", "CAUTIOUS", "SHOW-OFF", "CURIOUS", "STUBBORN",
  "LUCKY", "SLEEPY", "MISCHIEVOUS", "LOYAL", "DRAMATIC",
}

local MOODS = { "QUIET", "LUCKY", "RESTLESS", "STRANGE" }

local MUTATION_POOL = {
  "HARDENED_TRAINERS",
  "WILD_SURGE",
  "NIGHT_OWLS",
  "GOSSIP_CHAIN",
  "ROCKET_NERVES",
  "ODD_SPECIMENS",
}

return function(mod)
  local ctx = {
    MON_FIELD = "gen1Expansion",
    SCREEN_ID = "Gen1ExpansionStatus",
    personalities = PERSONALITIES,
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

  function ctx.nextRandom(max)
    max = math.max(1, math.floor(max or 1))
    local state = tonumber(mod.save:get("rng_state", 1297695540)) or 1297695540
    state = (state * 1103515245 + 12345) % 2147483648
    mod.save:set("rng_state", state)
    return (state % max) + 1
  end

  function ctx.chance(percent)
    percent = ctx.clamp(tonumber(percent) or 0, 0, 100)
    if percent <= 0 then return false end
    return ctx.nextRandom(10000) <= math.floor(percent * 100)
  end

  function ctx.pick(rows)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    return rows[ctx.nextRandom(#rows)]
  end

  function ctx.hasMutation(id)
    local active = ctx.getTable("run_mutations")
    for _, value in ipairs(active) do
      if value == id then return true end
    end
    return false
  end

  function ctx.ensureRunMutations()
    if not ctx.feature("anti_randomizer") then return {} end
    local active = ctx.getTable("run_mutations")
    if #active > 0 then return active end
    local pool = ctx.cloneArray(MUTATION_POOL)
    while #active < 3 and #pool > 0 do
      local index = ctx.nextRandom(#pool)
      active[#active + 1] = table.remove(pool, index)
    end
    ctx.putTable("run_mutations", active)
    return active
  end

  function ctx.worldMood()
    if not ctx.feature("luck") then return "QUIET" end
    local expires = tonumber(mod.save:get("mood_expires", 0)) or 0
    local mood = mod.save:get("world_mood")
    if not mood or ctx.runtime.steps >= expires then
      mood = ctx.pick(MOODS) or "QUIET"
      mod.save:set("world_mood", mood)
      mod.save:set("mood_expires", ctx.runtime.steps + 512 + ctx.nextRandom(384))
    end
    return mood
  end

  -- Shared semantic time-of-day. Gen 1 has no native clock, so the expansion
  -- supplies one from steps. Later generations should use the target game's
  -- native world time instead of inventing a second clock.
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

    local length = math.max(256, tonumber(mod.options:get("night_cycle_preset")) or 1024)
    return (math.floor(ctx.runtime.steps / length) % 2 == 0) and "DAY" or "NIGHT"
  end

  -- Compatibility alias for the initial framework name. New code should use
  -- currentTod(), since only Gen 1 derives the answer from steps.
  ctx.currentTodFromSteps = ctx.currentTod

  function ctx.registerDirectorEvent(def)
    assert(type(def) == "table" and type(def.run) == "function",
      "director event requires a run function")
    ctx.directorDefs[#ctx.directorDefs + 1] = def
    return def.id
  end

  function ctx.runDirector(reason)
    if not ctx.feature("director") then return false end
    local cooldown = ctx.hasMutation("GOSSIP_CHAIN") and 220 or 180
    local last = tonumber(mod.save:get("last_director_step", -999999)) or -999999
    if ctx.runtime.steps - last < cooldown then return false end
    if reason == "step" and not ctx.chance(18) then return false end
    if reason == "map" and not ctx.chance(35) then return false end

    local eligible, total = {}, 0
    for _, def in ipairs(ctx.directorDefs) do
      local ok = true
      if type(def.eligible) == "function" then
        local success, result = pcall(def.eligible, ctx.runtime.game, ctx.runtime.currentMap)
        ok = success and result ~= false
      end
      if ok then
        local weight = math.max(1, tonumber(def.weight) or 1)
        eligible[#eligible + 1] = { def = def, weight = weight }
        total = total + weight
      end
    end
    if total <= 0 then return false end

    local roll = ctx.nextRandom(total)
    local selected
    for _, row in ipairs(eligible) do
      roll = roll - row.weight
      if roll <= 0 then selected = row.def; break end
    end
    if not selected then return false end
    local ok, result = pcall(selected.run, ctx.runtime.game, ctx.runtime.currentMap, reason)
    if ok and result ~= false then
      mod.save:set("last_director_step", ctx.runtime.steps)
      mod.save:set("last_director_event", selected.id)
      return true
    end
    return false
  end

  return ctx
end
