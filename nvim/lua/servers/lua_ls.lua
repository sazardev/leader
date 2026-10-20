-- lua_ls loads every .lua file of the workspace and of its libraries before it can answer, and it keeps no cache of that
-- work between sessions. These cut what it does not need; <leader>L stops it when a project is too big to wait for.
return {
  settings = {
    Lua = {
      workspace = {
        checkThirdParty = false, -- no scan for third-party libraries, no "configure your workspace" prompt
        preloadFileSize = 100, -- KB: a bigger file (generated, bundled) is not parsed up front
        maxPreload = 2000, -- files read before it answers
      },
    },
  },
}
