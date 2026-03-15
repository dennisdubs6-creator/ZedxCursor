---@diagnostic disable: undefined-global
-- Hanbot provides globals like `player`, `_Q`, and `_E` at runtime.
-- This hint only avoids editor false positives.
-- spells.lua
-- This file owns spell-related helpers for Zed.

local M = {}

local Q_SLOT = _Q
local W_SLOT = _W
local E_SLOT = _E
local R_SLOT = _R

-- Champion data (verify in-client during testing).
local Q_RANGE = 900
local W_RANGE = 650
local E_RANGE = 290
local R_RANGE = 625
local W_SHADOW_LIFETIME = 5.25
local W_SHADOW_SETTLE_DELAY = 0.10

local DEFAULT_BRANCH_ENERGY_GATES = {
  poke = 165,
  all_in = 125,
  safe_harass = 75,
}

-- Zed Q (Razor Shuriken) – linear skillshot for pred.linear.get_prediction.
M.Q_PRED_INPUT = {
  delay = 0.25,
  speed = 1700,
  width = 50,
  boundingRadiusMod = 1,
}

local function has_learned_spell(slot)
  return slot ~= nil and slot.level > 0
end

local function is_slot_ready(slot)
  if slot == nil then
    return false
  end
  if not has_learned_spell(slot) then
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

local function get_spell_name(slot)
  if slot == nil or slot.name == nil then
    return ''
  end
  return tostring(slot.name)
end

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

function M.get_w_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(W_SLOT)
end

function M.get_w_range()
  return W_RANGE
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

function M.get_r_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(R_SLOT)
end

function M.get_r_range()
  return R_RANGE
end

function M.get_w_shadow_lifetime()
  return W_SHADOW_LIFETIME
end

function M.get_w_shadow_settle_delay()
  return W_SHADOW_SETTLE_DELAY
end

function M.get_branch_energy_gate(branch)
  return DEFAULT_BRANCH_ENERGY_GATES[branch] or 0
end

function M.get_current_energy()
  if player == nil then
    return 0
  end

  -- In Hanbot runtimes, `par` is the most reliable generic resource field
  -- for energy users, while `mana` remains a safe fallback.
  if player.par ~= nil then
    return player.par
  end

  return player.mana or 0
end

function M.get_max_energy()
  if player == nil then
    return 0
  end
  if player.maxPar ~= nil then
    return player.maxPar
  end
  return player.maxMana or 0
end

function M.is_q_ready()
  local q_slot = M.get_q_slot()
  if not is_slot_ready(q_slot) then
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

function M.is_w_ready()
  return is_slot_ready(M.get_w_slot())
end

function M.is_e_ready()
  return is_slot_ready(M.get_e_slot())
end

function M.is_r_ready()
  return is_slot_ready(M.get_r_slot())
end

function M.get_w_spell_name()
  return get_spell_name(M.get_w_slot())
end

function M.get_r_spell_name()
  return get_spell_name(M.get_r_slot())
end

function M.is_w_swap_ready()
  local w_slot = M.get_w_slot()
  if w_slot == nil then
    return false
  end

  local spell_name = string.lower(get_spell_name(w_slot))
  if spell_name == 'zedw2' or spell_name:find('w2', 1, true) ~= nil then
    return true
  end

  return (w_slot.toggleState or 0) ~= 0
end

function M.is_r_swap_ready()
  local r_slot = M.get_r_slot()
  if r_slot == nil then
    return false
  end

  local spell_name = string.lower(get_spell_name(r_slot))
  if spell_name == 'zedr2' or spell_name:find('r2', 1, true) ~= nil then
    return true
  end

  return (r_slot.toggleState or 0) ~= 0
end

return M
