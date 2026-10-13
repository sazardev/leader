-- Semantic folding (treesitter + indent, no extra LSP) + foldable long comments
-- (lua/utils/comments.lua, <leader>C menu).

--- Wraps an internal ufo provider and adds the folds of long comments to it.
--- If the provider asks for fallback (no parser), the exception propagates as is.
---@param name "treesitter"|"indent"
local function with_comments(name)
  return function(bufnr)
    return require("promise")(function(resolve)
      resolve(require("ufo").getFolds(bufnr, name))
    end):thenCall(function(ranges)
      if not ranges then
        return ranges
      end
      local taken = {}
      for _, r in ipairs(ranges) do
        taken[r.startLine .. ":" .. r.endLine] = true
      end
      for _, c in ipairs(require("utils.comments").ranges(bufnr)) do
        -- the provider already folds that block: the fold is not duplicated
        if not taken[c.first .. ":" .. c.last] then
          ranges[#ranges + 1] = { startLine = c.first, endLine = c.last, kind = require("utils.comments").KIND }
        end
      end
      return ranges
    end)
  end
end

--- Text of a closed fold: its first line + "󰁂 N". If that line is only the opening
--- of a comment (`/**`, `/*`), the first line with content is appended.
local function fold_text(virt_text, lnum, end_lnum, width, truncate)
  local text = table.concat(vim.tbl_map(function(chunk)
    return chunk[1]
  end, virt_text))
  if not text:find "%w" and lnum < end_lnum then
    local next_line = vim.api.nvim_buf_get_lines(0, lnum, lnum + 1, false)[1] or ""
    virt_text = { { text .. " " .. vim.trim(next_line:gsub("^%s*[%*#/-]+", "")), "Comment" } }
  end

  local suffix = (" 󰁂 %d "):format(end_lnum - lnum)
  local target = width - vim.fn.strdisplaywidth(suffix)
  local result, used = {}, 0
  for _, chunk in ipairs(virt_text) do
    local chunk_text, hl = chunk[1], chunk[2]
    local chunk_width = vim.fn.strdisplaywidth(chunk_text)
    if target > used + chunk_width then
      result[#result + 1] = chunk
    else
      chunk_text = truncate(chunk_text, target - used)
      result[#result + 1] = { chunk_text, hl }
      used = used + vim.fn.strdisplaywidth(chunk_text)
      break
    end
    used = used + chunk_width
  end
  result[#result + 1] = { suffix, "MoreMsg" }
  return result
end

return {
  "kevinhwang91/nvim-ufo",
  event = "BufReadPost",
  dependencies = { "kevinhwang91/promise-async" },
  opts = {
    provider_selector = function()
      return { with_comments "treesitter", with_comments "indent" }
    end,
    fold_virt_text_handler = fold_text,
  },
  config = function(_, opts)
    vim.o.foldcolumn = "0"
    vim.o.foldlevel = 99
    vim.o.foldlevelstart = 99
    vim.o.foldenable = true
    -- with the <leader>Cc preference on, new files open with long comments folded
    opts.close_fold_kinds_for_ft = { default = require("utils.comments").close_kinds() }
    require("ufo").setup(opts)
    require("utils.comments").setup()
  end,
}
