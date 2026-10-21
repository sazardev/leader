-- Stable / experimental split of the agent's features (agent/stability.lua) and how the menus honour it.
local root = vim.env.AGENT_TEST_ROOT
local K = dofile(root .. "/scripts/agent-kit.lua")
local stability = require "agent.stability"
local settings = require("core.settings").agent

local function ids(list, field)
  local out = {}
  for _, ctx in ipairs(list) do
    out[#out + 1] = ctx[field]
  end
  return out
end

K.ok("core features are stable", not stability.is_experimental "fix" and stability.visible(nil))
K.ok("ddd is experimental", stability.is_experimental "ddd")
K.ok(
  "every experimental feature says why",
  (function()
    for id, why in pairs(stability.EXPERIMENTAL) do
      if why == "" or stability.reason(id) ~= why then
        return false
      end
    end
    return true
  end)()
)
K.eq("a stable menu keeps its name", stability.named("Agent", nil), "Agent")
K.eq("an experimental menu says so", stability.named("Agent DDD", "ddd"), "Agent DDD · experimental")

-- default: hidden
settings.experimental = false
vim.env.NVIM_EXPERIMENTAL = nil
K.ok("experimental is hidden by default", not stability.visible "ddd")
local hidden = ids(require("menus").contexts(), "prefix")
K.ok("the DDD menu is not offered", not vim.tbl_contains(hidden, "aD"))
K.ok("the doctor menu is not offered", not vim.tbl_contains(hidden, "aX"))
K.ok("the everyday agent menu stays", vim.tbl_contains(hidden, "a"))
K.ok("the tests menu stays", vim.tbl_contains(hidden, "aT"))

-- the plan action leaves the advanced menu, fix all stays
package.loaded["menus.agent_advanced"] = nil
local adv = require "menus.agent_advanced"
local keys = {}
for _, m in ipairs(adv.maps) do
  keys[m[1]] = true
end
K.ok("plan is not in the advanced menu", not keys[require("agent.actions").get("plan").key])
K.ok("fix all is still there", keys[require("agent.actions").get("fixall").key])

-- the kit: documents stay, building goes
package.loaded["menus.agent_setup"] = nil
local setup = require "menus.agent_setup"
local function has(ctx, key)
  for _, m in ipairs(ctx.maps) do
    if m[1] == key then
      return true
    end
  end
  return false
end
K.ok("no build entries", not has(setup, "bb") and not has(setup, "bf") and not has(setup, "r"))
K.ok("the documents stay", has(setup, "t") and has(setup, "s") and has(setup, "a"))

-- opted in
settings.experimental = true
K.ok("opting in shows them", stability.visible "ddd")
K.ok("the DDD menu is offered", vim.tbl_contains(ids(require("menus").contexts(), "prefix"), "aD"))
package.loaded["menus.agent_setup"] = nil
K.ok("build entries come back", has(require "menus.agent_setup", "bb"))
settings.experimental = false

-- the documentation generators see everything
vim.env.NVIM_EXPERIMENTAL = "1"
K.ok("the env var shows them for the docs", stability.visible "doctor")
vim.env.NVIM_EXPERIMENTAL = nil

K.finish()
