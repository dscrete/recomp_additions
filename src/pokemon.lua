return function(mod, ctx)
  function ctx.ensureMonRecord(mon)
    if type(mon) ~= "table" then return nil end
    local rec = mon[ctx.MON_FIELD]
    if type(rec) ~= "table" then
      rec = { stats = {}, titles = {}, partners = {} }
      mon[ctx.MON_FIELD] = rec
    end
    if type(rec.stats) ~= "table" then rec.stats = {} end
    if type(rec.titles) ~= "table" then rec.titles = {} end
    if type(rec.partners) ~= "table" then rec.partners = {} end
    if ctx.feature("personalities") and not rec.personality then rec.personality = ctx.pick(ctx.personalities) end
    return rec
  end

  function ctx.awardTitle(mon, id)
    local rec = ctx.ensureMonRecord(mon)
    if not rec or rec.titles[id] then return false end
    rec.titles[id] = true
    return true
  end

  function ctx.bumpMon(mon, field, amount)
    local rec = ctx.ensureMonRecord(mon)
    if not rec then return 0 end
    rec.stats[field] = (tonumber(rec.stats[field]) or 0) + (amount or 1)
    return rec.stats[field]
  end

  local function notePartners(a, b)
    local ma, mb = ctx.monFromBattler(a), ctx.monFromBattler(b)
    if not ma or not mb or ma == mb then return end
    local sa, sb = ctx.speciesOf(ma), ctx.speciesOf(mb)
    if not sa or not sb then return end
    local ra, rb = ctx.ensureMonRecord(ma), ctx.ensureMonRecord(mb)
    if ra then ra.partners[sb] = (ra.partners[sb] or 0) + 1 end
    if rb then rb.partners[sa] = (rb.partners[sa] or 0) + 1 end
  end

  mod.events:on("battle.move_used", function(ev)
    if not ctx.isPlayerBattler(ev.user) then return end
    local mon = ctx.monFromBattler(ev.user)
    if ctx.runtime.battle then ctx.runtime.battle.lastPlayerMon = mon end
    local used = ctx.bumpMon(mon, "movesUsed", 1)
    if used >= 100 then ctx.awardTitle(mon, "VETERAN") end
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    if not ctx.isPlayerBattler(ev.user) then return end
    local mon = ctx.monFromBattler(ev.user)
    local damage = ctx.bumpMon(mon, "damageDealt", tonumber(ev.damage) or 0)
    if ev.crit then
      local crits = ctx.bumpMon(mon, "crits", 1)
      if crits >= 10 then ctx.awardTitle(mon, "SHARPSHOOTER") end
    end
    if damage >= 5000 then ctx.awardTitle(mon, "HEAVY_HITTER") end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    if ev.side ~= "player" then return end
    notePartners(ev.previous, ev.battler)
    if ctx.runtime.battle then ctx.runtime.battle.lastPlayerMon = ctx.monFromBattler(ev.battler) end
  end)

  mod.events:on("battle.fainted", function(ev)
    if ctx.isPlayerBattler(ev.battler) then
      ctx.bumpMon(ctx.monFromBattler(ev.battler), "faints", 1)
    elseif ctx.runtime.battle and ctx.runtime.battle.lastPlayerMon then
      local mon = ctx.runtime.battle.lastPlayerMon
      local kos = ctx.bumpMon(mon, "kos", 1)
      if kos >= 50 then ctx.awardTitle(mon, "BATTLER") end
    end
  end)

  mod.events:on("pokemon.caught", function(ev)
    local mon = ev.mon
    local rec = ctx.ensureMonRecord(mon)
    if rec then
      rec.caughtMap = ctx.runtime.currentMap
      rec.caughtAtStep = ctx.runtime.steps
      rec.originalSpecies = rec.originalSpecies or ev.species or ctx.speciesOf(mon)
      ctx.awardTitle(mon, "CAUGHT_IN_KANTO")
    end
    ctx.bumpReputation("catches", 1)
    local species = ev.species or ctx.speciesOf(mon)
    ctx.addEcologyPressure(ctx.runtime.currentMap, species, 1)
    if species == "OMANYTE" or species == "KABUTO" or species == "AERODACTYL" then
      ctx.unlockExhibit(species)
    end
  end)

  mod.events:on("pokemon.received", function(ev) ctx.ensureMonRecord(ev.mon) end)

  mod.events:on("pokemon.level_up", function(ev)
    local rec = ctx.ensureMonRecord(ev.mon)
    if rec then rec.maxLevel = math.max(tonumber(rec.maxLevel) or 0, tonumber(ev.level) or 0) end
    if (tonumber(ev.level) or 0) >= 50 then ctx.awardTitle(ev.mon, "HALFWAY_TO_100") end
  end)

  mod.events:on("pokemon.evolved", function(ev)
    ctx.bumpMon(ev.mon, "evolutions", 1)
    ctx.awardTitle(ev.mon, "EVOLVED")
  end)

  function ctx.playerObservation()
    local rep = ctx.reputation()
    local catches = tonumber(rep.catches) or 0
    local battles = tonumber(rep.battles) or 0
    local blackouts = tonumber(rep.blackouts) or 0
    if blackouts >= 5 then return "HUMAN: Frequently loses consciousness, resumes journey anyway." end
    if catches >= 50 then return "HUMAN: Collects wildlife with suspicious dedication." end
    if battles >= 100 then return "HUMAN: Resolves most disagreements through organized combat." end
    if ctx.runtime.steps >= 5000 then return "HUMAN: Walks enormous distances despite owning technology." end
    return "HUMAN: Repeatedly enters tall grass despite visible danger."
  end

  local function partySpecies(game)
    local found = {}
    local party = game and game.save and game.save.party or {}
    for _, mon in ipairs(party) do
      local species = ctx.speciesOf(mon)
      if species then found[species] = true end
    end
    return found
  end

  function ctx.superstition(game)
    local found = partySpecies(game)
    if found.ABRA then return "Gamblers may suspect that Abra knows too much." end
    if found.CUBONE then return "Lavender locals would probably notice the Cubone." end
    if found.HAUNTER or found.GENGAR then return "Several people would prefer not to discuss your Ghost." end
    if found.MAGIKARP then return "Someone, somewhere, respects your commitment to Magikarp." end
    if found.PIKACHU then return "Electricians would approve of your company." end
    return "Nobody has invented a superstition about this party yet."
  end
end
