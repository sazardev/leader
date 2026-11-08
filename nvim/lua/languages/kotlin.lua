return {
  filetypes = { "kotlin" },
  treesitter = { "kotlin" },
  menu = { name = "Kotlin", prefix = "k", maps = require "languages.actions.kotlin", groups = { S = "setup" } },
}
