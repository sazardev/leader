-- Smoke test of Mappings against the real config and installed plugins.
local ok, err = xpcall(function()
  local cheat = require("utils.cheatsheet")
  assert(cheat.wait_ready(), "keymaps did not finish loading")
  assert(vim.fn.exists(":Cheatsheet") == 2, ":Cheatsheet is not registered")
  local mapping = vim.fn.maparg(" ch", "n", false, true)
  assert(mapping.rhs == "<cmd>Cheatsheet<CR>", "<leader>ch points elsewhere: " .. vim.inspect(mapping))

  local entries = cheat.entries()
  assert(#entries > 100, "too few mappings collected: " .. #entries)
  local function has(field, value)
    return vim.iter(entries):any(function(entry)
      return entry[field] == value
    end)
  end
  assert(has("language", "Go"), "Go menu is missing")
  assert(has("source", "menu"), "leader menus are missing")
  assert(has("source", "global"), "global mappings are missing")
  assert(has("source", "lsp"), "LSP mappings are missing")
  assert(has("source", "completion"), "completion mappings are missing")
  assert(has("source", "tree"), "file-tree mappings are missing")
  assert(has("source", "native"), "native mappings are missing")
  assert(has("key", "<leader>ch"), "the cheatsheet key is missing")
  local function entry(group, key)
    return vim.iter(entries):find(function(item)
      return item.group == group and item.key == key
    end)
  end
  assert(entry("Go", "<leader>gt").usage:find("go mod tidy", 1, true), "Go tidy example is wrong")
  assert(entry("Go", "<leader>gM").usage:find("only the test", 1, true), "Go cursor-test example is wrong")
  local seen = {}
  for _, entry in ipairs(entries) do
    local signature = entry.key .. "\0" .. (entry.full or entry.action):lower()
    assert(not seen[signature], "duplicate mapping: " .. entry.key .. " / " .. entry.action)
    assert(entry.example and entry.example ~= "", "missing example: " .. entry.key .. " / " .. entry.action)
    assert(entry.usage and #entry.usage > 100, "usage is not detailed: " .. entry.key .. " / " .. entry.action)
    assert(entry.steps and #entry.steps >= 3, "missing steps: " .. entry.key .. " / " .. entry.action)
    assert(entry.result and entry.result ~= "", "missing result: " .. entry.key .. " / " .. entry.action)
    assert(entry.notes and #entry.notes > 0, "missing notes: " .. entry.key .. " / " .. entry.action)
    seen[signature] = true
  end

  local view = require("cheatsheet")
  local m = view.open({ entries = entries })
  assert(m and m.wins and m.wins.list, "the live view did not open")
  assert(vim.bo[m.bufs.list].filetype == "market", "the live view is not a market")
  require("utils.market").close(m)
end, debug.traceback)

if ok then
  print("LIVE OK")
  vim.cmd("qa!")
else
  print(err)
  vim.cmd("cquit 1")
end
