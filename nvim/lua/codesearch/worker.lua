-- ── Code search: the index worker ────────────────────────────────────────────
-- Runs inside a headless Neovim that `index.build` starts (several in parallel) so the treesitter parse of thousands of
-- files never happens in the editor's own loop: reads the files listed in the job file ($CODESEARCH_JOB, JSON
-- { root, out, items = { { rel, lang, stamp } } }) and writes { [rel] = { stamp, symbols } } to the job's `out` path.
local M = {}

function M.run()
  local job = vim.json.decode(table.concat(vim.fn.readfile(vim.env.CODESEARCH_JOB), "\n"))
  local index = require "codesearch.index"
  local out = {}
  for _, item in ipairs(job.items) do
    local f = io.open(job.root .. "/" .. item.rel, "rb")
    local text = f and f:read "*a"
    if f then
      f:close()
    end
    local ok, symbols = pcall(index.read, item.rel, text or "", item.lang)
    out[item.rel] = { stamp = item.stamp, symbols = (ok and text) and symbols or {} }
  end
  vim.fn.writefile({ vim.json.encode(out) }, job.out)
  vim.cmd "qa!"
end

return M
