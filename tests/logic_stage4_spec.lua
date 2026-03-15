local LOGIC_PATH = 'logic.lua'

local function assert_true(value, message)
  if not value then
    error(message or 'expected true')
  end
end

local function assert_false(value, message)
  if value then
    error(message or 'expected false')
  end
end

local function assert_equal(expected, actual, message)
  if expected ~= actual then
    error((message or 'values differ') .. string.format(' (expected=%s actual=%s)', tostring(expected), tostring(actual)))
  end
end

local function make_vec3(x, y, z)
  local pos = { x = x, y = y or 0, z = z or 0 }

  function pos:dist(other)
    local dx = (self.x or 0) - (other.x or 0)
    local dz = (self.z or 0) - (other.z or 0)
    return math.sqrt(dx * dx + dz * dz)
  end

  return pos
end

local function new_toggle(value)
  return {
    get = function()
      return value
    end,
  }
end

local function new_menu(overrides)
  overrides = overrides or {}
  return {
    enable_combo = new_toggle(overrides.enable_combo ~= false),
    combo_mode = new_toggle(overrides.combo_mode or 1),
    use_q = new_toggle(overrides.use_q ~= false),
    use_e = new_toggle(overrides.use_e ~= false),
    energy_gate_poke = new_toggle(overrides.energy_gate_poke or 0),
    energy_gate_all_in = new_toggle(overrides.energy_gate_all_in or 0),
    energy_gate_safe_harass = new_toggle(overrides.energy_gate_safe_harass or 0),
    debug_logs = new_toggle(overrides.debug_logs == true),
    debug_diag = new_toggle(overrides.debug_diag ~= false),
    debug_stage3 = new_toggle(overrides.debug_stage3 ~= false),
  }
end

local function new_spell_slot(slot_name, is_ready)
  return {
    level = 1,
    isNotEmpty = true,
    cooldown = is_ready == false and 5 or 0,
    name = slot_name,
    toggleState = 0,
  }
end

local function new_target(x, z, health)
  local target = {
    pos = make_vec3(x, 0, z),
    x = x,
    y = 0,
    z = z,
    valid = true,
    isDead = false,
    isEnemy = true,
    team = 200,
    type = 1,
    charName = 'TargetDummy',
    health = health or 1000,
    maxHealth = health or 1000,
    boundingRadius = 35,
  }

  function target:isValidTarget(range)
    return self.valid ~= false
      and self.isDead ~= true
      and player ~= nil
      and player.pos ~= nil
      and player.pos:dist(self.pos) <= range
  end

  return target
end

local function new_enemy(x, z)
  local enemy = new_target(x, z, 1000)
  enemy.charName = 'Enemy'
  return enemy
end

local function new_turret(x, z)
  return {
    pos = make_vec3(x, 0, z),
    x = x,
    y = 0,
    z = z,
    valid = true,
    isDead = false,
    isEnemy = true,
    team = 200,
    charName = 'Turret',
    name = 'Turret',
    type = 2,
  }
end

local function make_player(spell_names)
  local slots = {
    [_Q] = new_spell_slot(spell_names.q or 'zedq', spell_names.q_ready ~= false),
    [_W] = new_spell_slot(spell_names.w or 'zedw', spell_names.w_ready ~= false),
    [_E] = new_spell_slot(spell_names.e or 'zede', spell_names.e_ready ~= false),
    [_R] = new_spell_slot(spell_names.r or 'zedr', spell_names.r_ready ~= false),
  }

  local cast_log = {}
  local stub = {
    pos = make_vec3(0, 0, 0),
    team = 100,
    par = spell_names.energy or 200,
    maxPar = 200,
    activeSpell = nil,
  }

  function stub:spellSlot(slot_id)
    return slots[slot_id]
  end

  function stub:castSpell(kind, slot_id, arg)
    table.insert(cast_log, {
      kind = kind,
      slot = slot_id,
      arg = arg,
    })
  end

  return stub, cast_log
end

local function build_enemy_collection(entries)
  local collection = {}
  for index, entry in ipairs(entries) do
    collection[index - 1] = entry
    collection[index] = entry
  end
  return collection
end

