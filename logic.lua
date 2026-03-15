---@diagnostic disable: undefined-global
-- Hanbot provides globals like `game` at runtime.
-- This hint only avoids editor false positives.
-- logic.lua
-- Stage 3 goal: explicit combo branch selection with W shadow awareness.

local M = {}

local LOG_THROTTLE_SECONDS = 0.75
local DIAG_THROTTLE_SECONDS = 0.30
local BRANCH_LOG_THROTTLE_SECONDS = 0.35

local COMBO_MODE_AUTO = 1
local COMBO_MODE_POKE = 2
local COMBO_MODE_ALL_IN = 3
local COMBO_MODE_SAFE_HARASS = 4

local BRANCH_POKE = 'poke'
local BRANCH_ALL_IN = 'all_in'
local BRANCH_SAFE_HARASS = 'safe_harass'

local ENERGY_FAIL_REASON = {
  poke = 'energy_low_poke',
  all_in = 'energy_low_all_in',
  safe_harass = 'energy_low_safe_harass',
}

local shadow_state = {
  active = false,
  swap_ready = false,
  spawned_at = 0,
  expires_at = 0,
  settle_until = 0,
  last_seen_at = 0,
  last_cast_identifier = 0,
  last_player_pos = nil,
  last_known_pos = nil,
  spell_name = '',
}

local last_q_log_time = 0
local last_diag_time = 0
local last_branch_log_time = 0
local last_branch_log_key = ''

local function now_time()
  return (game and game.time) or 0
end

local function reset_shadow_state()
  shadow_state.active = false
  shadow_state.swap_ready = false
  shadow_state.spawned_at = 0
  shadow_state.expires_at = 0
  shadow_state.settle_until = 0
  shadow_state.last_seen_at = 0
  shadow_state.last_cast_identifier = 0
  shadow_state.last_player_pos = nil
  shadow_state.last_known_pos = nil
  shadow_state.spell_name = ''
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

local function get_position(obj)
  if obj == nil then
    return nil
  end
  if obj.pos ~= nil then
    return obj.pos
  end
  if obj.x ~= nil and obj.y ~= nil and obj.z ~= nil then
    return vec3(obj.x, obj.y, obj.z)
  end
  return nil
end

-- Clone a position into a vec3, preserving explicit x/y/z components.
-- @param pos Position-like table with numeric fields `x`, `y`, and `z`, or nil.
-- @return A vec3 constructed from `pos.x`, `pos.y`, and `pos.z` (missing components default to 0), or nil if `pos` is nil.
local function copy_position(pos)
  if pos == nil then
    return nil
  end
  -- Hanbot positions use x/y/z ordering, so keep y as height and never
  -- reuse it as a fallback for z when cloning coordinates.
  return vec3(pos.x or 0, pos.y or 0, pos.z or 0)
end

-- Computes the horizontal (planar) distance between two position-like values.
-- Accepts objects that implement a :dist(other) method or plain tables with numeric x/z or x/y fields.
-- @param a First position or object.
-- @param b Second position or object.
-- @return The horizontal distance between a and b; returns math.huge if either argument is nil.
local function distance_between(a, b)
  if a == nil or b == nil then
    return math.huge
  end
  if a.dist ~= nil then
    return a:dist(b)
  end

  local dx = (a.x or 0) - (b.x or 0)
  local dz = (a.z or a.y or 0) - (b.z or b.y or 0)
  return math.sqrt(dx * dx + dz * dz)
end

local function has_known_shadow_position()
  return shadow_state.active and shadow_state.last_known_pos ~= nil
end

-- Clamp a target position to lie within max_range of an origin and return the resulting vec3, or nil on invalid input.
-- @param origin Table with numeric fields `x` and `z` (or `y` as fallback for `z`) representing the origin position.
-- @param target_pos Table with numeric fields `x`, `z` (falls back to `y` for `z`) and `y` representing the target position to clamp.
-- @param max_range Positive number specifying the maximum allowed distance from origin; values <= 0 are invalid.
-- @return A vec3 positioned at the clamped location when inputs are valid and distance > 0, or `nil` if inputs are invalid or the origin and target coincide.
local function build_clamped_pos(origin, target_pos, max_range)
  if origin == nil or target_pos == nil or max_range == nil or max_range <= 0 then
    return nil
  end

  local dx = (target_pos.x or 0) - (origin.x or 0)
  local dz = (target_pos.z or target_pos.y or 0) - (origin.z or origin.y or 0)
  local len_sq = dx * dx + dz * dz
  if len_sq <= 0 then
    return nil
  end

  local len = math.sqrt(len_sq)
  local scale = math.min(1, max_range / len)
  return vec3(
    (origin.x or 0) + dx * scale,
    target_pos.y or 0,
    (origin.z or origin.y or 0) + dz * scale
  )
