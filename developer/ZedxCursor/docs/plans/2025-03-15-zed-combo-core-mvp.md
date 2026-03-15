# Zed Combo-Core MVP – Design & Implementation Plan

**Date:** 2025-03-15  
**Status:** Implemented  
**Scope:** Hanbot Zed script MVP with orb-target, predicted Q, range-checked E, manual W

---

## 1. Goal

Build a **first playable Zed script MVP** for Hanbot that:

- Loads only on Zed
- Acts only when combo/combat mode is active
- Uses the orbwalker target automatically
- Casts **E** when target is in range
- Casts **Q** with built-in prediction
- Keeps **W** fully manual
- Draws Q and E ranges
- Avoids shadow, swap, R, and clear logic

---

## 2. Out of Scope (Phase 2)

- Auto W
- Auto shadow swap
- Triple-Q logic
- R logic
- Lane / jungle clear
- Harass mode
- Killsteal
- Damage calculator
- Energy optimization
- Evade coordination

---

## 3. Architecture

### File Responsibilities

| File | Responsibility |
|------|----------------|
| `header.lua` | Plugin metadata, Zed-only load |
| `main.lua` | Module loading, orb combat + draw registration |
| `menu.lua` | MVP toggles (combo, draw, debug) |
| `spells.lua` | Q/E data, prediction input, readiness checks |
| `targeting.lua` | Orb combat target, validation |
| `logic.lua` | Combo decision flow, cast order |
| `draw.lua` | Q/E range circles only |

### APIs Used

- `module.internal("orb")`
- `module.internal("pred")`
- `orb.combat.register_f_pre_tick(func)`
- `orb.combat.get_target()`
- `orb.core.is_spell_locked()`
- `pred.linear.get_prediction(input, tar, src)`
- `player:spellSlot(_Q)` / `player:spellSlot(_E)`
- `player:castSpell("pos", slot, vec3)` / `player:castSpell("self", slot)`
- `graphics.draw_circle(...)`

---

## 4. Implemented Task Order

1. ✅ Orb combat integration in `main.lua`
2. ✅ MVP menu in `menu.lua`
3. ✅ Spell layer in `spells.lua`
4. ✅ Orb-target acquisition in `targeting.lua`
5. ✅ Predicted Q in `logic.lua`
6. ✅ Simple E in `logic.lua`
7. ✅ Combo ordering and anti-spam in `logic.lua`
8. ✅ Draw Q/E ranges in `draw.lua`
9. ✅ Safety review

---

## 5. Manual Test Plan

| Test | Expectation |
|------|-------------|
| Smoke | Loads only on Zed, menu visible |
| Idle | No casts when combo off |
| Combo target | Uses orb target, not manual selection |
| Q | Casts predicted Q, not when locked/cooldown |
| E | Casts when in range, skips when out of range |
| Manual W | No interference from script |
| Stability | No bugsplats, no spam, stable under fights |

---

## 6. Acceptance Criteria

MVP is done when:

- [x] Loads only on Zed
- [x] Combo logic gated by orb combat
- [x] Target from orb/combat
- [x] Q uses prediction
- [x] E uses range check
- [x] W stays manual
- [x] Draw toggles work
- [x] Code is safe per Hanbot best practices

---

## 7. Phase 2 Backlog

1. Hybrid targeting fallback
2. Harass mode
3. Manual-W–aware Q
4. Shadow position awareness
5. Safe W auto-cast
6. Safe W swap rules
7. Basic R logic
8. Damage checks
9. Clear modes
10. Advanced shadow combos
