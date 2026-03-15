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
