-- Repository review: lo propio de un adaptador de persistencia, contra su puerto y su esquema
local protocol = require "agent.protocol"

return {
  label = "repository review",
  desc = "repo review",
  key = "r",
  source = "repository",
  scope = "function",
  context = { "rules", "diagnostics", "contracts", "schema", "types" },
  output = "findings",
  numbered = true,
  system = function(env)
    return ("TASK review this repository adapter (messages in %s): defects specific to persistence, checked against the port in <contracts> and the table in <schema>: columns or types that do not match the schema, wrong or mixed parameter style for the database, SQL built by string concatenation (injection), rows or statements not closed, missing context or transaction/rollback handling, errors not wrapped or not mapped to the domain's not-found, mapping that drops or swaps fields, N+1 queries, a signature that differs from the port.\n%s"):format(
      env.language,
      protocol.FINDINGS_RULES
    )
  end,
  task = function()
    return "Review <target> as a repository adapter."
  end,
}
