-- ── pub: dependencies from the editor ────────────────────────────────────────
-- `<leader>dU` runs `flutter|dart pub outdated --json` and writes, next to each direct and dev dependency of
-- pubspec.yaml that is behind, what it can move to: `↑ 2.5.6` (within your constraint: `pub upgrade` takes it) or
-- `latest 3.0.0` (the constraint has to change), and `discontinued` / `security advisory` when pub says so. The notes go
-- away when pubspec.yaml is saved (the versions may have changed). `<leader>dP` adds packages (`pub add`, `dev:` prefix
-- for dev dependencies). Both ask pub.dev: they need the network, nothing runs on its own.
local log = require "utils.log"

local M = {}

local NS = vim.api.nvim_create_namespace "dartpub"

---@class DartPubInfo
---@field kind string "direct" | "dev" | "transitive"
---@field current string?
---@field upgradable string?
---@field latest string?
---@field discontinued boolean
---@field advisory boolean
---@field retracted boolean

--- `pub outdated --json` → package name → versions
---@param text string
---@return table<string, DartPubInfo>?
function M.outdated(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or type(data.packages) ~= "table" then
    return nil
  end
  local function version(v)
    return type(v) == "table" and v.version or nil
  end
  local out = {}
  for _, p in ipairs(data.packages) do
    out[p.package] = {
      kind = p.kind,
      current = version(p.current),
      upgradable = version(p.upgradable),
      latest = version(p.latest),
      discontinued = p.isDiscontinued == true,
      advisory = p.isCurrentAffectedByAdvisory == true,
      retracted = p.isCurrentRetracted == true,
    }
  end
  return out
end

--- What to write next to each dependency line of pubspec.yaml (only the ones that are behind or flagged)
---@param lines string[] pubspec.yaml
---@param info table<string, DartPubInfo>
---@return { lnum: integer, text: string, hl: string }[] lnum 1-based
function M.annotations(lines, info)
  local out, section = {}, nil
  for i, line in ipairs(lines) do
    local top = line:match "^([%w_]+):"
    if top then
      section = top
    elseif section == "dependencies" or section == "dev_dependencies" then
      local name = line:match "^  ([%w_]+):"
      local p = name and info[name]
      if p and p.kind ~= "transitive" and p.current then
        if p.discontinued or p.advisory or p.retracted then
          local why = p.advisory and "security advisory" or p.retracted and "retracted" or "discontinued"
          out[#out + 1] =
            { lnum = i, text = why .. (p.latest and (" · latest " .. p.latest) or ""), hl = "DartPubWarn" }
        elseif p.upgradable and p.upgradable ~= p.current then
          local more = p.latest and p.latest ~= p.upgradable and (" · latest " .. p.latest) or ""
          out[#out + 1] = { lnum = i, text = "↑ " .. p.upgradable .. more, hl = "DartPubUpgrade" }
        elseif p.latest and p.latest ~= p.current then
          out[#out + 1] = { lnum = i, text = "latest " .. p.latest .. " (change the constraint)", hl = "DartPubMajor" }
        end
      end
    end
  end
  return out
end

---@param root string
---@return string "flutter" | "dart"
local function tool(root)
  local f = io.open(root .. "/pubspec.yaml", "r")
  local text = f and f:read "*a" or ""
  if f then
    f:close()
  end
  return text:find "sdk:%s*flutter" and "flutter" or "dart"
end

--- The pubspec.yaml buffer of the current package, opened in this window when it is not the current one
---@return integer? buf, string? root
local function pubspec_buffer()
  local root = vim.fs.root(0, "pubspec.yaml")
  if not root then
    return nil
  end
  local path = root .. "/pubspec.yaml"
  if vim.api.nvim_buf_get_name(0) ~= path then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  return vim.api.nvim_get_current_buf(), root
end

--- Which dependencies are behind, written next to them in pubspec.yaml
function M.show_outdated()
  local buf, root = pubspec_buffer()
  if not buf then
    return log.warn "Pub: no pubspec.yaml above this file"
  end
  log.info "Pub: asking pub.dev which dependencies are behind…"
  vim.system({ tool(root), "pub", "outdated", "--json" }, { cwd = root, text = true }, function(out)
    vim.schedule(function()
      local info = out.code == 0 and M.outdated(out.stdout or "")
      if not info then
        local why = vim.trim((out.stderr or ""):match "[^\n]+" or "no answer (offline?)")
        return log.error("Pub outdated failed: " .. why)
      end
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
      local notes = M.annotations(vim.api.nvim_buf_get_lines(buf, 0, -1, false), info)
      local upgradable = 0
      for _, a in ipairs(notes) do
        vim.api.nvim_buf_set_extmark(
          buf,
          NS,
          a.lnum - 1,
          0,
          { virt_text = { { "  " .. a.text, a.hl } }, virt_text_pos = "eol" }
        )
        if a.hl == "DartPubUpgrade" then
          upgradable = upgradable + 1
        end
      end
      if #notes == 0 then
        return log.info "Pub: every dependency is up to date"
      end
      log.info(
        ("Pub: %d behind, %d within the constraints (%s pub upgrade takes those)"):format(
          #notes,
          upgradable,
          tool(root)
        )
      )
    end)
  end)
end

--- `pub add` for what is typed (`name`, `name:^1.2.0`, `dev:name`; several separated by spaces)
function M.add()
  local root = vim.fs.root(0, "pubspec.yaml")
  if not root then
    return log.warn "Pub: no pubspec.yaml above this file"
  end
  require("utils.modal").input({ "name  ·  dev:name  ·  name:^1.2.0  (several: separated by spaces)" }, {
    title = "Add packages",
    confirm = "Add",
  }, function(text)
    local names = vim.split(vim.trim(text or ""), "%s+", { trimempty = true })
    if #names == 0 then
      return
    end
    log.info("Pub: adding " .. table.concat(names, ", ") .. "…")
    local cmd = vim.list_extend({ tool(root), "pub", "add" }, names)
    vim.system(cmd, { cwd = root, text = true }, function(out)
      vim.schedule(function()
        if out.code ~= 0 then
          local text = (out.stderr or "") .. "\n" .. (out.stdout or "")
          local why = text:match "[^\n]*[Cc]ould not[^\n]*"
            or text:match "[^\n]*[Ee]rror[^\n]*"
            or vim.trim(text):match "[^\n]+$"
          return log.error("Pub add failed: " .. vim.trim(why or "unknown error"))
        end
        vim.cmd "checktime" -- the pubspec.yaml buffer shows the new lines
        log.info("Pub: added " .. table.concat(names, ", "))
      end)
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("DartPub", { clear = true }),
    pattern = "pubspec.yaml",
    callback = function(ev)
      vim.api.nvim_buf_clear_namespace(ev.buf, NS, 0, -1)
    end,
  })
end

return M
