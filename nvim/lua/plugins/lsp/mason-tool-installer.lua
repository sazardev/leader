-- Auto-installs the packages the languages declare (lua/languages/).
return {
  "WhoIsSethDaniel/mason-tool-installer.nvim",
  lazy = false,
  dependencies = { "mason-org/mason.nvim" },
  opts = {
    ensure_installed = require("languages").mason(),
    auto_update = false,
    run_on_start = false, -- tools already installed; do not check versions on every startup
  },
  config = function(_, opts)
    require("mason-tool-installer").setup(opts)
  end,
}
