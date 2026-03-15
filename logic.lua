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

-- Get the current game time.
-- @return The current game time in seconds, or 0 if the game time is unavailable.
local function now_time()
  return (game and game.time) or 0
end

-- Reset W shadow tracking state to default (clears active flags, timestamps, positions, and spell name).
-- After calling, shadow_state will reflect no active shadow and no stored shadow metadata.
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

-- Resolve a human-readable name for a target object.
-- @param target The target object (may be nil). If provided, the function prefers `charName`, then `name`.
-- @return The resolved name as a string; `'unknown'` if no name is available.
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

-- Extracts a 3D position from an object.
-- @param obj The object to read position from; may be nil.
-- @return A `vec3` representing the object's position if available, `nil` otherwise.
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

-- Create and return a new vector copied from the given position.
-- @param pos Table or vector containing numeric `x` and `y` fields and an optional `z` field.
-- @return A new `vec3` whose components are taken from `pos` (`z` defaults to `y` if absent), or `nil` if `pos` is `nil`.
local function copy_position(pos)
  if pos == nil then
    return nil
  end
  return vec3(pos.x or 0, pos.y or 0, pos.z or pos.y or 0)
end

-- Compute the planar distance between two positions or objects.
-- @param a A position table with numeric fields `x` and `z` (or `y` as fallback), or an object exposing a `:dist(other)` method.
-- @param b A position table with numeric fields `x` and `z` (or `y` as fallback), or an object compatible with `a`'s `:dist` if present.
-- @return The Euclidean distance on the X/Z plane between `a` and `b`. Returns `math.huge` if either argument is `nil`.
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

-- Indicates whether a W shadow is currently active and a last known position is available.
-- @return `true` if a shadow is active and its last known position is available, `false` otherwise.
local function has_known_shadow_position()
  return shadow_state.active and shadow_state.last_known_pos ~= nil
end

-- Compute a point on the line from `origin` toward `target_pos`, clamped to `max_range`.
-- @param origin Table with numeric position fields (`x` and `z`, or `x` and `y`).
-- @param target_pos Table with numeric position fields (`x` and `z`, or `x` and `y`).
-- @param max_range Maximum distance from `origin` for the resulting point; must be > 0.
-- @return A vec3 positioned along the origin→target line at distance <= `max_range`, or `nil` if inputs are invalid or the origin and target coincide.
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
    target_pos.y or target_pos.z or 0,
    (origin.z or origin.y or 0) + dz * scale
  )
end

-- Determines whether a Q log may be emitted according to the throttle timer.
-- @param now The current time in seconds (or nil).
-- @return `true` if at least LOG_THROTTLE_SECONDS have elapsed since the last Q log, `false` otherwise.
local function should_emit_q_log(now)
  return now ~= nil and (now - last_q_log_time) >= LOG_THROTTLE_SECONDS
end

-- Checks whether diagnostic output is enabled in the provided menu.
-- @param menu The menu/settings table (may be nil) containing diagnostic toggles.
-- @return `true` if either the `debug_diag` or `debug_logs` toggle is enabled, `false` otherwise.
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

-- Emits a diagnostic message when diagnostics are enabled and emission is not throttled.
-- The message is printed via print and throttled by an internal interval to avoid spam.
-- @param menu Table used to determine whether diagnostics are enabled.
-- @param reason The diagnostic message or value to print; will be converted to a string.
-- @param now Optional timestamp to use for throttling checks; if omitted, the current game time is used.
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

-- Emit a throttled diagnostic log of the chosen combo branch including shadow state.
-- This respects the stage-3 debug toggle and will suppress repeat messages for the same
-- branch/source/shadow combination for BRANCH_LOG_THROTTLE_SECONDS.
-- @param ctx Context table produced by build_context; used for timing, energy, target, and menu checks.
-- @param branch String identifier of the selected branch (e.g. "ALL_IN", "POKE", "SAFE_HARASS").
-- @param source String label describing how the branch was chosen (e.g. "auto", "manual").
-- (No return value.)
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

