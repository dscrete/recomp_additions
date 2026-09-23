return function(mod, ctx)
  local function countPairs(t, predicate)
    local n = 0
    for k, v in pairs(type(t) == "table" and t or {}) do
      if not predicate or predicate(k, v) then n = n + 1 end
    end
    return n
  end

  mod.content.screens:register(ctx.SCREEN_ID, {
    new = function(game)
      local Font = mod.ui.Font
      local state = { isOpaque = true, page = 1, monIndex = 1 }

      function state:update()
        if game.input:wasPressed("b") then game.stack:pop(); return end
        if game.input:wasPressed("a") then self.page = (self.page % 3) + 1 end
        if self.page == 3 then
          local party = game.save and game.save.party or {}
          if game.input:wasPressed("left") and #party > 0 then
            self.monIndex = ((self.monIndex - 2) % #party) + 1
          elseif game.input:wasPressed("right") and #party > 0 then
            self.monIndex = (self.monIndex % #party) + 1
          end
        end
      end

      local function header(title)
        Font.drawBox(0, 0, 20, 18)
        Font.draw(title, 8, 8)
      end

      local function drawOverview()
        header("KANTO EXPANSION")
        local rumor = ctx.currentRumor()
        local mutations = ctx.ensureRunMutations()
        local mutationText = #mutations > 0 and table.concat(mutations, ",") or "NONE"
        local rep = ctx.reputation()
        local mood = ctx.worldMoodState()
        Font.draw("MOOD " .. tostring(mood.id) .. " x" .. tostring(mood.intensity or 1), 8, 20)
        Font.draw("ROCKET " .. tostring(math.floor(ctx.getHeat() + 0.5)), 8, 32)
        Font.draw("RUMOR " .. ctx.truncate(rumor and rumor.id or "NONE", 11), 8, 44)
        Font.draw("TIP " .. ctx.truncate(mod.save:get("current_tip", "NONE"), 13), 8, 56)
        Font.draw("BOARD " .. ctx.truncate(mod.save:get("current_bulletin", "NONE"), 11), 8, 68)
        Font.draw("MUT " .. ctx.truncate(mutationText, 13), 8, 80)
        Font.draw(("BTL %d CAT %d"):format(tonumber(rep.battles) or 0, tonumber(rep.catches) or 0), 8, 92)
        Font.draw("MUSEUM " .. tostring(ctx.exhibitCount()), 8, 104)
        Font.draw("PARTY " .. ctx.truncate(ctx.superstition(game), 11), 8, 116)
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawSystems()
        header("SYSTEM STATE")
        local director = ctx.directorStatus()
        local tier = ctx.rocketHeatTier()
        local legends = ctx.getTable("urban_legends")
        local discovered = countPairs(legends, function(_, rec) return type(rec) == "table" and rec.discovered end)
        local ecology = ctx.getTable("ecology_pressure")
        local ecoMap = ecology[ctx.runtime.currentMap] or {}
        local traveler = ctx.travelerState("CON_ARTIST")
        local anomaly = mod.save:get("last_anomaly") or ctx.runtime.lastWildAnomaly
        local mood = ctx.worldMoodState()
        Font.draw("SCHEMA " .. tostring(mod.save:get("schema_version", 0)), 8, 20)
        Font.draw("SEED " .. ctx.truncate(ctx.runSeed(), 12), 8, 32)
        Font.draw("DIR " .. tostring(math.floor(tonumber(director.budget) or 0)) .. " " .. ctx.truncate(director.lastEvent or "NONE", 8), 8, 44)
        Font.draw("HEAT " .. tostring(tier), 8, 56)
        Font.draw("RUMORS " .. tostring(#ctx.activeRumors()), 8, 68)
        Font.draw(("LEGENDS %d/%d"):format(discovered, countPairs(ctx.legendDefs)), 8, 80)
        Font.draw("ECO SPECIES " .. tostring(countPairs(ecoMap)), 8, 92)
        Font.draw("MOOD P " .. tostring(math.floor(tonumber(mood.pressure) or 0)), 8, 104)
        Font.draw("CON " .. ctx.truncate(traveler and traveler.mapId or "NONE", 12), 8, 116)
        Font.draw("ANOM " .. ctx.truncate(anomaly and (anomaly.traits and anomaly.traits[1] or anomaly.id) or "NONE", 11), 8, 128)
        Font.draw("A:NEXT  B:EXIT", 8, 140)
      end

      local function drawPokemon()
        header("POKEMON HISTORY")
        local party = game.save and game.save.party or {}
        if #party == 0 then
          Font.draw("PARTY EMPTY", 8, 28)
          Font.draw("A:NEXT  B:EXIT", 8, 132)
          return
        end
        if self.monIndex > #party then self.monIndex = 1 end
        local mon = party[self.monIndex]
        local rec = ctx.ensureMonRecord(mon)
        local titleCount = countPairs(rec and rec.titles)
        local relCount = countPairs(rec and rec.relationships)
        local species = ctx.speciesOf(mon) or "UNKNOWN"
        Font.draw(("%d/%d %s"):format(self.monIndex, #party, ctx.truncate(species, 10)), 8, 20)
        Font.draw("ID " .. ctx.truncate(rec and rec.uid or "NONE", 15), 8, 32)
        Font.draw("PERS " .. ctx.truncate(rec and rec.personality or "NONE", 12), 8, 44)
        Font.draw("TITLES " .. tostring(titleCount), 8, 56)
        Font.draw("REL " .. tostring(relCount), 8, 68)
        Font.draw("MAPS " .. tostring(rec and rec.stats and rec.stats.mapsVisited or 0), 8, 80)
        Font.draw("KOS " .. tostring(rec and rec.stats and rec.stats.kos or 0), 8, 92)
        Font.draw("CRITS " .. tostring(rec and rec.stats and rec.stats.crits or 0), 8, 104)
        Font.draw("MOVES " .. tostring(rec and rec.stats and rec.stats.movesUsed or 0), 8, 116)
        Font.draw("< > MON  A:NEXT", 8, 128)
        Font.draw("B:EXIT", 8, 140)
      end

      function state:draw()
        if self.page == 1 then drawOverview()
        elseif self.page == 2 then drawSystems()
        else drawPokemon() end
      end
      return state
    end,
  })

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if not ctx.feature("ui_entry") or type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "OPTION", {
      label = "EXPANSION",
      onSelect = function() mod.ui.push(game, ctx.SCREEN_ID) end,
    })
  end)
end
