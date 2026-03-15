---@diagnostic disable: undefined-global
-- Hanbot provides globals like `TYPE_HERO` at runtime.
-- targeting.lua
-- This file owns target lookup using the orb combat target.

local M = {}

local orb = module.internal('orb')

--- Returns the orb combat target if valid, in range, and an enemy hero.
--- @param range number Maximum distance to consider.
--- @return obj|nil The target or nil.
function M.get_combat_target(range)
  if orb == nil or orb.combat == nil then
    return nil
  end

  local target = (orb.combat.target or orb.combat.get_target and orb.combat.get_target())
    or (game and game.selectedTarget)

  if target == nil then
    return nil
  end

  -- Prefer orb target; game.selectedTarget needs basic validation.
  if target.valid == false then
    return nil
  end
  if target.type ~= nil and target.type ~= TYPE_HERO then
    return nil
  end
  if target.isDead then
    return nil
  end
  if not target:isValidTarget(range) then
    return nil
  end

  return target
end

--- Compatible with existing logic; delegates to get_combat_target.
function M.get_q_target(q_range)
  return M.get_combat_target(q_range)
end

return M
