-- emmylua_ls (see servers/lua.lua): what NvChad gave lua_ls, in emmylua's own settings. `vim` is declared global so the
-- editor's own API never shows as undefined; lazydev adds the plugin libraries the code uses, when it uses them.
local data = vim.fn.stdpath "data"

return {
  cmd = { vim.uv.fs_stat(data .. "/mason/bin/emmylua_ls") and (data .. "/mason/bin/emmylua_ls") or "emmylua_ls" },
  settings = {
    emmylua = {
      runtime = { version = "LuaJIT" },
      diagnostics = { globals = { "vim" } },
      codeLens = { enable = true },
      hint = { enable = true },
      workspace = {
        -- the runtime's Lua directory (128 files): the type stubs alone (vim/_meta) leave hover at `any`, completion empty
        -- and `vim.*` reported as unknown, so the Neovim API needs these files
        library = { vim.env.VIMRUNTIME .. "/lua" },
      },
    },
  },
}
