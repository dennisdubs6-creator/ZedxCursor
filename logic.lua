---@diagnostic disable: undefined-global
-- Hanbot provides globals like `game` at runtime.
-- This hint only avoids editor false positives.
-- logic.lua
-- Stage 2 goal: deterministic cast flow with one reason code per tick.

local M = {}

local LOG_THROTTLE_SECONDS = 0.75
local DIAG_THROTTLE_SECONDS = 0.30

local last_q_log_time = 0
local last_diag_time = 0

local function should_emit_q_log(now)
  return now ~= nil and (now - last_q_log_time) >= LOG_THROTTLE_SECONDS
end

local function get_target_name(target)
  if target == nil then
    return 'unknown'
  end

  if target.charName ~= nil and target.charName ~= '' then
    return target.charName
  end
  if target.name ~= nil and target.name ~= '' then
    return target.name
  end

  return 'unknown'
end

local function emit_reason(menu, reason, now)
  if menu == nil then
    return
  end
  local debug_on = (menu.debug_diag and menu.debug_diag:get())
    or (menu.debug_logs and menu.debug_logs:get())
  if not debug_on then
    return
  end

  local tick_time = now or (game and game.time) or 0
  if (tick_time - last_diag_time) < DIAG_THROTTLE_SECONDS then
    return
  end

  last_diag_time = tick_time
  print('[Zedx] ' .. tostring(reason))
end

local function build_q_cast_log(ctx)
  return string.format(
    'attempting Q cast on target: %s | q_ready=true | q_range=%d',
    get_target_name(ctx.target),
    ctx.q_range
  )
end

local function build_context(menu, spells, targeting, orb, pred)
  if menu == nil or spells == nil or targeting == nil or orb == nil or pred == nil then
    return nil, 'nil_module'
  end
  if not menu.enable_combo:get() then
    return nil, nil
  end
  if player == nil or player.pos == nil then
    return nil, 'no_origin'
  end
  if orb.core ~= nil and orb.core.is_spell_locked ~= nil and orb.core.is_spell_locked() then
    return nil, 'spell_locked'
  end

  local q_range = spells.get_q_range()
  local e_range = spells.get_e_range()
  local max_range = math.max(q_range, e_range)
  local target = targeting.get_combat_target(max_range)
  if target == nil then
    return nil, 'no_target'
  end

  return {
    now = (game and game.time) or 0,
    menu = menu,
    spells = spells,
    pred = pred,
    target = target,
    origin = player.pos,
    q_range = q_range,
    e_range = e_range,
    q_enabled = menu.use_q:get(),
    e_enabled = menu.use_e:get(),
    q_ready = spells.is_q_ready(),
    e_ready = spells.is_e_ready(),
  }, nil
end

local function build_q_fallback_pos(ctx)
  local target = ctx.target
  local origin = ctx.origin
  local target_pos = target.pos or vec3(target.x, target.y, target.z)
  if target_pos == nil then
    return nil
  end

  local dx = (target_pos.x or 0) - (origin.x or 0)
  local dz = (target_pos.z or target_pos.y or 0) - (origin.z or origin.y or 0)
  local len_sq = dx * dx + dz * dz
  if len_sq <= 0 then
    return nil
  end

  local len = math.sqrt(len_sq)
  local scale = math.min(1, ctx.q_range / len)
  return vec3(
    (origin.x or 0) + dx * scale,
    target_pos.y or target.y,
    (origin.z or origin.y or 0) + dz * scale
  )
end

local function attempt_q(ctx)
  if not ctx.q_enabled then
    return false, 'use_q_off'
  end
  if not ctx.q_ready then
    return false, 'q_not_ready'
  end
  if not ctx.target:isValidTarget(ctx.q_range) then
    return false, 'q_out_of_range'
  end

  -- Stage 2 standard: exactly one prediction path, one fallback path.
  local seg = ctx.pred.linear.get_prediction(ctx.spells.Q_PRED_INPUT, ctx.target)
  local cast_pos = nil
  if seg ~= nil and seg.startPos ~= nil and seg.endPos ~= nil then
    local dist = seg.startPos:dist(seg.endPos)
    if dist <= ctx.q_range then
      cast_pos = seg.endPos:to3D(ctx.target.y)
    end
  end
  if cast_pos == nil then
    cast_pos = build_q_fallback_pos(ctx)
  end
  if cast_pos == nil then
    return false, 'pred_failed'
  end

  player:castSpell('pos', _Q, cast_pos)
  if ctx.menu.debug_logs:get() and should_emit_q_log(ctx.now) then
    print(build_q_cast_log(ctx))
    last_q_log_time = ctx.now
  end
  return true, 'q_casted'
end

local function attempt_e(ctx)
  if not ctx.e_enabled then
    return false, 'use_e_off'
  end
  if not ctx.e_ready then
    return false, 'e_not_ready'
  end
  if not ctx.target:isValidTarget(ctx.e_range) then
    return false, 'e_out_of_range'
  end

  player:castSpell('self', _E)
  return true, 'e_casted'
end

local function choose_skip_reason(q_reason, e_reason)
  if q_reason ~= nil and q_reason ~= 'use_q_off' then
    return q_reason
  end
  if e_reason ~= nil and e_reason ~= 'use_e_off' then
    return e_reason
  end
  return 'no_action_enabled'
end

function M.on_tick(menu, spells, targeting, orb, pred)
  local ctx, precheck_reason = build_context(menu, spells, targeting, orb, pred)
  if precheck_reason ~= nil then
    emit_reason(menu, precheck_reason, game and game.time or 0)
    return
  end
  if ctx == nil then
    return
  end

  local q_casted, q_reason = attempt_q(ctx)
  if q_casted then
    emit_reason(menu, q_reason, ctx.now)
    return
  end

  local e_casted, e_reason = attempt_e(ctx)
  if e_casted then
    emit_reason(menu, e_reason, ctx.now)
    return
  end

  emit_reason(menu, choose_skip_reason(q_reason, e_reason), ctx.now)
end

return M
