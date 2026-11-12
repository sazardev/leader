-- Settings panel: Go (see prefs/init.lua for the item contract)
return {
  {
    group = "Go",
    label = "GoHawk lint on save",
    kind = "toggle",
    id = "go.gohawk.lint",
  },
  {
    group = "Go",
    label = "go test output (each test)",
    kind = "toggle",
    id = "go.test.verbose",
  },
}
