---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player`, `graphics`, and color values
-- at runtime. This hint only avoids editor false positives.
-- draw.lua
-- This file only handles lightweight drawing work. Keep it lightweight.

local M = {}
local DRAW_POINT_COUNT = 32
local LINE_WIDTH = 2

function M.on_draw(menu, spells)
  if menu == nil or spells == nil or player == nil then
    return
  end

  if menu.draw_q_range:get() then
    local q_range = spells.get_q_range()
    if q_range ~= nil and q_range > 0 then
      graphics.draw_circle(player.pos, q_range, LINE_WIDTH, COLOR_WHITE, DRAW_POINT_COUNT)
    end
  end

  if menu.draw_e_range:get() then
    local e_range = spells.get_e_range()
    if e_range ~= nil and e_range > 0 then
      graphics.draw_circle(player.pos, e_range, LINE_WIDTH, COLOR_WHITE, DRAW_POINT_COUNT)
    end
  end
end

return M
