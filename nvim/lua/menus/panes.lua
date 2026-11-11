-- ── Paneles: <leader>V ───────────────────────────────────────────────────────
-- Un panel es una ventana real de Neovim (lua/panes): Alt+V / Alt+H abren uno a la derecha / abajo con la pantalla
-- de inicio, `ff`/`fo` cargan el archivo elegido AHÍ, Ctrl+h/j/k/l navega, Alt+flechas redimensiona. Este menú reúne
-- lo que no tiene una tecla directa: lista, tamaños iguales, rotar, intercambiar, zoom y cerrar.
return {
  name = "Panes",
  prefix = "V",
  global = true,
  maps = {
    {
      "v",
      "split right (start screen)",
      function()
        require("panes").open "right"
      end,
    },
    {
      "h",
      "split down (start screen)",
      function()
        require("panes").open "below"
      end,
    },
    {
      "d",
      "dashboard here",
      function()
        require("panes").dashboard()
      end,
    },
    {
      "l",
      "list",
      function()
        require("panes").pick()
      end,
    },
    {
      "=",
      "equal sizes",
      function()
        require("panes").equal()
      end,
    },
    {
      "r",
      "rotate",
      function()
        require("panes").rotate()
      end,
    },
    {
      "s",
      "swap with next",
      function()
        require("panes").swap()
      end,
    },
    {
      "z",
      "zoom (toggle)",
      function()
        require("panes").zoom()
      end,
    },
    {
      "x",
      "close",
      function()
        require("panes").close()
      end,
    },
  },
}
