-- Settings panel: the inline agent (see prefs/init.lua for the item contract). The model and backend have their own
-- selector (<leader>am); the rest are the settings that change how it behaves.
local LANGUAGES = { "English", "Spanish", "Portuguese", "French", "German", "Italian" }

local function chat_apply()
  pcall(function()
    local window = package.loaded["agent.chat.window"]
    if window and window.is_open() then
      window.relayout()
    end
  end)
end

local function redraw_chat()
  pcall(function()
    require("agent.chat.window").draw()
  end)
end

return {
  {
    group = "Agent",
    label = "Model",
    kind = "action",
    show = function()
      local ok, selection = pcall(require, "agent.selection")
      local sel = ok and selection.current()
      if not sel then
        return "not set"
      end
      -- the model alone: "opencode/opencode-go/deepseek-v4.1-flash" is longer than the panel's column
      return sel.model or sel.backend
    end,
    run = function()
      require("agent").settings()
    end,
  },
  {
    group = "Agent",
    label = "Chat panel",
    kind = "action",
    show = function()
      local window = package.loaded["agent.chat.window"]
      return window and window.is_open() and "open" or "hidden"
    end,
    run = function()
      require("gui.workspace").toggle_chat()
    end,
  },
  {
    group = "Agent",
    label = "Chat model",
    kind = "action",
    show = function()
      local window = package.loaded["agent.chat.window"]
      local session = window and window.session
      if session and session.model then
        return session.model
      end
      local ok, selection = pcall(require, "agent.selection")
      local sel = ok and selection.current()
      return sel and sel.model or "not set"
    end,
    run = function()
      require("agent.chat").pick_model()
    end,
  },
  {
    group = "Agent",
    label = "Chat width",
    kind = "choice",
    id = "agent.chat.width",
    choices = {
      { value = 0.35, label = "35 %" },
      { value = 0.42, label = "42 %" },
      { value = 0.5, label = "half" },
      { value = 0.6, label = "60 %" },
    },
    apply = chat_apply,
  },
  {
    group = "Agent",
    label = "Chat view",
    kind = "choice",
    id = "agent.chat.view",
    choices = { { value = "mini", label = "half panel" }, { value = "full", label = "full screen" } },
    apply = function()
      pcall(function()
        require("agent.chat").set_view(require("core.settings").agent.chat.view)
      end)
    end,
  },
  {
    group = "Agent",
    label = "Chat profile",
    kind = "choice",
    id = "agent.chat.profile",
    choices = {
      { value = "ask", label = "Ask · read-only" },
      { value = "write", label = "Write · code and plans" },
      { value = "minimal", label = "Minimal · few tokens" },
    },
  },
  { group = "Agent", label = "Chat docked (split)", kind = "toggle", id = "agent.chat.dock" },
  { group = "Agent", label = "Chat applies Write files", kind = "toggle", id = "agent.chat.apply" },
  { group = "Agent", label = "Chat opens on history", kind = "toggle", id = "agent.chat.history_on_open" },
  { group = "Agent", label = "Chat notifies when the answer is ready", kind = "toggle", id = "agent.chat.notify" },
  { group = "Agent", label = "Chat question picker", kind = "toggle", id = "agent.chat.ask_picker" },
  { group = "Agent", label = "Chat injects @need files", kind = "toggle", id = "agent.chat.auto_need" },
  {
    group = "Agent",
    label = "Chat shows injected context",
    kind = "toggle",
    id = "agent.chat.show_context",
    apply = redraw_chat,
  },
  {
    group = "Agent",
    label = "Chat shows thinking",
    kind = "toggle",
    id = "agent.chat.show_thinking",
    apply = redraw_chat,
  },
  {
    group = "Agent",
    label = "Chat shows tokens and cost",
    kind = "toggle",
    id = "agent.chat.show_tokens",
    apply = redraw_chat,
  },
  { group = "Agent", label = "Chat confirms before sending", kind = "toggle", id = "agent.chat.confirm_send" },
  {
    group = "Agent",
    label = "Answer language",
    kind = "choice",
    id = "agent.language",
    choices = vim.tbl_map(function(name)
      return { value = name, label = name }
    end, LANGUAGES),
  },
  {
    group = "Agent",
    label = "History scope",
    kind = "choice",
    id = "agent.history.scope",
    choices = {
      { value = "project", label = "this project" },
      { value = "all", label = "all projects" },
    },
  },
  { group = "Agent", label = "Verify after accepting", kind = "toggle", id = "agent.verify.enabled" },
  { group = "Agent", label = "Spend guard", kind = "toggle", id = "agent.budget.enabled" },
  { group = "Agent", label = "Smaller models get help", kind = "toggle", id = "agent.capability.enabled" },
  { group = "Agent", label = "Escalate to the main model", kind = "toggle", id = "agent.cascade.enabled" },
  { group = "Agent", label = "Preview prompt before sending", kind = "toggle", id = "agent.trust.preview" },
  { group = "Agent", label = "Experimental features", kind = "toggle", id = "agent.experimental", restart = true },
}
