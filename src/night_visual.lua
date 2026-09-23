-- Lightweight Gen 1 presentation fallback for the synthetic day/night cycle.
-- Gameplay time-of-day is owned by world.tod; this module only communicates
-- NIGHT visually. Gen 2/Gold has native time-of-day presentation, so the
-- fallback deliberately retires itself as soon as the renderer reports a
-- generation other than 1.
return function(mod, ctx)
  local function active()
    if not ctx.feature("night_cycle") or not ctx.feature("night_visual") then return false end
    if ctx.runtime.battle then return false end
    if ctx.runtime.generation ~= nil and ctx.runtime.generation ~= 1 then return false end
    return ctx.currentTodFromSteps() == "NIGHT"
  end

  -- render.output is gated because asking the engine for a composed output
  -- canvas has a cost. Preserve another mod's request if one already needs it.
  mod.hooks:wrap("render.output_enabled", function(next)
    if next() == true then return true end
    return active()
  end)

  mod.hooks:wrap("render.output", function(next, frame)
    if type(frame) ~= "table" then return next(frame) end
    if frame.generation ~= nil then ctx.runtime.generation = frame.generation end

    -- Let earlier/lower-priority output owners render first. If nobody handled
    -- the frame, draw the engine's finished composite ourselves before adding
    -- the night veil.
    local handled = next(frame)
    if frame.generation ~= 1 or not active() then return handled end

    if handled ~= true then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(frame.canvas, 0, 0)
    end

    -- No shader and no asset replacement: a mild cool/dark veil is enough to
    -- make Gen 1 night immediately legible while remaining easy to remove when
    -- a target game provides its own native day/night rendering.
    love.graphics.setScissor()
    love.graphics.setColor(0.03, 0.07, 0.18, 0.20)
    love.graphics.rectangle("fill", 0, 0, frame.width, frame.height)
    love.graphics.setColor(1, 1, 1, 1)
    return true
  end)
end
