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

local menu = load_plugin_module('menu')
local spells = load_plugin_module('spells')
local targeting = load_plugin_module('targeting')
local logic = load_plugin_module('logic')
local draw = load_plugin_module('draw')

-- The tick callback runs often, so keep it small and delegate.
cb.add(cb.tick, function()
  logic.on_tick(menu, spells, targeting)
end)

-- The draw callback should stay lightweight and drawing-only.
cb.add(cb.draw, function()
  draw.on_draw(spells)
end)

print('ZedxCursor v1 scaffold loaded')
