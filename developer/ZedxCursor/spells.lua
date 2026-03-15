---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player` and `_Q` at runtime.
-- This file owns spell-related helpers for Zed.
-- Task 3: Spell layer with Q pred_input, E support, readiness checks.

local M = {}

local Q_SLOT = _Q
local E_SLOT = _E

-- Champion data (verify in-client during testing).
local Q_RANGE = 900
local E_RANGE = 290

-- Zed Q (Razor Shuriken) – linear skillshot for pred.linear.get_prediction.
-- Tune delay/speed/width per patch or in-client tests.
M.Q_PRED_INPUT = {
  delay = 0.25,
  speed = 1700,
  width = 50,
  boundingRadiusMod = 1,
}

function M.get_q_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(Q_SLOT)
end

function M.get_q_range()
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

local function slot_ready(slot)
  if slot == nil then
    return false
  end
  if slot.level <= 0 then
    return false
  end
  if not slot.isNotEmpty then
    return false
  end
  if slot.cooldown > 0 then
    return false
  end
  return true
end

function M.is_q_ready()
  return slot_ready(M.get_q_slot())
end

function M.is_e_ready()
  return slot_ready(M.get_e_slot())
end

return M
