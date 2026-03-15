# Zed Gameplay Roadmap

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Track the current implementation roadmap for Zed after the project moved beyond the original starter scaffold.

**Architecture:** `main.lua` stays as wiring, `logic.lua` owns branch selection and execution, `spells.lua` keeps static spell/config data, and follow-up stages harden engage logic, shadow behavior, targeting quality, and validation.

**Tech Stack:** Lua, Hanbot documented callbacks, Hanbot menu API, Hanbot object/spell APIs

---

## Post-V1 Roadmap (Champion-Aligned)

The current codebase has already moved beyond the original v1 no-cast scope.
The deprecated starter task checklist was removed so this document now tracks the gameplay roadmap only.
These stages focus on Zed's real gameplay identity: shadow timing, burst windows, and safe exits.

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
