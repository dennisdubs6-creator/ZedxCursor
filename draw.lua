---@diagnostic disable: undefined-global
-- draw.lua
-- This file only handles lightweight drawing work.

local M = {}

function M.on_draw(spells)
  if spells == nil or player == nil then
    return
  end

  local q_range = spells.get_q_range()

  if q_range == nil or q_range <= 0 then
    return
  end

  -- v1 only draws the Q range around the player.
  graphics.draw_circle(player.pos, q_range, 2, COLOR_WHITE, 100)
end

return M
