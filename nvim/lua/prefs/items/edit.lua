-- Settings panel: editing (see prefs/init.lua for the item contract)
return {
  { group = "Editing", label = "Format on save", kind = "toggle", id = "format_on_save.enabled" },
  {
    group = "Editing",
    label = "Reload outside changes",
    kind = "toggle",
    id = "options.autoread",
    apply = function(on)
      vim.o.autoread = on
    end,
  },
  { group = "Editing", label = "Undo word by word", kind = "toggle", id = "history.word_undo" },
  { group = "Editing", label = "x / c keep the clipboard", kind = "toggle", id = "clipboard.keep" },
  {
    group = "Editing",
    label = "Session autosave",
    kind = "choice",
    id = "session.autosave_ms",
    choices = {
      { value = 60000, label = "every minute" },
      { value = 300000, label = "every 5 minutes" },
      { value = 0, label = "only on exit" },
    },
    restart = true,
  },
}
