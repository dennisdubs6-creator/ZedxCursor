---@diagnostic disable: undefined-global
-- menu.lua
-- This file builds the in-game menu for the plugin.

local menu = menu('zedx_cursor', 'ZedxCursor')

menu:header('settings', 'Settings')

-- v1 only needs one gameplay toggle.
menu:boolean('use_q', 'Use Q', true)

return menu
