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
local W_SHADOW_LIFETIME = 4.50
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

-- Checks if a spell slot has been learned.
-- @param slot The spell slot object (or `nil`) to inspect; expected to have a numeric `level` field.
-- @return `true` if `slot` is non-nil and `slot.level` is greater than 0, `false` otherwise.
local function has_learned_spell(slot)
  return slot ~= nil and slot.level > 0
end

-- Checks if a spell slot is usable (learned, populated, and not on cooldown).
-- @param slot The spell slot object to evaluate (may be nil).
-- @return `true` if the slot is learned, is populated, and its cooldown is zero; `false` otherwise.
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

-- Returns the name of a spell slot as a string, or an empty string if unavailable.
-- @param slot The spell slot object; may be nil or missing a `name` field.
-- @return The slot's name as a string, or `''` if `slot` or `slot.name` is nil.
local function get_spell_name(slot)
  if slot == nil or slot.name == nil then
    return ''
  end
  return tostring(slot.name)
end

-- Get the current Q spell slot object for the local player.
-- @return The Q spell slot object, or `nil` if the player is unavailable.
function M.get_q_slot()
  -- `player:spellSlot(_Q)` is documented and returns the current
  -- spell slot object for Q.
  if player == nil then
    return nil
  end

  return player:spellSlot(Q_SLOT)
end

-- Get the configured range for the Q spell.
-- @return The Q spell range in units.
function M.get_q_range()
  -- Keep the range in one place so it is easy to test and adjust later.
  return Q_RANGE
end

-- Retrieve the player's current W spell slot.
-- @return The W spell slot object, or nil if the player is not available.
function M.get_w_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(W_SLOT)
end

-- Get the configured range for the W spell.
-- @return The W spell range in game units.
function M.get_w_range()
  return W_RANGE
end

-- Retrieves the current E spell slot for the local player.
-- @return The E spell slot object, or `nil` if the player is not available.
function M.get_e_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(E_SLOT)
end

-- Retrieves the configured E spell range.
-- @return The E spell range in game units.
function M.get_e_range()
  return E_RANGE
end

-- Get the player's current R spell slot.
-- @return The R spell slot object, or `nil` if the global `player` is not available.
function M.get_r_slot()
  if player == nil then
    return nil
  end
  return player:spellSlot(R_SLOT)
end

-- Get the configured range for the R spell.
-- @return The R spell range in units (number).
function M.get_r_range()
  return R_RANGE
end

-- Returns the configured lifetime, in seconds, of the W shadow.
-- @return The W shadow lifetime in seconds.
function M.get_w_shadow_lifetime()
  return W_SHADOW_LIFETIME
end

-- Provides the configured settle delay for W shadow after placement.
-- @return The settle delay in seconds (number).
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

-- Get the energy gate threshold for a named decision branch.
-- @param branch The branch name (e.g., "poke", "all_in", "safe_harass").
-- @return The energy gate value for the branch, or 0 if the branch is not defined.
function M.get_branch_energy_gate(branch)
  return DEFAULT_BRANCH_ENERGY_GATES[branch] or 0
end

-- Get the player's current energy value, preferring `par` over `mana`.
-- @return The player's current energy value; `0` if `player` is nil or neither `par` nor `mana` is available.
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

-- Returns the player's maximum energy pool.
-- Prefers `player.maxPar` when present, falls back to `player.maxMana`.
-- @return The maximum energy value, or `0` if `player` is `nil` or neither field is available.
function M.get_max_energy()
  if player == nil then
    return 0
  end
  if player.maxPar ~= nil then
    return player.maxPar
  end
  return player.maxMana or 0
end

-- Determines whether the player's Q spell is currently usable.
-- Checks that the Q slot is learned, not empty, and not on cooldown.
-- @return `true` if Q is usable, `false` otherwise.
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

-- Determines whether the W spell slot is usable.
-- @returns `true` if the W spell is learned, not empty, and not on cooldown; `false` otherwise.
function M.is_w_ready()
  return is_slot_ready(M.get_w_slot())
end

-- Determines whether the E spell slot is ready to be used.
-- @returns `true` if the E slot is learned, not empty, and not on cooldown, `false` otherwise.
function M.is_e_ready()
  return is_slot_ready(M.get_e_slot())
end

-- Determines whether the R spell slot is currently ready to be used.
-- @return `true` if the R spell is learned, present, not on cooldown, and otherwise usable; `false` otherwise.
function M.is_r_ready()
  return is_slot_ready(M.get_r_slot())
end

-- Get the name of the current W spell slot.
-- @return The spell name as a string, or an empty string if the W slot or its name is unavailable.
function M.get_w_spell_name()
  return get_spell_name(M.get_w_slot())
end

-- Get the name of the current R spell slot.
-- @return The spell name as a string, or an empty string if the R slot or its name is unavailable.
function M.get_r_spell_name()
  return get_spell_name(M.get_r_slot())
end

-- Determines whether the W spell is currently in (or can be switched to) its swapped form.
-- Checks the active W slot's spell name for known swapped-form identifiers or the slot's toggleState.
-- @returns `true` if the W swap/form is available, `false` otherwise.
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

-- Determines whether the R spell is in its swapped (R2) form or otherwise indicates it can be swapped.
-- @returns `true` if the R spell is currently in R2/swapped form or reports swap readiness, `false` otherwise.
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
