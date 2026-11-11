#!/bin/sh
# Chat (<leader>aC) smoke tests: loads, menus, session/store/prompt/mention/render.
# Sources hermetic.sh so tests never touch the real state.
set -e
cd "$(dirname "$0")/.."
. scripts/hermetic.sh

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/leader-test-xdg-chat}"
mkdir -p "$XDG_CONFIG_HOME"
ln -sfn "$PWD/nvim" "$XDG_CONFIG_HOME/nvim"

fails=0
check() { # check <name> <got> <want>
  if [ "$2" != "$3" ]; then
    echo "FAIL $1: got $2 want $3"
    fails=$((fails+1))
  else
    echo "ok   $1"
  fi
}

nvim --headless -c "lua
local chat = require('agent.chat')
local window = require('agent.chat.window')
local session = require('agent.chat.session')
local store = require('agent.chat.store')
local mention = require('agent.chat.mention')
local render = require('agent.chat.render')
local prompt = require('agent.chat.prompt')

-- session new + add + totals
local s = session.new({ root = vim.uv.cwd() })
session.add(s, { role = 'user', text = 'hola' })
session.add(s, { role = 'assistant', text = 'hey' })
session.charge(s, { tokens_in = 100, tokens_out = 50, cost = 0.001 })
vim.api.nvim_input('')

