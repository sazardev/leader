-- ── Agent context (global): <leader>a ────────────────────────────────────────
-- The actions come from the registry (agent/actions): adding one does not require touching this
-- file. They work in normal mode (function under the cursor) and in visual mode (the selection).
-- Accepting/rejecting a proposal has NO entry here: it is ⏎/⎋ on the proposal.
local function agent()
  return require "agent"
end

local maps = {}
for _, action in ipairs(require("agent.actions").list()) do
  if not action.enabled or action.enabled() then
    maps[#maps + 1] = {
      action.key,
      action.desc,
      function()
        agent().run(action.name)
      end,
      action.modes or { "n", "x" },
    }
  end
end

vim.list_extend(maps, {
  {
    "m",
    "model",
    function()
      agent().settings()
    end,
  },
  {
    "h",
    "history",
    function()
      agent().history()
    end,
  },
  {
    "c",
    "clear",
    function()
      -- in visual, those of the selection; in normal, those of the line
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" or mode == "\22" then
        local a, b = vim.fn.line "v", vim.fn.line "."
        vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
        agent().clear("line", math.min(a, b), math.max(a, b))
      else
        agent().clear "line"
      end
    end,
    { "n", "x" },
  },
  {
    "C",
    "clear file",
    function()
      agent().clear "file"
    end,
  },
  {
    "x",
    "stop",
    function()
      agent().stop()
    end,
  },
  {
    "l",
    "last answer",
    function()
      agent().last()
    end,
  },
})

return {
  name = "Agent",
  prefix = "a",
  global = true,
  maps = maps,
}
