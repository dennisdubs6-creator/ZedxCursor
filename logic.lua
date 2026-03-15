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

local DEFAULT_STAGE4_DAMAGE_PROFILE = {
  q = 150,
  e = 110,
  r = 120,
  r_mark = 190,
  shadow_bonus = 40,
  kill_buffer = 25,
}

local DEFAULT_STAGE4_SAFETY_PROFILE = {
  enemy_scan_radius = 700,
  turret_danger_radius = 775,
  max_extra_enemies = 2,
}

local STAGE4_BLOCK_REASONS = {
  kill_check_failed = true,
  r_overkill = true,
  unsafe_turret = true,
  too_many_enemies = true,
  no_return_path = true,
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

local function copy_position(pos)
  if pos == nil then
    return nil
  end
  -- Hanbot positions use x/y/z ordering, so keep y as height and never
  -- reuse it as a fallback for z when cloning coordinates.
  return vec3(pos.x or 0, pos.y or 0, pos.z or 0)
end

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

local function for_each_candidate(candidates, seen, callback)
  if candidates == nil or callback == nil then
    return
  end

  local function visit(candidate)
    if candidate == nil then
      return
    end
    if seen ~= nil then
      if seen[candidate] then
        return
      end
      seen[candidate] = true
    end
    callback(candidate)
  end

  if type(candidates) == 'table' then
    for _, candidate in pairs(candidates) do
      visit(candidate)
    end
    return
  end

  for i = 0, 40 do
    visit(candidates[i])
  end
  for i = 1, 40 do
    visit(candidates[i])
  end
end

local function is_enemy_unit(unit)
  if unit == nil or unit.valid == false or unit.isDead == true then
    return false
  end
  if type(unit.isEnemy) == 'boolean' then
    return unit.isEnemy
  end
  if player ~= nil and player.team ~= nil and unit.team ~= nil then
    return unit.team ~= player.team
  end
  return true
end

local function is_enemy_hero(unit)
  if not is_enemy_unit(unit) then
    return false
  end
  if TYPE_HERO ~= nil and unit.type ~= nil and unit.type ~= TYPE_HERO then
    return false
  end
  return get_position(unit) ~= nil
end

local function is_enemy_turret(unit)
  if not is_enemy_unit(unit) then
    return false
  end
  if TYPE_TURRET ~= nil and unit.type ~= nil then
    return unit.type == TYPE_TURRET
  end

  local turret_name = string.lower(tostring(unit.charName or unit.name or ''))
  return turret_name:find('turret', 1, true) ~= nil
end

local function get_stage4_damage_profile(spells)
  if spells ~= nil and spells.get_stage4_damage_profile ~= nil then
    return spells.get_stage4_damage_profile() or DEFAULT_STAGE4_DAMAGE_PROFILE
  end
  return DEFAULT_STAGE4_DAMAGE_PROFILE
end

local function get_stage4_safety_profile(spells)
  if spells ~= nil and spells.get_stage4_safety_profile ~= nil then
    return spells.get_stage4_safety_profile() or DEFAULT_STAGE4_SAFETY_PROFILE
  end
  return DEFAULT_STAGE4_SAFETY_PROFILE
end

local function has_known_shadow_position()
  return shadow_state.active and shadow_state.last_known_pos ~= nil
end

local function has_return_path(ctx)
  if ctx == nil then
    return false
  end

  return ctx.w_swap_ready == true
    or shadow_state.swap_ready == true
    or ctx.r_swap_ready == true
end

local function count_enemies_near(position, radius, excluded_target)
  if position == nil or radius == nil or radius <= 0 then
    return 0
  end

  local seen = {}
  local count = 0
  local function visit(candidate)
    if candidate == excluded_target or not is_enemy_hero(candidate) then
      return
    end
    local candidate_pos = get_position(candidate)
    if candidate_pos ~= nil and distance_between(position, candidate_pos) <= radius then
      count = count + 1
    end
  end

  if objManager ~= nil then
    for_each_candidate(objManager.enemies, seen, visit)
    for_each_candidate(objManager.players, seen, visit)
  end
  if game ~= nil then
    for_each_candidate(game.players, seen, visit)
  end

  return count
end

local function is_position_in_enemy_turret_range(position, radius)
  if position == nil or radius == nil or radius <= 0 then
    return false
  end

  local seen = {}
  local dangerous = false
  local function visit(candidate)
    if dangerous or not is_enemy_turret(candidate) then
      return
    end
    local turret_pos = get_position(candidate)
    if turret_pos ~= nil and distance_between(position, turret_pos) <= radius then
      dangerous = true
    end
  end

  if objManager ~= nil then
    for_each_candidate(objManager.turrets, seen, visit)
    for_each_candidate(objManager.enemies, seen, visit)
  end

  return dangerous
end

local function get_target_health(target)
  if target == nil then
    return 0
  end

  return math.max(0, tonumber(target.health or target.maxHealth or 0) or 0)
end

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

local function estimate_non_ult_damage(ctx)
  local profile = get_stage4_damage_profile(ctx.spells)
  local total = 0
  local uses_shadow_setup = false

  if ctx.q_enabled and ctx.q_ready and (can_hit_q(ctx) or can_hit_q_after_w(ctx)) then
    total = total + profile.q
    if not ctx.target:isValidTarget(ctx.q_range) then
      uses_shadow_setup = true
    end
  end

  if ctx.e_enabled and ctx.e_ready and (can_hit_e(ctx) or can_hit_e_after_w(ctx)) then
    total = total + profile.e
    if not ctx.target:isValidTarget(ctx.e_range) then
      uses_shadow_setup = true
    end
  end

  if uses_shadow_setup then
    total = total + profile.shadow_bonus
  end

  return total
end

local function estimate_all_in_damage(ctx)
  local profile = get_stage4_damage_profile(ctx.spells)
  local total = estimate_non_ult_damage(ctx)
  if ctx.r_ready and ctx.target:isValidTarget(ctx.r_range) then
    total = total + profile.r + profile.r_mark
  end
  return total
end

local function evaluate_stage4_all_in(ctx)
  local damage_profile = get_stage4_damage_profile(ctx.spells)
  local safety_profile = get_stage4_safety_profile(ctx.spells)
  local target_health = get_target_health(ctx.target)
  local required_damage = target_health + (damage_profile.kill_buffer or 0)
  local non_ult_damage = estimate_non_ult_damage(ctx)

  if non_ult_damage >= required_damage then
    return false, 'r_overkill'
  end

  if estimate_all_in_damage(ctx) < required_damage then
    return false, 'kill_check_failed'
  end

  local target_pos = get_position(ctx.target)
  if is_position_in_enemy_turret_range(ctx.origin, safety_profile.turret_danger_radius)
    or is_position_in_enemy_turret_range(target_pos, safety_profile.turret_danger_radius) then
    return false, 'unsafe_turret'
  end

  if count_enemies_near(ctx.origin, safety_profile.enemy_scan_radius, ctx.target) > safety_profile.max_extra_enemies then
    return false, 'too_many_enemies'
  end

  if not has_return_path(ctx) then
    return false, 'no_return_path'
  end

  return true, nil
end

local function is_stage4_block_reason(reason)
  return reason ~= nil and STAGE4_BLOCK_REASONS[reason] == true
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
    w_swap_ready = spells.is_w_swap_ready ~= nil and spells.is_w_swap_ready() or false,
    r_swap_ready = spells.is_r_swap_ready ~= nil and spells.is_r_swap_ready() or false,
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

  local can_all_in, block_reason = evaluate_stage4_all_in(ctx)
  if not can_all_in then
    return false, block_reason
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
  if is_stage4_block_reason(r_reason) then
    emit_reason(ctx.menu, r_reason, ctx.now)
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
  local all_in_ready = ctx.r_ready and ctx.target:isValidTarget(ctx.r_range)
  local prefers_all_in = false
  local all_in_block_reason = nil
  if all_in_ready then
    prefers_all_in, all_in_block_reason = evaluate_stage4_all_in(ctx)
  end
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

  if all_in_ready and all_in_block_reason ~= nil then
    if prefers_poke then
      if has_branch_energy(ctx, BRANCH_POKE) then
        return BRANCH_POKE, 'fallback_poke_' .. all_in_block_reason
      end
      if has_branch_energy(ctx, BRANCH_SAFE_HARASS) then
        return BRANCH_SAFE_HARASS, 'fallback_safe_harass_' .. all_in_block_reason
      end
      return BRANCH_POKE, 'preferred_poke_' .. all_in_block_reason
    end
    if has_branch_energy(ctx, BRANCH_SAFE_HARASS) then
      return BRANCH_SAFE_HARASS, 'fallback_safe_harass_' .. all_in_block_reason
    end
    return BRANCH_SAFE_HARASS, 'preferred_safe_harass_' .. all_in_block_reason
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
