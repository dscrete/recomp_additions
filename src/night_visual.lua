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

-- Standard OVERWORLD light sources. $0A is the house window. The four door
-- tiles are also present, but only their small glass panel is lit: the mask is
-- expressed in tile-local pixels so the wooden/stone door frame stays dark.
local LIGHT_TILES = {
  [0x0A] = { x = 0, y = 0, w = 8, h = 8 },
  [0x0B] = { x = 4, y = 3, w = 4, h = 5 },
  [0x0C] = { x = 0, y = 3, w = 5, h = 5 },
  [0x1B] = { x = 4, y = 0, w = 4, h = 2 },
  [0x1C] = { x = 0, y = 0, w = 5, h = 2 },
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
    if type(world) ~= "table" or type(map) ~= "table" then return nil end

    local canvas = frame and frame.worldCanvas
    local viewW = canvas and canvas:getWidth() or 160
    local viewH = canvas and canvas:getHeight() or 144
    local camera = world.camera
    local camX = camera and tonumber(camera.x) or nil
    local camY = camera and tonumber(camera.y) or nil
    if camX == nil or camY == nil then
      local player = world.player
      local px = player and tonumber(player.px)
      local py = player and tonumber(player.py)
      if px == nil or py == nil then return nil end
      -- src/render/Camera.lua: Camera:follow()
      camX = px - (viewW / 2 - 16)
      camY = py - (viewH / 2 - 8)
    end
    return world, math.floor(camX), math.floor(camY), viewW, viewH
  end

  -- The engine draws the current map at (0,0) in world coordinates and every
  -- connected neighbour at its authored nb.ox/nb.oy offset. Scan those same
  -- resident maps and transform their light-source tiles into canvas coords.
  -- This keeps Pallet's windows lit even after the player steps onto Route 1
  -- while Pallet remains visible across the connection seam.
  local function eachVisibleLight(frame, fn)
    local world, camX, camY, viewW, viewH = worldView(frame)
    if not world then return false end

    local maps = { { map = world.map, ox = 0, oy = 0 } }
    for _, nb in ipairs(world.neighbors or {}) do
      if type(nb) == "table" and nb.map then
        maps[#maps + 1] = {
          map = nb.map,
          ox = tonumber(nb.ox) or 0,
          oy = tonumber(nb.oy) or 0,
        }
      end
    end

    local found = false
    for _, placed in ipairs(maps) do
      local map, ox, oy = placed.map, placed.ox, placed.oy
      if type(map) == "table" and map.tileset
        and map.tileset.id == "OVERWORLD"
        and type(map.tileset.blocks) == "table"
        and type(map.blockAt) == "function" then

        local localCamX = camX - ox
        local localCamY = camY - oy
        local mapTilesW = (map.def.width or 0) * 4
        local mapTilesH = (map.def.height or 0) * 4
        local tx0 = math.max(0, math.floor(localCamX / 8))
        local ty0 = math.max(0, math.floor(localCamY / 8))
        local tx1 = math.min(mapTilesW - 1,
                             math.floor((localCamX + viewW) / 8))
        local ty1 = math.min(mapTilesH - 1,
                             math.floor((localCamY + viewH) / 8))

        if tx1 >= tx0 and ty1 >= ty0 then
          local blocks = map.tileset.blocks
          for ty = ty0, ty1 do
            local by, ciY = math.floor(ty / 4), ty % 4
            for tx = tx0, tx1 do
              local blockId = map:blockAt(math.floor(tx / 4), by)
              local block = blockId ~= nil and blocks[blockId + 1] or nil
              local tile = block and block[ciY * 4 + (tx % 4) + 1] or nil
              local light = LIGHT_TILES[tile]
              if light then
                found = true
                fn(map, tile,
                   ox + tx * 8 - camX,
                   oy + ty * 8 - camY,
                   light)
              end
            end
          end
        end
      end
    end
    return found
  end

  local function addLitWindowZones(frame)
    local zones = frame and frame.worldZones
    if type(zones) ~= "table" then return end
    eachVisibleLight(frame, function(_, _, x, y, light)
      zones[#zones + 1] = {
        x = x + light.x, y = y + light.y,
        w = light.w, h = light.h,
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
  -- an empty world-zone list, so palette zones cannot brighten the lights at
  -- all. Redraw the authored source tile through a tile-local scissor after the
  -- blue night grade, then add a warm boost. Windows use the full tile; doors
  -- only expose the glass-panel rectangle.
  local function drawTrueColorWindows(frame)
    local canvas = frame and frame.worldCanvas
    if not canvas or not love.graphics.setCanvas then return end
    local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
    local previousMode, previousAlpha
    if love.graphics.getBlendMode then
      previousMode, previousAlpha = love.graphics.getBlendMode()
    end

    love.graphics.setCanvas(canvas)

    eachVisibleLight(frame, function(map, tile, x, y, light)
      local tr = map.renderer
      local image = tr and tr.image
      local quad = tr and tr.quads and tr.quads[tile]
      if not image or not quad then return end

      local sx = math.max(0, x + light.x)
      local sy = math.max(0, y + light.y)
      local ex = math.min(canvas:getWidth(), x + light.x + light.w)
      local ey = math.min(canvas:getHeight(), y + light.y + light.h)
      if ex <= sx or ey <= sy then return end
      love.graphics.setScissor(sx, sy, ex - sx, ey - sy)

      -- Restore the undarkened source pixels with a strong warm tint.
      love.graphics.setBlendMode("alpha", "alphamultiply")
      love.graphics.setColor(1.0, 0.86, 0.40, 0.98)
      love.graphics.draw(image, quad, x, y)

      -- Additive drawing makes the pane's bright pixels read as emitted light.
      love.graphics.setBlendMode("add", "alphamultiply")
      love.graphics.setColor(1.0, 0.58, 0.10, 0.46)
      love.graphics.draw(image, quad, x, y)
    end)

    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
    if previousMode then
      love.graphics.setBlendMode(previousMode, previousAlpha)
    else
      love.graphics.setBlendMode("alpha", "alphamultiply")
    end
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
  -- light graphics as warm sources. A render pipeline (Battle Art) owns its
  -- own lighting and is left completely untouched.
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
