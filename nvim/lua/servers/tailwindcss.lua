-- The server is a Node process of ~200 MB per session: it only starts where the project uses Tailwind (a
-- tailwind.config.* or a package.json that lists tailwindcss). lspconfig's own root_dir accepts any package.json,
-- so in a monorepo it also started for the API next to the web app.
local CONFIGS = { "tailwind.config.js", "tailwind.config.cjs", "tailwind.config.mjs", "tailwind.config.ts" }

local uses = {} -- package.json path → bool, read once per session

local function lists_tailwind(pkg)
  if uses[pkg] == nil then
    local ok, lines = pcall(vim.fn.readfile, pkg)
    uses[pkg] = ok and table.concat(lines, "\n"):find('"tailwindcss"', 1, true) ~= nil or false
  end
  return uses[pkg]
end

return {
  filetypes = {
    "html",
    "css",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
  root_dir = function(bufnr, on_dir)
    local file = vim.api.nvim_buf_get_name(bufnr)
    local config = vim.fs.find(CONFIGS, { path = file, upward = true, limit = 1 })[1]
    if config then
      return on_dir(vim.fs.dirname(config))
    end
    local pkg = vim.fs.find("package.json", { path = file, upward = true, limit = 1 })[1]
    if pkg and lists_tailwind(pkg) then
      on_dir(vim.fs.dirname(pkg))
    end
  end,
}
