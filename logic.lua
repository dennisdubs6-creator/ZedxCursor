---@diagnostic disable: undefined-global
-- Hanbot provides globals like `game` at runtime.
-- This hint only avoids editor false positives.
-- logic.lua
-- This file owns the per-tick gameplay decision flow.

local M = {}

local LOG_THROTTLE_SECONDS = 0.75
local last_log_time = 0

local function can_log_now(now)
  return now ~= nil and (now - last_log_time) >= LOG_THROTTLE_SECONDS
end

local function get_target_name(target)
  if target == nil then
    return 'unknown'
  end

  -- `charName` is documented for hero objects.
  if target.charName ~= nil and target.charName ~= '' then
    return target.charName
  end

  -- `name` is also documented on objects, so this is a safe fallback.
  if target.name ~= nil and target.name ~= '' then
    return target.name
  end

  return 'unknown'
end

local function build_debug_message(target, q_range)
  local target_name = get_target_name(target)

  return string.format(
    'attempting Q cast on target: %s | q_ready=true | q_range=%d',
    target_name,
    q_range
  )
end

function M.on_tick(menu, spells, targeting)
  if menu == nil or spells == nil or targeting == nil then
    return
  end

  if not menu.use_q:get() then
    return
  end

  local q_ready = spells.is_q_ready()

  if not q_ready then
    return
  end

  local q_range = spells.get_q_range()
  local target = targeting.get_q_target(q_range)
  local q_slot = spells.get_q_slot()

  if target == nil or q_slot == nil then
    return
  end

  -- Use game.time to prevent log spam while the same
  -- conditions stay true across many ticks.
  local now = game.time

  if not can_log_now(now) then
    return
  end

  if menu.debug_logs:get() then
    print(build_debug_message(target, q_range))
  end

  -- This is the smallest real cast step:
  -- cast Q as a position spell at the selected target's current position.
  -- This uses documented APIs only:
  -- `player:castSpell('pos', slot, vec3)` plus `target.pos`.
  -- It is still a simple first attempt, not prediction.
  player:castSpell('pos', q_slot.slot, target.pos)

  last_log_time = now
end

return M
