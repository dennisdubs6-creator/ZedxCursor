# Zed V1 Starter Design

**Goal:** Create a beginner-friendly Hanbot Lua starter scaffold for Zed that separates menu, spell helpers, targeting, logic, and drawing without casting any abilities yet.

## Scope

- Keep the documented scaffold:
  - `header.lua`
  - `menu.lua`
  - `main.lua`
  - `spells.lua`
  - `targeting.lua`
  - `logic.lua`
  - `draw.lua`
- Use only clearly documented Hanbot APIs for v1.
- Use `game.selectedTarget` plus `target:isValidTarget(q_range)` for target validation.
- Do not cast yet.
- Log `would cast Q on target` when conditions are met.

## Architecture

`main.lua` is the entry point and callback wiring file. It loads the other files with `module.load(...)`, then registers `cb.tick` and `cb.draw` callbacks.

`spells.lua` owns Q slot and readiness checks. `targeting.lua` owns selected-target validation. `logic.lua` combines menu, readiness, and targeting into one per-tick decision. `draw.lua` only renders Q range.

## Documented API Usage

- `module.load(...)`
- `cb.add(cb.tick, ...)`
- `cb.add(cb.draw, ...)`
- `graphics.draw_circle(...)`
- `player:spellSlot(_Q)`
- `hero:isValidTarget(range)`
- `player.charName`
- `game.time`

## Known Uncertainties

- `game.selectedTarget` appears in the Hanbot cast example, but I did not find a dedicated reference page for it.
- `spell_slot.state` exists in the docs, but its exact ready-state meaning is not clearly explained.
- Zed Q range is champion data, not Hanbot API documentation, so the chosen value still needs in-client validation.
