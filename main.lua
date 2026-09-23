-- Kanto Expansion for Gen1Recomp (API 2)
-- Multi-file mods are loaded through mod:read + sandboxed load(), the supported
-- Gen1Recomp pattern for code shipped inside a mod.

local MODULES = {
  "src/core.lua",
  "src/extras.lua",
  "src/trainers.lua",
  "src/world.lua",
  "src/compat.lua",
  "src/night_visual.lua",
  "src/pokemon.lua",
  "src/ui.lua",
  "src/api.lua",
}

local function loadModule(mod, path)
  local source, readErr = mod:read(path)
  assert(source, ("Kanto Expansion could not read %s: %s"):format(path, tostring(readErr)))
  local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. path)
  assert(chunk, ("Kanto Expansion could not compile %s: %s"):format(path, tostring(compileErr)))
  local factory = chunk()
  assert(type(factory) == "function", path .. " must return a module function")
  return factory
end

return function(mod)
  mod.options:define({
    { key = "enabled", label = "EXPANSION", type = "toggle", default = true },
    { key = "director", label = "WORLD DIRECTOR", type = "toggle", default = true },
    { key = "personalities", label = "POKEMON PERSONALITIES", type = "toggle", default = true },
    { key = "trainer_memory", label = "TRAINER MEMORY", type = "toggle", default = true },
    { key = "rumors", label = "RUMORS", type = "toggle", default = true },
    { key = "luck", label = "WORLD MOODS", type = "toggle", default = true },
    { key = "rocket_heat", label = "ROCKET HEAT", type = "toggle", default = true },
    { key = "ecology", label = "ROUTE ECOLOGY", type = "toggle", default = true },
    { key = "wild_anomalies", label = "STRANGE ENCOUNTERS", type = "toggle", default = true },
    { key = "night_cycle", label = "AFTER DARK", type = "toggle", default = true },
    {
      key = "night_time_source", label = "TIME SOURCE", type = "choice",
      default = "REAL_TIME",
      choices = {
        { "REAL TIME", "REAL_TIME" },
        { "ACCELERATED", "ACCELERATED" },
        { "FIXED DAY", "FIXED_DAY" },
        { "FIXED NIGHT", "FIXED_NIGHT" },
      },
    },
    { key = "anti_randomizer", label = "RUN MUTATIONS", type = "toggle", default = true },
    { key = "ui_entry", label = "START MENU ENTRY", type = "toggle", default = true },
    {
      key = "night_cycle_preset",
      label = "DAY/NIGHT LENGTH",
      type = "choice",
      default = 1024,
      choices = {
        { "VERY FAST (256)", 256 },
        { "FAST (512)", 512 },
        { "NORMAL (1024)", 1024 },
        { "LONG (2048)", 2048 },
        { "VERY LONG (4096)", 4096 },
        { "MARATHON (8192)", 8192 },
      },
    },
    { key = "night_visual", label = "NIGHT VISUAL", type = "toggle", default = true },
    { key = "anomaly_rate", label = "ODD ENCOUNTER %", type = "number", default = 2,
      min = 0, max = 15, step = 1 },
  })

  local ctx
  for i, path in ipairs(MODULES) do
    local factory = loadModule(mod, path)
    if i == 1 then
      ctx = factory(mod)
      assert(type(ctx) == "table", "src/core.lua must return the expansion context")
    else
      factory(mod, ctx)
    end
  end

  mod.log:info("Kanto Expansion framework %s loaded", mod.version)
end
