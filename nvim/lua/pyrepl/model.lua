-- ── Python REPL: el modelo local ──────────────────────────────────────────────
-- Todo pasa por el pipeline del agente (tier "light"): mismo backend/modelo que
-- <leader>am, mismos guards de gasto, sin duplicar cliente HTTP ni parser.
local M = {}

local EXPLAIN = [[You explain Python REPL output. Be concise and concrete.
Say what the code did, what each result/value means, and why an error happened when there is one.
Use short paragraphs and, when useful, a small bullet list. Never invent output that is not shown.]]

local GENERATE = [[You write Python code for an IPython REPL, in response to the user's instruction.
Return ONLY the code, with no prose and no markdown fences. Keep it self-contained and runnable:
imports first, then the statements. Prefer a few readable lines over a clever one-liner.]]

---@return table
function M.selection()
  return require("agent.selection").current { name = "pyrepl", tier = "light" }
end

---@return string
function M.label()
  local ok, sel = pcall(M.selection)
  if not ok or not sel then
    return "local model"
  end
  local backend = sel.backend or "?"
  return sel.model and (backend .. " · " .. sel.model) or backend
end

---@param text string
---@param cb fun(ok:boolean, answer:string, usage:table?)
function M.explain(text, cb)
  require("agent").complete({
    action = "pyrepl_explain",
    tier = "light",
    system = EXPLAIN,
    prompt = "<repl_output>\n" .. text .. "\n</repl_output>",
  }, cb)
end

---@param instruction string
---@param context string?
---@param cb fun(ok:boolean, answer:string, usage:table?)
function M.generate(instruction, context, cb)
  local prompt = "<task>\n" .. instruction .. "\n</task>"
  if context and vim.trim(context) ~= "" then
    prompt = prompt .. "\n<cell>\n" .. context .. "\n</cell>"
  end
  require("agent").complete({
    action = "pyrepl_generate",
    tier = "light",
    system = GENERATE,
    prompt = prompt,
  }, cb)
end

--- A model often wraps the answer in ```python … ``` even when told not to.
---@param text string?
---@return string
function M.clean_code(text)
  local body = vim.trim(text or "")
  local fenced = body:match "```[%w_+-]*%s*\n(.-)```"
  if fenced then
    body = vim.trim(fenced)
  else
    body = body:gsub("^```[%w_+-]*%s*\n", ""):gsub("\n```%s*$", "")
    body = vim.trim(body)
  end
  -- if there is chatter around the code, keep from the first line that looks like Python
  local first = body:find("[%w_#@]")
  if first then
    body = body:sub(first)
  end
  return body
end

--- Abre el chat con la sesión como contexto ya escrito en el composedor.
---@param prefill string
function M.chat(prefill)
  require("agent.chat").open()
  require("agent.chat.window").set_input(prefill)
end

---@return boolean
function M.fim()
  require("fim").toggle()
  return require("core.settings").fim.enabled == true
end

return M