end

local function should_emit_q_log(now)
  return now ~= nil and (now - last_q_log_time) >= LOG_THROTTLE_SECONDS
end

local function is_diag_enabled(menu)
  if menu == nil then
    return false
  end
  return (menu.debug_diag and menu.debug_diag:get())
    or (menu.debug_logs and menu.debug_logs:get())
end

local function is_stage3_debug_enabled(menu)
  if menu == nil then
    return false
  end
  return (menu.debug_stage3 and menu.debug_stage3:get())
    or (menu.debug_logs and menu.debug_logs:get())
end

local function emit_reason(menu, reason, now)
  if not is_diag_enabled(menu) then
    return
  end

  local tick_time = now or now_time()
  if (tick_time - last_diag_time) < DIAG_THROTTLE_SECONDS then
    return
  end

  last_diag_time = tick_time
  print('[Zedx] ' .. tostring(reason))
end

local function emit_branch_selection(ctx, branch, source)
  if ctx == nil or not is_stage3_debug_enabled(ctx.menu) then
    return
  end

  local shadow_desc = shadow_state.active and 'active' or 'inactive'
  if shadow_state.swap_ready then
    shadow_desc = shadow_desc .. ':swap'
  end

  local key = string.format('%s|%s|%s', branch, source, shadow_desc)
  if key == last_branch_log_key and (ctx.now - last_branch_log_time) < BRANCH_LOG_THROTTLE_SECONDS then
    return
  end

  last_branch_log_key = key
  last_branch_log_time = ctx.now
  print(string.format(
    '[Zedx] branch_selected:%s source=%s energy=%d shadow=%s target=%s',
    branch,
    source,
    math.floor(ctx.energy or 0),
    shadow_desc,
    get_target_name(ctx.target)
  ))
end

local function build_q_cast_log(ctx)
  return string.format(
    'attempting Q cast on target: %s | q_ready=true | q_range=%d',
    get_target_name(ctx.target),
    ctx.q_range
  )
end

local function get_menu_energy_gate(ctx, branch)
  local menu = ctx.menu
  if branch == BRANCH_POKE and menu.energy_gate_poke ~= nil then
    return menu.energy_gate_poke:get()
  end
  if branch == BRANCH_ALL_IN and menu.energy_gate_all_in ~= nil then
    return menu.energy_gate_all_in:get()
  end
  if branch == BRANCH_SAFE_HARASS and menu.energy_gate_safe_harass ~= nil then
    return menu.energy_gate_safe_harass:get()
  end
  return ctx.spells.get_branch_energy_gate(branch)
end

local function get_manual_branch(menu)
  local mode = (menu.combo_mode and menu.combo_mode:get()) or COMBO_MODE_AUTO
  if mode == COMBO_MODE_POKE then
    return BRANCH_POKE
  end
  if mode == COMBO_MODE_ALL_IN then
    return BRANCH_ALL_IN
  end
  if mode == COMBO_MODE_SAFE_HARASS then
    return BRANCH_SAFE_HARASS
  end
  return nil
end

local function is_target_in_extended_poke_range(ctx)
  local target_pos = get_position(ctx.target)
  local target_distance = distance_between(ctx.origin, target_pos)
  return target_distance <= math.max(ctx.w_range + ctx.e_range, ctx.w_range + ctx.q_range)
end

local function is_target_in_shadow_range(ctx, range)
  local target_pos = get_position(ctx.target)
  if target_pos == nil or not has_known_shadow_position() then
    return false
  end

  return distance_between(shadow_state.last_known_pos, target_pos) <= range
end

local function can_hit_q(ctx)
  if not ctx.q_enabled or not ctx.q_ready then
    return false
  end

  return ctx.target:isValidTarget(ctx.q_range)
    or is_target_in_shadow_range(ctx, ctx.q_range)
end

local function can_hit_e(ctx)
  if not ctx.e_enabled or not ctx.e_ready then
    return false
  end

  return ctx.target:isValidTarget(ctx.e_range)
    or is_target_in_shadow_range(ctx, ctx.e_range)
end

local function can_hit_q_after_w(ctx)
  if not ctx.q_enabled or not ctx.q_ready then
    return false
  end

  local target_pos = get_position(ctx.target)
  if target_pos == nil then
    return false
  end

  return ctx.target:isValidTarget(ctx.q_range)
    or distance_between(ctx.origin, target_pos) <= (ctx.w_range + ctx.q_range)
