-- Gen 1 presentation fallback for the synthetic day/night cycle.
--
-- The gameplay clock is owned by world.tod. This module only communicates the
-- result visually. It deliberately does nothing on later generations so Gold
-- and other games can keep their native time-of-day presentation.
local NIGHT_RAMP = {
  { 188, 211, 255 },
  { 100, 132, 205 },
  { 38, 59, 122 },
  { 8, 12, 32 },
}

return function(mod, ctx)
  local paletteCache = setmetatable({}, { __mode = "k" })
  local lastTod = nil
  local noticeText = nil
  local noticeFrames = 0

  local function isNight()
    return mod.generation == 1
      and ctx.feature("night_cycle")
      and ctx.feature("night_visual")
      and ctx.currentTod() == "NIGHT"
  end

  local function currentMapDef(game)
    local world = game and (game.overworld or game.world)
    local map = world and world.map
    return map and map.def or nil
  end

  local function isOutdoor(game)
    local def = currentMapDef(game)
    if type(def) ~= "table" then return false end
    if def.outdoor ~= nil then return def.outdoor == true end
    return def.tileset == "OVERWORLD"
  end

  local function blend(a, b, amount)
    return math.floor(a * (1 - amount) + b * amount + 0.5)
  end

  local function moonPalette(colors)
    if type(colors) ~= "table" then return colors end
    local cached = paletteCache[colors]
    if cached then return cached end

    local out = {}
    for i = 1, 4 do
      local source = colors[i] or colors[#colors] or { 255, 255, 255 }
      local target = NIGHT_RAMP[i]
      -- Keep enough of each map's identity that towns still differ, but push
      -- every shade decisively toward a moonlit blue/navy ramp.
      local amount = (i == 1) and 0.72 or 0.82
      out[i] = {
        blend(tonumber(source[1]) or 255, target[1], amount),
        blend(tonumber(source[2]) or 255, target[2], amount),
        blend(tonumber(source[3]) or 255, target[3], amount),
      }
    end
    paletteCache[colors] = out
    return out
  end

  local function tintZones(zones)
    if type(zones) ~= "table" then return false end
    local changed = false
    for _, zone in ipairs(zones) do
      if type(zone) == "table" and type(zone.colors) == "table" then
        zone.colors = moonPalette(zone.colors)
        changed = true
      end
    end
    return changed
  end

  local function tintTrueColorWorld(frame)
    local canvas = frame and frame.worldCanvas
    if not canvas or not canvas.getWidth or not love.graphics.setCanvas then return end

    local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
    love.graphics.setCanvas(canvas)
    love.graphics.setScissor()
    love.graphics.setColor(0.04, 0.10, 0.30, 0.34)
    love.graphics.rectangle("fill", 0, 0, canvas:getWidth(), canvas:getHeight())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setCanvas(previous)
  end

  local function queueTodNotice(tod)
    if tod == "NIGHT" then
      noticeText = "NIGHT HAS FALLEN"
    elseif tod == "DAY" then
      noticeText = "MORNING HAS COME"
    else
      noticeText = tostring(tod or "TIME CHANGED")
    end
    noticeFrames = 120
  end

  local function syncTodNotice()
    if mod.generation ~= 1 or not ctx.feature("night_cycle") then return end
    local tod = ctx.currentTod()
    if lastTod == nil then
      lastTod = tod
      return
    end
    if tod ~= lastTod then queueTodNotice(tod) end
    lastTod = tod
  end

  mod.events:on("game.ready", function()
    lastTod = ctx.currentTod()
  end)

  mod.events:on("world.stepped", syncTodNotice)

  -- At this seam the engine has separate world and UI canvases. For the normal
  -- SGB/OG palette path, recolor only the world zones and let the engine do its
  -- ordinary composite. ADVANCED bakes true color into the world canvas and
  -- therefore has no palette zones; use a world-canvas-only blue grade there.
  mod.hooks:wrap("render.compose", function(next, renderer, frame)
    if not isNight() or ctx.runtime.battle or type(frame) ~= "table"
      or frame.worldActive ~= true or not isOutdoor(ctx.runtime.game) then
      return next()
    end

    local recolored = tintZones(frame.worldZones)
    if not recolored then tintTrueColorWorld(frame) end
    return next()
  end)

  -- Non-blocking transition cue. It is drawn after the game frame, so it never
  -- enters dialogue state, pauses movement, changes saves, or contaminates the
  -- world palette. The normal UI stays bright and readable at night.
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    local result = next(game, viewport)
    if mod.generation ~= 1 or noticeFrames <= 0 or not noticeText
      or ctx.runtime.battle or type(viewport) ~= "table" then
      return result
    end

    noticeFrames = noticeFrames - 1
    local sx = (tonumber(viewport.gameWidth) or 160) / 160
    local sy = (tonumber(viewport.gameHeight) or 144) / 144
    local ox = tonumber(viewport.gameX) or 0
    local oy = tonumber(viewport.gameY) or 0
    local Font = mod.ui.Font

    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(sx, sy)
    Font.drawBox(1, 1, 18, 3)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(noticeText, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
    return result
  end)
end
