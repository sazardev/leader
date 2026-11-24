-- ── Mappings: examples and usage for every shortcut ──────────────────────────
-- A small recipe book for the shortcuts worth explaining precisely, plus a
-- deterministic fallback so every mapping has an example and a usage note.
-- Recipes are keyed by menu + key first, then by key for unique global actions.
local M = {}

local RECIPES = {
  ["Cheatsheet|<leader>ch"] = {
    example = "From any buffer, press <leader>ch and type part of what you need.",
    usage = "Searches keys, actions, languages, menus, modes and examples. Hover or click a row to read how to use it.",
  },
  ["General|;"] = {
    example = "Press ; instead of : to enter Command mode.",
    usage = "Type an Ex command and press Enter; Esc or q returns to Normal mode.",
  },
  ["General|<leader>fm"] = {
    example = "Edit a file, then press <leader>fm.",
    usage = "Formats the current buffer, or only the selected text in Visual mode, with conform.",
  },
  ["General|<leader>w"] = {
    example = "Edit a file, then press <leader>w.",
    usage = "Writes the current buffer to disk. If format-on-save is enabled, the formatter runs before the write.",
  },
  ["General|<leader>q"] = {
    example = "Close the current file with <leader>q.",
    usage = "Closes its window or buffer. If it is the last file, Leader asks before quitting the whole editor.",
  },
  ["General|<leader>Q"] = {
    example = "When you are done, press <leader>Q.",
    usage = "Saves the session and asks to quit all windows without discarding unsaved changes.",
  },
  ["General|<leader>d"] = {
    example = "Press <leader>dd to delete a line, or <leader>dw to delete a word.",
    usage = "Deletes without touching the clipboard. In Visual mode, select text first and press <leader>d.",
  },
  ["Rename|<leader>rn"] = {
    example = "Put the cursor on a file and press <leader>rn.",
    usage = "Renames the file on disk and updates the open buffer, references and LSP workspace.",
  },
  ["Rename|<leader>rN"] = {
    example = "Press <leader>rN to rename a symbol across the project.",
    usage = "Finds project references first, then applies the rename consistently. Unsaved work is preserved.",
  },
  ["Rename|<leader>rs"] = {
    example = "Place the cursor on a symbol and press <leader>rs.",
    usage = "Uses the language server to rename only that symbol in the current workspace.",
  },
  ["Telescope|<leader>ff"] = {
    example = "Press <leader>ff and start typing a filename.",
    usage = "Opens Telescope's file picker. Enter opens the selected file; Esc returns to where you were.",
  },
  ["Telescope|<leader>fw"] = {
    example = "Press <leader>fw, type a word, then press Enter on a match.",
    usage = "Searches text across the project and opens the file at the matching line.",
  },
  ["Find|<leader>fo"] = {
    example = "Press <leader>fo to return to a file you edited recently.",
    usage = "Lists recent files for this project first, with open buffers at the top.",
  },
  ["Find|<leader>fs"] = {
    example = "Press <leader>fs and type a function or type name.",
    usage = "Searches the project's code index and jumps to the selected symbol.",
  },
  ["Find|<leader>fc"] = {
    example = "Press <leader>fc to search inside the current file.",
    usage = "Narrows the current buffer without searching the rest of the project.",
  },
  ["LSP|gd"] = {
    example = "Put the cursor on a function call and press gd.",
    usage = "Jumps to its definition. Esc returns to the call site when you have not edited there.",
  },
  ["LSP|grr"] = {
    example = "Put the cursor on a symbol and press grr.",
    usage = "Lists every reference in quickfix so you can inspect each use before jumping.",
  },
  ["LSP|<leader>ca"] = {
    example = "Place the cursor on a warning or refactor opportunity and press <leader>ca.",
    usage = "Opens the language server's code actions, such as extract method, rename or import fix.",
  },
  ["Diagnostics|<leader>xd"] = {
    example = "Put the cursor on a line with a diagnostic and press <leader>xd.",
    usage = "Opens the full message. Press it again to enter the popup and copy its text.",
  },
  ["Diagnostics|<leader>xa"] = {
    example = "Press <leader>xa to see diagnostics inline under their lines.",
    usage = "Toggles the block view for the current buffer without changing the saved global preference.",
  },
  ["Diagnostics|<leader>xn"] = {
    example = "Press <leader>xn to move to the next diagnostic.",
    usage = "Enables inline blocks when needed and centers the next problem in the buffer.",
  },
  ["Diagnostics|<leader>xx"] = {
    example = "Press <leader>xx to see problems across the project.",
    usage = "Opens Trouble's project diagnostics list; Enter jumps to the selected problem.",
  },
  ["Go|<leader>gr"] = {
    example = "Open a Go file and press <leader>gr.",
    usage = "Runs the current Go program from the module root in the integrated terminal.",
  },
  ["Go|<leader>gt"] = {
    example = "Open go.mod or any file in the module, then press <leader>gt.",
    usage = "Runs go mod tidy to add missing requirements and remove unused ones.",
  },
  ["Go|<leader>gR"] = {
    example = "Open a Go package and press <leader>gR.",
    usage = "Runs go test -race ./... from the module root to detect data races.",
  },
  ["Go|<leader>gm"] = {
    example = "Open a Go module and press <leader>gm.",
    usage = "Runs go test ./... across the module and shows failures in quickfix.",
  },
  ["Go|<leader>gM"] = {
    example = "Put the cursor inside a Go test and press <leader>gM.",
    usage = "Runs only the test under the cursor and keeps its output attached to the test line.",
  },
  ["Go|<leader>gl"] = {
    example = "Open a file in a Go package and press <leader>gl.",
    usage = "Runs the tests for that file's package without running the whole module.",
  },
  ["Go|<leader>gc"] = {
    example = "Open a Go package and press <leader>gc.",
    usage = "Runs go test -cover ./... and reports coverage for the module.",
  },
  ["Go|<leader>ga"] = {
    example = "Put the cursor on a Go struct field and press <leader>ga.",
    usage = "Adds a json tag derived from the field name, for example SentAt becomes sent_at.",
  },
  ["Go|<leader>gA"] = {
    example = "Put the cursor on a Go struct field and press <leader>gA.",
    usage = "Adds the json tag with omitempty so zero values are left out of encoded JSON.",
  },
  ["Python|<leader>pr"] = {
    example = "Open a Python file and press <leader>pr.",
    usage = "Runs that file with the project's interpreter and sends the output to the integrated terminal.",
  },
  ["Python|<leader>pm"] = {
    example = "Put the cursor inside a pytest test and press <leader>pm.",
    usage = "Runs only the test under the cursor and reports failures on their source lines.",
  },
  ["Python|<leader>pM"] = {
    example = "Open a Python test file and press <leader>pM.",
    usage = "Runs every test in that file with the project's pytest environment.",
  },
  ["Python|<leader>pA"] = {
    example = "Press <leader>pA from a Python project.",
    usage = "Runs the full test suite and opens failures in quickfix.",
  },
  ["Python|<leader>pf"] = {
    example = "Edit a Python file, then press <leader>pf.",
    usage = "Formats the buffer with Ruff using the project's configuration.",
  },
  ["Agent|<leader>ai"] = {
    example = "Select a function or place the cursor inside it, then press <leader>ai.",
    usage = "Sends that target and its project context to the inline agent for implementation. Review the diff before accepting.",
  },
  ["Agent|<leader>ar"] = {
    example = "Select the code you want reviewed and press <leader>ar.",
    usage = "Returns findings anchored to real lines instead of rewriting the function silently.",
  },
  ["Agent|<leader>ae"] = {
    example = "Put the cursor on unfamiliar code and press <leader>ae.",
    usage = "Explains the target using its types, signatures and diagnostics as context.",
  },
  ["Agent|<leader>aa"] = {
    example = "Select code and press <leader>aa, then type your question.",
    usage = "Asks the inline agent about that exact target while keeping the answer next to your code.",
  },
  ["Agent|<leader>af"] = {
    example = "Put the cursor on a diagnostic and press <leader>af.",
    usage = "Builds an inline fix for those lines. Accept or reject the proposal; nothing changes automatically.",
  },
  ["Agent|<leader>aF"] = {
    example = "Put the cursor inside a function and press <leader>aF.",
    usage = "Fixes the whole function when the problem spans more than the diagnostic line.",
  },
  ["Agent|<leader>ad"] = {
    example = "Select a function and press <leader>ad.",
    usage = "Generates only its documentation comment in the language's idiomatic style.",
  },
  ["Agent|<leader>aR"] = {
    example = "Select a function and press <leader>aR.",
    usage = "Proposes a whole-function refactor as an inline diff you can inspect before accepting.",
  },
  ["Git|<leader>Gc"] = {
    example = "Stage the files you want, then press <leader>Gc.",
    usage = "Opens the conventional-commit panel with the staged diff, validation and optional AI draft.",
  },
  ["Git|<leader>Gm"] = {
    example = "Stage your changes and press <leader>Gm.",
    usage = "Opens the commit panel and asks the agent for an English Conventional Commit subject.",
  },
  ["Git|<leader>GP"] = {
    example = "Commit your work, then press <leader>GP.",
    usage = "Pushes the current branch and sets its upstream the first time it is pushed.",
  },
  ["Git|<leader>Gu"] = {
    example = "Press <leader>Gu to update the current branch.",
    usage = "Pulls with fast-forward only, so a divergent history is never merged silently.",
  },
  ["Session|<leader>Ps"] = {
    example = "Press <leader>Ps to return to another project's session.",
    usage = "Lists remembered projects and restores the selected project's windows and buffers.",
  },
  ["Session|<leader>Pw"] = {
    example = "Arrange your windows, then press <leader>Pw.",
    usage = "Saves the current session immediately; Leader also saves it periodically and on exit.",
  },
  ["Terminal|<leader>Tt"] = {
    example = "Press <leader>Tt to show or hide the command terminal.",
    usage = "Reopening it returns to the same shell and output; Esc does not kill the running process.",
  },
  ["Terminal|<leader>Tn"] = {
    example = "Press <leader>Tn when you need a fresh shell.",
    usage = "Creates a new named integrated terminal without disturbing the existing one.",
  },
  ["<Tab>"] = {
    example = "While completion items are visible, press Tab.",
    usage = "Selects the next item. With no menu, it moves to the next snippet placeholder when one exists.",
  },
  ["<S-Tab>"] = {
    example = "While completion items are visible, press Shift+Tab.",
    usage = "Selects the previous item or moves to the previous snippet placeholder.",
  },
  ["<CR>"] = {
    example = "Choose a completion item, then press Enter.",
    usage = "Accepts the item. With no completion, Enter keeps its normal editing behavior.",
  },
  ["grn"] = {
    example = "Put the cursor on a local symbol and press grn.",
    usage = "Uses the language server to rename that symbol and its references in the workspace.",
  },
  ["gra"] = {
    example = "Put the cursor on a code issue and press gra.",
    usage = "Opens Neovim's native code-action picker for the language server.",
  },
  ["gri"] = {
    example = "Put the cursor on an interface or method and press gri.",
    usage = "Jumps to an implementation of that symbol.",
  },
  ["grt"] = {
    example = "Put the cursor on a variable and press grt.",
    usage = "Jumps to the symbol's type definition.",
  },
  ["gO"] = {
    example = "Press gO in a source file.",
    usage = "Lists document symbols so you can jump to a function, class or type.",
  },
  ["K"] = {
    example = "Put the cursor on a symbol and press K.",
    usage = "Opens its documentation or type information from the language server.",
  },
  ["gx"] = {
    example = "Put the cursor on a URL or file path and press gx.",
    usage = "Opens that target with the system's configured handler.",
  },
  ["gc / gcc"] = {
    example = "Press gcc to comment the current line, or gc plus a motion to comment a region.",
    usage = "Uses the editor's native comment operator and the current filetype's comment style.",
  },
}