-- Builds a formatted log message describing a planned Q cast against the current target.
-- @param ctx The combo context table containing at least `target` and `q_range`.
-- @return A string describing the attempted Q cast, including the target name and Q range.
local function build_q_cast_log(ctx)
  return string.format(
    'attempting Q cast on target: %s | q_ready=true | q_range=%d',
    get_target_name(ctx.target),
    ctx.q_range
  )
end

-- Retrieves the configured energy gate threshold for a combo branch, preferring a menu override when available.
-- @param ctx Context table containing `menu` and `spells`.
-- @param branch Branch identifier (e.g., BRANCH_POKE, BRANCH_ALL_IN, BRANCH_SAFE_HARASS).
-- @return The energy gate threshold for the specified branch.
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

-- Derives the manual combo branch selected in the menu's combo_mode setting.
-- @param menu The menu table exposing `combo_mode:get()` which yields a COMBO_MODE_* value.
-- @return The corresponding `BRANCH_POKE`, `BRANCH_ALL_IN`, or `BRANCH_SAFE_HARASS` identifier, or `nil` if the mode is automatic or unrecognized.
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

-- Determines whether the current target is within the "extended poke" distance (combining W with either E or Q).
-- @param ctx Table containing at least `origin`, `target`, and numeric ranges `w_range`, `q_range`, `e_range`.
-- @return `true` if the target's distance from `origin` is less than or equal to the larger of (`w_range + e_range`) and (`w_range + q_range`), `false` otherwise.
local function is_target_in_extended_poke_range(ctx)
  local target_pos = get_position(ctx.target)
  local target_distance = distance_between(ctx.origin, target_pos)
  return target_distance <= math.max(ctx.w_range + ctx.e_range, ctx.w_range + ctx.q_range)
end

-- Determines whether the current target is within a given distance of the last known W shadow position.
-- @param ctx Table containing execution context; must have a `target` field representing the current target.
-- @param range Number maximum distance from the shadow position to consider "in range".
-- @return `true` if the target's position is within `range` of the last known shadow position, `false` otherwise.
local function is_target_in_shadow_range(ctx, range)
  local target_pos = get_position(ctx.target)
  if target_pos == nil or not has_known_shadow_position() then
    return false
  end

  return distance_between(shadow_state.last_known_pos, target_pos) <= range
end

-- Determines whether the current target can be struck by Q, either directly within Q range or indirectly via a known W shadow position.
-- @param ctx The context table (provides target, q_range, and Q enabled/ready flags).
-- @return `true` if the target is hittable by Q directly or through the shadow position, `false` otherwise.
local function can_hit_q(ctx)
  if not ctx.q_enabled or not ctx.q_ready then
    return false
  end

  return ctx.target:isValidTarget(ctx.q_range)
    or is_target_in_shadow_range(ctx, ctx.q_range)
end

-- Determines whether the E ability can reach the current target either directly or via a known W shadow position.
-- @param ctx Context table expected to include `target`, `e_range`, `e_enabled`, and `e_ready`.
-- @return `true` if E is enabled, ready, and the target is within direct E range or within E range relative to a known shadow; `false` otherwise.
local function can_hit_e(ctx)
  if not ctx.e_enabled or not ctx.e_ready then
    return false
  end

  return ctx.target:isValidTarget(ctx.e_range)
    or is_target_in_shadow_range(ctx, ctx.e_range)
end

-- Determines whether Q can reach the current target either directly from the player's origin or by leveraging the combined range of W plus Q.
-- @param ctx Table containing context fields used: `q_enabled`, `q_ready`, `target`, `origin`, `q_range`, and `w_range`.
-- @return `true` if the target is within Q range directly or within (W range + Q range) from the origin, `false` otherwise.
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

-- Determines if E can reach the current target either directly or by using the W shadow's range.
-- @param ctx Table containing the current context. Required fields: `e_enabled`, `e_ready`, `e_range`, `w_range`, `origin`, and `target`.
-- @return `true` if E can hit the target directly within `e_range` or if the distance from `origin` to the target is less than or equal to `w_range + e_range`, `false` otherwise.
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

