-- Tests of the code search (nvim/lua/codesearch): the ranking (pure) and the treesitter index on a small mixed project
-- (Go, TypeScript, Lua): names, doc comments, paths, refreshing by mtime, deleted files. Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local rank = require "codesearch.rank"
local index = require "codesearch.index"

-- ── words and stems ─────────────────────────────────────────────────────────
eq("words: camelCase", rank.words "CreateOrderHTTP", { "create", "order", "http" })
eq("words: snake_case and paths", rank.words "internal/order_repo.go", { "internal", "order", "repo", "go" })
eq("stem: verbs and plurals meet", {
  rank.stem "created",
  rank.stem "creates",
  rank.stem "create",
  rank.stem "orders",
}, { "creat", "creat", "creat", "order" })
eq("query: filler is dropped", rank.query "where is the order created?", { "order", "creat" })

-- ── ranking (pure) ──────────────────────────────────────────────────────────
local function sym(name, path, extra)
  return vim.tbl_extend(
    "force",
    { name = name, kind = "function", path = path, line = 1, sig = "func " .. name .. "()" },
    extra or {}
  )
end
local list = {
  sym("CreateOrder", "internal/orders/service.go"),
  sym("OrderHandler", "internal/http/orders.go", { doc = "creates an order from the request body" }),
  sym("DeleteUser", "internal/users/service.go"),
  sym("createOrderForTest", "internal/orders/service_test.go"),
  sym("Order", "internal/orders/model.go", { kind = "type", sig = "type Order struct{}" }),
  sym("sendEmail", "internal/mail/send.go", { doc = "notifies the customer when the order ships" }),
}
local function names(query, limit)
  return vim.tbl_map(function(s)
    return s.name
  end, rank.search(list, query, limit or 10))
end
eq("search: the name that says it all comes first", names("create order")[1], "CreateOrder")
eq("search: a question works like words", names("where is the order created?")[1], "CreateOrder")
eq("search: the doc comment finds what the name does not say", names("creates an order")[2], "OrderHandler")
eq("search: unrelated symbols do not match", vim.tbl_contains(names "order created", "DeleteUser"), false)
eq("search: nothing matches nonsense", names "zzzqqq", {})
ok(
  "search: tests rank below the real thing",
  vim.fn.index(names "create order", "createOrderForTest") > vim.fn.index(names "create order", "CreateOrder")
)
ok("search: the path counts", vim.tbl_contains(names "mail", "sendEmail"))
ok("search: a doc-only match is found", vim.tbl_contains(names "customer ships", "sendEmail"))
eq("search: the limit holds", #names("order", 2), 2)
eq("search: an empty query lists in order", names("", 3), { "CreateOrder", "OrderHandler", "DeleteUser" })

-- ── the index on a real project ─────────────────────────────────────────────
local dir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["orders/service.go"] = {
    "package orders",
    "",
    "// CreateOrder stores a new order and charges the customer.",
    "func CreateOrder(id string) error {",
    "\treturn nil",
    "}",
    "",
    "type Order struct{ ID string }",
    "",
    "func (o *Order) Cancel() {}",
  },
  ["web/cart.ts"] = {
    "// adds an item to the cart",
    "export function addToCart(item: string) {",
    "  return item",
    "}",
    "",
    "export const removeFromCart = (item: string) => {",
    "  return item",
    "}",
    "",
    "export class CartView {}",
  },
  ["lua/util.lua"] = {
    "local M = {}",
    "",
    "--- Parses the config file",
    "function M.parse_config(path)",
    "  return path",
    "end",
    "",
    "return M",
  },
  ["README.md"] = { "# not code" },
  ["node_modules/x/ignored.go"] = { "package x", "func Ignored() {}" },
}
local built, stats
index.build(dir, function(l, s)
  built, stats = l, s
end)
K.wait(function()
  return built ~= nil
end)
local function find(name)
  for _, s in ipairs(built or {}) do
    if s.name == name then
      return s
    end
  end
