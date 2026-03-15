---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player` and `_Q` at runtime.
-- This hint only avoids editor false positives.
-- spells.lua
-- This file owns spell-related helpers for Zed.

local M = {}

local Q_SLOT = _Q

-- This is champion data, not a Hanbot API value.
-- It should be verified in the client during testing.
local Q_RANGE = 900

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

return M
