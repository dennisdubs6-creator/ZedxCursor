---@diagnostic disable: undefined-global
-- Hanbot provides globals like `TYPE_HERO` and `objManager` at runtime.
-- targeting.lua
-- This file owns target lookup. It prefers orb targets and falls back
-- to nearest valid enemy when no explicit target is available.

local M = {}

local orb = module.internal('orb')

local function is_enemy(target)
  if target == nil then
    return false
  end
  if type(target.isEnemy) == 'boolean' then
    return target.isEnemy
  end
  if player ~= nil and player.team ~= nil and target.team ~= nil then
    return target.team ~= player.team
  end
  return true
end

local function is_valid_enemy_hero_target(target, range)
  if target == nil then
    return false
  end
  if target.valid == false then
    return false
  end
  -- Only enforce hero type when TYPE_HERO exists in this runtime.
  if TYPE_HERO ~= nil and target.type ~= nil and target.type ~= TYPE_HERO then
    return false
  end
  if target.isDead == true then
    return false
  end
  if not is_enemy(target) then
    return false
  end
  if not target:isValidTarget(range) then
    return false
  end
  return true
end

local function distance_to_player(target)
  if player == nil or player.pos == nil or target == nil then
    return math.huge
  end
  local target_pos = target.pos
  if target_pos == nil then
    return math.huge
  end
  return player.pos:dist(target_pos)
end

local function for_each_candidate(candidates, callback)
  if candidates == nil or callback == nil then
    return
  end

  if type(candidates) == 'table' then
    for _, candidate in pairs(candidates) do
      callback(candidate)
    end
    return
  end

  -- Engine collections can be userdata without __pairs and without
  -- safe member-name lookups (e.g. `.count` can throw). Probe numeric
  -- indices only, which is the safest cross-runtime fallback.
  for i = 0, 40 do
    local candidate = candidates[i]
    if candidate ~= nil then
      callback(candidate)
    end
  end

  -- Some runtimes expose 1-based indexing instead of 0-based.
  for i = 1, 40 do
    local candidate = candidates[i]
    if candidate ~= nil then
      callback(candidate)
    end
  end
end

local function select_closest_valid_target(candidates, range)
  if candidates == nil then
    return nil
  end

  local best_target = nil
  local best_distance = math.huge
  for_each_candidate(candidates, function(candidate)
    if is_valid_enemy_hero_target(candidate, range) then
      local dist = distance_to_player(candidate)
      if dist < best_distance then
        best_distance = dist
        best_target = candidate
      end
    end
  end)

  return best_target
end

local function get_orb_target(range)
  if orb == nil or orb.combat == nil then
    return nil
  end

  if is_valid_enemy_hero_target(orb.combat.target, range) then
    return orb.combat.target
  end

  if orb.combat.get_target ~= nil then
    -- Prefer the range-aware selector so non-AA-range spell targets can be picked.
    local target = orb.combat.get_target(range) or orb.combat.get_target()
    if is_valid_enemy_hero_target(target, range) then
      return target
    end
  end

  return nil
end

local function get_auto_fallback_target(range)
  -- Common Hanbot collections vary by runtime context; probe safely.
  if objManager ~= nil then
    local from_enemies = select_closest_valid_target(objManager.enemies, range)
    if from_enemies ~= nil then
      return from_enemies
    end

    local from_players = select_closest_valid_target(objManager.players, range)
    if from_players ~= nil then
      return from_players
    end
  end

  if game ~= nil then
    local from_players = select_closest_valid_target(game.players, range)
    if from_players ~= nil then
      return from_players
    end
  end

  return nil
end

--- Returns a valid enemy hero in range.
--- Priority: orb target -> selected target -> nearest valid enemy fallback.
--- @param range number Maximum distance to consider.
--- @return any|nil The target or nil.
function M.get_combat_target(range)
  local target = get_orb_target(range)
  if target ~= nil then
    return target
  end

  if game ~= nil and is_valid_enemy_hero_target(game.selectedTarget, range) then
    return game.selectedTarget
  end

  return get_auto_fallback_target(range)
end

--- Compatible with existing logic; delegates to get_combat_target.
function M.get_q_target(q_range)
  return M.get_combat_target(q_range)
end

return M