end

local function can_hit_e_after_w(ctx)
  if not ctx.e_enabled or not ctx.e_ready then
    return false
  end

  local target_pos = get_position(ctx.target)
  if target_pos == nil then
    return false
  end

  return ctx.target:isValidTarget(ctx.e_range)
    or distance_between(ctx.origin, target_pos) <= (ctx.w_range + ctx.e_range)
end

local function can_execute_poke_now(ctx)
  return can_hit_e(ctx) and can_hit_q(ctx)
end

local function can_execute_poke_after_w(ctx)
  if has_known_shadow_position() or not ctx.w_ready then
    return false
  end

  return is_target_in_extended_poke_range(ctx)
    and can_hit_e_after_w(ctx)
    and can_hit_q_after_w(ctx)
end

local function is_waiting_for_shadow_settle(ctx)
  if ctx == nil then
    return false
  end

  return shadow_state.active
    and shadow_state.settle_until ~= nil
    and shadow_state.settle_until > ctx.now
end

local function needs_w_setup(ctx)
  return not can_execute_poke_now(ctx)
    and can_execute_poke_after_w(ctx)
end

-- Compute the effective energy gate for a combo branch by combining the menu-configured gate with spell-configured branch gates and situational modifiers.
-- @param ctx Runtime context containing menu, spells, target, readiness flags, and shadow state.
-- @param branch One of the branch identifiers (e.g., BRANCH_POKE, BRANCH_ALL_IN, BRANCH_SAFE_HARASS).
-- @return The numeric energy threshold that must be met to execute the given branch; this value may be raised or lowered relative to the menu gate based on branch-specific spell gates and current combat/shadow conditions.
local function get_effective_energy_gate(ctx, branch)
  local gate = get_menu_energy_gate(ctx, branch)
  if branch == BRANCH_POKE then
    if needs_w_setup(ctx) then
      return math.max(gate, ctx.spells.get_branch_energy_gate(BRANCH_POKE))
    end
    if can_execute_poke_now(ctx) then
      return math.min(gate, ctx.spells.get_branch_energy_gate(BRANCH_POKE))
    end
  end
  if branch == BRANCH_ALL_IN then
    if ctx.r_ready and ctx.target:isValidTarget(ctx.r_range) then
      return math.min(gate, ctx.spells.get_branch_energy_gate(BRANCH_ALL_IN))
    end
    if has_known_shadow_position() then
      return math.min(gate, ctx.spells.get_branch_energy_gate(BRANCH_ALL_IN))
    end
    if needs_w_setup(ctx) then
      return math.max(gate, ctx.spells.get_branch_energy_gate(BRANCH_ALL_IN))
    end
  end
  return gate
end

local function has_branch_energy(ctx, branch)
  return (ctx.energy or 0) >= get_effective_energy_gate(ctx, branch)
end

local function update_w_shadow_state(ctx)
  local now = ctx.now
  local w_spell_name = ctx.spells.get_w_spell_name()
  local w_swap_ready = ctx.spells.is_w_swap_ready()
  local previous_player_pos = shadow_state.last_player_pos
  local active_spell = player and player.activeSpell or nil

  if active_spell ~= nil and active_spell.slot == _W and active_spell.identifier ~= shadow_state.last_cast_identifier then
    local active_spell_name = string.lower(tostring(active_spell.name or ''))
    shadow_state.last_cast_identifier = active_spell.identifier
    if active_spell_name == 'zedw2' or active_spell_name:find('w2', 1, true) ~= nil then
      if previous_player_pos ~= nil then
        shadow_state.last_known_pos = copy_position(previous_player_pos)
      end
    elseif active_spell.endPos ~= nil then
      shadow_state.last_known_pos = copy_position(active_spell.endPos)
    end
  end

  if w_swap_ready then
    if not shadow_state.active then
      shadow_state.active = true
      shadow_state.spawned_at = now
      shadow_state.expires_at = now + ctx.spells.get_w_shadow_lifetime()
    end
    shadow_state.swap_ready = true
    shadow_state.last_seen_at = now
    shadow_state.spell_name = w_spell_name
  elseif shadow_state.active then
    shadow_state.swap_ready = false
    shadow_state.spell_name = w_spell_name
    if shadow_state.expires_at > 0 and now >= shadow_state.expires_at then
      reset_shadow_state()
    end
  end

  if not shadow_state.active and ctx.w_ready and not w_swap_ready then
    shadow_state.spell_name = w_spell_name
  end

  shadow_state.last_player_pos = copy_position(ctx.origin)
  ctx.shadow_state = shadow_state
  return shadow_state
