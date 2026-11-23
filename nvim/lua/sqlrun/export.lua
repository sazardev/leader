-- ── Taking results out of the editor ──────────────────────────────────────────
-- The results buffer draws whatever the client printed. These helpers read the boxed table back into cells and write
-- CSV, JSON or Markdown to a file (a fresh name in the state dir, so nothing is overwritten), or copy just the row
-- under the cursor. Pure formatters are tested in test-langs.lua.
local M = {}

---@param line string
---@return boolean
local function separator(line)
  if line:match "^%s*[╞├]" then
    return true
  end
  local body = (line:gsub("^%s*[│|]", ""):gsub("[│|]%s*$", "")):gsub("%s", "")
  return body ~= "" and body:match("^[-=:|]+$") ~= nil
end

---@param lines string[]
---@return { header: string[], rows: string[][] }
function M.cells(lines)
  local header, rows = {}, {}
  local started = false
  for _, line in ipairs(lines or {}) do
    if line:match "^%s*[│|]" then
      local cells = {}
      for cell in (line:gsub("^%s*[│|]", ""):gsub("[│|]%s*$", "")):gmatch "[^│|]+" do
        cells[#cells + 1] = vim.trim(cell)
      end
      if #cells > 0 then
        if not started then
          header, started = cells, true
        elseif not separator(line) then
          rows[#rows + 1] = cells
        end
      end
    end
  end
  return { header = header, rows = rows }
end

local function quote(value)
  if value:find('[",\r\n]') then
    return '"' .. value:gsub('"', '""') .. '"'
  end
  return value
end

---@param data { header: string[], rows: string[][] }
---@return string[]
function M.csv(data)
  local out = {}
  if #data.header > 0 then
    out[#out + 1] = table.concat(vim.tbl_map(quote, data.header), ",")
  end
  for _, row in ipairs(data.rows) do
    out[#out + 1] = table.concat(vim.tbl_map(quote, row), ",")
  end
  return out
end

---@param data { header: string[], rows: string[][] }
---@return string[]
function M.json(data)
  local out = {}
  for _, row in ipairs(data.rows) do
    local fields = {}
    for i, value in ipairs(row) do
      local key = data.header[i] or ("col" .. i)
      fields[#fields + 1] = ("%q: %q"):format(key, value)
    end
    out[#out + 1] = "{" .. table.concat(fields, ", ") .. "}"
  end
  return out
end

---@param data { header: string[], rows: string[][] }
---@return string[]
function M.markdown(data)
  if #data.header == 0 then
    return {}
  end
  local out = { "| " .. table.concat(data.header, " | ") .. " |", "|" .. table.concat(vim.tbl_map(function()
    return " --- "
  end, data.header), "|") .. "|" }
  for _, row in ipairs(data.rows) do
    out[#out + 1] = "| " .. table.concat(row, " | ") .. " |"
  end
  return out
end

---@param lines string[]
---@param row integer 1-based line in the buffer
---@return string?
function M.row_at(lines, row)
  local data = M.cells(lines)
  local index = 0
  local started = false
  for row_index, line in ipairs(lines) do
    if line:match "^%s*[│|]" then
      if not started then
        started = true
      elseif not separator(line) then
        index = index + 1
        if row_index == row then
          return table.concat(data.rows[index] or {}, " | ")
        end
      end
    end
  end
end

local function save(lines, ext, format)
  local data = M.cells(lines)
  if #data.rows == 0 then
    return require("utils.log").warn "SQL: no rows to export"
  end
  local dir = vim.fn.stdpath "state" .. "/sqlrun-exports"
  vim.fn.mkdir(dir, "p")
  local target = ("%s/%s.%s"):format(dir, os.date "%Y%m%d-%H%M%S", ext)
  local f = io.open(target, "w")
  if not f then
    return require("utils.log").warn("SQL: could not write " .. target)
  end
  f:write(table.concat(format(data), "\n") .. "\n")
  f:close()
  require("utils.log").info("SQL: wrote " .. vim.fn.fnamemodify(target, ":~"))
end

--- Installs the export keys on a results buffer.
---@param buf integer
function M.keys(buf)
  local function lines()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  -- Under <leader>: a results buffer is still a buffer, j/k and the c operator must keep working.
  vim.keymap.set("n", "<leader>c", function()
    save(lines(), "csv", M.csv)
  end, { buffer = buf, nowait = true, desc = "SQL export results as CSV" })
  vim.keymap.set("n", "<leader>j", function()
    save(lines(), "json", M.json)
  end, { buffer = buf, nowait = true, desc = "SQL export results as JSON" })
  vim.keymap.set("n", "<leader>m", function()
    save(lines(), "md", M.markdown)
  end, { buffer = buf, nowait = true, desc = "SQL export results as Markdown" })
  vim.keymap.set("n", "yc", function()
    local yanked = M.row_at(lines(), vim.api.nvim_win_get_cursor(0)[1])
    if yanked then
      pcall(vim.fn.setreg, '"', yanked)
      require("utils.log").info "SQL: copied this row"
    end
  end, { buffer = buf, nowait = true, desc = "SQL copy this result row" })
end

return M
