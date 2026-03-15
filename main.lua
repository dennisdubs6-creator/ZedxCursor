---@diagnostic disable: undefined-global
-- Hanbot provides globals like `module` and `cb` at runtime.
-- This file keeps extra suppressions targeted to the one place
-- where the editor cannot understand Hanbot's module loader.
-- main.lua
-- This is the entry point. It loads the other files
-- and registers the Hanbot callbacks.

local PLUGIN_ID = 'zedx_cursor'

local function load_plugin_module(file_name)
  -- Hanbot examples use `module.load(...)`, but the editor treats
  -- that API as unknown because it is injected by the platform.
  ---@diagnostic disable-next-line: undefined-field, deprecated
  return module.load(PLUGIN_ID, file_name)
end

---@diagnostic disable-next-line: undefined-field
local orb = module.internal('orb')
---@diagnostic disable-next-line: undefined-field
local pred = module.internal('pred')

local menu = load_plugin_module('menu')
local spells = load_plugin_module('spells')
local targeting = load_plugin_module('targeting')
local logic = load_plugin_module('logic')
local draw = load_plugin_module('draw')

-- Run every tick when combo is active (cb.tick is more reliable than
-- f_pre_tick at range, since orb may not tick when outside AA range).
-- Use orb combat when available, else our combo keybind.
local diag_last = 0
cb.add(cb.tick, function()
  local now = game and game.time or 0
  local diag = menu.debug_diag and menu.debug_diag:get()
  local combo_active = (orb.combat and orb.combat.is_active and orb.combat.is_active())
    or (menu.combo_key and menu.combo_key:get())
  if diag and (now - diag_last) > 1 then
    diag_last = now
    print(string.format('[Zedx] enable_combo=%s combo_active=%s', tostring(menu.enable_combo:get()), tostring(combo_active)))
  end
  if menu.enable_combo:get() and (combo_active or diag) then
    logic.on_tick(menu, spells, targeting, orb, pred)
  end
end)

-- The draw callback should stay lightweight and drawing-only.
cb.add(cb.draw, function()
  draw.on_draw(menu, spells)
end)

print('ZedxCursor loaded. Enable Debug Logs or Diag to see why Q might not cast.')
