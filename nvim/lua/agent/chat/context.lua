-- Auto context for a chat turn: what Leader injects besides the messages.
-- Everything here is shown in the transcript as a disclosure ("injected: rules,
-- buffer, diagnostics, git, skills, mcp, ...") so the user sees what the model saw.
local text = require "agent.text"

local M = {}

--- Collect sections for the current buffer. Each section = { name, text }.
--- Capped by settings.agent.chat.max_context_chars, in priority order.
---@return { name: string, text: string }[]
function M.collect()
  local cap = require("core.settings").agent.chat.max_context_chars or 12000
  local sections, remaining = {}, cap

  local function push(name, body)
    if not body or remaining <= 0 then
      return
    end
    body = text.clip(body, math.min(#body, remaining))
    if body ~= "" then
      sections[#sections + 1] = { name = name, text = body }
      remaining = remaining - #body
    end
  end

  -- project rules (.agent.md) — always first, the model must obey them
  local ok_rules, rules = pcall(function()
    return require("agent.context.providers.rules").collect
  end)
  if ok_rules then
    -- rules.collect is async in some versions; best-effort sync read of .agent.md
    local root = vim.fs.root(0, ".git") or (vim.uv.cwd() or "")
    local f = io.open(root .. "/.agent.md", "r")
    if f then
      push("rules", f:read "*a")
      f:close()
    end
  end

  -- current buffer (trimmed to the function under the cursor when possible)
  local buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "" then
    local name = vim.api.nvim_buf_get_name(buf)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    push("buffer:" .. vim.fn.fnamemodify(name ~= "" and name or "unnamed", ":~:."), table.concat(lines, "\n"))
  end

  -- diagnostics of the current buffer
  local diags = vim.diagnostic.get(buf)
  if #diags > 0 then
    local lines = vim.tbl_map(function(d)
      return ("L%d [%s] %s (%s)"):format((d.lnum or 0) + 1, "E", d.message:gsub("\n", " "), d.source or "")
    end, diags)
    push("diagnostics", table.concat(lines, "\n"))
  end

  -- git status (branch + short porcelain, expanded on request only)
  local ok_git, git = pcall(require, "utils.git")
  if ok_git and git.info then
    local ok, info = pcall(git.info)
    if ok and info and info.branch ~= "" then
      push("git", "branch: " .. info.branch)
    end
  end

  -- skills matched to the project (available_list is already "- id: desc" text)
  local ok_skills, skills = pcall(require, "skills")
  if ok_skills and skills.available_list then
    local ok, list = pcall(skills.available_list)
    if ok and type(list) == "string" and list ~= "" then
      push("skills", list)
    elseif ok and type(list) == "table" and #list > 0 then
      push(
        "skills",
        table.concat(
          vim.tbl_map(function(s)
            return "- " .. tostring(s)
          end, list),
          "\n"
        )
      )
    end
  end

  -- MCP servers configured in the environment (shown, read-only here)
  local names = require("agent.chat.mention").mcp_servers()
  if #names > 0 then
    push(
      "mcp",
      table.concat(
        vim.tbl_map(function(n)
          return "- " .. n
        end, names),
        "\n"
      )
    )
  end

  return sections
end

return M
