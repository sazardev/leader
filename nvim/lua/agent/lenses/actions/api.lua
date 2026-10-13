return {
  key = "a",
  title = "api",
  tier = "light",
  context = { "rules", "changes", "types" },
  -- sin cambios sin commitear en el objetivo no hay contra qué comparar: no se llama al modelo
  check = function(target)
    if not require("agent.context.providers.changes").diff(target) then
      return "no uncommitted changes in the target: nothing to compare (0 tokens)"
    end
  end,
  focus = "<changes> is the uncommitted diff of <target>. Find changes that can break callers or consumers: removed or renamed exported names, changed signatures (parameter order, types, count), changed return shape or error values, nil/null/empty semantics, added or removed side effects, serialization tags and field names, changed defaults, stricter validation. Judge only what the diff shows and put each finding on the changed line.",
}
