---@diagnostic disable: undefined-global
-- spells.lua
-- This file owns spell-related helpers for Zed.

local M = {}

local Q_SLOT = _Q

-- This is champion data, not a Hanbot API value.
-- It should be verified in the client during testing.
local Q_RANGE = 900

function M.get_q_slot()
  if player == nil then
    return nil
  end

  return player:spellSlot(Q_SLOT)
end

function M.get_q_range()
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
  -- Keep the readiness logic isolated here so we can refine it
  -- after in-client testing without touching the rest of the scaffold.
  return true
end

return M
