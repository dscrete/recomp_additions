return function(mod, ctx)
  local function countPairs(t, predicate)
    local n = 0
    for k, v in pairs(type(t) == "table" and t or {}) do
      if not predicate or predicate(k, v) then n = n + 1 end
    end
    return n
  end

  local function humanize(value)
    return tostring(value or "NONE"):gsub("_", " ")
  end

  local function wrapText(value, width, maxLines)
    width = math.max(4, tonumber(width) or 18)
    maxLines = math.max(1, tonumber(maxLines) or 1)
    local text = humanize(value)
    local lines, current = {}, ""

    local function push(line)
      if line ~= "" then lines[#lines + 1] = line end
    end

    for word in text:gmatch("%S+") do
      if #word > width then
        push(current)
        current = ""
        while #word > width do
          push(word:sub(1, width))
          word = word:sub(width + 1)
        end
        current = word
      elseif current == "" then
        current = word
      elseif #current + #word + 1 <= width then
        current = current .. " " .. word
      else
        push(current)
        current = word
      end
    end
    push(current)
    if #lines == 0 then lines[1] = "NONE" end

    if #lines > maxLines then
      while #lines > maxLines do table.remove(lines) end
      local last = lines[maxLines] or ""
      if #last > width - 3 then last = last:sub(1, math.max(1, width - 3)) end
      lines[maxLines] = last .. "..."
    end
    return lines
  end

  local function drawWrapped(Font, value, y, maxLines)
    local lines = wrapText(value, 18, maxLines)
    for i, line in ipairs(lines) do
      Font.draw(line, 8, y + (i - 1) * 10)
    end
    return y + #lines * 10
  end

  local function formatTime()
    local hour = ctx.currentHour()
    if type(hour) ~= "number" then return humanize(ctx.currentTod()) end
    local h = math.floor(hour) % 24
    local m = math.floor((hour - math.floor(hour)) * 60 + 0.5)
    if m >= 60 then h = (h + 1) % 24; m = 0 end
    return ("%02d:%02d %s"):format(h, m, humanize(ctx.currentTod()))
  end

  local STATUS_BELIEVER_TAGS = { "GAMBLER", "LAVENDER", "FISHER", "ELECTRICIAN" }
  local PAGE_COUNT = 6

  mod.content.screens:register(ctx.SCREEN_ID, {
    new = function(game)
      local Font = mod.ui.Font
      local state = { isOpaque = true, page = 1, monIndex = 1 }

      function state:update()
        if game.input:wasPressed("b") then game.stack:pop(); return end
        if game.input:wasPressed("a") then self.page = (self.page % PAGE_COUNT) + 1 end
        if self.page == PAGE_COUNT then
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

      local function footer(extra)
        if extra then Font.draw(extra, 8, 120) end
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawWorld()
        header("WORLD STATUS 1/6")
        local mood = ctx.worldMoodState()
        local director = ctx.directorStatus()
        local rumorCount = #ctx.activeRumors()
        local heat = math.floor(ctx.getHeat() + 0.5)
        Font.draw("TIME " .. ctx.truncate(formatTime(), 13), 8, 22)
        Font.draw("MOOD " .. humanize(mood.id) .. " x" .. tostring(mood.intensity or 1), 8, 34)
        Font.draw("ROCKET " .. humanize(ctx.rocketHeatTier()) .. " " .. tostring(heat), 8, 46)
        Font.draw("RUMORS " .. tostring(rumorCount), 8, 58)
        Font.draw("DIRECTOR " .. tostring(math.floor(tonumber(director.budget) or 0)), 8, 70)
        Font.draw("LAST EVENT", 8, 82)
        drawWrapped(Font, director.lastEvent or "NONE", 94, 2)
        Font.draw("MAP", 8, 114)
        Font.draw(ctx.truncate(humanize(ctx.runtime.currentMap or "NONE"), 18), 8, 124)
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawRumor()
        header("RUMOR 2/6")
        local rumor = ctx.currentRumor()
        if not rumor then
          Font.draw("NO ACTIVE RUMOR", 8, 30)
          Font.draw("The Director has", 8, 50)
          Font.draw("nothing circulating", 8, 60)
          Font.draw("right now.", 8, 70)
        else
          drawWrapped(Font, rumor.text or rumor.id, 24, 7)
          Font.draw("SOURCE", 8, 98)
          Font.draw(ctx.truncate(humanize(rumor.source), 18), 8, 108)
          Font.draw("TRUTH " .. ctx.truncate(humanize(rumor.truth), 12), 8, 118)
        end
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawLocal()
        header("LOCAL INFO 3/6")
        Font.draw("TRAVEL ADVICE", 8, 22)
        local y = drawWrapped(Font, mod.save:get("current_tip", "NONE"), 34, 3)
        y = math.max(y + 4, 68)
        Font.draw("BULLETIN", 8, y)
        drawWrapped(Font, mod.save:get("current_bulletin", "NONE"), y + 12, 4)
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawRun()
        header("RUN STATUS 4/6")
        local mutations = ctx.ensureRunMutations()
        local rep = ctx.reputation()
        local superstition = ctx.superstition(game, { believerTags = STATUS_BELIEVER_TAGS })
        Font.draw("MUTATIONS", 8, 22)
        if #mutations == 0 then
          Font.draw("NONE", 8, 34)
        else
          for i = 1, math.min(3, #mutations) do
            Font.draw(ctx.truncate(humanize(mutations[i]), 18), 8, 24 + i * 10)
          end
        end
        Font.draw(("BATTLES %d"):format(tonumber(rep.battles) or 0), 8, 66)
        Font.draw(("CATCHES %d"):format(tonumber(rep.catches) or 0), 8, 78)
        Font.draw("MUSEUM " .. tostring(ctx.exhibitCount()), 8, 90)
        Font.draw("PARTY BELIEF", 8, 100)
        drawWrapped(Font, superstition, 110, 2)
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawSystems()
        header("SYSTEM STATE 5/6")
        local director = ctx.directorStatus()
        local legends = ctx.getTable("urban_legends")
        local discovered = countPairs(legends, function(_, rec) return type(rec) == "table" and rec.discovered end)
        local ecology = ctx.getTable("ecology_pressure")
        local ecoMap = ecology[ctx.runtime.currentMap] or {}
        local traveler = ctx.travelerState("CON_ARTIST")
        local anomaly = mod.save:get("last_anomaly") or ctx.runtime.lastWildAnomaly
        local mood = ctx.worldMoodState()
        local anomalyId = anomaly and (anomaly.traits and anomaly.traits[1] or anomaly.id) or "NONE"
        Font.draw("SCHEMA " .. tostring(mod.save:get("schema_version", 0)), 8, 20)
        Font.draw("SEED " .. ctx.truncate(tostring(ctx.runSeed()), 13), 8, 31)
        Font.draw("DIR BUDGET " .. tostring(math.floor(tonumber(director.budget) or 0)), 8, 42)
        Font.draw("HEAT " .. humanize(ctx.rocketHeatTier()), 8, 53)
        Font.draw(("LEGENDS %d/%d"):format(discovered, countPairs(ctx.legendDefs)), 8, 64)
        Font.draw("ECO SPECIES " .. tostring(countPairs(ecoMap)), 8, 75)
        Font.draw("MOOD PRESS " .. tostring(math.floor(tonumber(mood.pressure) or 0)), 8, 86)
        Font.draw("TRAVELER " .. ctx.truncate(humanize(traveler and traveler.mapId or "NONE"), 9), 8, 97)
        Font.draw("ANOMALY", 8, 108)
        Font.draw(ctx.truncate(humanize(anomalyId), 18), 8, 119)
        Font.draw("A:NEXT  B:EXIT", 8, 132)
      end

      local function drawPokemon()
        header("POKEMON 6/6")
        local party = game.save and game.save.party or {}
        if #party == 0 then
          Font.draw("PARTY EMPTY", 8, 30)
          Font.draw("A:NEXT  B:EXIT", 8, 132)
          return
        end
        if self.monIndex > #party then self.monIndex = 1 end
        local mon = party[self.monIndex]
        local rec = ctx.ensureMonRecord(mon)
        local titleCount = countPairs(rec and rec.titles)
        local relCount = countPairs(rec and rec.relationships)
        local species = ctx.speciesOf(mon) or "UNKNOWN"
        Font.draw(("%d/%d %s"):format(self.monIndex, #party, ctx.truncate(humanize(species), 12)), 8, 20)
        Font.draw("ID " .. ctx.truncate(rec and rec.uid or "NONE", 15), 8, 31)
        Font.draw("PERS " .. ctx.truncate(humanize(rec and rec.personality or "NONE"), 12), 8, 42)
        Font.draw("TITLES " .. tostring(titleCount), 8, 53)
        Font.draw("RELATIONSHIPS " .. tostring(relCount), 8, 64)
        Font.draw("MAPS " .. tostring(rec and rec.stats and rec.stats.mapsVisited or 0), 8, 75)
        Font.draw("KOS " .. tostring(rec and rec.stats and rec.stats.kos or 0), 8, 86)
        Font.draw("CRITS " .. tostring(rec and rec.stats and rec.stats.crits or 0), 8, 97)
        Font.draw("MOVES " .. tostring(rec and rec.stats and rec.stats.movesUsed or 0), 8, 108)
        footer("< > CHANGE MON")
      end

      function state:draw()
        if self.page == 1 then drawWorld()
        elseif self.page == 2 then drawRumor()
        elseif self.page == 3 then drawLocal()
        elseif self.page == 4 then drawRun()
        elseif self.page == 5 then drawSystems()
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
