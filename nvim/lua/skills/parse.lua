-- ── Skills: SKILL.md parsing (pure) ─────────────────────────────────────────
-- A skill is ONE file: `SKILL.md` inside `.agents/skills/<id>/` (or a flat
-- `skills/<id>.md`). Frontmatter is optional but `description` is what the
-- model reads to decide when to load it (OpenCode lists only id+name+
-- description per step; the body loads on demand via the `skill` tool).
-- Tested in scripts/test-skills.lua.
local M = {}

---@class SkillParsed
---@field id string
---@field name string
---@field description string
---@field body string
---@field autoinvoke boolean true = announced to the model (false = dormant)
---@field valid boolean
---@field errors string[]

--- Frontmatter between the first pair of `---` lines (YAML subset: `key: value`
--- and folded `key: >`). Returns meta (raw strings) + the body after it.
---@param text string
---@return table<string, string>, string body
function M.frontmatter(text)
  text = text:gsub("\r\n", "\n")
  local meta, rest = {}, text:gsub("^%s+", "")
  if rest:sub(1, 3) == "---" then
    local close = rest:find("\n%-%-%-%s*\n", 5) or rest:find("\n%-%-%-%s*$")
    if close then
      local inner = rest:sub(5, close - 1)
      rest = rest:sub(close + 6)
      -- top-level `key: value` + folded `key: >` lines (indented, no colon-key)
      -- + one level of nesting (`metadata:` → `  opencode/autoinvoke: false`)
      local last_key, last_val = nil, {}
      local last_is_map = false
      local function flush()
        if last_key then
          meta[last_key] = vim.trim(table.concat(last_val, " "))
        end
        last_key, last_val, last_is_map = nil, {}, false
      end
      for _, line in ipairs(vim.split(inner, "\n", { plain = true })) do
        if line:match "^%s*$" then
          flush()
        else
          local nkey, nval = line:match "^%s+([%w_%-%.%/]+)%s*:%s*(.-)%s*$"
          local key, value = line:match "^([%w_%-%.%/]+)%s*:%s*(.-)%s*$"
          if nkey and last_is_map then
            meta[nkey] = nval -- nested: metadata/opencode/autoinvoke
          elseif nkey and last_key == "metadata" then
            meta[nkey] = nval
            last_is_map = true
          elseif key then
            flush()
            last_key, last_val = key, {}
            if value ~= ">" and value ~= "|" and value ~= "" then
              last_val[#last_val + 1] = value
            end
            last_is_map = last_key == "metadata" and value == ""
          elseif last_key and not last_is_map then
            last_val[#last_val + 1] = vim.trim(line)
          end
        end
      end
      flush()
    end
  end
  rest = rest:gsub("^%s*\n", "")
  return meta, rest
end

--- Parse one SKILL.md. `fallback_id` is the folder/file name when the frontmatter has no `name`.
---@param text string
---@param fallback_id string?
---@return SkillParsed
function M.parse(text, fallback_id)
  local meta, body = M.frontmatter(text)
  local id = meta.name or fallback_id or "untitled"
  local errors = {}
  if not meta.description or meta.description == "" then
    errors[#errors + 1] = "missing description: the model only sees name+description to decide"
  end
  local name = meta.name or id
  -- autoinvoke off when metadata opencode/autoinvoke = false or disable-model-invocation = true
  local autoinvoke = true
  local auto = (meta["opencode/autoinvoke"] or meta["autoinvoke"] or ""):lower()
  local disable = (meta["disable-model-invocation"] or meta["disable_model_invocation"] or ""):lower()
  if auto == "false" or disable == "true" then
    autoinvoke = false
  end
  return {
    id = id,
    name = name,
    description = meta.description or "",
    body = body,
    autoinvoke = autoinvoke,
    valid = #errors == 0,
    errors = errors,
    metadata = meta,
  }
end

--- Validate a skill without writing it (name + description + body).
---@param skill { id: string?, name: string?, description: string?, body: string? }
---@return string[] errors
function M.validate(skill)
  local errors = {}
  local id = skill.id or skill.name
  if not id or id == "" or id:find("%s") then
    errors[#errors + 1] = "name is required and must have no spaces"
  end
  if not skill.description or vim.trim(skill.description) == "" then
    errors[#errors + 1] = "description is required: it is the trigger the model reads"
  end
  if not skill.body or vim.trim(skill.body) == "" then
    errors[#errors + 1] = "body is required: the instructions to load"
  end
  return errors
end

--- Render one SKILL.md from its parts (inverse of `parse`).
---@param id string
---@param description string
---@param body string
---@param autoinvoke boolean? default true
---@return string
function M.render(id, description, body, autoinvoke)
  local out = { "---", "name: " .. id }
  local folded = {}
  for _, line in ipairs(vim.split(description, "\n", { plain = true })) do
    folded[#folded + 1] = vim.trim(line)
  end
  out[#out + 1] = "description: >"
  for _, line in ipairs(folded) do
    out[#out + 1] = "  " .. line
  end
  if autoinvoke == false then
    out[#out + 1] = "metadata:"
    out[#out + 1] = "  opencode/autoinvoke: false"
  end
  out[#out + 1] = "---"
  out[#out + 1] = ""
  out[#out + 1] = body
  return table.concat(out, "\n")
end

return M
