return function(mod, ctx)
  ctx.personalityDefs = ctx.personalityDefs or {}

  -- Stable individual Pokemon identity -------------------------------------
  local function nextMonUid()
    local serial = (tonumber(mod.save:get("next_mon_uid", 0)) or 0) + 1
    mod.save:set("next_mon_uid", serial)
    return "KX-" .. tostring(ctx.runSeed()) .. "-" .. tostring(serial)
  end

  function ctx.ensureMonUid(mon)
    if type(mon) ~= "table" then return nil end
    local rec = mon[ctx.MON_FIELD]
    if type(rec) ~= "table" then rec = {}; mon[ctx.MON_FIELD] = rec end
    if rec.uid == nil or rec.uid == "" then rec.uid = nextMonUid() end
    return tostring(rec.uid)
  end

  function ctx.monUid(mon)
    if type(mon) ~= "table" then return nil end
    local rec = mon[ctx.MON_FIELD]
    return type(rec) == "table" and rec.uid or nil
  end

  local function normalizeRecord(rec)
    rec.stats = type(rec.stats) == "table" and rec.stats or {}
    rec.titles = type(rec.titles) == "table" and rec.titles or {}
    rec.relationships = type(rec.relationships) == "table" and rec.relationships or {}
    rec.partners = type(rec.partners) == "table" and rec.partners or {} -- legacy/species summary
    rec.personalitySignals = type(rec.personalitySignals) == "table" and rec.personalitySignals or {}
    rec.history = type(rec.history) == "table" and rec.history or {}
    rec.visitedMaps = type(rec.visitedMaps) == "table" and rec.visitedMaps or {}
    return rec
  end

  function ctx.ensureMonRecord(mon)
    if type(mon) ~= "table" then return nil end
    local rec = mon[ctx.MON_FIELD]
    if type(rec) ~= "table" then rec = {}; mon[ctx.MON_FIELD] = rec end
    normalizeRecord(rec)
    ctx.ensureMonUid(mon)
    if ctx.feature("personalities") and not rec.personality then
      rec.personality = ctx.pick(ctx.personalities, "personalities")
      rec.personalityAssignedAt = ctx.runtime.steps
    end
    return rec
  end

  function ctx.reconcilePokemonIdentity(game)
    local save = game and game.save
    if type(save) ~= "table" then return 0 end
    local seen, count = {}, 0
    local function visit(mon)
      if type(mon) ~= "table" then return end
      local rec = ctx.ensureMonRecord(mon)
      if not rec then return end
      local uid = tostring(rec.uid)
      if seen[uid] and seen[uid] ~= mon then
        -- A real deposit/withdraw moves one table, so a duplicate UID on two
        -- live tables indicates a clone/copy operation. Split the copy into a
        -- new individual while preserving its inherited history.
        rec.uid = nextMonUid()
        rec.clonedFrom = uid
        uid = rec.uid
      end
      seen[uid] = mon
      count = count + 1
    end
    for _, mon in ipairs(save.party or {}) do visit(mon) end
    for _, box in ipairs(save.boxes or {}) do
      if type(box) == "table" then for _, mon in ipairs(box) do visit(mon) end end
    end
    return count
  end

  local function appendMonHistory(mon, kind, data)
    local rec = ctx.ensureMonRecord(mon)
    if not rec then return end
    local row = type(data) == "table" and ctx.cloneTable(data) or {}
    row.kind = kind
    row.step = row.step or ctx.runtime.steps
    row.mapId = row.mapId or ctx.runtime.currentMap
    rec.history[#rec.history + 1] = row
    while #rec.history > 32 do table.remove(rec.history, 1) end
  end

  -- Personality expression -------------------------------------------------
  function ctx.registerPersonality(id, def)
    assert(type(id) == "string" and type(def) == "table")
    def.id = id
    ctx.personalityDefs[id] = def
    return id
  end

  function ctx.personalitySignal(mon, signal, amount)
    local rec = ctx.ensureMonRecord(mon)
    if not rec then return 0 end
    signal = tostring(signal or "UNKNOWN")
    rec.personalitySignals[signal] = (tonumber(rec.personalitySignals[signal]) or 0) + (tonumber(amount) or 1)
    local def = rec.personality and ctx.personalityDefs[rec.personality]
    if def and type(def.onSignal) == "function" then
      pcall(def.onSignal, mon, rec, signal, amount or 1)
    end
    return rec.personalitySignals[signal]
  end

  -- Relationships between individual Pokemon ------------------------------
  local function relationshipRecord(mon, other)
    local rec = ctx.ensureMonRecord(mon)
    local otherRec = ctx.ensureMonRecord(other)
    if not rec or not otherRec then return nil end
    local otherUid = otherRec.uid
    local rel = rec.relationships[otherUid]
    if type(rel) ~= "table" then
      rel = {
        uid = otherUid,
        species = ctx.speciesOf(other),
        affinity = 0,
        rivalry = 0,
        trust = 0,
        sharedBattles = 0,
        switches = 0,
        history = {},
      }
      rec.relationships[otherUid] = rel
    end
    rel.species = ctx.speciesOf(other) or rel.species
    return rel, rec
  end

  function ctx.adjustRelationship(mon, other, axis, amount, reason)
    if mon == other then return nil end
    local rel = relationshipRecord(mon, other)
    if not rel then return nil end
    axis = axis or "affinity"
    rel[axis] = ctx.clamp((tonumber(rel[axis]) or 0) + (tonumber(amount) or 0), -100, 100)
    rel.lastStep = ctx.runtime.steps
    rel.history[#rel.history + 1] = {
      axis = axis, amount = tonumber(amount) or 0,
      reason = reason or "unknown", step = ctx.runtime.steps,
    }
    while #rel.history > 10 do table.remove(rel.history, 1) end
    return rel
  end

  function ctx.relationship(mon, other)
    local rel = relationshipRecord(mon, other)
    if not rel then return nil end
    local state = "FAMILIAR"
    if (tonumber(rel.rivalry) or 0) >= 8 then state = "RIVALS"
    elseif (tonumber(rel.trust) or 0) >= 10 then state = "TRUSTED"
    elseif (tonumber(rel.affinity) or 0) >= 12 then state = "PARTNERS"
    elseif (tonumber(rel.affinity) or 0) <= -8 then state = "TENSE" end
    return rel, state
  end

  local function notePartners(a, b)
    local ma, mb = ctx.monFromBattler(a), ctx.monFromBattler(b)
    if not ma or not mb or ma == mb then return end
    local sa, sb = ctx.speciesOf(ma), ctx.speciesOf(mb)
    local ra, rb = ctx.ensureMonRecord(ma), ctx.ensureMonRecord(mb)
    if not ra or not rb then return end
    if sa and sb then
      ra.partners[sb] = (ra.partners[sb] or 0) + 1
      rb.partners[sa] = (rb.partners[sa] or 0) + 1
    end
    local ab = ctx.adjustRelationship(ma, mb, "affinity", 1, "battle_switch")
    local ba = ctx.adjustRelationship(mb, ma, "affinity", 1, "battle_switch")
    if ab then ab.switches = (tonumber(ab.switches) or 0) + 1 end
    if ba then ba.switches = (tonumber(ba.switches) or 0) + 1 end
  end

  -- Definition-driven achievements/titles ----------------------------------
  function ctx.registerTitle(id, def)
    assert(type(id) == "string" and type(def) == "table")
    def.id = id
    ctx.titleDefs[id] = def
    return id
  end

  function ctx.awardTitle(mon, id, reason)
    local rec = ctx.ensureMonRecord(mon)
    if not rec or rec.titles[id] then return false end
    rec.titles[id] = { unlockedAt = ctx.runtime.steps, reason = reason or "threshold" }
    appendMonHistory(mon, "TITLE", { id = id, reason = reason })
    return true
  end

  function ctx.evaluateTitles(mon)
    local rec = ctx.ensureMonRecord(mon)
    if not rec then return {} end
    local awarded = {}
    for id, def in pairs(ctx.titleDefs) do
      if not rec.titles[id] then
        local ok = true
        if def.metric then ok = (tonumber(rec.stats[def.metric]) or 0) >= (tonumber(def.threshold) or 1) end
        if ok and def.condition then
          ok = ctx.checkCondition(def.condition, { mon = mon, record = rec, game = ctx.runtime.game })
        end
        if ok and def.metric and ctx.awardTitle(mon, id, def.metric) then awarded[#awarded + 1] = id end
      end
    end
    return awarded
  end

  function ctx.bumpMon(mon, field, amount)
    local rec = ctx.ensureMonRecord(mon)
    if not rec then return 0 end
    rec.stats[field] = (tonumber(rec.stats[field]) or 0) + (amount or 1)
    ctx.evaluateTitles(mon)
    return rec.stats[field]
  end

  ctx.registerTitle("VETERAN", { metric = "movesUsed", threshold = 100 })
  ctx.registerTitle("SHARPSHOOTER", { metric = "crits", threshold = 10 })
  ctx.registerTitle("HEAVY_HITTER", { metric = "damageDealt", threshold = 5000 })
  ctx.registerTitle("BATTLER", { metric = "kos", threshold = 50 })
  ctx.registerTitle("HALFWAY_TO_100", { metric = "maxLevel", threshold = 50 })
  ctx.registerTitle("TRAVELER", { metric = "mapsVisited", threshold = 20 })

  -- Reverse Pokedex observation engine -------------------------------------
  function ctx.registerObservation(def)
    assert(type(def) == "table" and type(def.id) == "string")
    ctx.observationDefs[#ctx.observationDefs + 1] = def
    return def.id
  end

  function ctx.playerObservations()
    local rep = ctx.reputation()
    local env = {
      reputation = rep,
      steps = ctx.runtime.steps,
      game = ctx.runtime.game,
      mapId = ctx.runtime.currentMap,
    }
    local out = {}
    for _, def in ipairs(ctx.observationDefs) do
      local ok = true
      if def.condition then ok = ctx.checkCondition(def.condition, env) end
      if ok and type(def.eligible) == "function" then
        local success, value = pcall(def.eligible, env)
        ok = success and value ~= false
      end
      if ok then
        out[#out + 1] = {
          id = def.id,
          text = type(def.text) == "function" and def.text(env) or def.text,
          priority = tonumber(def.priority) or 0,
          confidence = tonumber(def.confidence) or 1,
        }
      end
    end
    table.sort(out, function(a, b) return a.priority > b.priority end)
    return out
  end

  function ctx.playerObservation()
    local rows = ctx.playerObservations()
    return rows[1] and rows[1].text or "HUMAN: Repeatedly enters tall grass despite visible danger."
  end

  ctx.registerObservation({
    id = "BLACKOUTS", priority = 50,
    eligible = function(env) return (tonumber(env.reputation.blackouts) or 0) >= 5 end,
    text = "HUMAN: Frequently loses consciousness, resumes journey anyway.",
  })
  ctx.registerObservation({
    id = "COLLECTOR", priority = 40,
    eligible = function(env) return (tonumber(env.reputation.catches) or 0) >= 50 end,
    text = "HUMAN: Collects wildlife with suspicious dedication.",
  })
  ctx.registerObservation({
    id = "BATTLER", priority = 30,
    eligible = function(env) return (tonumber(env.reputation.battles) or 0) >= 100 end,
    text = "HUMAN: Resolves most disagreements through organized combat.",
  })
  ctx.registerObservation({
    id = "WALKER", priority = 20,
    eligible = function(env) return (tonumber(env.steps) or 0) >= 5000 end,
    text = "HUMAN: Walks enormous distances despite owning technology.",
  })

  -- Superstitions -----------------------------------------------------------
  local function partySpecies(game)
    local found = {}
    local party = game and game.save and game.save.party or {}
    for _, mon in ipairs(party) do
      local species = ctx.speciesOf(mon)
      if species then found[species] = true end
    end
    return found
  end

  function ctx.registerSuperstition(def)
    assert(type(def) == "table" and type(def.id) == "string")
    ctx.superstitionDefs[#ctx.superstitionDefs + 1] = def
    return def.id
  end

  function ctx.superstitions(game, context)
    context = type(context) == "table" and context or {}
    local found = partySpecies(game)
    local tags = {}
    for _, tag in ipairs(context.believerTags or {}) do tags[tag] = true end
    local out = {}
    for _, def in ipairs(ctx.superstitionDefs) do
      local ok = true
      if def.species then
        ok = false
        for _, species in ipairs(def.species) do if found[species] then ok = true break end end
      end
      if ok and def.believerTags and #def.believerTags > 0 then
        ok = false
        for _, tag in ipairs(def.believerTags) do if tags[tag] then ok = true break end end
      end
      if ok and def.condition then
        ok = ctx.checkCondition(def.condition, { game = game, partySpecies = found, context = context })
      end
      if ok then out[#out + 1] = def end
    end
    table.sort(out, function(a, b) return (tonumber(a.priority) or 0) > (tonumber(b.priority) or 0) end)
    return out
  end

  function ctx.superstition(game, context)
    local rows = ctx.superstitions(game, context)
    return rows[1] and rows[1].text or "Nobody has invented a superstition about this party yet."
  end

  ctx.registerSuperstition({ id = "ABRA_GAMBLERS", species = { "ABRA" }, believerTags = { "GAMBLER" }, priority = 20, text = "Gamblers may suspect that Abra knows too much." })
  ctx.registerSuperstition({ id = "CUBONE_LAVENDER", species = { "CUBONE" }, believerTags = { "LAVENDER" }, priority = 20, text = "Lavender locals would probably notice the Cubone." })
  ctx.registerSuperstition({ id = "GHOSTS", species = { "HAUNTER", "GENGAR" }, priority = 10, text = "Several people would prefer not to discuss your Ghost." })
  ctx.registerSuperstition({ id = "MAGIKARP", species = { "MAGIKARP" }, believerTags = { "FISHER" }, priority = 10, text = "Someone, somewhere, respects your commitment to Magikarp." })
  ctx.registerSuperstition({ id = "PIKACHU", species = { "PIKACHU" }, believerTags = { "ELECTRICIAN" }, priority = 10, text = "Electricians would approve of your company." })

  -- Event tracking ----------------------------------------------------------
  mod.events:on("battle.move_used", function(ev)
    if not ctx.isPlayerBattler(ev.user) then return end
    local mon = ctx.monFromBattler(ev.user)
    if ctx.runtime.battle then ctx.runtime.battle.lastPlayerMon = mon end
    ctx.bumpMon(mon, "movesUsed", 1)
    ctx.personalitySignal(mon, "MOVE_USED", 1)
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    if not ctx.isPlayerBattler(ev.user) then return end
    local mon = ctx.monFromBattler(ev.user)
    ctx.bumpMon(mon, "damageDealt", tonumber(ev.damage) or 0)
    if ev.crit then
      ctx.bumpMon(mon, "crits", 1)
      ctx.personalitySignal(mon, "CRITICAL_HIT", 1)
    end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    if ev.side ~= "player" then return end
    notePartners(ev.previous, ev.battler)
    local mon = ctx.monFromBattler(ev.battler)
    ctx.personalitySignal(mon, "SWITCHED_IN", 1)
    if ctx.runtime.battle then ctx.runtime.battle.lastPlayerMon = mon end
  end)

  mod.events:on("battle.fainted", function(ev)
    if ctx.isPlayerBattler(ev.battler) then
      local mon = ctx.monFromBattler(ev.battler)
      ctx.bumpMon(mon, "faints", 1)
      ctx.personalitySignal(mon, "FAINTED", 1)
      appendMonHistory(mon, "FAINTED")
    elseif ctx.runtime.battle and ctx.runtime.battle.lastPlayerMon then
      local mon = ctx.runtime.battle.lastPlayerMon
      ctx.bumpMon(mon, "kos", 1)
      ctx.personalitySignal(mon, "KO", 1)
    end
  end)

  mod.events:on("pokemon.caught", function(ev)
    local mon = ev.mon
    local rec = ctx.ensureMonRecord(mon)
    if rec then
      rec.caughtMap = ctx.runtime.currentMap
      rec.caughtAtStep = ctx.runtime.steps
      rec.originalSpecies = rec.originalSpecies or ev.species or ctx.speciesOf(mon)
      ctx.awardTitle(mon, "CAUGHT_IN_KANTO", "caught")
      appendMonHistory(mon, "CAUGHT", { species = rec.originalSpecies })
    end
    ctx.bumpReputation("catches", 1)
    ctx.adjustReputationFacet("collector", 0.5, "catch")
    local species = ev.species or ctx.speciesOf(mon)
    ctx.recordEcologyEvent(ctx.runtime.currentMap, species, "catch", 1)
    if species == "OMANYTE" or species == "KABUTO" or species == "AERODACTYL" then
      ctx.unlockExhibit(species, { species = species, source = "caught", provenance = ctx.runtime.currentMap })
    end
  end)

  mod.events:on("pokemon.received", function(ev)
    ctx.ensureMonRecord(ev.mon)
    appendMonHistory(ev.mon, "RECEIVED")
  end)

  mod.events:on("pokemon.level_up", function(ev)
    local rec = ctx.ensureMonRecord(ev.mon)
    if rec then
      rec.maxLevel = math.max(tonumber(rec.maxLevel) or 0, tonumber(ev.level) or 0)
      rec.stats.maxLevel = math.max(tonumber(rec.stats.maxLevel) or 0, tonumber(ev.level) or 0)
      ctx.evaluateTitles(ev.mon)
    end
  end)

  mod.events:on("pokemon.evolved", function(ev)
    ctx.bumpMon(ev.mon, "evolutions", 1)
    ctx.awardTitle(ev.mon, "EVOLVED", "evolution")
    appendMonHistory(ev.mon, "EVOLVED", { species = ctx.speciesOf(ev.mon) })
  end)

  mod.events:on("map.entered", function(ev)
    local game = ctx.runtime.game
    local party = game and game.save and game.save.party or {}
    for _, mon in ipairs(party) do
      local rec = ctx.ensureMonRecord(mon)
      if rec and not rec.visitedMaps[ev.mapId] then
        rec.visitedMaps[ev.mapId] = true
        rec.stats.mapsVisited = (tonumber(rec.stats.mapsVisited) or 0) + 1
        ctx.evaluateTitles(mon)
      end
    end
    ctx.reconcilePokemonIdentity(game)
  end)

  mod.events:on("save.loaded", function()
    ctx.reconcilePokemonIdentity(ctx.runtime.game)
  end)
end
