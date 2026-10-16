-- ── Agent Setup context (global): <leader>aS ─────────────────────────────────
-- The documents coding agents read before they code (agent/kit) and the build from them. Labels are one or two words
-- (which-key drops the group's own words): lowercase = presets or the project (0 tokens, except agents), uppercase or
-- "· write" = described in your words, written by the model.
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

---@type { [1]: string, [2]: string, [3]: function }[]
local maps = {
  { "b", "setup build", build "open" },
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
  { "s", "setup spec", kit "spec" },
}

return {
  name = "Agent Setup",
  prefix = "aS",
  global = true,
  maps = maps,
}