-- Check if a poke can be executed immediately using current E and Q conditions.
-- @return `true` if both E and Q can hit the target now, `false` otherwise.
local function can_execute_poke_now(ctx)
  return can_hit_e(ctx) and can_hit_q(ctx)
end

-- Determines whether a poke (Q + E) can be performed after placing a W shadow.
-- @param ctx The execution context containing target, ranges, and readiness flags (expects `ctx.w_ready` and other fields used by hit checks).
-- @return `true` if no known shadow position exists, W is ready, the target is within extended poke range, and both Q and E can hit after W; `false` otherwise.
local function can_execute_poke_after_w(ctx)
  if has_known_shadow_position() or not ctx.w_ready then
    return false
  end

  return is_target_in_extended_poke_range(ctx)
    and can_hit_e_after_w(ctx)
    and can_hit_q_after_w(ctx)
end

-- Determines whether a currently tracked W shadow is in its settle window (i.e., still settling and not ready for swap).
-- @param ctx Context table containing `now` (current time); if `ctx` is nil the function returns `false`.
-- @return `true` if a shadow is active and its `settle_until` is greater than `ctx.now`, `false` otherwise.
local function is_waiting_for_shadow_settle(ctx)
  if ctx == nil then
    return false
  end

  return shadow_state.active
    and shadow_state.settle_until ~= nil
    and shadow_state.settle_until > ctx.now
end

-- Determines whether a W shadow setup is required to execute a poke.
-- @return `true` if the poke cannot be executed now but can be executed after placing a W shadow, `false` otherwise.
local function needs_w_setup(ctx)
  return not can_execute_poke_now(ctx)
    and can_execute_poke_after_w(ctx)
end

-- Compute the effective energy gate threshold for a combo branch, adjusting the base menu gate based on W-shadow setup, target readiness, and available spells.
-- @param ctx Context table containing target, ranges, spell readiness, and shadow state used to decide adjustments.
-- @param branch Branch identifier (e.g. BRANCH_POKE, BRANCH_ALL_IN) whose gate should be computed.
-- @return The numeric energy gate value to use for the given branch.
-- Compute the effective energy gate for a combo branch by combining the menu-configured gate with spell-configured branch gates and situational modifiers.
-- @param ctx Runtime context containing menu, spells, target, readiness flags, and shadow state.
-- @param branch One of the branch identifiers (e.g., BRANCH_POKE, BRANCH_ALL_IN, BRANCH_SAFE_HARASS).
-- @return The numeric energy threshold that must be met to execute the given branch; this value may be raised or lowered relative to the menu gate based on branch-specific spell gates and current combat/shadow conditions.
local function get_effective_energy_gate(ctx, branch)
  local gate = get_menu_energy_gate(ctx, branch)
  if branch == BRANCH_POKE then
    if needs_w_setup(ctx) then
      return math.max(gate, 165)
    end
    if can_execute_poke_now(ctx) then
      return math.min(gate, 125)
      return math.max(gate, ctx.spells.get_branch_energy_gate(BRANCH_POKE))
    end
    if can_execute_poke_now(ctx) then
      return math.min(gate, ctx.spells.get_branch_energy_gate(BRANCH_POKE))
    end
  end
  if branch == BRANCH_ALL_IN then
    if ctx.r_ready and ctx.target:isValidTarget(ctx.r_range) then
      return math.min(gate, 125)
    end
    if has_known_shadow_position() then
      return math.min(gate, 125)
    end
    if needs_w_setup(ctx) then
      return math.max(gate, 165)
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

-- Determines whether the current energy meets or exceeds the effective energy gate required for the specified combo branch.
-- @param ctx The combo context containing the current energy value.
-- @param branch The branch identifier (e.g. BRANCH_POKE, BRANCH_ALL_IN, BRANCH_SAFE_HARASS).
-- @return `true` if the current energy is greater than or equal to the branch's effective energy gate, `false` otherwise.
local function has_branch_energy(ctx, branch)
  return (ctx.energy or 0) >= get_effective_energy_gate(ctx, branch)
end

