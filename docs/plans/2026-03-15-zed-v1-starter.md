# Zed V1 Starter Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a minimal Hanbot starter scaffold for Zed that can draw Q range and log when Q would be cast on a valid selected target.

**Architecture:** `main.lua` loads the module files and registers tick and draw callbacks. The other files stay focused on one job each so a beginner can trace the flow from menu input to spell checks to target validation and drawing.

**Tech Stack:** Lua, Hanbot documented callbacks, Hanbot menu API, Hanbot object/spell APIs

---

### Task 1: Create starter metadata and menu

**Files:**
- Create: `header.lua`
- Create: `menu.lua`

**Step 1: Write the file contents**

- `header.lua`: plugin id, name, Zed-only load check
- `menu.lua`: one `Use Q` boolean toggle

**Step 2: Verify the design against docs**

Check that:
- `player.charName` is documented
- `menu(...)`, `menu:header(...)`, and `menu:boolean(...)` match the example pattern

**Step 3: Keep the code minimal**

- No extra toggles
- No combo keys
- No casting

### Task 2: Create Q helpers and targeting

**Files:**
- Create: `spells.lua`
- Create: `targeting.lua`

**Step 1: Add Q slot helpers**

- Expose `get_q_slot()`
- Expose `is_q_ready()`
- Keep readiness logic in one helper for easy adjustment after live testing

**Step 2: Add selected-target validation**

- Read `game.selectedTarget`
- Reject nil or invalid targets
- Validate with `target:isValidTarget(q_range)`

**Step 3: Keep uncertainty explicit**

- Mark `spell_slot.state` semantics as not fully confirmed
- Mark Zed Q range as a value to verify in client

### Task 3: Create logic, draw, and entry point

**Files:**
- Create: `logic.lua`
- Create: `draw.lua`
- Create: `main.lua`

**Step 1: Add tick logic**

- Check menu toggle
- Check Q readiness
- Check target
- Log `would cast Q on target`
- Throttle logs with `game.time`

**Step 2: Add draw logic**

- Only draw the Q range
- Avoid heavy calculations in draw

**Step 3: Wire the callbacks**

- Load all modules with `module.load(...)`
- Register `cb.tick`
- Register `cb.draw`

### Task 4: Verify edited files

**Files:**
- Verify: `header.lua`
- Verify: `menu.lua`
- Verify: `main.lua`
- Verify: `spells.lua`
- Verify: `targeting.lua`
- Verify: `logic.lua`
- Verify: `draw.lua`

**Step 1: Run available lint diagnostics**

Use the editor diagnostics for the edited files.

**Step 2: Re-read the code**

Confirm:
- no cast call exists
- only documented Hanbot APIs are used
- uncertainty is labeled where needed

**Step 3: Report status honestly**

- State what was verified
- State what still requires in-client testing

---

## Post-V1 Roadmap (Champion-Aligned)

The current codebase has already moved beyond the original v1 no-cast scope.
This roadmap defines the next implementation stages around Zed's real gameplay
identity: shadow timing, burst windows, and safe exits.

### Stage 2: Reliability Hardening

**Goal:** Make current Q/E cast flow deterministic and easy to debug.

**Tasks:**
- Consolidate cast preconditions in one place:
  - spell lock
  - target validity
  - range checks
  - cast position sanity
- Add reason-coded diagnostics (`no_target`, `q_not_ready`, `pred_failed`) with throttling.
- Standardize one Q prediction path plus one fallback path.

**Exit Criteria:**
- No duplicate/conflicting cast attempts in one tick.
- Every skipped cast path emits exactly one reason code in debug mode.

### Stage 3: Shadow-Aware Combo Engine

**Goal:** Encode Zed's W/R shadow windows and energy constraints into clear combo branches.

**Tasks:**
- Track W shadow lifecycle and swap eligibility.
- Implement combo modes:
  - poke: `W -> E -> Q`
  - all-in: `R -> E/Q -> swap decisions`
  - safe-harass: no `R`
- Add minimum energy gates per combo branch.

**Exit Criteria:**
- Combo branch is selected explicitly and logged in debug mode.
- Branches skip cleanly when energy gates fail.

### Stage 4: Kill and Safety Intelligence

**Goal:** Reduce wasted all-ins and improve survival after engage.

**Tasks:**
- Add conservative kill checks for `Q/E/R mark` thresholds.
- Gate risky engages by:
  - turret safety
  - nearby enemy count
  - return path availability (`W` or `R` swap)
- Prevent overkill `R` usage when non-ult combo secures kill.

**Exit Criteria:**
- `R` casts only when kill+safety thresholds pass.
- Unsafe all-ins are skipped with explicit debug reasons.

### Stage 5: Targeting and Prediction Quality

**Goal:** Improve target value and Q hit quality.

**Tasks:**
- Replace simple target selection with scored target priority:
  - killability
  - distance
  - threat/priority class
- Add optional prediction confidence gating for Q.

**Exit Criteria:**
- Q cast rate drops in low-confidence states.
- Hit quality improves in repeated test samples.

### Stage 6: Validation and Constant Tuning

**Goal:** Tune with repeatable in-client evidence.

**Tasks:**
- Build an in-client checklist for:
  - Q range/width behavior
  - E practical radius verification
  - shadow timing windows
- Record sample outcomes and tune constants incrementally.

**Exit Criteria:**
- Core constants are validated in real matches.
- Debug logs are stable and actionable across multiple sessions.

### Champion Data Notes (Reference)

Use these values as validation targets, then confirm in client:
- Q (Razor Shuriken): range 925, cast time 0.25, speed 1700, width 100
- W (Living Shadow): cast range 650, cooldown scales by rank
- E (Shadow Slash): effect radius listed as 315/290 depending on context
- R (Death Mark): target range 625

### External Sources

- Riot champion profile: https://www.leagueoflegends.com/en-us/champions/zed/
- Zed ability data and mechanics: https://wiki.leagueoflegends.com/en-us/Zed?output=1
- Patch history context: https://wiki.leagueoflegends.com/en-us/Zed/Patch_history
