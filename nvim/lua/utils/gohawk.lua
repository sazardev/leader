-- ── GoHawk diagnostics ───────────────────────────────────────────────────────
-- gohawk (https://gohawk.dev) finds ownership, lifecycle and concurrency bugs that go vet / golangci-lint do not see:
-- leaked files and SQL handles, defers in loops, goroutines nobody waits for, contradictory lock order… It runs on the
-- current package from nvim-lint and on the whole module from <leader>gH; `-json` prints package → analyzer → findings.
-- Install: `go install github.com/kojah/gohawk@latest` (Go 1.26+). Parsing here is pure; diagnostics/quickfix adapt it.
local M = {}

-- Checks whose evidence establishes broken behavior (defect kind); the rest are hazards (risky, not necessarily
-- broken). `gohawk list -checks` prints the catalog; an unknown category is a warning, so a new check never overstates.
local DEFECT = {
  ["cancellationownership/release"] = true,
  ["lockorder/missing-release"] = true,
  ["processownership/missing-wait"] = true,
  ["resourcelifetime/missing-release"] = true,
}

---@class GoHawkFinding
---@field package string
---@field analyzer string
---@field category string
---@field file string
---@field line integer
---@field col integer
---@field end_line integer?
---@field end_col integer?
---@field message string
---@field related table[]
---@field severity "error"|"warn"

--- `posn`/`end` are `file:line:col`; the file pattern is greedy so a Windows drive colon is kept.
---@param s string?
---@return string? file, integer? line, integer? col
local function pos(s)
  if type(s) ~= "string" then
    return
  end
  local file, line, col = s:match "^(.*):(%d+):(%d+)$"
  if not file then
    return
  end
  return file, tonumber(line), tonumber(col)
end

---@param output string?
---@return GoHawkFinding[]
function M.parse(output)
  if not output or output == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, output)
  if not ok or type(data) ~= "table" then
    return {}
  end
  local out = {}
  for package, analyzers in pairs(data) do
    if type(analyzers) == "table" then
      for analyzer, findings in pairs(analyzers) do
        if type(findings) == "table" then
          for _, item in ipairs(findings) do
            if type(item) == "table" then
              local file, line, col = pos(item.posn)
              if file and line and col then
                local _, end_line, end_col = pos(item["end"])
                local category = item.category or analyzer
                out[#out + 1] = {
                  package = package,
                  analyzer = analyzer,
                  category = category,
                  file = file,
                  line = line,
                  col = col,
                  end_line = end_line,
                  end_col = end_col,
                  message = item.message or "",
                  related = type(item.related) == "table" and item.related or {},
                  severity = DEFECT[category] and "error" or "warn",
                }
              end
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.col < b.col
  end)
  return out
end

--- The message plus the evidence gohawk attached to it (the floating diagnostic and the quickfix show it).
---@param finding GoHawkFinding
---@return string
function M.detail(finding)
  local parts = { finding.message }
  local seen = { [finding.message] = true }
  for _, related in ipairs(finding.related or {}) do
    local text = type(related) == "table" and related.message or nil
    if type(text) == "string" and text ~= "" and not seen[text] then
      seen[text] = true
      local rfile, rline = pos(related.posn)
      local where = ""
      if rline then
        where = rfile == finding.file and (" [line " .. rline .. "]")
          or (" [" .. vim.fs.basename(rfile or "?") .. ":" .. rline .. "]")
      end
      parts[#parts + 1] = text .. where
    end
  end
  return table.concat(parts, "\n")
end

---@param path string
---@param cwd string?
---@return string
local function absolute(path, cwd)
  if path:match "^/" or path:match "^%a:[/\\]" then
    return vim.fs.normalize(path)
  end
  return vim.fs.normalize((cwd or vim.fn.getcwd()) .. "/" .. path)
end

--- Symlinks are common (`~/.config/nvim`), so compare the real paths when they exist.
---@param path string
---@return string
local function normalized(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

--- Diagnostics for `bufnr` only: gohawk analyzes the whole package, so findings in sibling files must not land here.
---@param output string?
---@param bufnr integer
---@param cwd string? the linter's cwd (the module root)
---@return vim.Diagnostic[]
function M.diagnostics(output, bufnr, cwd)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return {}
  end
  local buffer = normalized(vim.fn.fnamemodify(name, ":p"))
  local out = {}
  for _, finding in ipairs(M.parse(output)) do
    if normalized(absolute(finding.file, cwd)) == buffer then
      out[#out + 1] = {
        lnum = finding.line - 1,
        col = finding.col - 1,
        end_lnum = (finding.end_line or finding.line) - 1,
        end_col = (finding.end_col or finding.col) - 1,
        severity = finding.severity == "error" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
        source = "gohawk",
        code = finding.category,
        message = M.detail(finding),
      }
    end
  end
  return out
end

--- Replaces the quickfix list with every finding (the module audit, <leader>gH).
---@param findings GoHawkFinding[]
function M.quickfix(findings)
  local items = {}
  for _, finding in ipairs(findings) do
    local text = ("%s: %s"):format(finding.category, (finding.message:gsub("\n", " ")))
    local related = finding.related[1]
    if type(related) == "table" and type(related.message) == "string" and related.message ~= "" then
      text = text .. " — " .. (related.message:gsub("\n", " "))
    end
    items[#items + 1] = {
      filename = finding.file,
      lnum = finding.line,
      col = finding.col,
      end_lnum = finding.end_line,
      end_col = finding.end_col,
      text = text,
      type = finding.severity == "error" and "E" or "W",
    }
  end
  vim.fn.setqflist({}, "r", { title = "gohawk", items = items })
end

--- The nearest go.mod above `file` (else its folder): gohawk needs the process in a module, while the package itself
--- can be passed as an absolute directory.
---@param file string
---@return string
function M.root(file)
  local dir = vim.fs.dirname(vim.fn.fnamemodify(file, ":p"))
  if dir == nil or dir == "" then
    return vim.fn.getcwd()
  end
  local gomod = vim.fs.find("go.mod", { path = dir, upward = true })[1]
  return vim.fs.normalize(gomod and vim.fs.dirname(gomod) or dir)
end

return M
