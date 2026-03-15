---@diagnostic disable: undefined-global
-- Hanbot provides the global `menu(...)` builder at runtime.
-- This hint only avoids editor false positives.
-- menu.lua
-- This file builds the in-game menu for the plugin.

local menu = menu('zedx_cursor', 'ZedxCursor')

menu:header('combo', 'Combo')
menu:keybind('combo_key', 'Combo Key', 'Space', nil)
menu:boolean('enable_combo', 'Enable Combo', true)
menu:boolean('use_q', 'Use Q', true)
menu:boolean('use_e', 'Use E', true)

menu:header('draw_options', 'Draw')  -- 'draw' is reserved/invalid in Hanbot menuconfig
menu:boolean('draw_q_range', 'Draw Q Range', true)
menu:boolean('draw_e_range', 'Draw E Range', true)

menu:header('debug', 'Debug')
menu:boolean('debug_logs', 'Debug Logs', false)
menu:boolean('debug_diag', 'Diag (prints why no Q)', false)

return menu