end

local function mark_w_shadow_cast(ctx, cast_pos)
  shadow_state.active = true
  shadow_state.swap_ready = false
  shadow_state.spawned_at = ctx.now
  shadow_state.expires_at = ctx.now + ctx.spells.get_w_shadow_lifetime()
  shadow_state.settle_until = ctx.now + ctx.spells.get_w_shadow_settle_delay()
  shadow_state.last_seen_at = ctx.now
  shadow_state.last_player_pos = copy_position(ctx.origin)
  shadow_state.last_known_pos = copy_position(cast_pos)
  shadow_state.spell_name = ctx.spells.get_w_spell_name()
  ctx.shadow_state = shadow_state
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
  local w_range = spells.get_w_range()
  local e_range = spells.get_e_range()
  local r_range = spells.get_r_range()
  local max_range = math.max(q_range, w_range + q_range, w_range + e_range, r_range)
  local target = targeting.get_combat_target(max_range)
  if target == nil then
    return nil, 'no_target'
  end

  return {
    now = now_time(),
    menu = menu,
    spells = spells,
    pred = pred,
    target = target,
    origin = player.pos,
    q_range = q_range,
    w_range = w_range,
    e_range = e_range,
    r_range = r_range,
    energy = spells.get_current_energy(),
    max_energy = spells.get_max_energy(),
    q_enabled = menu.use_q:get(),
    e_enabled = menu.use_e:get(),
    q_ready = spells.is_q_ready(),
    w_ready = spells.is_w_ready(),
    e_ready = spells.is_e_ready(),
    r_ready = spells.is_r_ready(),
  }, nil
end

local function attempt_q(ctx)
  if not ctx.q_enabled then
    return false, 'use_q_off'
  end
  if not ctx.q_ready then
    return false, 'q_not_ready'
  end
  local in_player_range = ctx.target:isValidTarget(ctx.q_range)
  local in_shadow_range = is_target_in_shadow_range(ctx, ctx.q_range)
  if not in_player_range and not in_shadow_range then
    return false, 'q_out_of_range'
  end

  -- Stage 2 standard: exactly one prediction path, one fallback path.
  local seg = ctx.pred.linear.get_prediction(ctx.spells.Q_PRED_INPUT, ctx.target)
  local cast_pos = nil
  if seg ~= nil and seg.startPos ~= nil and seg.endPos ~= nil then
    cast_pos = build_clamped_pos(ctx.origin, seg.endPos:to3D(ctx.target.y), ctx.q_range)
  end
  if cast_pos == nil then
    cast_pos = build_clamped_pos(ctx.origin, get_position(ctx.target), ctx.q_range)
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

local function attempt_w(ctx)
  if not ctx.w_ready then
    return false, 'w_not_ready'
  end

  local cast_pos = build_clamped_pos(ctx.origin, get_position(ctx.target), ctx.w_range)
  if cast_pos == nil then
    return false, 'w_pos_invalid'
  end

  player:castSpell('pos', _W, cast_pos)
  mark_w_shadow_cast(ctx, cast_pos)
  return true, 'w_casted'
end

local function attempt_e(ctx, allow_shadow_range)
  if not ctx.e_enabled then
    return false, 'use_e_off'
  end
  if not ctx.e_ready then
    return false, 'e_not_ready'
  end

  local in_player_range = ctx.target:isValidTarget(ctx.e_range)
  local in_shadow_range = allow_shadow_range and is_target_in_shadow_range(ctx, ctx.e_range)
  if not in_player_range and not in_shadow_range then
    return false, 'e_out_of_range'
  end

  player:castSpell('self', _E)
  if in_shadow_range and not in_player_range then
    return true, 'e_casted_shadow'
  end
  return true, 'e_casted'
end

local function attempt_r(ctx)
  if not ctx.r_ready then
    return false, 'r_not_ready'
  end
  if not ctx.target:isValidTarget(ctx.r_range) then
    return false, 'r_out_of_range'
  end

  player:castSpell('obj', _R, ctx.target)
  return true, 'r_casted'
end

local function choose_reason(default_reason, ...)
  local reasons = { ... }
  for _, reason in ipairs(reasons) do
    if reason ~= nil and reason ~= 'use_q_off' and reason ~= 'use_e_off' then
      return reason
    end
  end
  return default_reason
end

