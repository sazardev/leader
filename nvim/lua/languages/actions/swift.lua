-- ── Swift actions (Swift Package Manager) ────────────────────────────────────
-- At the package root (Package.swift). Tests run in the editor (langtest: XCTest and Swift Testing), debugging with
-- lldb-dap (langdebug), setup files under `S`.
local actions = require "utils.actions"

local function swift(sub)
  return actions.run("swift", "swift " .. sub, { "Package.swift" })
end

local maps = {
  { "r", "run", swift "run" },
  { "b", "build", swift "build" },
  { "B", "build release", swift "build -c release" },
  { "f", "format", actions.format },
  { "F", "format the package", swift "format --in-place --recursive Sources Tests" },
  { "v", "swiftlint", actions.run("swiftlint", "swiftlint", { "Package.swift", ".git" }) },
  { "u", "package update", swift "package update" },
  { "p", "package resolve", swift "package resolve" },
  { "c", "package clean", swift "package clean" },
  {
    "o",
    "open Package.swift",
    function()
      local found = vim.fs.find("Package.swift", { path = vim.fn.expand "%:p:h", upward = true })[1]
      if found then
        vim.cmd.edit(vim.fn.fnameescape(found))
      else
        require("utils.log").info "Swift: no Package.swift here (`swift package init --type executable` makes one)"
      end
    end,
  },
}

vim.list_extend(maps, require("langtest").maps())
vim.list_extend(maps, require("langdebug").maps "swift")
vim.list_extend(maps, require("langsetup").maps "swift")
return maps