end
ok("index: Go function", find "CreateOrder" and find("CreateOrder").kind == "function")
eq(
  "index: its line and path",
  find "CreateOrder" and { find("CreateOrder").path, find("CreateOrder").line },
  { "orders/service.go", 4 }
)
ok(
  "index: its doc comment",
  find "CreateOrder" and (find("CreateOrder").doc or ""):find("charges the customer", 1, true) ~= nil
)
ok("index: Go type", find "Order" and find("Order").kind == "type")
ok("index: Go method", find "Cancel" ~= nil)
ok("index: TypeScript function", find "addToCart" ~= nil)
ok("index: TypeScript arrow function takes the name it is assigned to", find "removeFromCart" ~= nil)
ok("index: TypeScript class", find "CartView" and find("CartView").kind == "type")
ok("index: Lua function", find "M.parse_config" ~= nil)
eq("index: excluded folders are not read", find "Ignored", nil)
ok(
  "index: the whole thing answers a question",
  rank.search(built, "where is the cart item added", 3)[1].name == "addToCart"
)
eq("index: first build reads every file that has a parser (go.mod and README.md too)", stats.read, 5)

-- refresh: only what changed is read again
local again
index.build(dir, function(_, s)
  again = s
end)
K.wait(function()
  return again ~= nil
end)
eq("refresh: nothing changed, nothing read", again.read, 0)

vim.uv.sleep(1100) -- mtime has a one-second grain on some file systems
vim.fn.writefile({ "package orders", "func Refund() {}" }, dir .. "/orders/service.go")
vim.fn.delete(dir .. "/web/cart.ts")
local third
index.build(dir, function(l, s)
  built, third = l, s
end)
K.wait(function()
  return third ~= nil
end)
eq("refresh: only the changed file is read again (the deleted one is not)", third.read, 1)
ok("refresh: new symbols appear", find "Refund" ~= nil)
eq("refresh: old symbols of that file go", find "CreateOrder", nil)
eq("refresh: deleted files go", find "addToCart", nil)

-- ── the index on disk: a new session starts from the last one ───────────────
local store = require "codesearch.store"
local settings = require("core.settings").search
local store_dir = vim.fn.tempname()
settings.store_dir = store_dir
settings.persist = true
index.drop(dir) -- start clean: nothing in memory or on disk for this project
local function build()
  local out
  index.build(dir, function(l, s)
    out = { list = l, stats = s }
  end)
  K.wait(function()
    return out ~= nil
  end)
  return out
end
local first = build()
vim.wait(300, function()
  return vim.fn.filereadable(store.path(dir)) == 1
end)
ok("store: the index is written after a build that read files", vim.fn.filereadable(store.path(dir)) == 1)
index.unload(dir) -- what a new session has: nothing in memory
local second = build()
eq("store: a new session re-reads nothing", second.stats.read, 0)
eq("store: and finds the same symbols", #second.list, #first.list)
-- a file that changed since the last session is the only one read again
index.unload(dir)
vim.uv.sleep(1100)
vim.fn.writefile({ "package orders", "func Refund() {}", "func Replace() {}" }, dir .. "/orders/service.go")
local third_session = build()
eq("store: only the file changed since the last session is read", third_session.stats.read, 1)
-- corrupt or foreign files are ignored, never an error
local f = io.open(store.path(dir), "wb")
f:write "{ not json"
f:close()
index.unload(dir)
ok("store: a corrupt file is ignored", store.load(dir) == nil)
eq("store: and the index is rebuilt from scratch", build().stats.read > 0, true)
local g = io.open(store.path(dir), "wb")
g:write(vim.json.encode { format = store.FORMAT + 1, root = dir, files = {} })
g:close()
ok("store: another format is ignored", store.load(dir) == nil)
g = io.open(store.path(dir), "wb")
g:write(vim.json.encode { format = store.FORMAT, root = "/somewhere/else", files = {} })
g:close()
ok("store: another folder is ignored", store.load(dir) == nil)
settings.persist = false
ok("store: off means nothing is loaded", store.load(dir) == nil)
eq("store: and nothing is saved", store.save(dir, {}), false)
settings.persist = true
index.drop(dir)
eq("store: drop forgets the copy on disk too", vim.fn.filereadable(store.path(dir)), 0)
vim.fn.delete(store_dir, "rf")

K.finish()
