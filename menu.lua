---@diagnostic disable: undefined-global
-- Hanbot provides the global `menu(...)` builder at runtime.
-- This hint only avoids editor false positives.
-- menu.lua
-- This file builds the in-game menu for the plugin.

local menu = menu('zedx_cursor', 'ZedxCursor')

menu:header('combo', 'Combo')
menu:keybind('combo_key', 'Combo Key', 'Space', nil)
menu:boolean('enable_combo', 'Enable Combo', true)
menu:dropdown('combo_mode', 'Combo Mode', 1, { 'Auto', 'Poke', 'All-In', 'Safe Harass' })
menu:boolean('use_q', 'Use Q', true)
menu:boolean('use_e', 'Use E', true)

menu:header('stage3_energy', 'Stage 3 Energy Gates')
menu:slider('energy_gate_poke', 'Min Energy: Poke', 165, 0, 200, 5)
menu:slider('energy_gate_all_in', 'Min Energy: All-In', 125, 0, 200, 5)
menu:slider('energy_gate_safe_harass', 'Min Energy: Safe Harass', 75, 0, 200, 5)

menu:header('draw_options', 'Draw')  -- 'draw' is reserved/invalid in Hanbot menuconfig
menu:boolean('draw_q_range', 'Draw Q Range', true)
menu:boolean('draw_e_range', 'Draw E Range', true)

menu:header('debug', 'Debug')
menu:boolean('debug_logs', 'Debug Logs', false)
menu:boolean('debug_diag', 'Diag (prints why no Q)', false)
menu:boolean('debug_stage3', 'Stage 3 Branch/Shadow Logs', false)

return menu
