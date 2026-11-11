-- Settings panel: panes (lua/panes). Both values are read where they are used, so a change applies to the next key.
return {
  {
    group = "Panes",
    label = "Split opens the start screen",
    kind = "toggle",
    id = "panes.dashboard",
  },
  {
    group = "Panes",
    label = "Resize step",
    kind = "choice",
    id = "panes.resize_step",
    choices = {
      { value = 1, label = "1 cell" },
      { value = 2, label = "2 cells" },
      { value = 4, label = "4 cells" },
      { value = 8, label = "8 cells" },
    },
  },
}
