-- ── Composition root of the optional features ────────────────────────────────
-- The only place that knows which features listen to the agent's events. Each feature is a module with a `setup()` that
-- subscribes to what it needs (agent/events.lua); the flow that emits the events never imports them. Adding one =
-- a line in NAMES. Idempotent: the pipeline calls it every time it loads.
local M = {}

local NAMES = { "verify", "convert_header", "checkpoint" }

local done = false

function M.setup()
  if done then
    return
  end
  done = true
  for _, name in ipairs(NAMES) do
    local ok, feature = pcall(require, "agent." .. name)
    if ok and feature.setup then
      pcall(feature.setup)
    end
  end
end

--- Forgets the wiring (tests that reset the events bus)
function M.reset()
  done = false
end

return M
