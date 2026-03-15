---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player`, `_Q`, and `_E` at runtime.
-- This hint only avoids editor false positives.
-- spells.lua
-- This file owns spell-related helpers for Zed.

local M = {}

local Q_SLOT = _Q
local E_SLOT = _E

-- Champion data (verify in-client during testing).
local Q_RANGE = 900
local E_RANGE = 290

-- Zed Q (Razor Shuriken) – linear skillshot for pred.linear.get_prediction.
M.Q_PRED_INPUT = {
  delay = 0.25,
  speed = 1700,
  width = 50,
  boundingRadiusMod = 1,
}

function M.get_q_slot()
  -- `player:spellSlot(_Q)` is documented and returns the current
  -- spell slot object for Q.
  if player == nil then
    return nil
  end

  return player:spellSlot(Q_SLOT)
end

function M.get_q_range()
  -- Keep the range in one place so it is easy to test and adjust later.
  return Q_RANGE
end

function M.get_e_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(E_SLOT)
end

function M.get_e_range()
  return E_RANGE
end

local function has_learned_q(q_slot)
  return q_slot ~= nil and q_slot.level > 0
end

function M.is_q_ready()
  local q_slot = M.get_q_slot()

  if q_slot == nil then
    return false
  end

  if not has_learned_q(q_slot) then
    return false
  end

  -- If the slot is empty, we should not treat it as ready.
  if not q_slot.isNotEmpty then
    return false
  end

  -- Cooldown is documented and easy to reason about.
  if q_slot.cooldown > 0 then
    return false
  end

  -- `spell_slot.state` is documented, but its exact ready/not-ready
  -- semantics are not clearly explained in the docs.
  -- So this v1 check is still an approximation:
  -- learned + not empty + not on cooldown.
  -- That is good enough for this first real cast step, but it may
  -- still need refinement after in-client cast testing.
  return true
end

function M.is_e_ready()
  local e_slot = M.get_e_slot()
  if e_slot == nil then
    return false
  end
  if e_slot.level <= 0 then
    return false
  end
  if not e_slot.isNotEmpty then
    return false
  end
  if e_slot.cooldown > 0 then
    return false
  end
  return true
end

return M
