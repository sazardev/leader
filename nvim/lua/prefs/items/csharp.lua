-- Settings panel: C# / .NET (lua/utils/csharpsmart.lua, lua/languages/actions/csharp.lua). Smart completion is read
-- where it is used, so these choices apply on the next keystroke; the server and the inlay hints need their own
-- effect.
local function toggle(label, id)
  return { group = "C#", label = label, kind = "toggle", id = id }
end

return {
  {
    group = "C#",
    label = "Language server",
    kind = "choice",
    id = "lsp.csharp_server",
    choices = {
      { value = "auto", label = "auto (Roslyn if installed)" },
      { value = "roslyn", label = "Roslyn (official)" },
      { value = "csharp_ls", label = "csharp-ls (Mason)" },
    },
    restart = true,
  },
  toggle("Smart completion", "csharp.smart.enabled"),
  toggle("Declaration suggestions", "csharp.smart.declarations"),
  toggle("Constructor from fields", "csharp.smart.constructor"),
  toggle("Properties from fields", "csharp.smart.properties"),
  toggle("DbSet suggestions", "csharp.smart.dbset"),
  toggle("Dependency injection", "csharp.smart.di"),
  toggle("Add missing usings", "csharp.smart.usings"),
  {
    group = "C#",
    label = "Inlay hints",
    kind = "toggle",
    id = "csharp.inlay_hints",
    apply = function(on)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].filetype == "cs" and vim.api.nvim_buf_is_loaded(buf) then
          pcall(vim.lsp.inlay_hint.enable, on, { bufnr = buf })
        end
      end
    end,
  },
  {
    group = "C#",
    label = "Run profile",
    kind = "choice",
    id = "csharp.run.profile",
    choices = {
      { value = "first", label = "first of launchSettings" },
      { value = "ask", label = "ask" },
      { value = "none", label = "none" },
    },
  },
}
