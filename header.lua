---@diagnostic disable: undefined-global
-- header.lua
-- This file tells Hanbot what the plugin is called
-- and when it should load.

return {
  id = 'zedx_cursor',
  name = 'ZedxCursor',
  load = function()
    -- Only load this starter when the local player is Zed.
    return player ~= nil and player.charName == 'Zed'
  end,
}
