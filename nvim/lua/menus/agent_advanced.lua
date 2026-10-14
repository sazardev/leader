-- ── Agent Advanced context (global): <leader>aA ─────────────────────────────
-- What is not everyday stays out of <leader>a: work on many pieces at once (fix all, fix from a build's output, plans across
-- files) and the queue of proposals those leave waiting. The actions come from the registry (the ones flagged `advanced`).
local queue = require "agent.batch.queue"

local maps = {}
for _, action in ipairs(require("agent.actions").list()) do
  if action.advanced and (not action.enabled or action.enabled()) then
    maps[#maps + 1] = {
      action.key,
      action.desc,
      function()
        require("agent").run(action.name)
      end,
      action.modes or { "n", "x" },
    }
  end
end

local K = queue.KEYS
vim.list_extend(maps, {
  {
    K.next,
    "next proposal",
    function()
      queue.step(1)
    end,
  },
  {
    K.previous,
    "previous proposal",
    function()
      queue.step(-1)
    end,
  },
  {
    K.accept_all,
    "accept all",
    function()
      queue.accept_all()
    end,
  },
  {
    K.list,
    "proposals list",
    function()
      queue.list()
    end,
  },
})

return {
  name = "Agent Advanced",
  prefix = "aA",
  global = true,
  maps = maps,
}
