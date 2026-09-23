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

-- Pallet's standard house windows use OVERWORLD tile $0A. The previous
-- $0B/$0C/$1B/$1C mapping was the glass-panelled DOOR, which is why the door
-- lit correctly while the actual windows stayed dark. The same $0A pane is
-- reused across the standard OVERWORLD house facade.
local WINDOW_TILES = {
  [0x0A] = true,
}
local WINDOW_RAMP = {
  { 255, 252, 218 },
  { 255, 222, 118 },
  { 218, 142, 44 },
  { 72, 40, 20 },
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

  local function worldView(frame)
    local game = ctx.runtime.game
    local world = game and (game.overworld or game.world)
    local map = world and world.map
    if type(map) ~= "table" or not map.tileset
      or map.tileset.id ~= "OVERWORLD" then return nil end

    local canvas = frame and frame.worldCanvas
    local viewW = canvas and canvas:getWidth() or 160
    local viewH = canvas and canvas:getHeight() or 144
    local camera = world and world.camera
    local camX = camera and tonumber(camera.x) or nil
    local camY = camera and tonumber(camera.y) or nil
    if camX == nil or camY == nil then
      local player = world and world.player
      local px = player and tonumber(player.px)
      local py = player and tonumber(player.py)
      if px == nil or py == nil then return nil end
      -- src/render/Camera.lua: Camera:follow()
      camX = px - (viewW / 2 - 16)
      camY = py - (viewH / 2 - 8)
    end
    return world, map, math.floor(camX), math.floor(camY), viewW, viewH
  end

  local function eachVisibleWindow(frame, fn)
    local _, map, camX, camY, viewW, viewH = worldView(frame)
    if not map then return false end
    local blocks = map.tileset.blocks
    if type(blocks) ~= "table" or type(map.blockAt) ~= "function" then return false end

    local tx0 = math.max(0, math.floor(camX / 8))
    local ty0 = math.max(0, math.floor(camY / 8))
    local tx1 = math.min((map.def.width or 0) * 4 - 1,
                         math.floor((camX + viewW) / 8))
    local ty1 = math.min((map.def.height or 0) * 4 - 1,
                         math.floor((camY + viewH) / 8))
    local found = false
    for ty = ty0, ty1 do
      local by, ciY = math.floor(ty / 4), ty % 4
      for tx = tx0, tx1 do
        local blockId = map:blockAt(math.floor(tx / 4), by)
        local block = blockId ~= nil and blocks[blockId + 1] or nil
        local tile = block and block[ciY * 4 + (tx % 4) + 1] or nil
        if WINDOW_TILES[tile] then
          found = true
          fn(map, tile, tx * 8 - camX, ty * 8 - camY)
        end
      end
    end
    return found
  end

  local function addLitWindowZones(frame)
    local zones = frame and frame.worldZones
    if type(zones) ~= "table" then return end
    eachVisibleWindow(frame, function(_, _, x, y)
      zones[#zones + 1] = {
        x = x, y = y, w = 8, h = 8,
        colors = WINDOW_RAMP,
      }
    end)
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

  -- GBC/ADVANCED color modes bake true color into the tileset atlas and return
  -- an empty world-zone list, so palette zones cannot brighten the windows at
  -- all. Redraw the *actual window tile art* after the blue night grade. That
  -- bypasses the darkening for the panes, keeps their dark pixel detail intact,
  -- and adds a warm additive boost so they read like Gold's lit windows.
  local function drawTrueColorWindows(frame)
    local canvas = frame and frame.worldCanvas
    if not canvas or not love.graphics.setCanvas then return end
    local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
    local previousMode, previousAlpha
    if love.graphics.getBlendMode then
      previousMode, previousAlpha = love.graphics.getBlendMode()
    end

    love.graphics.setCanvas(canvas)
    love.graphics.setScissor(0, 0, canvas:getWidth(), canvas:getHeight())

    eachVisibleWindow(frame, function(map, tile, x, y)
      local tr = map.renderer
      local image = tr and tr.image
      local quad = tr and tr.quads and tr.quads[tile]
      if not image or not quad then return end

      -- First put the undarkened source pane back with a strong warm tint.
      love.graphics.setBlendMode("alpha", "alphamultiply")
      love.graphics.setColor(1.0, 0.86, 0.40, 0.98)
      love.graphics.draw(image, quad, x, y)

      -- Then make the pane's brighter pixels emit extra warm light.
      love.graphics.setBlendMode("add", "alphamultiply")
      love.graphics.setColor(1.0, 0.58, 0.10, 0.46)
      love.graphics.draw(image, quad, x, y)
    end)

    love.graphics.setColor(1, 1, 1, 1)
    if previousMode then
      love.graphics.setBlendMode(previousMode, previousAlpha)
    else
      love.graphics.setBlendMode("alpha", "alphamultiply")
    end
    love.graphics.setScissor()
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
  -- SGB/OG palette path, recolor only the world zones. GBC/ADVANCED already
  -- contains true-color pixels, so darken the canvas and redraw the authored
  -- window graphics as warm light sources. A render pipeline (Battle Art) owns
  -- its own lighting and is left completely untouched.
  mod.hooks:wrap("render.compose", function(next, renderer, frame)
    if not isNight() or ctx.runtime.battle or type(frame) ~= "table"
      or frame.worldActive ~= true or frame.worldOverride
      or not isOutdoor(ctx.runtime.game) then
      return next()
    end

    local recolored = tintZones(frame.worldZones)
    if recolored then
      addLitWindowZones(frame)
    else
      tintTrueColorWorld(frame)
      drawTrueColorWindows(frame)
    end
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
