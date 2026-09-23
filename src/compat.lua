-- Renderer interoperability adapters.
--
-- Kanto Expansion owns Gen 1's semantic clock, not another mod's pixels.
-- Battle Art already has a full voxel day/night renderer; when it is set to
-- SYNC, feed that renderer our Kanto hour through its deliberately named
-- DayNight.hours seam. Its explicit time modes remain Battle Art overrides.
return function(mod, ctx)
  local BATTLE_ART_ID = "BATTLE_ART_VOXEL_FORK"
  local installed, dayNight, originalHours, wrappedHours = false, nil, nil, nil

  local function installBattleArt()
    if installed or mod.generation ~= 1 then return installed end
    local other = mod.find(BATTLE_ART_ID)
    local exports = other and other.exports
    local lib = exports and exports.lib
    if type(lib) ~= "table" or type(lib.require) ~= "function" then return false end

    local ok, candidate = pcall(lib.require, "DayNight")
    if not ok or type(candidate) ~= "table" or type(candidate.hours) ~= "function" then
      return false
    end

    dayNight, originalHours = candidate, candidate.hours
    candidate.hours = function()
      if ctx.feature("night_cycle") then
        local hour = ctx.currentHour()
        if type(hour) == "number" then return hour % 24 end
      end
      return originalHours()
    end
    installed = true
    mod.log:info("Battle Art SYNC clock is following Kanto Expansion time")
    return true
  end

  local function uninstallBattleArt()
    if installed and dayNight and originalHours then dayNight.hours = originalHours end
    installed, dayNight, originalHours = false, nil, nil
  end

  -- optional_dependencies guarantees Battle Art loads first when present.
  -- mods.loaded also makes this resilient to future load-order changes.
  installBattleArt()
  mod.events:on("mods.loaded", installBattleArt)

  mod.hooks:wrap("core.quit_to_launcher", function(next, ...)
    uninstallBattleArt()
    return next(...)
  end)
end
