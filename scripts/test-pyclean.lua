-- Tests of the Python import cleanup (nvim/lua/pyclean: pure import analysis, the buffer flows are exercised through
-- the same pure functions). Hermetic: nvim -u NONE, no ruff, no network.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-pyclean.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end

local clean = require "pyclean.imports"
local pyimports = require "utils.pyimports"

-- parsing ---------------------------------------------------------------------
local src = {
  "from __future__ import annotations",
  "import os",
  "import numpy as np",
  "from sklearn.model_selection import train_test_split",
  "from pkg import (",
  "    a,",
  "    b as c,",
  ")",
  "print('hi')",
}
local sts = clean.statements(src)
eq("parse: statement count", #sts, 5)
eq("parse: __future__", sts[1].future, true)
eq("parse: import alias", sts[3].bound, { "np" })
eq("parse: from symbol", sts[4].bound, { "train_test_split" })
eq("parse: multiline from", sts[5].bound, { "a", "c" })
eq("parse: multiline range", { sts[5].first, sts[5].last }, { 5, 8 })

-- unused ----------------------------------------------------------------------
local removed, remaining = clean.remove_unused {
  "import os",
  "import numpy as np",
  "from pathlib import Path",
  "",
  "a = np.array([1])",
  "print(a)",
}
eq("unused: removed", removed, { "import os", "from pathlib import Path" })
eq("unused: remaining", remaining, { "import numpy as np", "", "a = np.array([1])", "print(a)" })

local keep_all = clean.remove_unused {
  "import os",
  "__all__ = ['os']",
}
eq("unused: __all__ is a re-export", keep_all, {})

local keep_comment = clean.remove_unused {
  "import os",
  "# os is used in the docs",
}
eq("unused: name in a comment counts as used", keep_comment, {})

local keep_string = clean.remove_unused {
  "import os",
  "name = 'os'",
}
eq("unused: name in a string counts as used", keep_string, {})

local keep_noqa = clean.remove_unused {
  "import os  # noqa: F401",
  "x = 1",
}
eq("unused: noqa is kept", keep_noqa, {})

-- sort / dedupe ----------------------------------------------------------------
local sorted, dups = clean.sort {
  "import pandas as pd",
  "import os",
  "import numpy as np",
  "import os",
  "from .local import thing",
  "",
  "x = 1",
}
eq("sort: duplicates", dups, 1)
eq("sort: sections", sorted, {
  "import os",
  "",
  "import numpy as np",
  "import pandas as pd",
  "",
  "from .local import thing",
  "",
  "x = 1",
})
eq("sort: no imports is a no-op", clean.sort { "x = 1" }, { "x = 1" })

-- missing ---------------------------------------------------------------------
eq("missing: aliases without import", clean.missing { "a = np.array([1])", "df = pd.DataFrame(a)" }, {
  "import numpy as np",
  "import pandas as pd",
})
eq("missing: already imported", clean.missing { "import numpy as np", "a = np.array([1])" }, {})
eq("missing: a string is not code", clean.missing { 's = "np.array"' }, {})

-- one pass --------------------------------------------------------------------
local out, counts = clean.clean {
  "import os",
  "import numpy as np",
  "a = np.array([1])",
}
eq("clean: result", out, { "import numpy as np", "a = np.array([1])" })
eq("clean: counts removed", counts.removed, { "import os" })
eq("clean: counts added", counts.added, {})
eq("clean: counts duplicates", counts.duplicates, 0)

-- shared masking ---------------------------------------------------------------
eq("mask: string", pyimports.mask('x = "np"'), "x =     ")
eq("mask: comment", pyimports.mask("x = 1  # np"), "x = 1      ")
eq("mask: plain code", pyimports.mask("x = np.array()"), "x = np.array()")

if fails == 0 then
  print("ALL OK (" .. total .. " checks)")
else
  print("FAILURES: " .. fails .. "/" .. total)
end
vim.cmd(fails == 0 and "qa!" or "cquit 1")
