local DEFAULT_RUMORS = {
  { id = "restless_routes", text = "People say the routes have felt unusually restless lately.", duration = 420 },
  { id = "rocket_whispers", text = "There are whispers that Team Rocket is keeping tabs on certain trainers.", duration = 520, minHeat = 4 },
  { id = "odd_wilds", text = "A fisherman swears the wild Pokemon are acting strangely today.", duration = 360 },
  { id = "false_alarm", text = "Someone claims a rare Pokemon was seen nearby. Nobody agrees where.", duration = 300 },
}

local DEFAULT_TIPS = {
  "Locals insist the next town is somewhere beyond here.",
  "A sign used to point north. Or maybe south.",
  "The safest shortcut is usually the one nobody recommends.",
  "Someone nearby is very confident and completely wrong about directions.",
  "If the road looks suspiciously convenient, it probably leads somewhere.",
}

local DEFAULT_BULLETINS = {
  "TRAINER NOTICE: Please stop challenging strangers inside doorways.",
  "PUBLIC NOTICE: Do not feed unattended Diglett.",
  "MISSING: One perfectly ordinary Pokeball. Probably.",
  "LOCAL NEWS: Young trainer claims shorts remain comfortable and easy to wear.",
  "SAFETY NOTICE: Caves may contain rocks, bats, and regrettable decisions.",
}