local function execute_poke_branch(ctx)
  if needs_w_setup(ctx) then
    return attempt_w(ctx)
  end

  if is_waiting_for_shadow_settle(ctx) then
    return false, 'w_shadow_settling'
  end

  local e_casted, e_reason = attempt_e(ctx, true)
  if e_casted then
    return true, e_reason
  end

  local q_casted, q_reason = attempt_q(ctx)
  if q_casted then
    return true, q_reason
  end

  return false, choose_reason('poke_no_action', e_reason, q_reason)
end

local function execute_all_in_branch(ctx)
  local r_casted, r_reason = attempt_r(ctx)
  if r_casted then
    return true, r_reason
  end

  if needs_w_setup(ctx) then
    local w_casted, w_reason = attempt_w(ctx)
    if w_casted then
      return true, w_reason
    end
  end

  if is_waiting_for_shadow_settle(ctx) then
    return false, 'w_shadow_settling'
  end

  local e_casted, e_reason = attempt_e(ctx, true)
  if e_casted then
    return true, e_reason
  end

  local q_casted, q_reason = attempt_q(ctx)
  if q_casted then
    return true, q_reason
  end

  return false, choose_reason('all_in_no_action', r_reason, e_reason, q_reason)
end

local function execute_safe_harass_branch(ctx)
  local q_casted, q_reason = attempt_q(ctx)
  if q_casted then
    return true, q_reason
  end

  local e_casted, e_reason = attempt_e(ctx, true)
  if e_casted then
    return true, e_reason
  end

  return false, choose_reason('safe_harass_no_action', e_reason, q_reason)
end

local function select_auto_branch(ctx)
  local prefers_all_in = ctx.r_ready and ctx.target:isValidTarget(ctx.r_range)
  local prefers_poke = can_execute_poke_now(ctx)
    or can_execute_poke_after_w(ctx)

  if prefers_all_in then
    if has_branch_energy(ctx, BRANCH_ALL_IN) then
      return BRANCH_ALL_IN, 'auto_all_in'
    end
    if prefers_poke and has_branch_energy(ctx, BRANCH_POKE) then
      return BRANCH_POKE, 'fallback_poke'
    end
    if has_branch_energy(ctx, BRANCH_SAFE_HARASS) then
      return BRANCH_SAFE_HARASS, 'fallback_safe_harass'
    end
    return BRANCH_ALL_IN, 'preferred_all_in'
  end

  if prefers_poke then
    if has_branch_energy(ctx, BRANCH_POKE) then
      return BRANCH_POKE, 'auto_poke'
    end
    if has_branch_energy(ctx, BRANCH_SAFE_HARASS) then
      return BRANCH_SAFE_HARASS, 'fallback_safe_harass'
    end
    return BRANCH_POKE, 'preferred_poke'
  end

  if has_branch_energy(ctx, BRANCH_SAFE_HARASS) then
    return BRANCH_SAFE_HARASS, 'auto_safe_harass'
  end

  return BRANCH_SAFE_HARASS, 'preferred_safe_harass'
end

local function select_combo_branch(ctx)
  local manual_branch = get_manual_branch(ctx.menu)
  if manual_branch ~= nil then
    return manual_branch, 'manual_override'
  end

  return select_auto_branch(ctx)
end

local function validate_branch_energy(ctx, branch)
  if has_branch_energy(ctx, branch) then
    return true, nil
  end

  return false, ENERGY_FAIL_REASON[branch] or 'energy_low_unknown'
end

function M.on_tick(menu, spells, targeting, orb, pred)
  local ctx, precheck_reason = build_context(menu, spells, targeting, orb, pred)
  if precheck_reason ~= nil then
    emit_reason(menu, precheck_reason, now_time())
    return
  end
  if ctx == nil then
    return
  end

  update_w_shadow_state(ctx)

  local branch, branch_source = select_combo_branch(ctx)
  emit_branch_selection(ctx, branch, branch_source)

  local energy_ok, energy_reason = validate_branch_energy(ctx, branch)
  if not energy_ok then
    emit_reason(menu, energy_reason, ctx.now)
    return
  end

  local casted, action_reason = false, nil
  if branch == BRANCH_POKE then
    casted, action_reason = execute_poke_branch(ctx)
  elseif branch == BRANCH_ALL_IN then
    casted, action_reason = execute_all_in_branch(ctx)
  else
    casted, action_reason = execute_safe_harass_branch(ctx)
  end

  if casted then
    emit_reason(menu, action_reason, ctx.now)
    return
  end

  emit_reason(menu, action_reason or 'branch_no_action', ctx.now)
end

return M
