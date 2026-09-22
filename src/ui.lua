return function(mod, ctx)
  mod.content.screens:register(ctx.SCREEN_ID, {
    new = function(game)
      local Font = mod.ui.Font
      local state = { isOpaque = true }

      function state:update()
        if game.input:wasPressed("b") then game.stack:pop() end
      end

      function state:draw()
        local rumor = ctx.currentRumor()
        local mutations = ctx.ensureRunMutations()
        local mutationText = #mutations > 0 and table.concat(mutations, ",") or "NONE"
        local rep = ctx.reputation()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("KANTO EXPANSION", 8, 8)
        Font.draw("MOOD " .. tostring(ctx.worldMood()), 8, 20)
        Font.draw("ROCKET " .. tostring(ctx.getHeat()), 8, 32)
        Font.draw("RUMOR " .. ctx.truncate(rumor and rumor.id or "NONE", 11), 8, 44)
        Font.draw("TIP " .. ctx.truncate(mod.save:get("current_tip", "NONE"), 13), 8, 56)
        Font.draw("BOARD " .. ctx.truncate(mod.save:get("current_bulletin", "NONE"), 11), 8, 68)
        Font.draw("MUT " .. ctx.truncate(mutationText, 13), 8, 80)
        Font.draw(("BTL %d CAT %d"):format(tonumber(rep.battles) or 0, tonumber(rep.catches) or 0), 8, 92)
        Font.draw("MUSEUM " .. tostring(ctx.exhibitCount()), 8, 104)
        Font.draw("PARTY " .. ctx.truncate(ctx.superstition(game), 11), 8, 116)
        Font.draw("B: EXIT", 8, 128)
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
