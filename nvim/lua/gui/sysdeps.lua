-- ── Desktop app: what the system needs, per Linux family ─────────────────────
-- Pure (no process, no prompt): which tools Leader uses from the system, which of
-- them are missing, the package that brings each one on every package manager
-- (pacman, apt, dnf, zypper, apk, brew) and the one command that installs a list
-- of them. The setup wizard shows that command before anything runs and runs it in
-- a terminal, where sudo asks for the password.
local M = {}

---@class SysTool
---@field id string
---@field label string
---@field bins string[]   any of them on PATH = present (`all = true`: every one)
---@field all boolean?
---@field why string
---@field required boolean? Leader does not work well without it
---@field pkgs table<string, string?> package manager → package names (space separated); nil = not packaged there
---@field pack string?    only for this language pack (a runtime)

---@type SysTool[]
M.TOOLS = {
  {
    id = "git",
    label = "git",
    bins = { "git" },
    why = "plugins, projects, everything in the Git menu",
    required = true,
    pkgs = { pacman = "git", apt = "git", dnf = "git", zypper = "git", apk = "git", brew = "git" },
  },
  {
    id = "rg",
    label = "ripgrep",
    bins = { "rg" },
    why = "find a word in the whole project",
    required = true,
    pkgs = {
      pacman = "ripgrep",
      apt = "ripgrep",
      dnf = "ripgrep",
      zypper = "ripgrep",
      apk = "ripgrep",
      brew = "ripgrep",
    },
  },
  {
    id = "cc",
    label = "C compiler",
    bins = { "cc", "gcc", "clang" },
    why = "builds the syntax parsers",
    required = true,
    pkgs = {
      pacman = "base-devel",
      apt = "build-essential",
      dnf = "gcc gcc-c++ make",
      zypper = "gcc gcc-c++ make",
      apk = "build-base",
    },
  },
  {
    id = "unzip",
    label = "unzip",
    bins = { "unzip" },
    why = "unpacks language servers",
    required = true,
    pkgs = { pacman = "unzip", apt = "unzip", dnf = "unzip", zypper = "unzip", apk = "unzip", brew = "unzip" },
  },
  {
    id = "fd",
    label = "fd",
    bins = { "fd", "fdfind" },
    why = "finds your projects and files fast",
    pkgs = { pacman = "fd", apt = "fd-find", dnf = "fd-find", zypper = "fd", apk = "fd", brew = "fd" },
  },
  {
    id = "node",
    label = "Node.js and npm",
    bins = { "node", "npm" },
    all = true,
    why = "JavaScript, TypeScript and web language servers, prettier",
    pkgs = {
      pacman = "nodejs npm",
      apt = "nodejs npm",
      dnf = "nodejs npm",
      zypper = "nodejs npm",
      apk = "nodejs npm",
      brew = "node",
    },
  },
  {
    id = "cmake",
    label = "cmake",
    bins = { "cmake" },
    why = "the faster fuzzy finder",
    pkgs = { pacman = "cmake", apt = "cmake", dnf = "cmake", zypper = "cmake", apk = "cmake", brew = "cmake" },
  },
  {
    id = "go",
    label = "Go",
    bins = { "go" },
    why = "the Go toolchain (gopls and the Go menu need it)",
    pack = "go",
    pkgs = { pacman = "go", apt = "golang-go", dnf = "golang", zypper = "go", apk = "go", brew = "go" },
  },
  {
    id = "python",
    label = "Python 3",
    bins = { "python3" },
    why = "running and testing Python",
    pack = "python",
    pkgs = {
      pacman = "python",
      apt = "python3 python3-venv",
      dnf = "python3",
      zypper = "python3",
      apk = "python3",
      brew = "python",
    },
  },
  {
    id = "sqlite",
    label = "SQLite",
    bins = { "sqlite3", "psql" },
    why = "running SQL queries from the editor",
    pack = "sql",
    pkgs = { pacman = "sqlite", apt = "sqlite3", dnf = "sqlite", zypper = "sqlite3", apk = "sqlite", brew = "sqlite" },
  },
  {
    id = "java",
    label = "Java (JDK)",
    bins = { "java" },
    why = "the Java and Kotlin language servers",
    pack = "jvm",
    pkgs = {
      pacman = "jdk-openjdk",
      apt = "default-jdk",
      dnf = "java-latest-openjdk-devel",
      zypper = "java-21-openjdk-devel",
      apk = "openjdk21",
      brew = "openjdk",
    },
  },
}

--- How each package manager installs, in order of preference when several exist.
M.MANAGERS = {
  { id = "pacman", bin = "pacman", install = { "pacman", "-S", "--needed", "--noconfirm" }, family = "Arch" },
  {
    id = "apt",
    bin = "apt-get",
    install = { "apt-get", "install", "-y" },
    refresh = { "apt-get", "update" },
    family = "Debian",
  },
  { id = "dnf", bin = "dnf", install = { "dnf", "install", "-y" }, family = "Fedora" },
  { id = "zypper", bin = "zypper", install = { "zypper", "--non-interactive", "install" }, family = "openSUSE" },
  { id = "apk", bin = "apk", install = { "apk", "add" }, family = "Alpine" },
  { id = "brew", bin = "brew", install = { "brew", "install" }, family = "Homebrew", nosudo = true },
}

---@param exe fun(bin: string): boolean
---@return table? manager
function M.manager(exe)
  for _, m in ipairs(M.MANAGERS) do
    if exe(m.bin) then
      return m
    end
  end
end

---@param tool SysTool
---@param exe fun(bin: string): boolean
---@return boolean
function M.present(tool, exe)
  if tool.all then
    return vim.iter(tool.bins):all(exe)
  end
  return vim.iter(tool.bins):any(exe)
end

--- The tools missing here, for the packs that are on (a runtime only when its pack is).
---@param exe fun(bin: string): boolean
---@param packs table<string, boolean>
---@return SysTool[]
function M.missing(exe, packs)
  return vim.tbl_filter(function(t)
    return (not t.pack or packs[t.pack]) and not M.present(t, exe)
  end, M.TOOLS)
end

--- The command that installs `tools` with `manager` (one line, shown before it runs). `root` = no sudo needed.
---@param manager table
---@param tools SysTool[]
---@param root boolean
---@return string? command, string[] skipped labels of the tools this manager does not package
function M.command(manager, tools, root)
  local pkgs, skipped = {}, {}
  for _, t in ipairs(tools) do
    local p = t.pkgs[manager.id]
    if p then
      vim.list_extend(pkgs, vim.split(p, " ", { trimempty = true }))
    else
      skipped[#skipped + 1] = t.label
    end
  end
  if #pkgs == 0 then
    return nil, skipped
  end
  local sudo = (root or manager.nosudo) and "" or "sudo "
  local install = sudo .. table.concat(manager.install, " ") .. " " .. table.concat(pkgs, " ")
  if manager.refresh then
    return sudo .. table.concat(manager.refresh, " ") .. " && " .. install, skipped
  end
  return install, skipped
end

--- "Arch Linux", "Debian GNU/Linux 12 (bookworm)", … from os-release text.
---@param text string?
---@return string?
function M.distro(text)
  return text and (text:match 'PRETTY_NAME="([^"]+)"' or text:match "PRETTY_NAME=([^\n]+)")
end

return M
