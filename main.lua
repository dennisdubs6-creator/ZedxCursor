---@diagnostic disable: undefined-global, undefined-field, deprecated
-- main.lua
-- This is the entry point. It loads the other files
-- and registers the Hanbot callbacks.

local PLUGIN_ID = 'zedx_cursor'

local menu = module.load(PLUGIN_ID, 'menu')
local spells = module.load(PLUGIN_ID, 'spells')
local targeting = module.load(PLUGIN_ID, 'targeting')
local logic = module.load(PLUGIN_ID, 'logic')
local draw = module.load(PLUGIN_ID, 'draw')

cb.add(cb.tick, function()
  logic.on_tick(menu, spells, targeting)
end)

cb.add(cb.draw, function()
  draw.on_draw(spells)
end)

print('ZedxCursor v1 scaffold loaded')