local MODE_LABEL = { n = "Normal", x = "Visual", o = "Operator-pending", i = "Insert", t = "Terminal" }

---@param text string
---@return string
local function sentence(text)
  text = vim.trim(text)
  if text == "" then
    return text
  end
  return text:match "%.$" and text or (text .. ".")
end

---@param entry table
---@return string
local function situation(entry)
  local mode = entry.modes and entry.modes[1] or "n"
  if mode == "x" then
    return "Select the text first, then press " .. entry.key .. "."
  elseif mode == "o" then
    return "Press " .. entry.key .. ", then choose a motion or text object."
  elseif mode == "i" then
    return "While typing in Insert mode, press " .. entry.key .. "."
  elseif mode == "t" then
    return "From Terminal mode, press " .. entry.key .. "."
  elseif entry.source == "tree" then
    return "Inside nvim-tree, press " .. entry.key .. "."
  elseif entry.language and entry.language ~= "Global" then
    return "In a " .. entry.language .. " buffer, press " .. entry.key .. "."
  elseif entry.where and entry.where ~= "everywhere" then
    if entry.where:find "git" then
      return "Inside a Git repository, press " .. entry.key .. "."
    elseif entry.where:find "buffer" then
      return "In a matching buffer, press " .. entry.key .. "."
    end
    return "In " .. entry.where .. ", press " .. entry.key .. "."
  end
  return "In the editor, press " .. entry.key .. "."
end

