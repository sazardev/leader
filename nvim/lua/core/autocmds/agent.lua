-- ── Agent findings that survive the session ──────────────────────────────────
-- When a file is opened its saved findings are restored (agent/persist.lua); when it is saved, their
-- positions are updated. Nearly free: without a findings file it does nothing.
local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("AgentFindings", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      require("agent.persist").restore(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      if package.loaded["agent.persist"] then
        require("agent.persist").resync(args.buf)
      end
    end,
  })

  -- what you change, as small hunks, for "next edit" (agent/edits.lua): a baseline when a file is entered, compared when an
  -- insert ends or a normal-mode change settles. Cheap: one diff of the file against its snapshot, and only on those events.
  local edits = vim.api.nvim_create_augroup("AgentEdits", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = edits,
    callback = function(args)
      if vim.bo[args.buf].buftype == "" then
        require("agent.edits").watch(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged" }, {
    group = edits,
    callback = function(args)
      if package.loaded["agent.edits"] then
        require("agent.edits").record(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = edits,
    callback = function(args)
      if package.loaded["agent.edits"] then
        require("agent.edits").forget(args.buf)
      end
    end,
  })

  -- :AgentClear [file|all]; with a range (`:'<,'>AgentClear`) or no argument, the line / selection
  vim.api.nvim_create_user_command("AgentClear", function(o)
    local scope = o.args ~= "" and o.args or "line"
    if scope ~= "line" and scope ~= "file" and scope ~= "all" then
      return require("utils.log").warn "AgentClear: use file, all or nothing (line)"
    end
    local ranged = o.range > 0 and scope == "line"
    require("agent").clear(scope, ranged and o.line1 or nil, ranged and o.line2 or nil)
  end, {
    nargs = "?",
    range = true,
    complete = function()
      return { "file", "all" }
    end,
    desc = "Discard agent findings: line (default), file or all",
  })

  -- :Chat — the persistent chat (<leader>aC). One panel, backend-agnostic.
  vim.api.nvim_create_user_command("Chat", function(o)
    local arg = (o.args or ""):match "%S+"
    if arg == "new" then
      require("agent.chat").new_session()
    elseif arg == "history" or arg == "sessions" then
      require("agent.chat").pick_session()
    elseif arg == "model" then
      require("agent.chat").pick_model()
    elseif arg == "effort" then
      require("agent.chat").pick_effort()
    elseif arg == "adr" then
      require("agent.chat").draft_adr()
    elseif arg == "collapse" then
      require("agent.chat").toggle_collapse()
    elseif arg == "full" then
      require("agent.chat").set_view "full"
    elseif arg == "mini" then
      require("agent.chat").set_view "mini"
    elseif arg == "help" then
      require("agent.chat").help()
    else
      require("agent.chat").open()
    end
  end, {
    nargs = "?",
    complete = function()
      return { "new", "history", "sessions", "model", "effort", "adr", "collapse", "full", "mini", "help" }
    end,
    desc = "Toggle Leader Chat (backend-agnostic, <leader>aC)",
  })
end

return M