-- Update global W shadow tracking state from the provided context and spell system.
-- This examines the current active spell and W spell status to maintain shadow_state fields:
-- `active`, `swap_ready`, `spawned_at`, `expires_at`, `settle_until` (if set elsewhere), `last_seen_at`,
-- `last_cast_identifier`, `last_player_pos`, `last_known_pos`, and `spell_name`. It will reset the
-- shadow_state when the shadow lifetime expires and attaches the updated table to `ctx.shadow_state`.
-- @param ctx Table containing runtime values used to determine shadow status. Required fields:
-- `now` (current time), `spells` (providing `get_w_spell_name`, `is_w_swap_ready`, `get_w_shadow_lifetime`),
-- and `origin` (player position). The global `player` and `_W` are also inspected if present.
-- @return The updated `shadow_state` table.
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

-- Record that a W shadow was cast and populate the module shadow_state with timing, position, and identifying information.
-- @param ctx Context table containing `now`, `origin`, and `spells` accessors; used to set timestamps, obtain spell metadata, and attach the shadow_state back to `ctx.shadow_state`.
-- @param cast_pos Vector-like position where the W shadow was created; stored as `last_known_pos` in the shadow_state.
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

-- Build and validate a runtime context used by combo decision and execution logic.
-- Returns a context table populated with current timing, targets, ranges, energy and readiness flags when inputs are valid; otherwise returns nil and a short error code.
-- @param menu UI/settings object (expected methods/fields: enable_combo:get(), use_q:get(), use_e:get(), combo_mode, energy gate getters).
-- @param spells Spell interface providing range and state queries (expected functions: get_q_range/get_w_range/get_e_range/get_r_range, get_current_energy/get_max_energy, is_q_ready/is_w_ready/is_e_ready/is_r_ready).
-- @param targeting Targeting utility (expected function: get_combat_target(max_range)).
-- @param orb Orbwalker/controller object (may provide core.is_spell_locked()).
-- @param pred Prediction module (passed through into the context for use by cast attempts).
-- @return On success: a table with fields { now, menu, spells, pred, target, origin, q_range, w_range, e_range, r_range, energy, max_energy, q_enabled, e_enabled, q_ready, w_ready, e_ready, r_ready }.
-- @return On failure: nil and one of the error codes: 'nil_module', 'no_origin', 'spell_locked', or 'no_target'.
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

-- Attempts to cast the Q skillshot at the current target using prediction, falling back to a direct clamp toward the target or known shadow position when necessary.
-- Returns whether a cast was performed and a short reason code describing the outcome.
-- The function will perform checks for Q enablement, readiness, and range (including shadow-based range), compute a cast position via prediction or clamped fallback, perform the cast when possible, and emit a debug log line when enabled.
-- @return boolean true if Q was cast, `false` otherwise.
-- @return string A short reason code: one of `q_casted`, `use_q_off`, `q_not_ready`, `q_out_of_range`, or `pred_failed`.
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

-- Attempts to cast W toward the current target; if successful it records the spawned shadow.
-- @param ctx The execution context containing origin, target, w_range and readiness flags.
-- @return `true` and `"w_casted"` when W was cast and shadow state was marked; `false` and `"w_not_ready"` if W is not ready; `false` and `"w_pos_invalid"` if a valid cast position could not be determined.
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

-- Attempts to cast E (self-targeted) against the current target, optionally allowing a shadow-based range check.
-- @param allow_shadow_range If true, treat proximity to a known W shadow as an acceptable range for E when the target is out of direct player range.
-- @return `true` and a reason string when E is cast; `false` and a reason string otherwise.
-- Possible return reasons:
--   `use_e_off`        - E usage is disabled in configuration.
--   `e_not_ready`      - E is not ready to cast.
--   `e_out_of_range`   - Target is neither within player range nor (when allowed) within shadow range.
--   `e_casted`         - E was cast directly from the player onto the target.
--   `e_casted_shadow`  - E was cast using the shadow-based range (target out of player range but within shadow range).
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