local function run_logic_case(config)
  _Q = 0
  _W = 1
  _E = 2
  _R = 3
  TYPE_HERO = 1
  TYPE_TURRET = 2
  vec3 = make_vec3

  local prints = {}
  local original_print = print
  print = function(message)
    table.insert(prints, tostring(message))
  end

  game = {
    time = config.now or 1,
    selectedTarget = config.target,
    players = build_enemy_collection(config.players or {}),
  }

  player, cast_log = make_player(config.spell_names or {})

  objManager = {
    enemies = build_enemy_collection(config.enemies or {}),
    players = build_enemy_collection(config.players or {}),
    turrets = build_enemy_collection(config.turrets or {}),
  }

  local logic = dofile(LOGIC_PATH)
  local menu = new_menu(config.menu or {})
  local targeting = {
    get_combat_target = function()
      return config.target
    end,
  }
  local orb = {
    core = {
      is_spell_locked = function()
        return false
      end,
    },
  }
  local pred = {
    linear = {
      get_prediction = function()
        return nil
      end,
    },
  }

  logic.on_tick(menu, config.spells or {
    Q_PRED_INPUT = {},
    get_q_range = function() return 900 end,
    get_w_range = function() return 650 end,
    get_e_range = function() return 290 end,
    get_r_range = function() return 625 end,
    get_current_energy = function() return player.par end,
    get_max_energy = function() return player.maxPar end,
    get_branch_energy_gate = function() return 0 end,
    is_q_ready = function() return config.spell_names.q_ready ~= false end,
    is_w_ready = function() return config.spell_names.w_ready ~= false end,
    is_e_ready = function() return config.spell_names.e_ready ~= false end,
    is_r_ready = function() return config.spell_names.r_ready ~= false end,
    get_w_shadow_lifetime = function() return 5.25 end,
    get_w_shadow_settle_delay = function() return 0.1 end,
    get_w_spell_name = function() return (config.spell_names.w or 'zedw') end,
    get_r_spell_name = function() return (config.spell_names.r or 'zedr') end,
    is_w_swap_ready = function() return config.spell_names.w_swap_ready == true end,
    is_r_swap_ready = function() return config.spell_names.r_swap_ready == true end,
  }, targeting, orb, pred)

  print = original_print

  return {
    casts = cast_log,
    prints = prints,
  }
end

local function has_cast(result, slot_id)
  for _, cast in ipairs(result.casts) do
    if cast.slot == slot_id then
      return true
    end
  end
  return false
end

local function has_print(result, needle)
  for _, line in ipairs(result.prints) do
    if line:find(needle, 1, true) ~= nil then
      return true
    end
  end
  return false
end

return {
  {
    name = 'auto mode avoids all-in when q and e should already secure the kill',
    run = function()
      local target = new_target(250, 0, 120)
      local result = run_logic_case({
        target = target,
        menu = {
          combo_mode = 1,
        },
        spell_names = {
          q_ready = true,
          w_ready = true,
          e_ready = true,
          r_ready = true,
        },
        enemies = { target },
      })

      assert_true(has_print(result, 'branch_selected:poke'), 'expected auto branch to fall back to poke')
      assert_false(has_cast(result, _R), 'expected R to be skipped when non-ult damage is enough')
    end,
  },
  {
    name = 'manual all-in blocks raw r without return path and uses w setup instead',
    run = function()
      local target = new_target(600, 0, 400)
      local result = run_logic_case({
        target = target,
        menu = {
          combo_mode = 3,
        },
        spell_names = {
          q_ready = true,
          w_ready = true,
          e_ready = true,
          r_ready = true,
          w = 'zedw',
          r = 'zedr',
        },
        enemies = { target },
      })

      assert_false(has_cast(result, _R), 'expected R to be blocked without a return path')
      assert_true(has_cast(result, _W), 'expected W setup after raw R is rejected')
      assert_true(has_print(result, 'no_return_path'), 'expected explicit no_return_path reason')
    end,
  },
  {
    name = 'manual all-in blocks r when enemy pressure is too high',
    run = function()
      local target = new_target(500, 0, 500)
      local ally_return = new_enemy(50, 50)
      local other_enemy = new_enemy(100, 30)
      other_enemy.charName = 'EnemyTwo'
      local third_enemy = new_enemy(80, -40)
      third_enemy.charName = 'EnemyThree'

      local result = run_logic_case({
        target = target,
        menu = {
          combo_mode = 3,
        },
        spell_names = {
          q_ready = true,
          w_ready = true,
          e_ready = true,
          r_ready = true,
          w = 'zedw2',
          w_swap_ready = true,
        },
        enemies = { target, ally_return, other_enemy, third_enemy },
      })

      assert_false(has_cast(result, _R), 'expected R to be blocked under heavy enemy pressure')
      assert_true(has_print(result, 'too_many_enemies'), 'expected too_many_enemies safety reason')
    end,
  },
  {
    name = 'manual all-in casts r when kill check and safety both pass',
    run = function()
      local target = new_target(500, 0, 400)
      local result = run_logic_case({
        target = target,
        menu = {
          combo_mode = 3,
        },
        spell_names = {
          q_ready = true,
          w_ready = true,
          e_ready = true,
          r_ready = true,
          w = 'zedw2',
          w_swap_ready = true,
        },
        enemies = { target },
      })

      assert_true(has_cast(result, _R), 'expected safe lethal all-in to cast R')
      assert_equal(1, #result.casts, 'expected only one spell cast this tick')
    end,
  },
  {
    name = 'manual all-in blocks r into enemy turret range',
    run = function()
      local target = new_target(500, 0, 400)
      local result = run_logic_case({
        target = target,
        menu = {
          combo_mode = 3,
        },
        spell_names = {
          q_ready = true,
          w_ready = true,
          e_ready = true,
          r_ready = true,
          w = 'zedw2',
          w_swap_ready = true,
        },
        enemies = { target },
        turrets = { new_turret(540, 0) },
      })

      assert_false(has_cast(result, _R), 'expected R to be blocked under turret danger')
      assert_true(has_print(result, 'unsafe_turret'), 'expected unsafe_turret reason')
    end,
  },
}
