-- ── Backend: Claude Code (`claude -p`) ───────────────────────────────────────
-- Flags that make it cheap, fast and predictable (measured: 579 input tokens
-- per call versus ~46,000 with the CLI's default config):
--   --setting-sources ""      do not load settings, plugins, skills, hooks or memory
--   --system-prompt           replaces the CLI's system prompt with the action's
--   --tools ""                no tools: text only, does not touch files
--   --no-session-persistence  no sessions on disk
--   DISABLE_PROMPT_CACHING=1  the cache only charges the write (every message is new): -40% per call
-- It does not use --bare or CLAUDE_CODE_SIMPLE: they disable OAuth and would break subscription use. About
-- ~560 fixed input tokens from the CLI itself remain that no safe flag trims.
local settings = require("core.settings").agent.claude
local ndjson = require "agent.backends.ndjson"
local sandbox = require "agent.sandbox"
local text = require "agent.text"

local M = {
  name = "claude",
  label = "Claude",
  default_model = settings.model,
  efforts = { "low", "medium", "high", "xhigh", "max" },
}

---@return boolean
function M.available()
  return vim.fn.executable "claude" == 1
end

---@param cb fun(models: table[])
function M.models(cb)
  cb(vim.tbl_map(function(id)
    return { id = id }
  end, settings.models))
end

---@param req table
---@return table
function M.build(req)
  local cmd = {
    "claude",
    "-p",
    "--model",
    req.model,
    "--tools",
    "",
    "--system-prompt",
    req.system,
    "--setting-sources",
    "",
    "--strict-mcp-config",
    "--disable-slash-commands",
    "--no-session-persistence",
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
  } -- stylua: ignore
  if req.effort then
    vim.list_extend(cmd, { "--effort", req.effort })
  end
  if settings.max_cost_usd then
    vim.list_extend(cmd, { "--max-budget-usd", tostring(settings.max_cost_usd) })
  end
  -- no prompt caching unless requested: see settings.agent.claude.prompt_cache. `req.cache`: a series of requests that share a
  -- long prefix (the build sends the same documents with every file) turns it on for itself: reads cost a tenth
  -- (not `cond and nil or x`: that is always x, and kept the cache off even with prompt_cache = true)
  local env = nil ---@type table?
  if not (settings.prompt_cache or req.cache) then
    env = { DISABLE_PROMPT_CACHING = "1" }
  end
  return { cmd = cmd, stdin = req.prompt, cwd = sandbox.dir(), env = env }
end

---@param result table `result` event of the stream
---@return table
local function usage_of(result)
  local u = result.usage or {}
  return {
    cost = result.total_cost_usd,
    tokens_in = (u.input_tokens or 0) + (u.cache_creation_input_tokens or 0) + (u.cache_read_input_tokens or 0),
    tokens_out = u.output_tokens,
    cache_read = u.cache_read_input_tokens or 0,
    cache_write = u.cache_creation_input_tokens or 0,
    ms = result.duration_ms,
  }
end

--- `opts.on_think(delta)`: the model's thinking as it streams (it comes before any text: a long plan thinks for a minute)
---@param opts { on_think: fun(delta: string)? }?
---@return table
function M.parser(opts)
  local on_think = opts and opts.on_think
  local chunks, final = {}, nil
  local feed = ndjson.new(function(ev)
    if ev.type == "stream_event" then
      local delta = ev.event and ev.event.delta
      if delta and delta.type == "text_delta" and delta.text then
        chunks[#chunks + 1] = delta.text
        return delta.text
      elseif on_think and delta and delta.type == "thinking_delta" and delta.thinking then
        on_think(delta.thinking)
      end
    elseif ev.type == "result" then
      final = ev
    end
  end)

  return {
    feed = feed,
    finish = function(code, stderr)
      if final then
        if final.is_error then
          return { ok = false, err = text.trim(final.result) ~= "" and final.result or "Claude error" }
        end
        return { ok = true, text = final.result or table.concat(chunks), usage = usage_of(final) }
      end
      if code ~= 0 then
        local msg = text.trim(stderr)
        return { ok = false, err = msg ~= "" and msg or ("claude exited with code %d"):format(code) }
      end
      return { ok = #chunks > 0, text = table.concat(chunks), err = "empty response" }
    end,
  }
end

return M
