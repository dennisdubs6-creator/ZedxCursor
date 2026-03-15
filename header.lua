---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player` at runtime.
-- This hint only avoids editor false positives.
-- header.lua
-- This file tells Hanbot what the plugin is called
-- and when it should load.

return {
  id = 'zedx_cursor',
  name = 'ZedxCursor',
  load = function()
    -- Only load this starter when the local player is Zed.
    -- `player.charName` is documented on Hanbot hero objects.
    return player ~= nil and player.charName == 'Zed'
  end,
}
