-- ── Output shaped by the server ──────────────────────────────────────────────
-- A small model told to "answer with one fenced block" breaks the format often enough to matter (prose around it, two
-- blocks, no closing fence). Servers that can constrain decoding (Ollama's `format`, OpenAI-style `response_format`)
-- make that impossible: the answer is a JSON object that matches a schema. The pipeline's protocol stays the one text
-- format everything else reads, so the JSON is turned back into it here and nothing downstream knows the difference.
--
--   code       { code, needs_import, note }               replace actions: `code` is what the fenced block would hold
--   findings   { findings = { { line, severity, message } } }   review: an empty list is "OK"
local M = {}

---@param action table
---@return "code"|"findings"?
function M.kind(action)
  if action.output == "replace" then
    return "code"
  end
  if action.output == "findings" then
    return "findings"
  end
end

---@param kind "code"|"findings"
---@return table json schema
function M.json(kind)
  if kind == "findings" then
    return {
      type = "object",
      additionalProperties = false,
      required = { "findings" },
      properties = {
        findings = {
          type = "array",
          items = {
            type = "object",
            additionalProperties = false,
            required = { "line", "severity", "message" },
            properties = {
              line = { type = "integer" },
              severity = { type = "string", enum = { "error", "warn", "info" } },
              message = { type = "string" },
            },
          },
        },
      },
    }
  end
  return {
    type = "object",
    additionalProperties = false,
    required = { "code", "needs_import", "note" },
    properties = {
      code = { type = "string" },
      needs_import = { type = "string" },
      note = { type = "string" },
    },
  }
end

--- Appended to the system prompt: the OUTPUT rules above it describe the text format, which this replaces
---@param kind "code"|"findings"
---@return string
function M.suffix(kind)
  if kind == "findings" then
    return '\n\nFORMAT OVERRIDE: ignore the OUTPUT line format above. Answer ONLY with a JSON object {"findings":[{"line":<absolute line>,"severity":"error|warn|info","message":"<problem and fix>"}]}; an empty list when nothing is wrong.'
  end
  return '\n\nFORMAT OVERRIDE: ignore the fenced-block format above. Answer ONLY with a JSON object {"code":"<exactly what the fenced block would hold>","needs_import":"<imports or empty>","note":"<max 15 words or empty>"}.'
end

--- The JSON answer as the protocol's text. On anything that does not decode, the text is returned as it came
---@param kind "code"|"findings"
---@param text string
---@return string
function M.to_protocol(kind, text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return text
  end
  if kind == "findings" then
    local lines = {}
    for _, f in ipairs(data.findings or {}) do
      if type(f) == "table" and f.line and f.message then
        lines[#lines + 1] = ("L%d|%s|%s"):format(
          f.line,
          f.severity or "info",
          (tostring(f.message):gsub("[\r\n]+", " "))
        )
      end
    end
    return #lines > 0 and table.concat(lines, "\n") or "OK"
  end
  if type(data.code) ~= "string" then
    return text
  end
  local out = { "```", (data.code:gsub("\n$", "")), "```" }
  if type(data.needs_import) == "string" and data.needs_import ~= "" then
    out[#out + 1] = "needs-import: " .. data.needs_import
  end
  if type(data.note) == "string" and data.note ~= "" then
    out[#out + 1] = "note: " .. data.note
  end
  return table.concat(out, "\n")
end

--- A parser that hides the raw JSON while it streams and hands the protocol's text at the end
---@param inner table the backend's parser
---@param kind "code"|"findings"
---@return table
function M.wrap(inner, kind)
  return {
    feed = function(chunk)
      inner.feed(chunk)
      return nil -- half a JSON object is not something to show
    end,
    finish = function(code, stderr)
      local result = inner.finish(code, stderr)
      if result.ok and result.text then
        result.text = M.to_protocol(kind, result.text)
      end
      return result
    end,
  }
end

return M
