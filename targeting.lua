---@diagnostic disable: undefined-global
-- targeting.lua
-- This file owns the v1 target lookup rules.

local M = {}

function M.get_q_target(q_range)
  if game == nil then
    return nil
  end

  -- v1 uses the documented example pattern of reading
  -- the currently selected target rather than inventing
  -- a target selector API.
  local target = game.selectedTarget

  if target == nil then
    return nil
  end

  if not target.valid then
    return nil
  end

  -- Keep this focused on champion targeting for Zed Q logic.
  if target.type ~= TYPE_HERO then
    return nil
  end

  -- This is the key documented validation check for v1.
  if not target:isValidTarget(q_range) then
    return nil
  end

  return target
end

return M
