---@diagnostic disable: undefined-global
-- logic.lua
-- This file owns the per-tick gameplay decision flow.

local M = {}

local LOG_THROTTLE_SECONDS = 0.75
local last_log_time = 0

local function can_log_now(now)
  return now ~= nil and (now - last_log_time) >= LOG_THROTTLE_SECONDS
end

function M.on_tick(menu, spells, targeting)
  if menu == nil or spells == nil or targeting == nil then
    return
  end

  if not menu.use_q:get() then
    return
  end

  if not spells.is_q_ready() then
    return
  end

  local q_range = spells.get_q_range()
  local target = targeting.get_q_target(q_range)

  if target == nil then
    return
  end

  -- Use game.time to prevent log spam while the same
  -- conditions stay true across many ticks.
  local now = game.time

  if not can_log_now(now) then
    return
  end

  -- We do not store the target object after this point.
  -- v1 only reports that a cast would happen.
  print('would cast Q on target')
  last_log_time = now
end

return M
