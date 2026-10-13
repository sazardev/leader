-- Explain: short answer, in a window next to the code
return {
  label = "explain",
  desc = "explain",
  key = "e",
  scope = "function",
  context = { "rules", "types", "callees" },
  output = "text",
  tier = "light",
  system = function(env)
    return ("TASK explain in %s, Markdown, max 12 lines: one sentence on what <target> does and why, then only what is not obvious (edge cases, side effects, assumptions, pitfalls). No line-by-line narration."):format(
      env.language
    )
  end,
  task = function()
    return "Explain <target>."
  end,
}