--- Classifies the workflow so every mapping gets steps that match what it actually does.
---@param entry table
---@return string
local function classify(entry)
  local action = (entry.action or ""):lower()
  local key, source, group = entry.key, entry.source, entry.group or ""

  if source == "completion" then
    if key == "<Tab>" then
      return "completion_next"
    elseif key == "<S-Tab>" then
      return "completion_prev"
    elseif key == "<CR>" then
      return "completion_accept"
    end
    return "completion"
  elseif source == "tree" then
    if action:find "delete" or action:find "trash" or action:find "remove" then
      return "tree_delete"
    elseif action:find "rename" or action:find "create" then
      return "tree_edit"
    elseif action:find "copy" or action:find "cut" or action:find "paste" or action:find "move" then
      return "tree_clipboard"
    elseif action:find "open" then
      return "tree_open"
    elseif action:find "filter" or action:find "toggle" then
      return "tree_filter"
    elseif action:find "reload" or action:find "refresh" then
      return "tree_refresh"
    elseif action:find "expand" or action:find "collapse" then
      return "tree_expand"
    elseif action:find "info" or action:find "help" then
      return "tree_info"
    elseif action:find "run command" or action:find "run system" then
      return "tree_run"
    elseif action:find "search" or action:find "live filter" then
      return "tree_search"
    elseif
      action == "up"
      or action:find "parent"
      or action:find "root"
      or action:find "sibling"
      or action:find "^next"
      or action:find "^prev"
      or action == "last"
      or action == "first"
      or action == "cd"
    then
      return "tree_navigation"
    end
    return "tree"
  elseif source == "native" then
    if key == "gO" then
      return "native_symbols"
    elseif key == "gx" then
      return "native_external"
    elseif key == "gc / gcc" then
      return "native_comment"
    elseif key == "grn" then
      return "native_rename"
    end
    return "native_navigation"
  elseif source == "lsp" or group == "LSP" then
    if action:find "reference" then
      return "lsp_references"
    elseif action:find "code action" then
      return "lsp_action"
    elseif action:find "definition" or action:find "implementation" then
      return "lsp_definition"
    end
    return "lsp"
  elseif group == "Cheatsheet" then
    return "cheatsheet"
  elseif group:find "^Agent" then
    if action:find "implement" then
      return "agent_implement"
    elseif action:find "review" then
      return "agent_review"
    elseif action:find "explain" then
      return "agent_explain"
    elseif action:find "ask" then
      return "agent_ask"
    elseif action:find "fix" then
      return "agent_fix"
    elseif action:find "refactor" then
      return "agent_refactor"
    elseif action:find "docs" or action:find "document" then
      return "agent_docs"
    end
    return "agent"
  elseif group == "Git" then
    if action:find "commit" then
      return "git_commit"
    elseif action:find "push" then
      return "git_push"
    elseif action:find "pull" then
      return "git_pull"
    elseif action:find "fetch" then
      return "git_fetch"
    end
    return "git"
  elseif group == "Session" then
    return "session"
  elseif group == "Terminal" then
    return "terminal"
  elseif group == "Diagnostics" then
    if action:find "popup" then
      return "diagnostics_popup"
    elseif action:find "block" then
      return "diagnostics_blocks"
    elseif action:find "next" or action:find "previous" then
      return "diagnostics_step"
    elseif action:find "project" or action:find "list" then
      return "diagnostics_list"
    end
    return "diagnostics"
  elseif group == "Telescope" or group == "Find" then
    return "picker"
  elseif group == "History" then
    return "history"
  elseif group == "Fold" then
    return "fold"
  elseif group == "SQL" then
    return "sql"
  elseif key == ";" then
    return "command"
  elseif
    action:find "go mod tidy"
    or action:find "dependency"
    or action:find "dependencies"
    or action:find "outdated"
  then
    return "dependencies"
  elseif action:find "json tag" or action:find "struct tag" then
    return "tags"
  elseif action:find "debug breakpoint" then
    return "debug_breakpoint"
  elseif action:find "test under cursor" then
    return "test_cursor"
  elseif action:find "test file" then
    return "test_file"
  elseif action:find "test all" or action:find "test project" or action:find "test module" then
    return "test_all"
  elseif action:find "test again" then
    return "test_again"
  elseif action:find "test" or action:find "coverage" then
    return "test"
  elseif action:find "debug" then
    return "debug"
  elseif action:find "repl" or action:find "jupyter" or action:find "send line" or action:find "send selection" then
    return "repl"
  elseif action:find "build" then
    return "build"
  elseif action:find "run" or action:find "start" then
    return "run"
  elseif action:find "format" then
    return "format"
  elseif action:find "lint" or action:find "check" or action:find "fix" then
    return "check"
  elseif action:find "setup" or action:find "init" or action:find "install" or action:find "create config" then
    return "setup"
  elseif action:find "find" or action:find "search" or action:find "picker" or action:find "pick" then
    return "picker"
  elseif action:find "save" or action:find "write" then
    return "save"
  elseif action:find "close" or action:find "quit" or action:find "exit" then
    return "close"
  elseif action:find "rename" then
    return "rename"
  elseif action:find "copy" or action:find "cut" or action:find "paste" then
    return "clipboard"
  elseif action:find "delete" or action:find "remove" or action:find "trash" then
    return "delete"
  elseif action:find "toggle" then
    return "toggle"
  elseif action:find "open" or action:find "show" or action:find "view" then
    return "view"
  elseif action:find "document" or action:find "docs" or action:find "comment" then
    return "docs"
  elseif
    action:find "reference"
    or action:find "definition"
    or action:find "implementation"
    or action:find "type definition"
  then
    return "navigation"
  elseif action:find "commit" then
    return "git_commit"
  elseif action:find "push" then
    return "git_push"
  elseif action:find "pull" then
    return "git_pull"
  elseif action:find "fetch" then
    return "git_fetch"
  elseif action:find "implement" then
    return "agent_implement"
  elseif action:find "review" then
    return "agent_review"
  elseif action:find "explain" then
    return "agent_explain"
  elseif action:find "ask" then
    return "agent_ask"
  elseif action:find "refactor" then
    return "agent_refactor"
  end
  return "generic"
end

---@param usage string
---@param steps string[]
---@param result string
---@param notes string[]
---@return table
local function guide(usage, steps, result, notes)
  return { usage = usage, steps = steps, result = result, notes = notes }
end

