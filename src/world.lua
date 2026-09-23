local DEFAULT_RUMORS = {
  { id = "restless_routes", text = "People say the routes have felt unusually restless lately.", duration = 420, credibility = 0.65, category = "WORLD" },
  { id = "rocket_whispers", text = "There are whispers that Team Rocket is keeping tabs on certain trainers.", duration = 520, minHeat = 4, credibility = 0.75, category = "ROCKET" },
  { id = "odd_wilds", text = "A fisherman swears the wild Pokemon are acting strangely today.", duration = 360, credibility = 0.55, category = "WILD" },
  { id = "false_alarm", text = "Someone claims a rare Pokemon was seen nearby. Nobody agrees where.", duration = 300, credibility = 0.30, truth = "FALSE", category = "WILD" },
}

local DEFAULT_TIPS = {
  { text = "Locals insist the next town is somewhere beyond here.", truth = "VAGUE", topic = "travel" },
  { text = "A sign used to point north. Or maybe south.", truth = "UNCERTAIN", topic = "directions" },
  { text = "The safest shortcut is usually the one nobody recommends.", truth = "UNCERTAIN", topic = "shortcut" },
  { text = "Someone nearby is very confident and completely wrong about directions.", truth = "FALSE", topic = "directions" },
  { text = "If the road looks suspiciously convenient, it probably leads somewhere.", truth = "VAGUE", topic = "travel" },
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

  -- Rumors ------------------------------------------------------------------
  local function rumorEligible(def)
    if type(def) ~= "table" then return false end
    if def.minHeat and ctx.getHeat() < def.minHeat then return false end
    if def.maxHeat and ctx.getHeat() > def.maxHeat then return false end
    if def.mapId and ctx.runtime.currentMap and def.mapId ~= ctx.runtime.currentMap then return false end
    if def.tod and def.tod ~= ctx.currentTod() then return false end
    if def.condition and not ctx.checkCondition(def.condition, {
      game = ctx.runtime.game, mapId = ctx.runtime.currentMap, rumor = def,
    }) then return false end
    if type(def.eligible) == "function" then
      local ok, result = pcall(def.eligible, ctx.runtime.game, ctx.runtime.currentMap)
      return ok and result ~= false
    end
    return true
  end

  function ctx.activeRumors(mapId)
    local rows = ctx.getTable("active_rumors")
    local out, changed = {}, false
    mapId = mapId or ctx.runtime.currentMap
    for _, rumor in ipairs(rows) do
      local expired = ctx.runtime.steps >= (tonumber(rumor.expiresAt) or math.huge)
      if expired then
        changed = true
      elseif rumor.status ~= "RESOLVED" and rumor.status ~= "DISPROVEN" then
        if not rumor.mapId or not mapId or rumor.mapId == mapId
          or (type(rumor.heardMaps) == "table" and rumor.heardMaps[mapId]) then
          out[#out + 1] = rumor
        end
      end
    end
    if changed then
      local kept = {}
      for _, rumor in ipairs(rows) do
        if ctx.runtime.steps < (tonumber(rumor.expiresAt) or math.huge) then kept[#kept + 1] = rumor end
      end
      ctx.putTable("active_rumors", kept)
    end
    table.sort(out, function(a, b)
      local as = tonumber(a.strength) or 1
      local bs = tonumber(b.strength) or 1
      if as == bs then return (tonumber(a.startedAt) or 0) > (tonumber(b.startedAt) or 0) end
      return as > bs
    end)
    return out
  end

  function ctx.activateRumor(def, opts)
    if type(def) ~= "table" then return nil end
    opts = type(opts) == "table" and opts or {}
    local duration = tonumber(opts.duration or def.duration) or 384
    if ctx.hasMutation("GOSSIP_CHAIN") then duration = math.floor(duration * 1.5) end
    local active = {
      id = def.id or ("rumor_" .. tostring(ctx.nextRandom(999999, "rumors"))),
      text = def.text or "Something odd is being discussed around Kanto.",
      category = def.category or "WORLD",
      source = opts.source or def.source or "word_of_mouth",
      subject = def.subject,
      mapId = opts.mapId or def.mapId,
      species = def.species,
      replacementSpecies = def.replacementSpecies,
      encounterChance = def.encounterChance,
      credibility = ctx.clamp(tonumber(opts.credibility or def.credibility) or 0.5, 0, 1),
      strength = ctx.clamp(tonumber(opts.strength or def.strength) or 1, 0.1, 5),
      distortionChance = ctx.clamp(tonumber(def.distortionChance) or 0.15, 0, 1),
      truth = def.truth or "UNKNOWN",
      status = "ACTIVE",
      heardMaps = {},
      startedAt = ctx.runtime.steps,
      expiresAt = ctx.runtime.steps + duration,
      payload = type(def.payload) == "table" and ctx.cloneTable(def.payload) or nil,
    }
    if active.mapId then active.heardMaps[active.mapId] = { step = ctx.runtime.steps, credibility = active.credibility } end
    local rows = ctx.getTable("active_rumors")
    rows[#rows + 1] = active
    while #rows > 6 do table.remove(rows, 1) end
    ctx.putTable("active_rumors", rows)
    mod.save:set("active_rumor", active) -- compatibility mirror
    return active
  end

  function ctx.currentRumor(mapId)
    return ctx.activeRumors(mapId)[1]
  end

  function ctx.resolveRumor(id, resolution)
    local rows = ctx.getTable("active_rumors")
    for _, rumor in ipairs(rows) do
      if rumor.id == id then
        rumor.status = (resolution == "FALSE" or resolution == "DISPROVEN") and "DISPROVEN" or "RESOLVED"
        rumor.resolution = resolution or "RESOLVED"
        rumor.resolvedAt = ctx.runtime.steps
        ctx.putTable("active_rumors", rows)
        return rumor
      end
    end
  end

  function ctx.spreadRumors(mapId)
    if not mapId then return end
    local rows = ctx.getTable("active_rumors")
    local changed = false
    for _, rumor in ipairs(rows) do
      if rumor.status == "ACTIVE" and ctx.runtime.steps < (tonumber(rumor.expiresAt) or 0) then
        rumor.heardMaps = type(rumor.heardMaps) == "table" and rumor.heardMaps or {}
        if not rumor.heardMaps[mapId] then
          local spreadChance = ctx.clamp(25 + (tonumber(rumor.strength) or 1) * 10, 5, 80)
          spreadChance = spreadChance * (1 + ctx.moodModifier("rumor_weight"))
          if ctx.hasMutation("GOSSIP_CHAIN") then spreadChance = spreadChance + 20 end
          if ctx.chance(spreadChance, "rumor_spread") then
            local inherited = rumor.credibility * 0.88
            local distorted = ctx.chance((rumor.distortionChance or 0) * 100, "rumor_distortion")
            if distorted then inherited = inherited * 0.75 end
            rumor.heardMaps[mapId] = {
              step = ctx.runtime.steps,
              credibility = inherited,
              distorted = distorted,
            }
            rumor.strength = math.max(0.1, (tonumber(rumor.strength) or 1) - 0.05)
            changed = true
          end
        end
      end
    end
    if changed then ctx.putTable("active_rumors", rows) end
  end

  function ctx.chooseRumor()
    if not ctx.feature("rumors") or #ctx.activeRumors() >= 3 then return nil end
    local eligible = {}
    for _, def in ipairs(ctx.rumorDefs) do if rumorEligible(def) then eligible[#eligible + 1] = def end end
    return ctx.activateRumor(ctx.pick(eligible, "rumors"))
  end

  ctx.registerMigration(4, function()
    local rows = ctx.getTable("active_rumors")
    if #rows == 0 then
      local legacy = mod.save:get("active_rumor")
      if type(legacy) == "table" then
        legacy.status = legacy.status or "ACTIVE"
        legacy.credibility = tonumber(legacy.credibility) or 0.5
        legacy.strength = tonumber(legacy.strength) or 1
        legacy.heardMaps = type(legacy.heardMaps) == "table" and legacy.heardMaps or {}
        rows[1] = legacy
        ctx.putTable("active_rumors", rows)
      end
    end
  end)

  -- Advice claims -----------------------------------------------------------
  function ctx.issueAdvice(def)
    if type(def) == "string" then def = { text = def } end
    if type(def) ~= "table" then return nil end
    local claims = ctx.getTable("advice_claims")
    local claim = ctx.cloneTable(def)
    claim.id = claim.id or ("advice_" .. tostring(ctx.nextRandom(999999, "advice")))
    claim.source = claim.source or "local"
    claim.truth = claim.truth or "UNKNOWN"
    claim.confidence = ctx.clamp(tonumber(claim.confidence) or 0.6, 0, 1)
    claim.createdAt = ctx.runtime.steps
    claim.expiresAt = ctx.runtime.steps + (tonumber(claim.duration) or 640)
    claim.disproven = false
    claims[#claims + 1] = claim
    while #claims > 10 do table.remove(claims, 1) end
    ctx.putTable("advice_claims", claims)
    mod.save:set("current_tip", claim.text)
    mod.save:set("current_tip_id", claim.id)
    return claim
  end

  function ctx.currentAdvice()
    local id = mod.save:get("current_tip_id")
    for _, claim in ipairs(ctx.getTable("advice_claims")) do
      if claim.id == id then return claim end
    end
  end

  function ctx.disproveAdvice(id)
    local claims = ctx.getTable("advice_claims")
    for _, claim in ipairs(claims) do
      if claim.id == id then
        claim.disproven = true
        claim.disprovenAt = ctx.runtime.steps
        claim.confidence = 0
        ctx.putTable("advice_claims", claims)
        return claim
      end
    end
  end

  function ctx.chooseTip()
    return ctx.issueAdvice(ctx.pick(DEFAULT_TIPS, "advice"))
  end

  -- Bulletin feeds ----------------------------------------------------------
  function ctx.postBulletin(boardId, def)
    boardId = boardId or ctx.runtime.currentMap or "GLOBAL"
    if type(def) == "string" then def = { text = def } end
    if type(def) ~= "table" then return nil end
    local all = ctx.getTable("bulletin_boards")
    local rows = type(all[boardId]) == "table" and all[boardId] or {}
    local post = ctx.cloneTable(def)
    post.id = post.id or ("post_" .. tostring(ctx.nextRandom(999999, "bulletins")))
    post.author = post.author or "PUBLIC"
    post.priority = tonumber(post.priority) or 0
    post.createdAt = ctx.runtime.steps
    post.expiresAt = post.expiresAt or (ctx.runtime.steps + (tonumber(post.duration) or 900))
    rows[#rows + 1] = post
    while #rows > 12 do table.remove(rows, 1) end
    all[boardId] = rows
    ctx.putTable("bulletin_boards", all)
    return post
  end

  function ctx.bulletins(boardId)
    boardId = boardId or ctx.runtime.currentMap or "GLOBAL"
    local all = ctx.getTable("bulletin_boards")
    local rows = type(all[boardId]) == "table" and all[boardId] or {}
    local out, changed = {}, false
    for _, post in ipairs(rows) do
      if ctx.runtime.steps < (tonumber(post.expiresAt) or math.huge) then
        local ok = true
        if post.condition then ok = ctx.checkCondition(post.condition, { mapId = boardId, post = post }) end
        if ok then out[#out + 1] = post end
      else changed = true end
    end
    if changed then all[boardId] = out; ctx.putTable("bulletin_boards", all) end
    table.sort(out, function(a, b)
      if (a.priority or 0) == (b.priority or 0) then return (a.createdAt or 0) > (b.createdAt or 0) end
      return (a.priority or 0) > (b.priority or 0)
    end)
    return out
  end

  function ctx.currentBulletin()
    local rows = ctx.bulletins()
    if #rows > 0 then return rows[1].text end
    local context = {
      heat = ctx.getHeat(), mood = ctx.worldMood(), mapId = ctx.runtime.currentMap,
      reputation = ctx.reputation(),
    }
    local eligible = {}
    for _, def in ipairs(ctx.bulletinDefs) do
      local ok = not def.condition or ctx.checkCondition(def.condition, context)
      if ok and type(def.eligible) == "function" then
        local success, result = pcall(def.eligible, context)
        ok = success and result ~= false
      end
      if ok then eligible[#eligible + 1] = def end
    end
    local def = ctx.pick(eligible, "bulletins")
    if not def then return nil end
    local text = def.text
    if type(text) == "function" then
      local ok, value = pcall(text, context)
      text = ok and value or nil
    end
    if text then ctx.postBulletin(ctx.runtime.currentMap, { text = text, duration = 700 }) end
    return text
  end

  -- Ecology -----------------------------------------------------------------
  local function ecologyRule(mapId, species)
    local rules = ctx.ecologyRules[mapId]
    return type(rules) == "table" and rules[species] or nil
  end

  local function normalizeEcologyRecord(value)
    if type(value) == "number" then return { pressure = value, catches = value, history = {} } end
    local rec = type(value) == "table" and value or {}
    rec.pressure = tonumber(rec.pressure) or 0
    rec.catches = tonumber(rec.catches) or 0
    rec.defeats = tonumber(rec.defeats) or 0
    rec.flees = tonumber(rec.flees) or 0
    rec.lastStep = tonumber(rec.lastStep) or ctx.runtime.steps
    rec.history = type(rec.history) == "table" and rec.history or {}
    return rec
  end

  local function recoverEcology(mapId, species, rec)
    local rule = ecologyRule(mapId, species) or {}
    local elapsed = math.max(0, ctx.runtime.steps - (tonumber(rec.lastStep) or ctx.runtime.steps))
    local recoverySteps = math.max(32, tonumber(rule.recoverySteps) or 512)
    local recoveryRate = math.max(0, tonumber(rule.recovery) or 1)
    if elapsed > 0 and rec.pressure ~= 0 then
      local recovery = (elapsed / recoverySteps) * recoveryRate
      if rec.pressure > 0 then rec.pressure = math.max(0, rec.pressure - recovery)
      else rec.pressure = math.min(0, rec.pressure + recovery) end
    end
    rec.lastStep = ctx.runtime.steps
    return rec
  end

  function ctx.ecologyState(mapId, species)
    local ecology = ctx.getTable("ecology_pressure")
    local byMap = ecology[mapId]
    if type(byMap) ~= "table" then byMap = {}; ecology[mapId] = byMap end
    local rec = normalizeEcologyRecord(byMap[species])
    recoverEcology(mapId, species, rec)
    byMap[species] = rec
    ctx.putTable("ecology_pressure", ecology)
    return rec
  end

  function ctx.ecologyPressure(mapId, species)
    if not mapId or not species then return 0 end
    return ctx.ecologyState(mapId, species).pressure
  end

  function ctx.ecologyAbundance(mapId, species)
    local rec = ctx.ecologyState(mapId, species)
    local rule = ecologyRule(mapId, species) or {}
    local cap = math.max(1, tonumber(rule.cap) or 20)
    return ctx.clamp(1 - rec.pressure / cap, 0.1, 1.5)
  end

  function ctx.recordEcologyEvent(mapId, species, kind, amount)
    if not ctx.feature("ecology") or not mapId or not species then return nil end
    kind = kind or "generic"
    amount = tonumber(amount) or 1
    local rec = ctx.ecologyState(mapId, species)
    local multiplier = 1
    if kind == "defeat" then multiplier = 0.35 end
    if kind == "flee" then multiplier = -0.10 end
    if kind == "release" then multiplier = -0.50 end
    local rule = ecologyRule(mapId, species) or {}
    local cap = math.max(1, tonumber(rule.cap) or 20)
    rec.pressure = ctx.clamp(rec.pressure + amount * multiplier, -cap, cap)
    if kind == "catch" then rec.catches = rec.catches + amount end
    if kind == "defeat" then rec.defeats = rec.defeats + amount end
    if kind == "flee" then rec.flees = rec.flees + amount end
    rec.lastStep = ctx.runtime.steps
    rec.history[#rec.history + 1] = { kind = kind, amount = amount, step = ctx.runtime.steps }
    while #rec.history > 10 do table.remove(rec.history, 1) end

    local ecology = ctx.getTable("ecology_pressure")
    ecology[mapId] = type(ecology[mapId]) == "table" and ecology[mapId] or {}
    ecology[mapId][species] = rec
    ctx.putTable("ecology_pressure", ecology)

    for _, migration in ipairs(rule.migration or {}) do
      if migration.mapId and migration.rate then
        local targetSpecies = migration.species or species
        local other = ctx.ecologyState(migration.mapId, targetSpecies)
        other.pressure = ctx.clamp(other.pressure + amount * multiplier * (tonumber(migration.rate) or 0), -cap, cap)
        local all = ctx.getTable("ecology_pressure")
        all[migration.mapId] = type(all[migration.mapId]) == "table" and all[migration.mapId] or {}
        all[migration.mapId][targetSpecies] = other
        ctx.putTable("ecology_pressure", all)
      end
    end
    return rec
  end

  function ctx.addEcologyPressure(mapId, species, amount)
    return ctx.recordEcologyEvent(mapId, species, "generic", amount)
  end

  ctx.registerMigration(4, function()
    local ecology = ctx.getTable("ecology_pressure")
    local changed = false
    for _, byMap in pairs(ecology) do
      if type(byMap) == "table" then
        for species, value in pairs(byMap) do
          if type(value) == "number" then
            byMap[species] = { pressure = value, catches = value, defeats = 0, flees = 0, lastStep = 0, history = {} }
            changed = true
          end
        end
      end
    end
    if changed then ctx.putTable("ecology_pressure", ecology) end
  end)

  local function applyReplacementRules(enc, hookCtx, ruleBook)
    if type(enc) ~= "table" or not hookCtx or not hookCtx.mapId then return enc end
    local mapRules = ruleBook[hookCtx.mapId]
    if type(mapRules) ~= "table" then return enc end
    local rule = mapRules[enc.species]
    if type(rule) ~= "table" then return enc end

    local chance = tonumber(rule.chance) or 25
    if ruleBook == ctx.ecologyRules then
      local pressure = ctx.ecologyPressure(hookCtx.mapId, enc.species)
      local threshold = tonumber(rule.threshold) or 0
      if pressure < threshold then return enc end
      local cap = math.max(threshold + 1, tonumber(rule.cap) or 20)
      local scale = ctx.clamp((pressure - threshold) / math.max(1, cap - threshold), 0, 1)
      chance = chance * (0.5 + scale * 0.5)
    end
    if rule.condition and not ctx.checkCondition(rule.condition, { encounter = enc, hook = hookCtx }) then return enc end
    if not ctx.chance(chance, "encounter_rules") then return enc end
    return { species = rule.replacement or enc.species, level = enc.level }
  end

  -- Wild anomaly traits -----------------------------------------------------
  function ctx.registerAnomaly(id, def)
    assert(type(id) == "string" and type(def) == "table")
    def.id = id
    ctx.anomalyDefs[id] = def
    return id
  end

  ctx.registerAnomaly("LEVEL_SURGE", {
    weight = 5,
    applyEncounter = function(enc)
      enc.level = ctx.clamp((tonumber(enc.level) or 1) + 2, 1, 100)
      return enc
    end,
  })

  function ctx.anomalyRate()
    local rate = tonumber(mod.options:get("anomaly_rate")) or 2
    rate = rate + ctx.moodModifier("anomaly_rate")
    if ctx.hasMutation("ODD_SPECIMENS") then rate = rate + 2 end
    if ctx.hasMutation("NIGHT_OWLS") and ctx.currentTod() == "NIGHT" then rate = rate + 2 end
    return ctx.clamp(rate, 0, 30)
  end

  function ctx.rollAnomaly(enc, hookCtx)
    if not ctx.feature("wild_anomalies") or not ctx.chance(ctx.anomalyRate(), "anomaly_gate") then return enc end
    local weighted = {}
    for id, def in pairs(ctx.anomalyDefs) do
      local eligible = not def.condition or ctx.checkCondition(def.condition, { encounter = enc, hook = hookCtx })
      if eligible then weighted[#weighted + 1] = { value = def, weight = tonumber(def.weight) or 1 } end
    end
    local def = ctx.weightedPick(weighted, "anomaly_pick")
    if not def then return enc end
    local out = { species = enc.species, level = enc.level }
    if type(def.applyEncounter) == "function" then
      local ok, value = pcall(def.applyEncounter, out, hookCtx)
      if ok and type(value) == "table" then out = value end
    end
    local anomaly = {
      id = "A" .. tostring(ctx.runtime.steps) .. ":" .. tostring(ctx.nextRandom(9999, "anomaly_ids")),
      mapId = hookCtx and hookCtx.mapId,
      species = out.species,
      level = out.level,
      traits = { def.id },
      atStep = ctx.runtime.steps,
    }
    ctx.runtime.lastWildAnomaly = anomaly
    ctx.addCounter("wild_anomalies", 1)
    return out
  end

  -- Shared wild encounter arbiter ------------------------------------------
  mod.hooks:wrap("encounter.species", function(next, enc, hookCtx)
    local rolled = next(enc, hookCtx)
    if not ctx.feature() or type(rolled) ~= "table" then return rolled end
    local out = { species = rolled.species, level = rolled.level }

    if ctx.feature("rumors") then
      for _, rumor in ipairs(ctx.activeRumors(hookCtx and hookCtx.mapId)) do
        if rumor.replacementSpecies
          and (not rumor.mapId or rumor.mapId == (hookCtx and hookCtx.mapId))
          and ctx.chance(tonumber(rumor.encounterChance) or 8, "rumor_encounters") then
          out.species = rumor.replacementSpecies
          break
        end
      end
    end

    if ctx.feature("night_cycle") and ctx.currentTod() == "NIGHT" then
      out = applyReplacementRules(out, hookCtx, ctx.nightRules)
    end
    if ctx.feature("ecology") then out = applyReplacementRules(out, hookCtx, ctx.ecologyRules) end
    if ctx.hasMutation("WILD_SURGE") then out.level = ctx.clamp((tonumber(out.level) or 1) + 1, 1, 100) end
    out = ctx.rollAnomaly(out, hookCtx)
    return out
  end)

  mod.hooks:wrap("world.tod", function(next, tod, hookCtx)
    local base = next(tod, hookCtx)
    if mod.generation ~= 1 then return base end
    if not ctx.feature("night_cycle") then return base end
    if base ~= nil and base ~= "DAY" then return base end
    return ctx.currentTod()
  end)

  -- Director events ---------------------------------------------------------
  ctx.registerDirectorEvent({
    id = "rumor", category = "RUMOR", weight = 4, cost = 18, cooldown = 220,
    eligible = function() return ctx.feature("rumors") and #ctx.activeRumors() < 3 end,
    run = function() return ctx.chooseRumor() ~= nil end,
  })
  ctx.registerDirectorEvent({
    id = "tip", category = "SOCIAL", weight = 3, cost = 10, cooldown = 160,
    run = function() return ctx.chooseTip() ~= nil end,
  })
  ctx.registerDirectorEvent({
    id = "mood", category = "WORLD", weight = 2, cost = 25, cooldown = 420,
    eligible = function() return ctx.feature("luck") end,
    run = function()
      local state = ctx.worldMoodState()
      state.expiresAt = 0
      mod.save:set("mood_state", state)
      ctx.worldMood()
      return true
    end,
  })
  ctx.registerDirectorEvent({
    id = "bulletin", category = "SOCIAL", weight = 2, cost = 12, cooldown = 180,
    run = function()
      local text = ctx.currentBulletin()
      if text then mod.save:set("current_bulletin", text) end
      return text ~= nil
    end,
  })
  ctx.registerDirectorEvent({
    id = "legend_whisper", category = "STRANGE", weight = 1, cost = 30, cooldown = 520,
    run = function()
      local undiscovered = {}
      local states = ctx.getTable("urban_legends")
      for id in pairs(ctx.legendDefs) do
        if type(states[id]) ~= "table" or not states[id].discovered then undiscovered[#undiscovered + 1] = id end
      end
      local id = ctx.pick(undiscovered, "legends")
      if not id then return false end
      ctx.activateLegend(id, 1, "director_whisper")
      return true
    end,
  })

  -- Runtime events ----------------------------------------------------------
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
    ctx.spreadRumors(ev.mapId)
    if ctx.chance(28, "advice") then ctx.chooseTip() end
    if ctx.chance(35, "bulletins") then
      local text = ctx.currentBulletin()
      if text then mod.save:set("current_bulletin", text) end
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
      local npcId = ev.target.id
      local interactions = ctx.getTable("npc_interactions")
      interactions[npcId] = (interactions[npcId] or 0) + 1
      ctx.putTable("npc_interactions", interactions)

      local community = ctx.getTable("community_memories")[ctx.runtime.currentMap] or {}
      local known = ctx.npcMemories(npcId)
      local knownIds = {}
      for _, fact in ipairs(known) do if fact.id then knownIds[fact.id] = true end end
      local candidates = {}
      for _, fact in ipairs(community) do if not knownIds[fact.id] then candidates[#candidates + 1] = fact end end
      local fact = ctx.pick(candidates, "memory_spread")
      if fact and ctx.chance(45 * (tonumber(fact.confidence) or 1), "memory_spread") then
        local copy = ctx.cloneTable(fact)
        copy.confidence = (tonumber(copy.confidence) or 1) * 0.82
        copy.learnedFrom = "community"
        ctx.rememberNpc(npcId, copy)
      end
    end
  end)

  mod.events:on("world.blacked_out", function()
    ctx.bumpReputation("blackouts", 1)
    ctx.adjustMoodPressure(-3, "blackout")
    ctx.adjustReputationFacet("competence", -1, "blackout")
  end)
  mod.events:on("flag.changed", function() ctx.bumpReputation("story_changes", 1) end)
  mod.events:on("world.tod_changed", function(ev) mod.save:set("last_tod", ev.tod) end)
end
