-- ruff's server: lint, quick fixes (`<leader>ca`: fix all, organize imports) and format. Hover stays basedpyright's
-- (ruff's would only describe the lint rule under the cursor and hide the type).
return {
  on_attach = function(client)
    client.server_capabilities.hoverProvider = false
  end,
}