-- Attempts to cast the R spell on the current target.
-- Checks that R is ready and the target is within R range before casting.
-- @param ctx Context table containing at least `r_ready`, `r_range`, and `target`.
-- @return boolean `true` if R was cast, `false` otherwise.
-- @return string A reason code: `'r_casted'` when cast, `'r_not_ready'` if R was not ready, or `'r_out_of_range'` if the target was out of range.
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

-- Selects the first meaningful reason from a list of candidates, falling back to a default.
-- @param default_reason The fallback reason to return if no candidate is acceptable.
-- @param ... Candidate reason strings to evaluate in order.
-- @return The first candidate that is not `nil`, `"use_q_off"`, or `"use_e_off"`, otherwise `default_reason`.
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

-- Attempts the "poke" branch: performs W setup if required, waits for shadow settle when necessary, then tries E (allowing shadow-range) and Q in that order.
-- This returns as soon as an action is executed or a definitive no-action reason is determined.
-- @param ctx The combo context table containing target, origin, spell states, shadow_state, ranges, menu and energy info.
-- @return `true` and a success reason string if an action was executed; `false` and a failure reason string otherwise.
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

-- Attempts to perform the "all-in" combo branch, executing the highest-priority available action for an all-in engage.
-- Tries R first, then W if a W setup is required, waits for shadow settling when applicable, then attempts E (allowing shadow-range) and finally Q.
-- @return boolean `true` and the action reason string if an action was executed, `false` and a reason identifier otherwise.
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

-- Attempts the "safe harass" branch: try Q first, then E (allowing shadow-range).
-- @param ctx The combo execution context produced by build_context.
-- @return boolean true and the action reason if an ability was cast; `false` and a no-action reason otherwise.
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

-- Selects the combo branch to execute based on readiness, target state, and energy availability.
-- Chooses between BRANCH_ALL_IN, BRANCH_POKE, and BRANCH_SAFE_HARASS by preferring all-in when R is ready and the target is in R range, otherwise preferring poke when a poke path is available (now or after W), and falling back to safe harass when energy for higher-priority branches is insufficient.
-- @param ctx Context table containing fields and helpers used for selection (readiness flags, target, and energy checks).
-- @return branch The chosen BRANCH_* constant.
-- @return reason A short identifier string explaining the selection (for logging), e.g. "auto_all_in", "fallback_poke".
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

-- Choose the combo branch, honoring a manual override from the menu when present.
-- @param ctx The decision context containing at least `menu` and other runtime state.
-- @return branch The chosen branch identifier (e.g., one of the `BRANCH_*` constants) or `nil` if none selected.
-- @return source A string describing the selection source — `'manual_override'` when the menu forced a branch, otherwise the label returned by automatic selection.
local function select_combo_branch(ctx)
  local manual_branch = get_manual_branch(ctx.menu)
  if manual_branch ~= nil then
    return manual_branch, 'manual_override'
  end

  return select_auto_branch(ctx)
end

-- Check whether the current energy meets the required gate for the specified combo branch.
-- @param ctx The action context containing current energy and branch/equipment state.
-- @param branch The branch identifier (e.g., BRANCH_POKE, BRANCH_ALL_IN, BRANCH_SAFE_HARASS).
-- @return `true`, nil if energy is sufficient for the branch.
-- @return `false`, a string reason from ENERGY_FAIL_REASON for why the branch is unavailable, or `"energy_low_unknown"` if no specific reason is mapped.
local function validate_branch_energy(ctx, branch)
  if has_branch_energy(ctx, branch) then
    return true, nil
  end

  return false, ENERGY_FAIL_REASON[branch] or 'energy_low_unknown'
end

-- Process a single combo tick: build and validate context, update W shadow state, select a combo branch (manual or automatic),
-- validate energy for that branch, attempt the branch-specific action sequence, and emit diagnostic/branch/action reasons.
-- @param menu Table of user-configurable options and toggles used to influence branch selection and diagnostics.
-- @param spells Table containing spell objects/state (cooldowns, ranges, readiness) required to evaluate and cast abilities.
-- @param targeting Targeting helper that provides the current target and prediction utilities.
-- @param orb Orbwalker/state provider exposing the player's current position and movement state.
-- @param pred Prediction module used to compute cast positions for skillshots.
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
