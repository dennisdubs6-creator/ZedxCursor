---@diagnostic disable: undefined-global
-- Hanbot provides the global `menu(...)` builder at runtime.
-- This hint only avoids editor false positives.
-- menu.lua
-- This file builds the in-game menu for the plugin.

local menu = menu('zedx_cursor', 'ZedxCursor')

menu:header('settings', 'Settings')

-- `use_q` controls whether the tick logic should consider Q at all.
menu:boolean('use_q', 'Use Q', true)

-- `debug_logs` controls whether the script prints beginner-friendly
-- debug messages when Q would be used.
menu:boolean('debug_logs', 'Debug Logs', true)

return menu
