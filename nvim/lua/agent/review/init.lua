-- ── Review what is staged ────────────────────────────────────────────────────
-- Before the commit: the staged diff goes through the cheap checks first (secrets, conflict markers, debugger leftovers,
-- sensitive files: no model), and only if there is real code to read is it sent, once, numbered, within `review_max_chars`.
-- Findings land as diagnostics on the lines they name (open files at once, the rest when you open them) and as a quickfix
-- list. Nothing staged, or only noise (lockfiles, generated files, deletions): 0 tokens, and it says so.
local diff = require "agent.review.diff"
local git = require "commit.git"
local log = require "utils.log"
local protocol = require "agent.protocol"
local static = require "agent.review.static"

local M = {}

local SYSTEM = table.concat({
  "Review a git diff BEFORE it is committed. You see only the diff: the files are listed as `## path`, and each line is `+L<n> code` (added, line n of the new file), ` L<n> code` (unchanged context) or `-    code` (removed).",
  "Judge the added code: it must work, handle its errors and not break what it touches. A removed line may be what an added line replaces; do not report removals on their own.",
  protocol.REVIEW_FILES_RULES,
}, "\n")

---@class AgentReviewResult
---@field findings { path: string, line: integer, severity: integer, message: string, source: string }[]
---@field static integer       how many came from the free checks
---@field sent boolean         whether a model was asked
---@field model string?
---@field files integer
---@field skipped string[]

---@param root string
---@return string
local function staged_raw(root)
  return (git.run({ "diff", "--cached", "-U1", "--no-color", "--no-ext-diff", "--no-renames" }, root))
end

--- Writes the findings where they will be seen: diagnostics in open files, persisted for the rest, and a quickfix list
---@param root string
---@param findings table[]
local function place(root, findings)
  local by_path = {}
  for _, f in ipairs(findings) do
    local abs = root .. "/" .. f.path
    by_path[abs] = by_path[abs] or {}
    table.insert(by_path[abs], f)
  end
  local out = require "agent.output.findings"
  local persist = require "agent.persist"
  for abs, list in pairs(by_path) do
    local buf = vim.fn.bufnr(abs)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      out.put(buf, list, static.SOURCE)
    else
      persist.merge("findings", abs, list, static.SOURCE)
    end
  end
  local items = {}
  for _, f in ipairs(findings) do
    items[#items + 1] = {
      filename = root .. "/" .. f.path,
      lnum = f.line,
      type = f.severity == vim.diagnostic.severity.ERROR and "E"
        or (f.severity == vim.diagnostic.severity.WARN and "W" or "I"),
      text = f.message,
    }
  end
  vim.fn.setqflist({}, " ", { title = "Staged review", items = items })
end

--- What the model would read, for showing it BEFORE spending anything
---@param root string
---@return { files: integer, chars: integer, truncated: boolean, skipped: string[], static: integer }
function M.describe(root)
  local files = diff.parse(staged_raw(root))
  local _, stats = diff.render(files, require("core.settings").git.commit.review_max_chars, git.is_noise)
  stats.static = #static.check(files, require("core.settings").git.commit.sensitive)
  return stats
end

--- Reviews the staged changes of the repo at `root`.
---@param root string
---@param cb fun(result: AgentReviewResult?, err: string?)?
function M.run(root, cb)
  cb = cb or function() end
  local cfg = require("core.settings").git.commit
  local files = diff.parse(staged_raw(root))
  if #files == 0 then
    log.info "Agent: nothing is staged"
    return cb(nil, "nothing is staged")
  end

  local findings = vim.tbl_map(function(f)
    return vim.tbl_extend("force", f, { source = static.SOURCE })
  end, static.check(files, cfg.sensitive))
  local static_count = #findings
  local text, stats = diff.render(files, cfg.review_max_chars, git.is_noise)

  ---@param model string?
  ---@param sent boolean
  local function finish(model, sent)
    place(root, findings)
    local n = #findings
    local files_with = {}
    for _, f in ipairs(findings) do
      files_with[f.path] = true
    end
    log.info(
      n == 0
          and ("Agent: staged review ✓ nothing found (%d file%s%s)"):format(
            stats.files,
            stats.files == 1 and "" or "s",
            sent and "" or ", checked locally"
          )
        or ("Agent: staged review · %d finding%s in %d file%s · quickfix has them%s"):format(
          n,
          n == 1 and "" or "s",
          vim.tbl_count(files_with),
          vim.tbl_count(files_with) == 1 and "" or "s",
          static_count > 0 and (" (%d from the free checks)"):format(static_count) or ""
        )
    )
    cb {
      findings = findings,
      static = static_count,
      sent = sent,
      model = model,
      files = stats.files,
      skipped = stats.skipped,
    }
  end

  -- nothing a model should read (only noise, deletions, binaries): the free checks are the whole review
  if stats.files == 0 then
    return finish(nil, false)
  end

  local selection = require "agent.selection"
  local sel = selection.current { name = "review_staged", tier = "main" }
  if not sel then
    log.warn "Agent: no backend for the model review; the free checks ran"
    return finish(nil, false)
  end
  local prompt = text
  log.info(
    ("Agent: reviewing %d staged file%s with %s…"):format(
      stats.files,
      stats.files == 1 and "" or "s",
      selection.label(sel)
    )
  )
  -- the spend guard is in the one-shot call itself (agent/oneshot): a no there comes back as a failure
  require("agent").complete(
    { action = "review_staged", system = SYSTEM, prompt = prompt, tier = "main" },
    function(ok, out)
      if not ok then
        log.warn("Agent: the model review did not run (" .. tostring(out) .. "); the free checks ran")
        return finish(selection.label(sel), false)
      end
      -- the lines the model was shown: a finding must point at one of them, anything else is invented and is dropped
      local shown = {}
      for _, f in ipairs(files) do
        shown[f.path] = {}
        for _, hunk in ipairs(f.hunks) do
          for _, l in ipairs(hunk.lines) do
            if l.n then
              shown[f.path][l.n] = true
            end
          end
        end
      end
      for _, f in ipairs(protocol.parse_file_findings(out)) do
        if shown[f.path] and shown[f.path][f.line] then
          findings[#findings + 1] = vim.tbl_extend("force", f, { source = static.SOURCE })
        end
      end
      finish(selection.label(sel), true)
    end
  )
end

return M
