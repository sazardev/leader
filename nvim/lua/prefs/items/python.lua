-- Settings panel: Python (see prefs/init.lua for the item contract)
return {
  {
    group = "Python",
    label = "Pretty run output",
    kind = "toggle",
    id = "python.pretty",
  },
  {
    group = "Python",
    label = "Traceback with locals",
    kind = "toggle",
    id = "python.pretty_locals",
  },
  {
    group = "Python",
    label = "Clear terminal on run",
    kind = "toggle",
    id = "python.pretty_clear",
  },
  {
    group = "Python",
    label = "Plots in terminal",
    kind = "toggle",
    id = "python.pretty_plots",
  },
}
