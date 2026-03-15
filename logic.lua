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

local DIAG_THROTTLE = 1.0
local diag_last = 0

local function diag(menu, msg)
  if not menu then return end
  local diag_on = (menu.debug_diag and menu.debug_diag:get())
    or (menu.debug_logs and menu.debug_logs:get())
  if not diag_on then return end
  local now = game and game.time or 0
  if now - diag_last < DIAG_THROTTLE then
    return
  end
  diag_last = now
  print('[Zedx] ' .. tostring(msg))
end

function M.on_tick(menu, spells, targeting, orb, pred)
  if menu == nil or spells == nil or targeting == nil or orb == nil or pred == nil then
    diag(menu, 'nil_module')
    return
  end

  if not menu.enable_combo:get() then
    return
  end

  if orb.core.is_spell_locked() then
    diag(menu, 'spell_locked')
    return
  end

  local q_range = spells.get_q_range()
  local e_range = spells.get_e_range()
  local target = targeting.get_combat_target(math.max(q_range, e_range))

  if target == nil then
    diag(menu, 'no_target')
    return
  end

  local now = game.time

  -- E first (instant slow), then Q only after E (user prefers E -> Q order).
  if menu.use_e:get() and spells.is_e_ready() then
    if target:isValidTarget(e_range) then
      player:castSpell('self', _E)
      return
    end
  end

  -- Q only after E when both in range. If target out of E range, allow Q (can't E anyway).
  if not menu.use_q:get() then
    diag(menu, 'use_q_off')
    return
  end
  -- Only wait for E when use_e is on; if use_e off, allow Q regardless.
  -- No longer block Q for "E first" - cast Q when ready; E handled above.
  if not spells.is_q_ready() then
    diag(menu, 'q_not_ready')
    return
  end

  local origin = player and player.pos or nil
  if not origin then
    diag(menu, 'no_origin')
    return
  end

  local q_slot = spells.get_q_slot()
  if q_slot then
    -- Try 2-arg pred first (matches spell-timing example); fallback to 3-arg with origin
    local seg = pred.linear.get_prediction(spells.Q_PRED_INPUT, target)
      or pred.linear.get_prediction(spells.Q_PRED_INPUT, target, origin)

    local cast_pos
    if seg and seg.startPos and seg.endPos then
      local dist = seg.startPos:dist(seg.endPos)
      if dist <= q_range then
        cast_pos = seg.endPos:to3D(target.y)
      end
    end

    -- Fallback: cast at target when prediction fails (clamped to range)
    if not cast_pos then
      local target_pos = target.pos or vec3(target.x, target.y, target.z)
      local dx = (target_pos.x or 0) - (origin.x or 0)
      local dz = (target_pos.z or target_pos.y or 0) - (origin.z or origin.y or 0)
      local len_sq = dx * dx + dz * dz
      if len_sq > 0 then
        local len = math.sqrt(len_sq)
        local scale = math.min(1, q_range / len)
        cast_pos = vec3(
          (origin and origin.x or 0) + dx * scale,
          target_pos.y or target.y,
          (origin and (origin.z or origin.y) or 0) + dz * scale
        )
      end
    end

    if cast_pos then
      if menu.debug_logs:get() and can_log_now(now) then
        print(build_debug_message(target, q_range))
        last_log_time = now
      end
      diag(menu, 'casting_q')
      player:castSpell('pos', _Q, cast_pos)
      return
    end
    diag(menu, 'no_cast_pos')
  else
    diag(menu, 'q_slot_nil')
  end

  -- E when Q not cast (e.g. Q on cooldown, use_q off, or prediction failed)
  if menu.use_e:get() and spells.is_e_ready() then
    if target:isValidTarget(e_range) then
      player:castSpell('self', _E)
    end
  end
end

return M