--- Builds a complete, readable workflow for a mapping. The short recipe explains the specific
--- command; this guide adds preparation, numbered steps, expected output and caveats.
---@param kind string
---@param entry table
---@param overview string
---@return table
local function workflow(kind, entry, overview)
  local key = entry.key
  local language = entry.language ~= "Global" and entry.language or "project"
  local where = entry.where or "the matching buffer"

  if kind == "completion_next" or kind == "completion_prev" or kind == "completion_accept" or kind == "completion" then
    local forward = kind == "completion_next"
    local accept = kind == "completion_accept"
    return guide(
      overview
        .. " Completion is contextual: the same key behaves differently when the menu, a snippet placeholder or plain text is active.",
      {
        "Start typing in Insert mode and wait for blink.cmp to show its completion menu.",
        accept and "Highlight the item you want, then press Enter."
          or (
            forward and "Press Tab to move forward through the candidates."
            or "Press Shift+Tab to move backward through the candidates."
          ),
        "Continue typing or press Enter to insert the chosen text.",
        "If no item applies, use Esc once to close the menu and stay in Insert mode.",
      },
      accept and "The highlighted completion is inserted; with no menu, Enter keeps its normal editing behavior."
        or "The selection moves without leaving Insert mode; with no menu, the key can jump between snippet placeholders.",
      {
        "Esc with the menu open only closes completion and keeps your cursor in the snippet.",
        "Tab never accepts the local FIM ghost text; Ctrl+Tab does.",
      }
    )
  elseif kind == "tree_delete" then
    return guide(
      overview .. " The operation targets the row under the nvim-tree cursor, not the file open in the editor.",
      {
        "Open nvim-tree and select the file or folder you intend to remove.",
        "Read the confirmation carefully, especially for folders with contents.",
        "Press " .. key .. " and confirm only if the target is correct.",
        "Refresh the tree if the view does not update immediately.",
      },
      "The selected entry is deleted or moved to the trash, according to the exact nvim-tree action.",
      {
        "Open buffers with unsaved changes are not a safe target.",
        "Trash and permanent delete are different actions; check the prompt before confirming.",
      }
    )
  elseif kind == "tree_edit" then
    return guide(
      overview .. " nvim-tree edits the selected path in place and keeps the rest of the tree unchanged.",
      {
        "Select the file or folder to rename or create in nvim-tree.",
        "Press " .. key .. " to open the name field.",
        "Type the new name or path and review it before confirming.",
        "Press Enter to apply, or Esc to cancel without changing the filesystem.",
      },
      "The selected entry is renamed or the new file/folder is created at the chosen path.",
      {
        "A name that already exists may be refused.",
        "Renaming a file open in another buffer can require that buffer to be reloaded.",
      }
    )
  elseif kind == "tree_clipboard" then
    return guide(
      overview .. " Copy and cut only mark the tree entry; the filesystem changes when you paste.",
      {
        "Select the source file or folder in nvim-tree.",
        "Press " .. key .. " to copy or cut it.",
        "Move to the destination folder.",
        "Press the paste key to complete the operation and review any overwrite prompt.",
      },
      "The marked entry is copied or moved into the destination folder.",
      {
        "Cut removes the source only after a successful paste.",
        "Pasting into a folder with conflicting names requires a deliberate choice.",
      }
    )
  elseif kind == "tree_open" then
    return guide(
      overview .. " The exact target depends on whether the action opens in place, a split, a tab or a preview.",
      {
        "Select the desired entry in nvim-tree.",
        "Press " .. key .. ".",
        "Use the resulting window or tab to work with the file.",
        "Return to the tree with its toggle or focus shortcut when needed.",
      },
      "The selected entry opens in the target requested by the action; opening a file normally closes the tree.",
      {
        "Preview opens the file without replacing your working buffer.",
        "Folders may expand or change the tree root instead of opening a file.",
      }
    )
  elseif kind == "tree_navigation" then
    return guide(
      overview .. " Navigation only moves the selection or tree root; it does not modify files.",
      {
        "Open nvim-tree and select the entry you want to move from.",
        "Press " .. key .. " to go up, change root or move to a sibling.",
        "Check the new cursor row or root label.",
        "Open the desired entry with Enter when you reach it.",
      },
      "The nvim-tree cursor or root changes to the requested location.",
      {
        "Going up may change the visible root rather than close a directory.",
        "The file open in the editor is unaffected by tree navigation.",
      }
    )
  elseif kind == "tree_refresh" then
    return guide(
      overview .. " Refresh rereads the filesystem so external changes become visible.",
      {
        "Select the tree or folder that looks stale.",
        "Press " .. key .. " to reload it.",
        "Wait for the new listing.",
        "Inspect added, removed or renamed entries.",
      },
      "nvim-tree reloads its listing from disk.",
      { "Refresh does not save editor buffers.", "A focused tree may reload only the current root or folder." }
    )
  elseif kind == "tree_expand" then
    return guide(
      overview .. " Expanding and collapsing changes visibility only.",
      {
        "Select a folder or the tree root.",
        "Press " .. key .. " to expand or collapse the requested level.",
        "Continue navigating the visible rows.",
        "Collapse again when you want a compact overview.",
      },
      "The selected folder or tree level expands or collapses.",
      {
        "Collapsed folders still exist and may contain unsaved editor buffers.",
        "Some actions expand every folder; use the matching collapse action afterward.",
      }
    )
  elseif kind == "tree_info" or kind == "tree_search" or kind == "tree_run" then
    local result = kind == "tree_info" and "Information or key help for the selected entry appears."
      or kind == "tree_search" and "The tree narrows to entries matching the query."
      or "The requested command runs for the selected entry and its output appears in the terminal."
    return guide(
      overview .. " The action works on the current tree selection.",
      {
        "Select the relevant file or folder in nvim-tree.",
        "Press " .. key .. " to open information, search or run the command.",
        "Read the popup, filtered list or terminal output.",
        "Return to the tree and continue navigating.",
      },
      result,
      {
        kind == "tree_run" and "Commands can modify files; review what will run before confirming."
          or "Closing the information view returns you to the same tree selection.",
        "Search and information views do not change the filesystem.",
      }
    )
  elseif kind == "tree_filter" or kind == "tree" then
    return guide(
      overview .. " This changes the tree view, not the files on disk.",
      {
        "Select the relevant entry or filter in nvim-tree.",
        "Press " .. key .. " to apply the action.",
        "Inspect which rows are now shown or hidden.",
        "Use the matching clear/toggle action when you want the full tree again.",
      },
      "The nvim-tree listing updates to reflect the selected filter or command.",
      {
        "Hidden entries still exist on disk.",
        "Git-ignored and dotfile filters can be combined, so a missing row may have more than one cause.",
      }
    )
  elseif kind == "native_symbols" then
    return guide(
      overview .. " It is useful when you know the symbol name but not its line.",
      {
        "Open the source file and press gO.",
        "Type part of a function, class or type name to narrow the list.",
        "Choose the symbol with Enter.",
        "Use Esc or the back shortcut to return to the previous location.",
      },
      "Neovim's document-symbol picker opens and jumps to the selected declaration.",
      {
        "The quality of the symbol list depends on the filetype parser or language server.",
        "gO lists document symbols; it does not search the entire project.",
      }
    )
  elseif kind == "native_external" then
    return guide(
      overview .. " The target is taken from the text under the cursor.",
      {
        "Place the cursor on a URL, local path or other recognized resource.",
        "Press gx.",
        "Wait for the operating system's configured handler to open it.",
        "Return to Neovim after inspecting the external application.",
      },
      "The URL or path opens in the system browser, file manager or associated application.",
      { "Remote URLs require network access.", "A path with spaces or an unsupported scheme may not be recognized." }
    )
  elseif kind == "native_comment" or kind == "native_rename" then
    return guide(
      overview .. " The current filetype determines the exact edit and comment style.",
      {
        "Place the cursor on the line or symbol, or select a region in Visual mode.",
        "Press " .. key .. " and provide a motion when the command is an operator.",
        "Review the affected lines before continuing.",
        "Save the file when the change is correct.",
      },
      kind == "native_comment" and "The selected lines are commented or uncommented using the filetype's native syntax."
        or "The symbol and its language-server references are renamed consistently.",
      {
        "Operator-pending commands wait for a motion; Esc cancels them.",
        "LSP rename requires an attached server and may fail on unsupported symbols.",
      }
    )
  elseif kind == "native_navigation" then
    return guide(
      overview .. " This is a built-in Neovim navigation command.",
      {
        "Open a file supported by the active parser or language server.",
        "Place the cursor on the relevant symbol.",
        "Press " .. key .. " and wait for the destination.",
        "Use Esc, Ctrl+o or the jump list to return when needed.",
      },
      "The cursor moves to the related declaration, type, implementation or documentation.",
      {
        "Results depend on the language server and the symbol under the cursor.",
        "A missing destination usually means the server is still loading or cannot resolve that symbol.",
      }
    )
  elseif kind == "lsp_definition" then
    return guide(
      overview .. " Use it to move from a use site to its declaration without losing your place.",
      {
        "Open a project file with its language server attached.",
        "Place the cursor on the call, variable or type you want to inspect.",
        "Press " .. key .. ".",
        "Read the declaration, then press Esc or Ctrl+o to return.",
      },
      "Neovim jumps to the definition or implementation and records the previous location in the jump list.",
      {
        "The first LSP load on a large project can take time.",
        "If the definition is in another file, the current buffer remains available in the buffer list.",
      }
    )
  elseif kind == "lsp_references" then
    return guide(
      overview .. " References are gathered across the workspace, not just the current file.",
      {
        "Put the cursor on the symbol whose usages you want to inspect.",
        "Press " .. key .. " and wait for the language server.",
        "Review the quickfix entries and their file/line locations.",
        "Press Enter on an entry to jump; return to the list when finished.",
      },
      "A quickfix list shows each reference so you can visit uses one by one.",
      {
        "Very large workspaces can take longer to answer.",
        "Dynamic references may include false positives; inspect the surrounding code before editing.",
      }
    )
  elseif kind == "lsp_action" then
    return guide(
      overview .. " Available actions depend on the language server and the exact cursor position.",
      {
        "Place the cursor on the diagnostic, symbol or expression to change.",
        "Press " .. key .. " to request code actions.",
        "Read the picker and choose the intended fix or refactor.",
        "Review the resulting edit before saving.",
      },
      "The selected action is applied, or a further input such as a new name is requested.",
      {
        "The list can be empty when the server has no action for that position.",
        "Some actions modify several files; inspect the diff before accepting broad changes.",
      }
    )
  elseif kind == "lsp" then
    return guide(
      overview .. " The command delegates to the active language server.",
      {
        "Open a file whose language server has attached.",
        "Position the cursor on the relevant symbol or range.",
        "Press " .. key .. " and wait for the result.",
        "Inspect the edit, navigation or information before continuing.",
      },
      "The language server performs the requested operation for the current buffer.",
      {
        "No attached server means the command cannot resolve project symbols.",
        "Server startup and workspace indexing may delay the first answer.",
      }
    )
  elseif kind == "cheatsheet" then
    return guide(
      overview .. " The search is live and the detail pane documents every result.",
      {
        "Press <leader>ch from any buffer to open Mappings.",
        "Press / or click the bottom input and type a few words.",
        "Refine the query while the list, count and detail update immediately.",
        "Click or press Enter on a result to read its example, steps, result and notes; y copies the key.",
      },
      "The matching mappings appear instantly, grouped by menu or feature, with complete usage documentation.",
      {
        "Search also matches examples, steps and notes.",
        "Enter keeps the query; Esc clears it; r resets every filter.",
        "The same mappings are generated into CHEATSHEET.md for offline reference.",
      }
    )
  elseif kind == "agent_implement" then
    return guide(
      overview .. " Treat the output as a proposal: the agent does not get to silently rewrite your project.",
      {
        "Select the function or place the cursor inside the target to implement.",
        "Press " .. key .. " and describe the required behavior if prompted.",
        "Wait for the inline diff and inspect every changed line.",
        "Accept only after the change matches the requirement; otherwise reject or refine it.",
      },
      "A reviewable implementation proposal appears next to the target, with diagnostics and project context already considered.",
      {
        "The model can miss project conventions; compare the result with nearby code.",
        "Run the project's tests after accepting a proposal.",
        "Prompts and code may leave your machine when using a remote model.",
      }
    )
  elseif kind == "agent_review" then
    return guide(
      overview .. " Review produces findings tied to real lines instead of replacing the function.",
      {
        "Select the code to review or place the cursor inside it.",
        "Press " .. key .. " and add a focus area if needed.",
        "Read each finding with its severity and line context.",
        "Fix the issues you agree with, then rerun the review to confirm.",
      },
      "Findings appear as diagnostics or a report anchored to the reviewed code.",
      {
        "A clean review is not proof that the code is correct.",
        "Findings can be saved and cleared individually when resolved.",
      }
    )
  elseif kind == "agent_explain" then
    return guide(
      overview
        .. " Explanation uses the target plus related types and signatures to avoid guessing from one isolated function.",
      {
        "Place the cursor on the code you do not understand.",
        "Press " .. key .. " and optionally ask for a specific angle.",
        "Read the explanation while keeping the source visible.",
        "Use the cited types or related functions to continue exploring.",
      },
      "A readable explanation appears in the answer window without modifying the buffer.",
      {
        "Explanations can be wrong about runtime behavior; verify with tests or documentation.",
        "Large targets may be shortened to fit the context budget.",
      }
    )
  elseif kind == "agent_ask" then
    return guide(
      overview .. " The selected code is included automatically, so ask about that target rather than pasting it again.",
      {
        "Select the relevant code or put the cursor inside it.",
        "Press " .. key .. " to open the instruction field.",
        "Write a precise question and press Enter.",
        "Read the answer and ask a follow-up only if something remains unclear.",
      },
      "The answer appears beside your code and stays available while you continue working.",
      {
        "Avoid including secrets in code sent to a remote model.",
        "The answer is contextual advice, not an automatic edit.",
      }
    )
  elseif kind == "agent_fix" then
    return guide(
      overview
        .. " Inline fix is narrow; block fix gives the model the whole function when the cause spans several lines.",
      {
        "Put the cursor on the diagnostic for an inline fix, or inside the function for a block fix.",
        "Press " .. key .. " and wait for the proposal.",
        "Compare the diff with the original code and the diagnostic message.",
        "Accept, reject or refine; run tests after an accepted fix.",
      },
      "An inline diff proposes the smallest change that addresses the selected problem.",
      {
        "A proposal can introduce regressions outside the original diagnostic.",
        "Verify that the original error is gone and no new diagnostics appeared.",
      }
    )
  elseif kind == "agent_refactor" then
    return guide(
      overview .. " Refactor intentionally rewrites the whole selected function, so review structure as well as syntax.",
      {
        "Select the function or block to refactor.",
        "Press " .. key .. " and state the desired structural change.",
        "Inspect the complete proposed diff and naming changes.",
        "Accept only when behavior is preserved, then run tests.",
      },
      "A whole-function proposal appears as an inline diff.",
      {
        "Refactors can change public APIs; check callers before accepting.",
        "Keep behavior-preserving tests around the target.",
      }
    )
  elseif kind == "agent_docs" then
    return guide(
      overview .. " The action asks for documentation only, not a retyped implementation.",
      {
        "Select the function, type or method to document.",
        "Press " .. key .. " and add any special contract details.",
        "Review the generated comment for accuracy and project style.",
        "Edit or accept the comment, then save the file.",
      },
      "An idiomatic documentation comment is proposed at the target without changing its code.",
      {
        "Generated parameter descriptions may need correction.",
        "Do not document behavior that the implementation does not actually guarantee.",
      }
    )
  elseif kind == "agent" then
    return guide(
      overview .. " The target and relevant project context are sent together.",
      {
        "Select the code or place the cursor on the target.",
        "Press " .. key .. " and provide the optional instruction.",
        "Wait for the answer or proposal.",
        "Review the result before applying any change.",
      },
      "The inline agent returns an answer, findings or a reviewable proposal according to the action.",
      { "Remote models receive the prompt and selected code.", "Use local backends for sensitive source." }
    )
  elseif kind == "git_commit" then
    return guide(
      overview .. " The panel separates staged and unstaged work so the commit contains only what you reviewed.",
      {
        "Inspect git status and stage the intended files.",
        "Press " .. key .. " to open the commit panel.",
        "Write a Conventional Commit subject and inspect the staged diff.",
        "Commit, then verify the resulting hash and file list.",
      },
      "A validated commit is created from the staged changes; the working tree remains open for further work.",
      {
        "Unstaged files are not included.",
        "Hooks can reject a commit; fix the reported problem instead of bypassing checks blindly.",
        "AI drafts are optional and should still be reviewed.",
      }
    )
  elseif kind == "git_push" then
    return guide(
      overview .. " Push runs in the integrated terminal because credentials, SSH prompts and hooks may need a TTY.",
      {
        "Commit or stage the work you intend to publish.",
        "Confirm the current branch and remote.",
        "Press " .. key .. " and watch the terminal output.",
        "Return with Esc after the push finishes; the process keeps running if needed.",
      },
      "The current branch is pushed and its upstream is configured on the first push.",
      {
        "A rejected non-fast-forward push requires pulling or rebasing first.",
        "Never force-push merely to silence a rejection.",
      }
    )
  elseif kind == "git_pull" then
    return guide(
      overview .. " Fast-forward-only protects you from an unexpected merge commit.",
      {
        "Save or commit local changes.",
        "Press " .. key .. " from the branch you want to update.",
        "Read the terminal result.",
        "If Git refuses because histories diverged, reconcile deliberately instead of forcing.",
      },
      "The branch updates when it can advance cleanly; otherwise Leader reports the conflict without merging.",
      { "Uncommitted changes can block a pull.", "A divergent branch needs an explicit rebase or merge decision." }
    )
  elseif kind == "git_fetch" or kind == "git" then
    return guide(
      overview .. " Fetch updates remote-tracking refs without changing your working files.",
      {
        "Confirm you are inside the intended repository.",
        "Press " .. key .. " and wait for the terminal command.",
        "Inspect fetched or pruned refs.",
        "Pull or rebase only when you decide to integrate them.",
      },
      "Remote branches and tags are refreshed; deleted remote branches may be pruned.",
      { "Fetch does not modify your current branch.", "Network credentials may be requested in the terminal." }
    )
  elseif kind == "session" then
    return guide(
      overview .. " Sessions remember windows and buffers per project and branch.",
      {
        "Save any work you do not want to lose.",
        "Open the session picker or save action with " .. key .. ".",
        "Choose the intended project or confirm the current session.",
        "Wait for the windows and buffers to restore, then continue working.",
      },
      "The selected project's editor layout is restored, or the current layout is written for the next launch.",
      {
        "Auxiliary windows are closed before saving; your files remain.",
        "A session does not replace version control; commit important changes separately.",
      }
    )
  elseif kind == "terminal" then
    return guide(
      overview .. " The integrated terminal keeps its shell and scrollback between focuses.",
      {
        "Press " .. key .. " to show, hide, list or create the requested terminal.",
        "Type the command in Terminal mode and press Enter.",
        "Use Esc to return to the code without killing a running process.",
        "Reopen the same terminal to inspect output or continue the shell.",
      },
      "The requested terminal is focused or created while existing shells and output remain intact.",
      {
        "Esc closes or hides the window; it does not terminate the child process.",
        "Use Ctrl+C or the Terminal stop action when a command must be interrupted.",
      }
    )
  elseif kind == "diagnostics_popup" then
    return guide(
      overview .. " The popup shows the full message when the inline block is too small.",
      {
        "Move the cursor to the line with the diagnostic.",
        "Press " .. key .. " to open the message.",
        "Press the key again to enter the popup and select/copy text.",
        "Press Esc to return to the code.",
      },
      "The complete diagnostic message appears in a floating window.",
      {
        "A line can have several diagnostics; inspect the source and code, not only the first line.",
        "The popup is read-only unless you explicitly enter it.",
      }
    )
  elseif kind == "diagnostics_blocks" then
    return guide(
      overview .. " Blocks show messages beneath their source lines and can be expanded one at a time.",
      {
        "Open a buffer with diagnostics from the language server or linter.",
        "Press " .. key .. " to toggle the inline block view.",
        "Expand or collapse blocks as needed.",
        "Return to normal editing when the view becomes distracting.",
      },
      "Diagnostic blocks appear under their lines, or disappear when toggled off.",
      {
        "The global preference is separate from the current buffer's temporary view.",
        "Blocks are hidden while you type in Insert mode.",
      }
    )
  elseif kind == "diagnostics_step" then
    return guide(
      overview .. " Navigation can enable the block view automatically so the next problem is visible.",
      {
        "Open a buffer with one or more diagnostics.",
        "Press " .. key .. " to move forward or backward.",
        "Read the centered message and source line.",
        "Fix the issue or continue to the next diagnostic.",
      },
      "The cursor lands on the next or previous diagnostic in the buffer.",
      {
        "The direction depends on whether the action says next or previous.",
        "If nothing happens, the buffer may have no diagnostics in that direction.",
      }
    )
  elseif kind == "diagnostics_list" or kind == "diagnostics" then
    return guide(
      overview .. " The list is the fastest way to triage problems across many files.",
      {
        "Open the diagnostics list with " .. key .. ".",
        "Filter by file, severity or source if needed.",
        "Select an entry and press Enter to jump to its source line.",
        "Fix the issue and refresh the list to confirm it disappeared.",
      },
      "A structured diagnostics list opens with file, line, severity and message.",
      {
        "Some linters run asynchronously; wait for the first results before assuming the list is complete.",
        "A server still loading may not have published diagnostics yet.",
      }
    )
  elseif kind == "dependencies" then
    return guide(
      overview .. " Dependency commands can change manifests or lockfiles, so review the resulting diff.",
      {
        "Open the project root or a file inside the project.",
        "Save pending edits and inspect the current dependency state.",
        "Press " .. key .. " and provide a package name if prompted.",
        "Review go.mod, package manifests and lockfiles before committing.",
      },
      "Dependencies are synchronized, added, removed, upgraded or reported according to the selected command.",
      {
        "Lockfile changes should be committed with the manifest.",
        "An upgrade can introduce breaking changes; run tests afterward.",
      }
    )
  elseif kind == "tags" then
    return guide(
      overview .. " The tag is derived from the field name and type, then inserted into the struct.",
      {
        "Put the cursor on the struct field that needs a tag.",
        "Press " .. key .. " to generate or remove the tag.",
        "Review the exact spelling and options in the source.",
        "Save and run serialization tests when the tag affects an API.",
      },
      'The struct field receives the requested tag, such as json:"sent_at" or json:"sent_at,omitempty".',
      {
        "omitempty changes encoded output for zero values.",
        "Existing custom tags may be replaced; inspect them first.",
      }
    )
  elseif
    kind == "test_cursor"
    or kind == "test_file"
    or kind == "test_all"
    or kind == "test_again"
    or kind == "test"
  then
    local scope = kind == "test_cursor" and "the test under the cursor"
      or kind == "test_file" and "the current test file"
      or kind == "test_all" and "the whole project"
      or kind == "test_again" and "the previous test selection"
      or "the selected test scope"
    return guide(
      overview .. " This action runs " .. scope .. " and keeps feedback close to the code.",
      {
        "Open the test or source file and place the cursor in the intended scope.",
        "Save pending edits so the runner sees the current code.",
        "Press " .. key .. " and wait for the test process.",
        "Inspect failures in the test runner or quickfix, fix them, and rerun.",
      },
      "The selected tests run and their status is shown on the test lines; failures include the useful stack or assertion output.",
      {
        kind == "test_again"
            and "The previous scope is reused; choose another test first if you want a different target."
          or "A broad scope can take longer; use the cursor/file variant while iterating.",
        "Race and coverage modes cost more time but catch different classes of problem.",
        "A passing build does not imply passing tests.",
      }
    )
  elseif kind == "debug_breakpoint" then
    return guide(
      overview .. " Breakpoints are attached to the current line and used by the next debug session.",
      {
        "Open the source file and place the cursor on an executable line.",
        "Press " .. key .. " to add, remove or condition the breakpoint.",
        "Start the matching debug configuration.",
        "When execution stops, inspect variables and step through the code.",
      },
      "The breakpoint is created or updated and will pause the debugger when reached.",
      {
        "A conditional breakpoint needs a valid expression for the language.",
        "Optimized or generated code may not map cleanly to source lines.",
      }
    )
  elseif kind == "debug" then
    return guide(
      overview .. " A debug session needs the correct launch target and adapter for the project.",
      {
        "Open the program or test you want to debug.",
        "Set breakpoints where the investigation should pause.",
        "Press " .. key .. " to launch the matching debug configuration.",
        "Use continue, step over, step into and variable inspection; stop when finished.",
      },
      "The debugger starts and pauses at breakpoints or the configured entry point.",
      {
        "The first build can take time before the debugger attaches.",
        "Profile and release modes may hide variables or optimize lines.",
      }
    )
  elseif kind == "repl" then
    return guide(
      overview .. " The REPL keeps interpreter state between sends, which is useful for exploration and data work.",
      {
        "Open the source file and start or focus the language REPL.",
        "Select a line, expression or cell to evaluate.",
        "Press " .. key .. " to send it.",
        "Inspect the returned value or error, then send the next expression.",
      },
      "The selection is evaluated in the persistent interpreter and its output appears in the REPL workspace.",
      {
        "State from earlier cells can affect later results.",
        "Restart the session when the environment becomes stale.",
      }
    )
  elseif kind == "build" then
    return guide(
      overview .. " Building validates compilation and produces the project's configured artifacts.",
      {
        "Open the project and save pending source changes.",
        "Press " .. key .. " from a file inside the project.",
        "Wait for the compiler and read the first real error if it fails.",
        "Fix the error and rebuild before running or packaging.",
      },
      "The project builds successfully or reports actionable compiler errors.",
      { "A successful build does not run tests.", "Generated code may need its normal generation step first." }
    )
  elseif kind == "run" then
    return guide(
      overview
        .. " Leader resolves the project root and uses the integrated terminal so long-running output stays available.",
      {
        "Open the entry point, script or package you want to run.",
        "Save pending edits and check required environment variables.",
        "Press " .. key .. " and watch the terminal output.",
        "Return to the code with Esc; stop the process explicitly when needed.",
      },
      "The program or command starts from the project root and its output remains in the terminal.",
      {
        "Esc does not kill the process.",
        "Interactive commands may need terminal focus and input.",
        "Secrets from .env files should not be printed or committed.",
      }
    )
  elseif kind == "format" then
    return guide(
      overview
        .. " Formatting changes presentation, not behavior; review the diff if the formatter also applies lint fixes.",
      {
        "Open the file and finish the edit you want to format.",
        "Place the cursor in the file or select a range in Visual mode.",
        "Press " .. key .. " and wait for conform.",
        "Inspect the result and save the file.",
      },
      "The buffer is formatted with the language's configured formatter.",
      {
        "Format-on-save may run the same formatter again.",
        "A missing formatter binary should be installed through Mason or the project toolchain.",
      }
    )
  elseif kind == "check" then
    return guide(
      overview .. " Checks are only useful when you read and resolve the reported problems.",
      {
        "Save the file so external tools analyze the current content.",
        "Press " .. key .. " to run the checker or fixer.",
        "Inspect diagnostics, quickfix entries or terminal output.",
        "Apply deliberate fixes and rerun until the relevant checks pass.",
      },
      "The checker reports issues, or the selected fixer applies safe automated corrections.",
      {
        "Auto-fix can change more lines than expected; inspect the diff.",
        "Some warnings require a human decision rather than an automatic rewrite.",
      }
    )
  elseif kind == "setup" then
    return guide(
      overview .. " Setup actions create project files from presets and avoid silent overwrites.",
      {
        "Open the project root and inspect existing configuration.",
        "Press " .. key .. " and review the preset preview.",
        "Confirm the target path and adapt the generated file to the project.",
        "Run the project's normal validation after creation.",
      },
      "The requested configuration file is created or opened, ready for project-specific edits.",
      {
        "An existing file is opened rather than overwritten.",
        "Generated defaults may not match production requirements.",
      }
    )
  elseif kind == "picker" then
    return guide(
      overview .. " The picker is keyboard-first but also supports typing, arrows and mouse selection.",
      {
        "Press " .. key .. " to open the picker.",
        "Type a query to narrow the candidates.",
        "Move to the intended item and read its preview or description.",
        "Press Enter to choose, or Esc to cancel without changing anything.",
      },
      "The selected item is opened or the requested action receives the chosen value.",
      {
        "An empty query may show a large list; type a more specific term.",
        "Canceling leaves the current buffer and project state unchanged.",
      }
    )
  elseif kind == "save" then
    return guide(
      overview
        .. " Saving writes the current buffer; session and project state may use a broader meaning in some menus.",
      {
        "Finish the edit and resolve merge markers or obvious syntax errors.",
        "Press " .. key .. " to write the buffer or state.",
        "Wait for format-on-save or write hooks to finish.",
        "Confirm the file was written and review any hook error.",
      },
      "The current buffer or project state is persisted to disk.",
      {
        "A failed write leaves the buffer modified; read the error before retrying.",
        "Formatting hooks can change the file immediately after the write.",
      }
    )
  elseif kind == "close" then
    return guide(
      overview .. " Closing protects unsaved work and may quit the editor only when no usable file window remains.",
      {
        "Save changes you want to keep.",
        "Press " .. key .. " on the window, buffer or session you intend to close.",
        "Read any confirmation about unsaved files.",
        "Confirm only when the remaining layout is correct.",
      },
      "The requested window, buffer or editor session closes.",
      {
        "Closing a terminal window does not necessarily terminate its process.",
        "The last file may turn close into a quit-all confirmation.",
      }
    )
  elseif kind == "rename" then
    return guide(
      overview .. " Rename can affect the filesystem, open buffers and language-server references.",
      {
        "Place the cursor on the file or symbol to rename.",
        "Press " .. key .. " and enter the new name.",
        "Review affected files or references before confirming.",
        "Save and run a search to verify no stale name remains.",
      },
      "The target is renamed and supported references or buffers are updated.",
      {
        "Project-wide symbol rename requires a working language server.",
        "Case-only renames can be tricky on case-insensitive filesystems.",
      }
    )
  elseif kind == "clipboard" then
    return guide(
      overview .. " Clipboard actions preserve the source until you deliberately paste or replace it.",
      {
        "Select the text, file or tree entry.",
        "Press " .. key .. " to copy or cut it.",
        "Move to the destination.",
        "Paste and inspect the result before saving.",
      },
      "The selected content is placed on the relevant clipboard or marked for a later paste.",
      {
        "Leader's delete-without-copy shortcut intentionally bypasses the clipboard.",
        "File clipboard operations may ask before overwriting.",
      }
    )
  elseif kind == "delete" then
    return guide(
      overview .. " Destructive actions should target a deliberate selection, not an accidental cursor row.",
      {
        "Select the exact text, file or entry to remove.",
        "Press " .. key .. " and read the confirmation.",
        "Confirm only after checking the path or affected lines.",
        "Use trash/restore when the operation supports recovery.",
      },
      "The selected target is removed, or moved to the trash when the action uses it.",
      { "Permanent delete cannot be undone by the editor.", "Open unsaved buffers may need to be handled separately." }
    )
  elseif kind == "toggle" then
    return guide(
      overview .. " Toggles are reversible; the affected UI should show the new state immediately.",
      {
        "Look at the feature's current state in the statusline, panel or buffer.",
        "Press " .. key .. " to switch it.",
        "Observe the visual or behavioral change.",
        "Press the same key again when you want the previous state.",
      },
      "The feature switches between enabled and disabled without changing project files.",
      {
        "Some preferences are saved globally; others affect only the current buffer or session.",
        "A restart may be required when the setting is read only at startup.",
      }
    )
  elseif kind == "view" then
    return guide(
      overview
        .. " Views are temporary workspaces over your files; closing them should not discard the underlying buffer.",
      {
        "Press " .. key .. " to open the requested view.",
        "Navigate or filter its contents.",
        "Perform the intended action or inspect the information.",
        "Close the view with Esc, q or its own close command.",
      },
      "The requested panel, picker, outline or information window opens.",
      {
        "Unsaved file buffers remain open behind auxiliary views.",
        "Some views have their own Escape behavior; read the local hint.",
      }
    )
  elseif kind == "docs" then
    return guide(
      overview .. " Documentation should describe contracts and intent, not repeat the implementation line by line.",
      {
        "Place the cursor on the function, type or comment to document.",
        "Press " .. key .. " to insert, generate or list documentation work.",
        "Review names, parameters, return values and edge cases.",
        "Save the file after the comment is accurate.",
      },
      "The documentation comment is inserted or the missing documentation is listed for review.",
      { "Generated text can hallucinate parameters or guarantees.", "Keep comments in sync when behavior changes." }
    )
  elseif kind == "navigation" then
    return guide(
      overview .. " Navigation changes the cursor location, not the file.",
      {
        "Open the source file and position the cursor on the relevant symbol.",
        "Press " .. key .. " and wait for the destination.",
        "Inspect the target code.",
        "Use Esc, Ctrl+o or the jump list to return.",
      },
      "The cursor moves to the related code or documentation.",
      {
        "Cross-file jumps may trigger language-server loading.",
        "The previous location is preserved in the jump list.",
      }
    )
  elseif kind == "history" then
    return guide(
      overview .. " History views help you recover editor state; they are not a replacement for commits.",
      {
        "Open the history view with " .. key .. ".",
        "Find the entry, undo step or previous save you need.",
        "Preview or select it carefully.",
        "Return to the current buffer and verify the restored state.",
      },
      "The requested history entry or editor state is shown or restored.",
      {
        "Restoring an old save can discard newer edits; save first.",
        "Persistent undo survives restarts but is still local to this machine.",
      }
    )
  elseif kind == "fold" then
    return guide(
      overview .. " Folds change how much code is visible, not the buffer content.",
      {
        "Place the cursor in the function, type or region you want to fold.",
        "Press " .. key .. " to apply the requested fold scope.",
        "Use zO or the fold menu to unfold when inspecting details.",
        "Return to normal navigation with all needed code visible.",
      },
      "The requested code region is folded, unfolded or focused in the current buffer.",
      {
        "Folds rely on treesitter or Neovim's fold expressions.",
        "A folded region can hide unsaved or diagnostic lines; expand it before broad edits.",
      }
    )
  elseif kind == "sql" then
    return guide(
      overview
        .. " SQL actions use the connection selected for the current project and show results in Leader's SQL buffers.",
      {
        "Check the active database connection and dialect.",
        "Write or select the SQL statement you intend to run.",
        "Press " .. key .. " and wait for the database response.",
        "Inspect rows, errors, schema or history in the SQL result view.",
      },
      "The statement or SQL tool runs against the configured connection and its output appears in the SQL workspace.",
      {
        "Read the connection URL before running destructive statements.",
        "Transactions and production databases require deliberate review.",
        "A query can succeed while returning no rows.",
      }
    )
  elseif kind == "command" then
    return guide(
      overview .. " Semicolon is simply a more reachable entry to Ex command mode.",
      {
        "Press ; instead of :.",
        "Type the Ex command without a leading colon.",
        "Press Enter to execute it.",
        "Use Esc or q to leave the command line if you cancel.",
      },
      "Neovim enters Command mode and runs the typed Ex command.",
      {
        "This does not change what the command does; it only changes the trigger key.",
        "Command history and completion remain available.",
      }
    )
  end

  return guide(
    overview .. " This mapping belongs to " .. (entry.group or "the editor") .. " and is available in " .. where .. ".",
    {
      "Open " .. where .. " and prepare the file, selection or project state the action needs.",
      "Review the current target so the action cannot affect the wrong buffer or file.",
      "Press " .. key .. " in " .. MODE_LABEL[entry.modes and entry.modes[1] or "n"] .. " mode.",
      "Inspect the resulting edit, view, terminal output or diagnostics before continuing.",
    },
    "The requested «"
      .. (entry.action or "action")
      .. "» operation completes and its result is shown in the relevant Leader UI.",
    {
      "If nothing happens, verify that this mapping applies to the current filetype and mode.",
      "Save or commit only after reviewing the resulting change.",
    }
  )