return function(mod, ctx)
  for _, def in ipairs(DEFAULT_RUMORS) do ctx.rumorDefs[#ctx.rumorDefs + 1] = def end
  for _, text in ipairs(DEFAULT_BULLETINS) do ctx.bulletinDefs[#ctx.bulletinDefs + 1] = { text = text } end

  local function rumorEligible(def)
    if type(def) ~= "table" then return false end
    if def.minHeat and ctx.getHeat() < def.minHeat then return false end
    if def.mapId and ctx.runtime.currentMap and def.mapId ~= ctx.runtime.currentMap then return false end
    if type(def.eligible) == "function" then
      local ok, result = pcall(def.eligible, ctx.runtime.game, ctx.runtime.currentMap)
      return ok and result ~= false
    end
    return true
  end

  function ctx.activateRumor(def)
    if type(def) ~= "table" then return nil end
    local duration = tonumber(def.duration) or 384
    if ctx.hasMutation("GOSSIP_CHAIN") then duration = math.floor(duration * 1.5) end
    local active = {
      id = def.id or ("rumor_" .. tostring(ctx.nextRandom(999999))),
      text = def.text or "Something odd is being discussed around Kanto.",
      mapId = def.mapId,
      species = def.species,
      replacementSpecies = def.replacementSpecies,
      encounterChance = def.encounterChance,
      startedAt = ctx.runtime.steps,
      expiresAt = ctx.runtime.steps + duration,
    }
    mod.save:set("active_rumor", active)
    return active
  end

  function ctx.currentRumor()
    local active = mod.save:get("active_rumor")
    if type(active) ~= "table" then return nil end
    if ctx.runtime.steps >= (tonumber(active.expiresAt) or 0) then
      mod.save:set("active_rumor", nil)
      return nil
    end
    return active
  end

  function ctx.chooseRumor()
    if not ctx.feature("rumors") or ctx.currentRumor() then return nil end
    local eligible = {}
    for _, def in ipairs(ctx.rumorDefs) do
      if rumorEligible(def) then eligible[#eligible + 1] = def end
    end
    return ctx.activateRumor(ctx.pick(eligible))
  end

  function ctx.chooseTip()
    local tip = ctx.pick(DEFAULT_TIPS)
    mod.save:set("current_tip", tip)
    return tip
  end

  function ctx.currentBulletin()
    local context = {
      heat = ctx.getHeat(), mood = ctx.worldMood(), mapId = ctx.runtime.currentMap,
      reputation = ctx.reputation(),
    }
    local eligible = {}
    for _, def in ipairs(ctx.bulletinDefs) do
      local ok = true
      if type(def.eligible) == "function" then
        local success, result = pcall(def.eligible, context)
        ok = success and result ~= false
      end
      if ok then eligible[#eligible + 1] = def end
    end
    local def = ctx.pick(eligible)
    if not def then return nil end
    if type(def.text) == "function" then
      local ok, text = pcall(def.text, context)
      return ok and text or nil
    end
    return def.text
  end

  function ctx.ecologyPressure(mapId, species)
    local ecology = ctx.getTable("ecology_pressure")
    local byMap = ecology[mapId]
    if type(byMap) ~= "table" then return 0 end
    return tonumber(byMap[species]) or 0
  end

  function ctx.addEcologyPressure(mapId, species, amount)
    if not ctx.feature("ecology") or not mapId or not species then return end
    local ecology = ctx.getTable("ecology_pressure")
    local byMap = ecology[mapId]
    if type(byMap) ~= "table" then byMap = {}; ecology[mapId] = byMap end
    byMap[species] = (tonumber(byMap[species]) or 0) + (amount or 1)
    ctx.putTable("ecology_pressure", ecology)
  end

  local function applyReplacementRules(enc, hookCtx, ruleBook)
    if type(enc) ~= "table" or not hookCtx or not hookCtx.mapId then return enc end
    local mapRules = ruleBook[hookCtx.mapId]
    if type(mapRules) ~= "table" then return enc end
    local rule = mapRules[enc.species]
    if type(rule) ~= "table" then return enc end
    if ruleBook == ctx.ecologyRules then
      local threshold = tonumber(rule.threshold) or 0
      if ctx.ecologyPressure(hookCtx.mapId, enc.species) < threshold then return enc end
    end
    if not ctx.chance(tonumber(rule.chance) or 25) then return enc end
    return { species = rule.replacement or enc.species, level = enc.level }
  end

  local function anomalyRate()
    local rate = tonumber(mod.options:get("anomaly_rate")) or 2
    if ctx.worldMood() == "RESTLESS" then rate = rate + 2 end
    if ctx.hasMutation("ODD_SPECIMENS") then rate = rate + 2 end
    if ctx.hasMutation("NIGHT_OWLS") and ctx.currentTod() == "NIGHT" then rate = rate + 2 end
    return ctx.clamp(rate, 0, 30)
  end

  mod.hooks:wrap("encounter.species", function(next, enc, hookCtx)
    local rolled = next(enc, hookCtx)
    if not ctx.feature() or type(rolled) ~= "table" then return rolled end
    local out = { species = rolled.species, level = rolled.level }

    local rumor = ctx.currentRumor()
    if ctx.feature("rumors") and rumor and rumor.replacementSpecies
      and (not rumor.mapId or rumor.mapId == (hookCtx and hookCtx.mapId))
      and ctx.chance(tonumber(rumor.encounterChance) or 8) then
      out.species = rumor.replacementSpecies
    end

    if ctx.feature("night_cycle") and ctx.currentTod() == "NIGHT" then
      out = applyReplacementRules(out, hookCtx, ctx.nightRules)
    end
    if ctx.feature("ecology") then out = applyReplacementRules(out, hookCtx, ctx.ecologyRules) end
    if ctx.hasMutation("WILD_SURGE") then
      out.level = ctx.clamp((tonumber(out.level) or 1) + 1, 1, 100)
    end
    if ctx.feature("wild_anomalies") and ctx.chance(anomalyRate()) then
      out.level = ctx.clamp((tonumber(out.level) or 1) + 2, 1, 100)
      ctx.runtime.lastWildAnomaly = {
        mapId = hookCtx and hookCtx.mapId, species = out.species,
        level = out.level, atStep = ctx.runtime.steps,
      }
      ctx.addCounter("wild_anomalies", 1)
    end
    return out
  end)

  mod.hooks:wrap("world.tod", function(next, tod, hookCtx)
    local base = next(tod, hookCtx)
    -- Gold/Gen 2 already owns a real MORN/DAY/NITE clock and palette system.
    -- Never replace that with Gen 1's synthetic step clock.
    if mod.generation ~= 1 then return base end
    if not ctx.feature("night_cycle") then return base end
    if base ~= nil and base ~= "DAY" then return base end
    return ctx.currentTod()
  end)

  ctx.registerDirectorEvent({
    id = "rumor", weight = 4,
    eligible = function() return ctx.feature("rumors") and ctx.currentRumor() == nil end,
    run = function() return ctx.chooseRumor() ~= nil end,
  })
  ctx.registerDirectorEvent({ id = "tip", weight = 3, run = function() ctx.chooseTip(); return true end })
  ctx.registerDirectorEvent({
    id = "mood", weight = 2,
    eligible = function() return ctx.feature("luck") end,
    run = function() mod.save:set("mood_expires", 0); ctx.worldMood(); return true end,
  })
  ctx.registerDirectorEvent({
    id = "bulletin", weight = 2,
    run = function()
      local text = ctx.currentBulletin()
      if text then mod.save:set("current_bulletin", text) end
      return text ~= nil
    end,
  })
  ctx.registerDirectorEvent({
    id = "legend_whisper", weight = 1,
    run = function()
      local undiscovered = {}
      local states = ctx.getTable("urban_legends")
      for id in pairs(ctx.legendDefs) do
        if type(states[id]) ~= "table" or not states[id].discovered then undiscovered[#undiscovered + 1] = id end
      end
      local id = ctx.pick(undiscovered)
      if not id then return false end
      ctx.activateLegend(id, 1)
      return true
    end,
  })

  mod.events:on("game.ready", function(ev)
    ctx.runtime.game = ev.game
    ctx.runtime.steps = tonumber(mod.save:get("step_count", 0)) or 0
    ctx.ensureRunMutations()
    ctx.worldMood()
    ctx.updateTravelers()
    if not mod.save:get("current_tip") then ctx.chooseTip() end
    if not mod.save:get("current_bulletin") then mod.save:set("current_bulletin", ctx.currentBulletin()) end
    mod.save:set("framework_version", mod.version)
  end)

  mod.events:on("map.entered", function(ev)
    ctx.runtime.currentMap = ev.mapId
    local visits = ctx.getTable("map_visits")
    visits[ev.mapId] = (visits[ev.mapId] or 0) + 1
    ctx.putTable("map_visits", visits)
    mod.save:set("last_map", ev.mapId)
    mod.save:set("step_count", ctx.runtime.steps)
    ctx.updateTravelers()
    if ctx.chance(28) then ctx.chooseTip() end
    if ctx.chance(35) then
      local bulletin = ctx.currentBulletin()
      if bulletin then mod.save:set("current_bulletin", bulletin) end
    end
    ctx.worldMood()
    ctx.runDirector("map")
  end)

  mod.events:on("world.stepped", function()
    ctx.runtime.steps = ctx.runtime.steps + 1
    if ctx.runtime.steps % 32 == 0 then mod.save:set("step_count", ctx.runtime.steps) end
    if ctx.runtime.steps % 96 == 0 then ctx.worldMood() end
    if ctx.runtime.steps % 128 == 0 then ctx.runDirector("step") end
  end)

  mod.events:on("world.interacted", function(ev)
    ctx.bumpReputation("interactions", 1)
    if ev.kind == "npc" and type(ev.target) == "table" and ev.target.id then
      local interactions = ctx.getTable("npc_interactions")
      interactions[ev.target.id] = (interactions[ev.target.id] or 0) + 1
      ctx.putTable("npc_interactions", interactions)
    end
  end)

  mod.events:on("world.blacked_out", function() ctx.bumpReputation("blackouts", 1) end)
  mod.events:on("flag.changed", function() ctx.bumpReputation("story_changes", 1) end)
  mod.events:on("world.tod_changed", function(ev) mod.save:set("last_tod", ev.tod) end)
end
