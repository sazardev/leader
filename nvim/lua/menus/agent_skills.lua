-- ── Skills context (global): <leader>aK ─────────────────────────────────────
-- The marketplace (utils/market) is the main view: read, install, edit and
-- delete without leaving it. Shortcuts below for the everyday moves.
local function skills()
  return require "skills"
end

return {
  name = "Skills",
  prefix = "aK",
  global = true,
  maps = {
    {
      "o",
      "marketplace",
      function()
        skills().open()
      end,
    },
    {
      "n",
      "new skill",
      function()
        skills().create()
      end,
    },
    {
      "s",
      "apply suggestions",
      function()
        skills().apply_suggestions()
      end,
    },
    {
      "e",
      "edit skill",
      function()
        skills().edit()
      end,
    },
    {
      "u",
      "check updates",
      function()
        require("skills.catalog").check_updates(function(ok, text)
          require("utils.log").info(ok and (text ~= "" and text or "Skills: up to date")
            or ("Skills: " .. (text or "check failed")))
        end)
      end,
    },
    {
      "d",
      "detected doctor",
      function()
        skills().doctor()
      end,
    },
    {
      "l",
      "list installed",
      function()
        local skills_list = skills().list()
        if #skills_list == 0 then
          return require("utils.log").info "Skills: none installed (aKo for the marketplace)"
        end
        local rows = vim.tbl_map(function(s)
          return { label = s.id .. " — " .. s.description, value = s.id, current = s.autoinvoke }
        end, skills_list)
        require("agent.ui.select").pick(rows, { title = ("Skills · %d"):format(#rows) }, function(row)
          skills().edit(row.value)
        end)
      end,
    },
  },
}
