-- Presentador "findings": cada hallazgo es un diagnóstico en su línea (namespace propio)
local anchor = require "agent.anchor"
local persist = require "agent.persist"
local protocol = require "agent.protocol"
local runs = require "agent.runs"

local M = {}

local NS = vim.api.nvim_create_namespace "agent.findings"

vim.diagnostic.config({
  virtual_text = false, -- se ve en los bloques en línea (utils/diagblocks.lua)
  underline = true,
  signs = false,
  severity_sort = true,
}, NS)

---@return integer
function M.namespace()
  return NS
end

--- Quita los hallazgos del agente (de un buffer, o de todos), también de lo guardado
---@param buf integer?
function M.clear(buf)
  vim.diagnostic.reset(NS, buf)
  if buf then
    local path = vim.api.nvim_buf_get_name(buf)
    if path ~= "" then
      persist.forget(path, "findings")
    end
  else
    persist.forget_all "findings"
  end
end

--- Quita los hallazgos que caen en un rango (el código se acaba de reescribir: ya no aplican)
---@param buf integer
---@param first integer 1-based
---@param last integer 1-based
---@return integer removed cuántos quitó
function M.resolve(buf, first, last)
  local all = vim.diagnostic.get(buf, { namespace = NS })
  local kept = vim.tbl_filter(function(d)
    return d.lnum + 1 < first or d.lnum + 1 > last
  end, all)
  vim.diagnostic.set(NS, buf, kept)
  persist.sync(buf, "findings")
  return #all - #kept
end

---@param job AgentJob
---@param result table
---@return string? summary
function M.done(job, result)
  local items = protocol.parse_findings(result.text)
  if #items == 0 and not protocol.is_ok(result.text) then
    -- formato inesperado: mejor enseñar la respuesta cruda que perderla
    return require("agent.output.text").done(job, result)
  end

  local first, last = anchor.range(job.buf, job.anchor)
  anchor.delete(job.buf, job.anchor)
  if not first then
    runs.event(job, "discarded", "target deleted")
    return nil
  end

  -- un review nuevo reemplaza al anterior SOLO en ese rango y SOLO el de su mismo origen: una lente (seguridad,
  -- rendimiento...) no borra lo que dijo otra
  local source = job.action.source or "agent"
  local kept = vim.tbl_filter(function(d)
    return d.lnum + 1 < first or d.lnum + 1 > last or (d.source or "agent") ~= source
  end, vim.diagnostic.get(job.buf, { namespace = NS }))

  local shift = first - job.target.first -- por si se editó encima mientras corría
  for _, f in ipairs(items) do
    local line = math.min(math.max(f.line + shift, first), last)
    local content = vim.api.nvim_buf_get_lines(job.buf, line - 1, line, false)[1] or ""
    kept[#kept + 1] = {
      lnum = line - 1,
      end_lnum = line - 1,
      col = (content:find "%S" or 1) - 1,
      end_col = #content,
      severity = f.severity,
      message = f.message,
      source = source,
    }
  end
  vim.diagnostic.set(NS, job.buf, kept)
  persist.sync(job.buf, "findings") -- por atender: sobrevive a la sesión
  runs.event(job, "findings", #items)

  if #items == 0 then
    return "no findings ✓"
  end
  return ("%d finding%s"):format(#items, #items == 1 and "" or "s")
end

---@param job AgentJob
function M.release(job)
  anchor.delete(job.buf, job.anchor)
end

return M
