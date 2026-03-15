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

## Post-V1 Design Direction

The implementation has progressed past the original no-cast starter intent.
The next design should optimize for Zed-specific reliability first, then
shadow-aware combo behavior, then kill/safety decision quality.

### Design Priorities

1. Deterministic cast pipeline (clear prechecks, single decision path per tick).
2. Shadow state modeling (W and R shadow lifetime, swap eligibility, timing windows).
3. Explicit combo modes (poke, all-in, safe harass) with energy gating.
4. Safety-aware engage logic (turret risk, nearby enemies, return path).
5. Testable tuning loop (debug reasons, measurable outcomes, constant tuning).

### Recommended Module Evolution

- `spells.lua`
  - Keep per-spell static data in one place.
  - Add optional config layer for runtime-tunable constants.
- `targeting.lua`
  - Move from "first valid target" toward scored target selection.
  - Keep scoring explainable for debug output.
- `logic.lua`
  - Split into:
    - precondition checks
    - combo branch selection
    - execution phase
  - Ensure exactly one branch executes per tick.
- `draw.lua`
  - Add optional debug overlays for branch, cast reason, and shadow state.
  - Keep draw callback computationally lightweight.
- `main.lua`
  - Keep as pure composition/wiring for modules and callbacks.
  - Avoid gameplay logic drift into entry point.

### Champion Mechanics to Respect

- Shadows mimic `Q` and `E`, and shadow interactions drive both burst and energy return.
- Q is a linear skillshot with cast timing and missile travel that should anchor prediction tuning.
- E slow interaction depends on shadow hit behavior, making shadow placement central to combo reliability.
- R all-in flow should account for post-engage return safety through swap windows.

### Verification Philosophy

Use conservative assumptions first, validate in client, then tune:
- prefer "skip cast with reason" over uncertain casts
- collect repeatable debug evidence before adjusting constants
- separate "API uncertainty" from "champion data uncertainty" in docs and logs

### Champion Reference Sources

- Riot profile: https://www.leagueoflegends.com/en-us/champions/zed/
- Ability/mechanic data: https://wiki.leagueoflegends.com/en-us/Zed?output=1
- Patch trend context: https://wiki.leagueoflegends.com/en-us/Zed/Patch_history
