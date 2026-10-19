-- ── Agent Setup context (global): <leader>aS ─────────────────────────────────
-- The documents coding agents read before they code (agent/kit) and the build from them. Labels are one or two words
-- (which-key drops the group's own words): lowercase = presets or the project (0 tokens, except agents), uppercase or
-- "· write" = described in your words, written by the model. `b` is the build: the whole project (bb) or one layer from
-- the document that describes it, with the same letter that document has here (bt STACK.md → foundation, bs SPEC.md →
-- domain, bd DESIGN.md → design) or one feature (bf: a requirement of SPEC.md, or a new one). `r` applies a recipe
-- (a prefab task for the stack), `m` adds SPEC.md modules (accounts, roles, payments…), `v` the coverage of SPEC/STACK/DESIGN by the code, `P` PROGRESS.md and the decisions.
local function kit(fn)
  return function()
    require("agent.kit")[fn]()
  end
end

local function build(fn)
  return function()
    require("agent.kit.build")[fn]()
  end
end

--- A function of another kit module (feature, recipes, coverage)
local function kit_module(name, fn)
  return function()
    require("agent.kit." .. name)[fn]()
  end
end

---@type { [1]: string, [2]: string, [3]: function }[]
local maps = {
  { "bb", "setup build all", build "all" },
  { "bt", "setup build foundation", build "foundation" },
  { "bs", "setup build domain", build "domain" },
  { "bd", "setup build design", build "design" },
  { "bf", "setup build feature", kit_module("feature", "open") },
  { "r", "setup recipe", kit_module("recipes", "open") },
  { "v", "setup coverage", kit_module("coverage", "open") },
  { "P", "setup progress", kit "progress" },
  { "B", "setup recheck", build "check_again" },
  { "/", "setup find", kit "find" },
  { "o", "setup overview", kit "overview" },
  { "a", "setup agents", kit "agents" },
  { "A", "setup agents template", kit "agents_template" },
  { "c", "setup claude link", kit "claude" },
  { "t", "setup stack", kit "stack" },
  { "T", "setup stack write", kit "stack_prompt" },
  { "k", "setup stack addons", kit "stack_customize" },
  { "p", "setup principles", kit "principles" },
  { "d", "setup design", kit "design" },
  { "D", "setup design write", kit "design_prompt" },
  { "K", "setup design addons", kit "design_customize" },
  { "w", "setup screens", kit "screens" },
  { "s", "setup spec", kit "spec" },
  { "m", "setup spec modules", kit_module("specmodules", "open") },
}

return {
  name = "Agent Setup",
  prefix = "aS",
  global = true,
  maps = maps,
  groups = { b = "build" },
}
