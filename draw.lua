---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player`, `graphics`, and color values
-- at runtime. This hint only avoids editor false positives.
-- draw.lua
-- This file only handles lightweight drawing work.

local M = {}
local DRAW_POINT_COUNT = 32

function M.on_draw(spells)
  if spells == nil or player == nil then
    return
  end

  local q_range = spells.get_q_range()

  if q_range == nil or q_range <= 0 then
    return
  end

  -- v1 only draws the Q range around the player.
  graphics.draw_circle(player.pos, q_range, 2, COLOR_WHITE, DRAW_POINT_COUNT)
end

return M
