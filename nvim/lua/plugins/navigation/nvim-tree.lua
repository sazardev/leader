-- Explorer: hides git-ignored files (fast), no icons.
local modal = require "utils.modal"
local hl = modal.hl

-- Folder to create in: the node itself if it is a folder, or the file's folder if not
local function node_dir(node)
  return node.type == "directory" and node.absolute_path or vim.fs.dirname(node.absolute_path)
end

-- Visual view of the location: project root → … → destination, with its subfolders
local MAX_CHILDREN = 6
local function location_lines(dir)
  local root = vim.fn.getcwd()
  if dir:find(root, 1, true) ~= 1 then
    return { { { "Location:" } }, { { "  " }, { dir .. "/", hl.folder } } }
  end

  local parts = vim.split(dir:sub(#root + 2), "/", { plain = true, trimempty = true })
  local mark = { "   <- new folder(s) go here", hl.mark }
  local lines = { { { "Location:" } } }

  local root_line = { { "  " }, { vim.fn.fnamemodify(root, ":t") .. "/", hl.folder } }
  if #parts == 0 then
    vim.list_extend(root_line, { mark })
  end
  lines[#lines + 1] = root_line

  for i, part in ipairs(parts) do
    local line = {
      { ("  %s└── "):format(("   "):rep(i - 1)), hl.tree },
      { part .. "/", hl.folder },
    }
    if i == #parts then
      line[#line + 1] = mark
    end
    lines[#lines + 1] = line
  end

  local indent = ("  %s"):format(("   "):rep(#parts))
  local children = {}
  for name, t in vim.fs.dir(dir, { depth = 1 }) do
    if t == "directory" then
      children[#children + 1] = name
    end
  end
  table.sort(children)
  for i, name in ipairs(children) do
    if i > MAX_CHILDREN then
      lines[#lines + 1] = { { indent .. "…", hl.muted } }
      break
    end
    lines[#lines + 1] = { { indent .. "├── ", hl.tree }, { name .. "/", hl.folder } }
  end
  return lines
end

-- Counts what is inside a folder, to warn before deleting it
local function contents_summary(path)
  local files, dirs = 0, 0
  for _, t in vim.fs.dir(path, { depth = math.huge }) do
    if t == "directory" then
      dirs = dirs + 1
    else
      files = files + 1
    end
  end
  return files, dirs
end

local function on_attach(bufnr)
  local api = require "nvim-tree.api"

  api.config.mappings.default_on_attach(bufnr)

  -- <CR> on a file → opens it and closes nvim-tree
  vim.keymap.set("n", "<CR>", function()
    local node = api.tree.get_node_under_cursor()
    api.node.open.edit()
    if not node.nodes then
      api.tree.close()
    end
  end, { buffer = bufnr, desc = "nvim-tree: Open file and close tree", nowait = true })

  -- <leader>nd → modal with the location; accepts several paths separated by ";"
  -- e.g. "src/ui; src/core; test"
  vim.keymap.set("n", "<leader>nd", function()
    local node = api.tree.get_node_under_cursor()
    if not node then
      return
    end
    local base = node_dir(node)
    local lines = location_lines(base)
    vim.list_extend(lines, { "", { { "Separate several paths with ';'", hl.muted } } })
    modal.input(lines, { title = "New folder(s)" }, function(input)
      if input == "" then
        return
      end
      for path in input:gmatch "[^;]+" do
        path = vim.trim(path)
        if path ~= "" then
          vim.fn.mkdir(base .. "/" .. path, "p")
        end
      end
      api.tree.reload()
    end)
  end, { buffer = bufnr, desc = "nvim-tree: New folder(s)" })

  -- <leader>nx → modal showing what gets deleted and how much it contains; asks for confirmation
  vim.keymap.set("n", "<leader>nx", function()
    local node = api.tree.get_node_under_cursor()
    if not node or node.type ~= "directory" then
      return vim.notify("Not a folder", vim.log.levels.WARN)
    end
    local files, dirs = contents_summary(node.absolute_path)
    local lines = {
      { { "Delete folder:" } },
      { { "  " }, { vim.fn.fnamemodify(node.absolute_path, ":~:.") .. "/", hl.folder } },
      "",
      { { "Contains: " }, { ("%d files, %d folders"):format(files, dirs), hl.file } },
      { { "This removes everything inside and cannot be undone.", hl.warn } },
    }
    modal.confirm(lines, { title = "Delete folder" }, function()
      vim.fn.delete(node.absolute_path, "rf")
      api.tree.reload()
    end)
  end, { buffer = bufnr, desc = "nvim-tree: Delete folder with contents" })
end

return {
  "nvim-tree/nvim-tree.lua",
  opts = {
    filters = {
      dotfiles = true,
      git_ignored = true,
    },
    renderer = {
      root_folder_label = function(path)
        return vim.fn.fnamemodify(path, ":t") -- the project name, like the demo (not the full path)
      end,
      icons = {
        show = {
          file = false,
          folder = false,
          folder_arrow = false,
          git = false,
        },
      },
    },
    on_attach = on_attach,
  },
  config = function(_, opts)
    require("nvim-tree").setup(opts)
  end,
}
