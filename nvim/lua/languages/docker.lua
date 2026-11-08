return {
  filetypes = { "dockerfile" },
  treesitter = { "dockerfile" },
  lsp = { "dockerls", "docker_compose_language_service" },
  mason = { full = { "dockerfile-language-server", "docker-compose-language-service" } },
  menu = { name = "Docker", prefix = "D", maps = require "languages.actions.docker", groups = { S = "setup" } },
}
