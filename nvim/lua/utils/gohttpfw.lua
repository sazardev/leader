-- ── Go HTTP frameworks: what changes from one to another (no LLM, 0 tokens) ───
-- gohttp generates handlers and routes; ALL router-dependent things live here: how it is detected via go.mod, the
-- handler signature, where the context, path parameter, query and body come from, and how it responds or fails. Adding a
-- framework = one entry in FRAMEWORKS (and its name in `detect`); gohttp doesn't change.
-- Each entry: sig, ctx, path(name), query(key), query_setup?, decode(var), bad(err), fail(err), ok(status, value), empty().
local M = {}

---@param path string
---@return "nethttp"|"chi"|"gin"|"echo"|nil
function M.detect(path)
  local gomod = vim.fs.find("go.mod", { path = vim.fs.dirname(path), upward = true })[1]
  if not gomod then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, gomod)
  local text = ok and table.concat(lines, "\n") or ""
  if text:find("go-chi/chi", 1, true) then
    return "chi"
  elseif text:find("gin-gonic/gin", 1, true) then
    return "gin"
  elseif text:find("labstack/echo", 1, true) then
    return "echo"
  elseif text:find("gofiber/fiber", 1, true) then
    return nil
  end
  local minor = text:match "\ngo%s+1%.(%d+)"
  return (tonumber(minor) or 0) >= 22 and "nethttp" or nil
end

-- ── what changes per framework ───────────────────────────────────────────────

---@class GoHttpFw
---@field sig string
---@field ctx string
---@field path fun(name: string): string
---@field query_setup string?
---@field query fun(key: string): string
---@field decode fun(var: string): string  full `err := ...; err != nil` condition
---@field bad fun(err: string): string[]
---@field fail fun(err: string): string[]
---@field ok fun(status: string, value: string): string[]
---@field empty fun(): string[]
M.FRAMEWORKS = {
  nethttp = {
    sig = "(w http.ResponseWriter, r *http.Request)",
    ctx = "r.Context()",
    path = function(n)
      return ('r.PathValue("%s")'):format(n)
    end,
    query_setup = "q := r.URL.Query()",
    query = function(k)
      return ('q.Get("%s")'):format(k)
    end,
    decode = function(v)
      return ("json.NewDecoder(r.Body).Decode(&%s)"):format(v)
    end,
    bad = function(e)
      return { ("http.Error(w, %s.Error(), http.StatusBadRequest)"):format(e), "return" }
    end,
    fail = function(e)
      return { ("writeError(w, %s)"):format(e), "return" }
    end,
    ok = function(status, v)
      return { ("writeJSON(w, %s, %s)"):format(status, v) }
    end,
    empty = function()
      return { "w.WriteHeader(http.StatusNoContent)" }
    end,
  },
  gin = {
    sig = "(c *gin.Context)",
    ctx = "c.Request.Context()",
    path = function(n)
      return ('c.Param("%s")'):format(n)
    end,
    query = function(k)
      return ('c.Query("%s")'):format(k)
    end,
    decode = function(v)
      return ("c.ShouldBindJSON(&%s)"):format(v)
    end,
    bad = function(e)
      return { ('c.JSON(http.StatusBadRequest, gin.H{"error": %s.Error()})'):format(e), "return" }
    end,
    fail = function(e)
      return { ('c.JSON(http.StatusInternalServerError, gin.H{"error": %s.Error()})'):format(e), "return" }
    end,
    ok = function(status, v)
      return { ("c.JSON(%s, %s)"):format(status, v) }
    end,
    empty = function()
      return { "c.Status(http.StatusNoContent)" }
    end,
  },
  echo = {
    sig = "(c echo.Context) error",
    ctx = "c.Request().Context()",
    path = function(n)
      return ('c.Param("%s")'):format(n)
    end,
    query = function(k)
      return ('c.QueryParam("%s")'):format(k)
    end,
    decode = function(v)
      return ("c.Bind(&%s)"):format(v)
    end,
    bad = function(e)
      return { ("return echo.NewHTTPError(http.StatusBadRequest, %s.Error())"):format(e) }
    end,
    fail = function(e)
      return { ("return %s"):format(e) }
    end,
    ok = function(status, v)
      return { ("return c.JSON(%s, %s)"):format(status, v) }
    end,
    empty = function()
      return { "return c.NoContent(http.StatusNoContent)" }
    end,
  },
}
M.FRAMEWORKS.chi = vim.tbl_extend("force", M.FRAMEWORKS.nethttp, {
  path = function(n)
    return ('chi.URLParam(r, "%s")'):format(n)
  end,
})

return M