end

---@param entry table
---@param base { example: string, usage: string }
---@return table
local function finish(entry, base)
  local detail = workflow(classify(entry), entry, base.usage or "")
  local notes = vim.deepcopy(detail.notes or {})
  local mode = entry.modes and entry.modes[1] or "n"
  if mode == "x" then
    table.insert(notes, 1, "Visual mode: make the selection first; without one, the command may use a default target.")
  elseif mode == "o" then
    table.insert(notes, 1, "Operator-pending mode: the command waits for a motion or text object; Esc cancels it.")
  elseif mode == "i" then
    table.insert(notes, 1, "Insert mode: this mapping is active only while you are typing.")
  elseif mode == "t" then
    table.insert(
      notes,
      1,
      "Terminal mode: use the terminal's own key handling; return to Normal mode when editing commands."
    )
  end
  if entry.source == "menu" and entry.language ~= "Global" then
    table.insert(notes, "This shortcut is registered only for " .. (entry.where or entry.language) .. " buffers.")
  end
  local usage =
    sentence((detail.usage or "") .. " The numbered steps below cover preparation, execution and verification.")
  return {
    example = sentence(base.example),
    usage = usage,
    steps = detail.steps,
    result = sentence(detail.result),
    notes = notes,
    note = #notes > 0 and table.concat(notes, " ") or nil,
  }
end

--- Every mapping gets a concrete example, detailed steps, an expected result and practical notes.
---@param entry table
---@return { example: string, usage: string, steps: string[], result: string, notes: string[], note?: string }
function M.describe(entry)
  local recipe = RECIPES[(entry.group or "") .. "|" .. entry.key] or RECIPES[entry.key]
  if recipe then
    return finish(entry, { example = recipe.example, usage = recipe.usage })
  end
  return finish(entry, {
    example = situation(entry),
    usage = "Use " .. entry.key .. " to " .. (entry.action or "perform this action") .. ".",
  })
end

return M