-- store put/get roundtrip
s.profile = 'ask'
store.put(s)
local back = store.get(s.id)
assert(back ~= nil, 'store get returns the session')
assert(back.title ~= '', 'title non-empty')
assert(back.profile == 'ask', 'store keeps the profile')
-- history is scoped to the project: no session from elsewhere is borrowed
local other = session.new({ root = '/tmp/other-chat-project', backend = 'x' })
store.put(other)
assert(#store.list_for_root('/tmp/other-chat-project') == 1, 'list_for_root finds its session')
assert(#store.list_for_root(vim.uv.cwd()) >= 1, 'list_for_root keeps projects apart')
assert(store.last_for_root('/tmp/does-not-exist') == nil, 'last_for_root never falls back to another project')
assert(store.last_for_root('/tmp/other-chat-project').id == other.id, 'last_for_root matches its project')
store.remove(other.id)
assert(store.last_for_root('/tmp/other-chat-project') == nil, 'removing forgets the project pointer')

-- mention parse: no @ -> no sections, slash detection
local clean, secs, slash = mention.parse('hola mundo')
assert(slash == nil, 'no slash on plain text')
assert(#secs == 0, 'no sections on plain text')
local c2, _, sl = mention.parse('/new')
assert(sl == 'new', 'slash /new detected')

-- prompt build: stable head + history + sections
local system, p, injected = prompt.build(s, 'hi', { { name = 'rules', text = 'obey' } })
assert(system:find('Leader Chat'), 'system mentions Leader Chat')
assert(p:find('rules'), 'prompt carries sections')
assert(injected[1] == 'rules', 'injected names')

-- render: header + user + assistant lines, no errors
local lines = render.lines(s, {})
assert(#lines > 5, 'render produced lines')
local joined = table.concat(lines, '\n')
assert(joined:find('Leader Chat'), 'header shows Chat')
assert(joined:find('hola'), 'user message visible')
assert(joined:find('hey'), 'assistant message visible')

-- window open/hide + statusline when idle is empty
window.session = s
window.toggle()
assert(window.is_open(), 'panel open')
assert(package.loaded['render-markdown'] ~= nil, 'render-markdown loads on demand for the transcript')
-- the parser is registered for the chat filetype, so the renderer really draws
local md_session = session.new({ root = vim.uv.cwd(), backend = 'claude', model = 'haiku', profile = 'ask' })
session.add(md_session, { role = 'assistant', text = '## Title\n\n**bold** and a [link](https://example.com)\n\n- one\n- two' })
window.session = md_session
window.draw()
vim.wait(300)
local md_ns = vim.api.nvim_create_namespace('render-markdown.nvim')
assert(#vim.api.nvim_buf_get_extmarks(window.transcript_buf, md_ns, 0, -1, {}) > 0, 'markdown is rendered')
window.session = s
window.draw()
-- activity animation: a waiting strip before the first token, a pulsing caret while text streams
window.set_running(true)
window.pending_text, window.pending_think = '', ''
window.activity()
local activity_ns = vim.api.nvim_create_namespace('chat.activity')
local function activity_text()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(window.transcript_buf, activity_ns, 0, -1, { details = true })) do
    for _, c in ipairs((m[4] and m[4].virt_text) or {}) do
      out[#out + 1] = c[1]
    end
  end
  return table.concat(out, '')
end
assert(activity_text():find('Working', 1, true) ~= nil, 'waiting activity strip')
window.pending_text = 'hola'
window.activity()
assert(activity_text():find('▌', 1, true) ~= nil, 'typing caret')
window.pending_text, window.pending_think = '', ''
window.set_running(false)
assert(activity_text() == '', 'activity cleared when the turn ends')
window.hide()
assert(not window.is_open(), 'panel hidden keeps session')
assert(window.statusline() == '', 'statusline idle is empty')

-- the input is free text: no completion popup may sit over it and eat <CR>
window.toggle()
assert(vim.b[window.input_buf].completion == false, 'blink is off in the chat input')
assert(vim.bo[window.input_buf].omnifunc == '' and vim.bo[window.input_buf].completefunc == '', 'native completion off')
window.hide()
-- premium: the mini view is a REAL right split (dock), the editor shrinks
window.toggle()
assert(window.is_open(), 'panel reopens')
assert(window.docked, 'mini is docked in real splits')
local tcfg = vim.api.nvim_win_get_config(window.transcript_win)
assert(tcfg.relative == '', 'transcript is a split, not a float')
assert(vim.api.nvim_win_get_config(window.input_win).relative == '', 'input is a split too')
local mini_w = vim.api.nvim_win_get_width(window.transcript_win)
assert(math.abs(mini_w - math.floor(vim.o.columns * 0.5)) <= 2, 'mini takes half the columns: ' .. mini_w)
assert(vim.api.nvim_win_get_width(window.input_win) == mini_w, 'input shares the column')
local editor_w, editor_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local b = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[b].filetype
  if vim.api.nvim_win_get_config(win).relative == '' and ft ~= 'leaderchat' and ft ~= 'leaderchat_input' then
    editor_w, editor_win = vim.api.nvim_win_get_width(win), win
  end
end
assert(editor_win ~= nil and editor_w + mini_w + 1 == vim.o.columns, 'the editor shrinks beside the panel')
assert(vim.api.nvim_win_get_height(window.input_win) == window.input_lines, 'input keeps its height')
-- fullscreen: floats, full width, still right-anchored blocks
window.toggle_view()
assert(window.is_open(), 'full stays open')
assert(window.current_view() == 'full', 'full view set')
assert(not window.docked, 'full is not docked')
local full_cfg = vim.api.nvim_win_get_config(window.transcript_win)
assert(full_cfg.width > mini_w, 'full is wider than mini')
assert(full_cfg.col == 0 and full_cfg.row == 0, 'full starts at the screen edge')
assert(full_cfg.width == vim.o.columns, 'full spans every column')
local full_input = vim.api.nvim_win_get_config(window.input_win)
assert(full_input.col == 0 and full_input.width == vim.o.columns, 'input spans every column')
assert(full_input.row == full_cfg.height, 'input is glued below the transcript')
assert(full_input.row + full_input.height <= vim.o.lines - 1, 'the single statusline row stays free')
window.toggle_view()
assert(window.current_view() == 'mini', 'mini restored')
assert(window.docked, 'mini comes back as a real split')
local mini_cfg = vim.api.nvim_win_get_config(window.transcript_win)
assert(mini_cfg.relative == '' and vim.api.nvim_win_get_width(window.transcript_win) <= mini_w + 4, 'mini width restored')
window.toggle_collapse()
assert(window.is_open(), 'rail stays open')
assert(window.collapsed, 'collapsed flag set')
assert(not window.docked, 'the rail is a float')
local rail_cfg = vim.api.nvim_win_get_config(window.transcript_win)
assert(rail_cfg.width <= 12, 'rail is narrow')
assert(rail_cfg.col + rail_cfg.width == vim.o.columns, 'rail flush right')
assert(window.input_win == nil, 'rail hides the input')
window.toggle_collapse()
assert(not window.collapsed, 'expand restores the input')
assert(window.input_win ~= nil, 'input back')
assert(window.docked, 'expanding comes back to the real split')
local chat_wins = 0
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
  if ft == 'leaderchat' or ft == 'leaderchat_input' then
    chat_wins = chat_wins + 1
  end
end
assert(chat_wins == 2, 'expanding closes the rail (no leftover window)')
-- setting dock = false keeps the old floating partition
window.hide()
require('core.settings').agent.chat.dock = false
window.toggle()
assert(window.is_open() and not window.docked, 'dock = false opens the float')
assert(vim.api.nvim_win_get_config(window.transcript_win).relative ~= '', 'the float is right-anchored')
window.hide()
require('core.settings').agent.chat.dock = true
-- history home inside the panel (the same buffer, no floating picker)
window.show_home(vim.uv.cwd())
window.draw()
local home_text = table.concat(vim.api.nvim_buf_get_lines(window.transcript_buf, 0, -1, false), '\n')
assert(home_text:find('Recent chats', 1, true), 'home shows the history')
assert(home_text:find('hola', 1, true), 'home lists this project\'s chats')
assert(window.home ~= nil and window.home.sel >= 2, 'the current chat is selected')
window.session = nil
window.home.sel = 2
window.home_open()
assert(window.session and window.session.id == s.id, 'home opens the selected session')
window.home = nil
window.session = s
window.draw()
window.hide()
-- the first open in a repo with chats lands on that repo's history
window.session, window.home = nil, nil
chat.open()
assert(window.home ~= nil, 'first open with history shows the home')
assert(window.home.root == vim.uv.cwd(), 'home belongs to this repository')
assert(window.home.sel and window.home.sel >= 2, 'the last chat is selected')
window.hide()
window.session, window.home = s, nil

-- Esc leaves insert / does nothing in the panel: it NEVER hides it (Ctrl-Q or
-- <leader>aC do). A real split stays, like the terminal opened with Alt-V.
window.toggle()
assert(window.is_open(), 'panel open for esc test')
vim.api.nvim_set_current_win(window.input_win)
vim.cmd 'startinsert'
vim.wait(100)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'mx', false)
vim.wait(200)
assert(window.is_open(), 'esc in insert leaves the panel open')
assert(vim.fn.mode() ~= 'i', 'esc leaves insert mode')
-- and from the transcript in normal mode
vim.api.nvim_set_current_win(window.transcript_win)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'mx', false)
vim.wait(200)
assert(window.is_open(), 'esc in transcript leaves the panel open')
vim.api.nvim_feedkeys('q', 'mx', false)
vim.wait(200)
assert(window.is_open(), 'q does not hide the panel either')
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-q>', true, false, true), 'mx', false)
vim.wait(200)
assert(not window.is_open(), 'Ctrl-Q hides the panel')
-- closing one of the panel's windows hides the whole panel, never a half one
window.toggle()
vim.api.nvim_set_current_win(window.transcript_win)
vim.cmd 'q'
vim.wait(200)
assert(not window.is_open(), 'closing a panel window hides the panel')
local rail_lines = render.lines(s, { rail = true })
assert(#rail_lines >= 4, 'rail lines produced')
local rail_joined = table.concat(rail_lines, '\n')
assert(rail_joined:find('C'), 'rail shows C')

-- input triggers: "/" commands, "@" files, "#" skills, "$" mcp
local completion = require('agent.chat.completion')
local kind, q = completion.detect('/m', 2)
assert(kind == 'command' and q == 'm', 'detect a slash command')
assert(#completion.candidates('command', 'm') == 2, 'commands filter')
assert(completion.candidates('command', '')[1].value == 'new', 'commands in order')
assert(completion.detect('hola', 4) == nil, 'no trigger on plain text')
local k2, q2, sc2 = completion.detect('hola @nv', 8)
assert(k2 == 'file' and q2 == 'nv' and sc2 == 5, 'detect a file mention after text')
local k3, q3 = completion.detect('lee #cave', 9)
assert(k3 == 'skill' and q3 == 'cave', 'detect a skill mention')
local k4 = completion.detect('usa ' .. string.char(36) .. 'open', 9)
assert(k4 == 'mcp', 'detect an mcp mention')
-- a command runs at once; a mention is inserted in place
window.session = s
window.toggle()
vim.api.nvim_set_current_win(window.input_win)
local chat = require('agent.chat')
local sent
local orig_send = chat.send
chat.send = function(text) sent = text end
vim.api.nvim_buf_set_lines(window.input_buf, 0, -1, false, { '/mo' })
vim.api.nvim_win_set_cursor(window.input_win, { 1, 3 })
completion.sync(window.input_buf, window.input_win)
assert(completion.is_visible(), 'popup shows for /')
assert(completion.accept() == true, 'command accept consumes')
assert(sent == '/model', 'command runs immediately')
assert(not completion.is_visible(), 'popup hides after accept')
chat.send = orig_send
vim.api.nvim_buf_set_lines(window.input_buf, 0, -1, false, { 'mira @nvim/init' })
vim.api.nvim_win_set_cursor(window.input_win, { 1, 14 })
completion.sync(window.input_buf, window.input_win)
assert(completion.is_visible(), 'file popup shows for @')
assert(completion.accept() == true, 'file accept consumes')
local line_after = vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1]
assert(line_after:match '^mira @%S+ $', 'mention inserted with trailing space')
window.hide()

-- menu: <leader>aC is Chat open, <leader>aW is clear file
local maps = require('menus.agent').maps
local found_c, found_w = false, false
for _, m in ipairs(maps) do
  if m[1] == 'C' then found_c = true end
  if m[1] == 'W' then found_w = true end
end
assert(found_c, '<leader>aC present')
assert(found_w, '<leader>aW present')

-- live turn (fake backend, no model/network): send("hola") appends a turn
local backends = require('agent.backends')
backends.register('chatfake', {
  name = 'chatfake', label = 'ChatFake', default_model = 'fake-1',
  available = function() return true end,
  models = function(cb) cb({ { id = 'fake-1' } }) end,
  build = function() return { cmd = { 'echo', 'hello from fake' } } end,
  parser = function()
    local acc = {}
    return {
      feed = function(chunk) acc[#acc + 1] = chunk; return chunk end,
      finish = function(code) return { ok = true, text = table.concat(acc), usage = { tokens_in = 10, tokens_out = 5, cost = 0 } } end,
    }
  end,
})
local fake_session = require('agent.chat.session').new({ root = vim.uv.cwd(), backend = 'chatfake', model = 'fake-1' })
window.session = fake_session
window.toggle()
chat.send('hola')
local waited = vim.wait(3000, function() return not window.running end, 50)
assert(waited, 'fake turn finished')
assert(#fake_session.messages == 2, 'fake turn appended user+assistant')
assert(fake_session.turns == 1, 'fake turn counted')
assert(fake_session.messages[2].role == 'assistant', 'assistant answered')
-- typing while the answer streams queues it; the queue runs when the turn settles
local slow = vim.deepcopy(backends.get('chatfake'))
slow.name, slow.label, slow.default_model = 'chatslow', 'ChatSlow', 'slow-1'
slow.build = function() return { cmd = { 'sh', '-c', 'sleep 0.4; echo slow answer' } } end
backends.register('chatslow', slow)
local qsession = require('agent.chat.session').new({ root = vim.uv.cwd(), backend = 'chatslow', model = 'slow-1' })
window.session = qsession
assert(chat.send('first') == true, 'first message accepted')
assert(chat.send('second') == true, 'second message queued while the first runs')
assert(#window.queue == 1, 'one message queued')
local queued_ok = vim.wait(6000, function() return qsession.turns == 2 and not window.running end, 50)
assert(queued_ok, 'the queued turn ran after the first settled')
assert(#qsession.messages == 4, 'two user+assistant turns')
assert(qsession.messages[3].text == 'second', 'the queued text is the next user turn')
-- a settled answer with an ask block opens the picker (empty composer, focused)
local fence = string.rep(string.char(96), 3)
local ask_cmd = { 'printf', '%s\n', fence .. 'ask', 'Which one?', '- first', '- second', fence }
local askb = vim.deepcopy(backends.get('chatfake'))
askb.name, askb.label, askb.default_model = 'chatask', 'ChatAsk', 'ask-1'
askb.build = function() return { cmd = ask_cmd } end
backends.register('chatask', askb)
local asession = require('agent.chat.session').new({ root = vim.uv.cwd(), backend = 'chatask', model = 'ask-1' })
window.session = asession
if not window.is_open() then window.toggle() end
window.clear_input()
vim.api.nvim_set_current_win(window.input_win)
local askselect = require('agent.ui.select')
local askpick = askselect.pick
local seen
askselect.pick = function(items, _, cb)
  seen = items
  cb(items[1])
end
assert(chat.send('pregunta') == true, 'ask turn accepted')
assert(vim.wait(5000, function() return not window.running end, 50), 'ask turn settled')
vim.wait(300, function() return vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1] == 'first' end, 20)
assert(seen and #seen == 3, 'the picker offered both options plus free text')
assert(vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1] == 'first', 'the auto-opened picker fills the composer')
askselect.pick = askpick
window.clear_input()
-- typing from the history home starts a NEW chat with the draft's profile/model
local draft = session.new({ root = vim.uv.cwd(), backend = 'chatfake', model = 'fake-1', profile = 'minimal' })
window.session = draft
window.show_home(vim.uv.cwd())
assert(window.home ~= nil, 'home is showing')
assert(chat.send('nueva desde home') == true, 'message from home accepted')
local waited_home = vim.wait(3000, function() return not window.running end, 50)
assert(waited_home, 'home turn finished')
assert(window.home == nil and window.session ~= draft, 'a message from home starts a new chat')
assert(window.session.profile == 'minimal', 'new chat inherits the profile')
assert(#window.session.messages == 2, 'new chat has the turn')

-- rendered ranges: one per message, and copy under the cursor copies THAT message
window.session = fake_session
window.draw()
local lines2, _, ranges = render.lines(fake_session, {})
assert(#ranges == 2, 'one range per message')
local ui = require('agent.chat.window')
if not ui.is_open() then ui.toggle() end
ui.draw()
vim.api.nvim_set_current_win(ui.transcript_win)
vim.api.nvim_win_set_cursor(ui.transcript_win, { ui.ranges[1].first, 0 })
assert(ui.copy_message(), 'copy message under cursor')
assert(vim.fn.getreg(string.char(34)) == 'hola', 'copied the exact user text')
-- copy the last answer / your last message without moving the cursor
assert(ui.copy_last('assistant'), 'copy last answer')
assert(vim.fn.getreg(string.char(34)) == render.message_text(fake_session.messages[2]), 'last answer copied exactly')
assert(ui.copy_last('user'), 'copy last prompt')
assert(vim.fn.getreg(string.char(34)) == 'hola', 'last user message copied exactly')
-- Alt-Q: the options of the last ask block land in the composer (not sent)
local select = require('agent.ui.select')
local orig_pick = select.pick
select.pick = function(items, _, cb) cb(items[1]) end
local qs = session.new({ root = vim.uv.cwd(), backend = 'chatfake', model = 'fake-1' })
local bt = string.rep(string.char(96), 3)
session.add(qs, { role = 'assistant', text = bt .. 'ask\nWhich one?\n- first\n- second\n' .. bt })
ui.session = qs
ui.draw()
ui.answer_question()
assert(vim.api.nvim_buf_get_lines(ui.input_buf, 0, 1, false)[1] == 'first', 'the chosen option fills the composer')
select.pick = orig_pick
ui.clear_input()
-- the picker opens by itself only for an empty composer that has the focus
vim.api.nvim_set_current_win(ui.input_win)
assert(ui.can_auto_ask(), 'auto-ask waits for the empty composer')
ui.set_input('typing something')
assert(not ui.can_auto_ask(), 'auto-ask never interrupts typing')
ui.clear_input()
ui.session = fake_session
ui.draw()
-- the composer maps both in insert mode too (the focus stays there after sending)
vim.api.nvim_set_current_win(ui.input_win)
assert(type(vim.fn.maparg('<C-y>', 'i', false, true).callback) == 'function', 'Ctrl-Y mapped in the composer')
assert(type(vim.fn.maparg('<M-y>', 'i', false, true).callback) == 'function', 'Alt-Y mapped in the composer')
vim.api.nvim_set_current_win(ui.transcript_win)
-- while a turn runs, your last message is the prompt that started it (still not in the session)
ui.running, ui.sent_text = true, 'recién enviado'
assert(ui.copy_last('user'), 'copy the prompt of the running turn')
assert(vim.fn.getreg(string.char(34)) == 'recién enviado', 'the in-flight prompt wins while it runs')
ui.running, ui.sent_text = false, nil
-- view more (o): the message opens full size and y copies it
vim.api.nvim_set_current_win(ui.transcript_win)
vim.api.nvim_win_set_cursor(ui.transcript_win, { ui.ranges[2].first, 0 })
vim.api.nvim_feedkeys('o', 'mx', false)
vim.wait(200)
assert(ui.zoom and vim.api.nvim_win_is_valid(ui.zoom.win), 'o opens the message view')
assert(ui.zoom.msg.text == fake_session.messages[2].text, 'view holds the message')
vim.api.nvim_feedkeys('y', 'mx', false)
vim.wait(100)
assert(vim.fn.getreg(string.char(34)) == fake_session.messages[2].text, 'y copies the viewed message')
ui.hide()
assert(ui.zoom == nil, 'hide closes the message view')

-- reopening the panel: TextChangedI must not anchor the popup to a dead window
if not window.is_open() then window.toggle() end
local stale = window.input_win
window.hide()
window.toggle()
vim.api.nvim_set_current_win(window.input_win)
vim.api.nvim_buf_set_lines(window.input_buf, 0, -1, false, { '/' })
vim.api.nvim_win_set_cursor(window.input_win, { 1, 1 })
local ok_sync, err_sync = pcall(completion.sync, window.input_buf, stale)
assert(ok_sync, 'sync survives a stale input window: ' .. tostring(err_sync))
assert(completion.is_visible(), 'popup shows after reopening')
completion.hide()
window.hide()

-- input history (Up/Down) and auto-grow
if not window.is_open() then window.toggle() end
local hist = require('agent.chat.session').new({ root = vim.uv.cwd(), backend = 'chatfake', model = 'fake-1' })
require('agent.chat.session').add(hist, { role = 'user', text = 'primero' })
require('agent.chat.session').add(hist, { role = 'user', text = 'segundo' })
window.session = hist
window.clear_input()
window.history_step(-1)
assert(vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1] == 'segundo', 'Up recalls the last message')
window.history_step(-1)
assert(vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1] == 'primero', 'Up again goes older')
window.history_step(1)
assert(vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1] == 'segundo', 'Down goes newer')
window.history_step(1)
assert(vim.api.nvim_buf_get_lines(window.input_buf, 0, 1, false)[1] == '', 'Down again returns to the draft')
window.clear_input()
vim.api.nvim_buf_set_lines(window.input_buf, 0, -1, false, { 'una', 'dos', 'tres' })
window.auto_height()
assert(window.input_lines == 3, 'input grows with its lines')
assert(vim.api.nvim_win_get_height(window.input_win) == 3, 'window height follows')
window.clear_input()
assert(window.input_lines == 3, 'clearing shrinks it back to the composer minimum')
window.hide()

-- every model of a backend is offered (chat_models when it exists)
backends.register('multimodel', {
  name = 'multimodel', label = 'Multi', default_model = 'a',
  available = function() return true end,
  models = function(cb) cb({ { id = 'a' } }) end,
  chat_models = function(cb) cb({ { id = 'a' }, { id = 'b' }, { id = 'c' } }) end,
})
local listed
chat.models(function(items) listed = items end)
vim.wait(8000, function() return listed ~= nil end, 50)
assert(listed ~= nil, 'models answered')
local multi = vim.tbl_filter(function(it) return it.backend == 'multimodel' end, listed or {})
assert(#multi == 3, 'all chat_models offered (not the one-shot shortlist)')
-- Enter sends immediately: a backend with no model gets one silently (no picker)
backends.register('needmodel', {
  name = 'needmodel', label = 'NeedModel', requires_model = true,
  available = function() return true end,
  models = function(cb) cb({ { id = 'only-one' } }) end,
  build = function() return { cmd = { 'echo', 'model picked answer' } } end,
  parser = function()
    local acc = {}
    return {
      feed = function(c) acc[#acc + 1] = c; return c end,
      finish = function() return { ok = true, text = table.concat(acc), usage = { tokens_in = 1, tokens_out = 1 } } end,
    }
  end,
})
local need = require('agent.chat.session').new({ root = vim.uv.cwd(), backend = 'needmodel' })
window.session = need
if not window.is_open() then window.toggle() end
window.clear_input()
vim.api.nvim_buf_set_lines(window.input_buf, 0, -1, false, { 'hola sin modelo' })
local accepted = chat.send('hola sin modelo')
assert(accepted == true, 'enter sends immediately (no picker step)')
vim.wait(3000, function() return #need.messages >= 2 end, 50)
assert(#need.messages >= 2, 'the message was sent with the auto-picked model')
assert(need.model == 'only-one', 'the picked model is remembered')
assert(vim.api.nvim_buf_get_lines(window.input_buf, 0, -1, false)[1] == '', 'input cleared when sent')
window.clear_input()

-- export copies the whole transcript
chat.export()
local reg = vim.fn.getreg(string.char(34))
assert(reg:find('hola sin modelo', 1, true) and reg:find('model picked answer', 1, true), 'export copies every message')
window.hide()

print('CHAT OK')
" -c "qa" 2>&1 | tee /tmp/chat-test.out
grep -q "CHAT OK" /tmp/chat-test.out || { echo "FAIL chat smoke"; fails=$((fails+1)); }
if [ $fails -gt 0 ]; then echo "FAILURES: $fails"; exit 1; fi
echo "ALL OK"
