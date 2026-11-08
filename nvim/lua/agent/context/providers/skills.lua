-- Skills for the prompt: ONE relevant skill body (tool-less backends receive
-- it here; opencode with the `skill` tool loads it on demand and this stays a
-- cheap trigger). Picked by language + file + action words (0 tokens), capped
-- so a small model is not drowned. Silent when skills are off or none matches.
return {
  cap = 1200,
  stability = 1,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  ---@param opts { action?: table? }?
  collect = function(target, done, opts)
    local ok, skills = pcall(require, "skills")
    if not ok or require("core.settings").skills.enabled == false then
      return done(nil)
    end
    local action = opts and opts.action
    local hint = table.concat({
      target.lang or "",
      vim.fn.fnamemodify(target.path or "", ":t"),
      action and action.name or "",
      action and action.label or "",
    }, " ")
    local matches = skills.match_for_prompt(hint, 1)
    local skill = matches[1]
    if not skill then
      return done(nil)
    end
    done(("skill %s: %s"):format(skill.id, vim.trim(skill.body)))
  end,
}
