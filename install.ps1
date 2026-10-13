# Installs this Neovim config on Windows in ONE command: junction at %LOCALAPPDATA%\nvim, git hooks, plugins, LSPs/formatters,
# parsers and the AI agent. Idempotent.
#
#   irm https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/sazardev/my-nvim-setup/master/install.ps1))) -Lang go -Theme catppuccin
#
# That fetches the repo into %LOCALAPPDATA%\my-nvim-setup (override: $env:NVIM_CONFIG_DIR, NVIM_CONFIG_REPO, NVIM_CONFIG_BRANCH)
# and runs its install.ps1. From a clone: ./install.ps1 [-NoPlugins] [-Lang go,typescript] [-Theme catppuccin]
# [-Light | -NoLight] [-Agent auto|none|claude/haiku] (same options as install.sh; -Agent defaults to auto).
# Requirements: Neovim >= 0.11, git (or just curl/tar for the fetch) and a C compiler (for example
# `winget install -e --id MartinStorsjo.LLVM-MinGW.UCRT` or Visual Studio Build Tools). Optional: ripgrep, node, cmake.
param([switch]$NoPlugins, [string]$Lang = '', [string]$Theme = '', [switch]$Light, [switch]$NoLight, [string]$Agent = 'auto')
$ErrorActionPreference = 'Stop'

# One command: run from a pipe ($PSScriptRoot is empty) there is no repo next to the script, so fetch it and hand over
$Root = $PSScriptRoot
if (-not $Root -or -not (Test-Path (Join-Path $Root 'nvim'))) {
  $repo = if ($env:NVIM_CONFIG_REPO) { $env:NVIM_CONFIG_REPO } else { 'https://github.com/sazardev/my-nvim-setup.git' }
  $branch = if ($env:NVIM_CONFIG_BRANCH) { $env:NVIM_CONFIG_BRANCH } else { 'master' }
  $dest = if ($env:NVIM_CONFIG_DIR) { $env:NVIM_CONFIG_DIR } else { Join-Path $env:LOCALAPPDATA 'my-nvim-setup' }
  Write-Host "nvim config: fetching $repo -> $dest"
  if (Get-Command git -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $dest '.git')) { git -C $dest pull --ff-only -q }
    elseif (-not (Test-Path $dest)) { git clone -q --depth 1 --branch $branch $repo $dest }
  } else {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $tar = Join-Path $env:TEMP 'my-nvim-setup.tar.gz'
    Invoke-WebRequest "$($repo -replace '\.git$','')/archive/refs/heads/$branch.tar.gz" -OutFile $tar
    tar -xzf $tar --strip-components=1 -C $dest
  }
  if (-not (Test-Path (Join-Path $dest 'install.ps1'))) { throw "could not fetch the config into $dest" }
  & (Join-Path $dest 'install.ps1') @PSBoundParameters
  return
}
$RootU = $Root.Replace('\', '/')
$Target = Join-Path $env:LOCALAPPDATA 'nvim'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Step 'Requirements'
foreach ($c in 'nvim', 'git') {
  if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "$c is missing (winget install Neovim.Neovim / Git.Git)" }
}
$v = [version](((nvim --version)[0]) -replace '[^\d\.]', '' -replace '\.$', '')
if ($v -lt [version]'0.11') { throw "Neovim >= 0.11 is required (you have $v)" }
if (-not ((Get-Command gcc, clang, cl -ErrorAction SilentlyContinue))) { Write-Warning 'no C compiler found: treesitter will not be able to compile parsers' }

Step "Link $Target"
$want = Join-Path $Root 'nvim'
$item = Get-Item $Target -ErrorAction SilentlyContinue
if ($item -and $item.LinkType -and ($item.Target -eq $want)) {
  Write-Host '  already points to this repo'
} else {
  if ($item) {
    $bak = "$Target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Write-Warning "a config already existed: saving it to $bak"
    Move-Item $Target $bak
  }
  New-Item -ItemType Junction -Path $Target -Target $want | Out-Null
  Write-Host "  $Target -> $want"
}

if (Test-Path (Join-Path $Root '.git')) {
  git -C $Root config core.hooksPath .githooks
  Write-Host '  git hooks enabled (.githooks)'
}

# Per-machine settings (lua/local.lua): the same implementation as install.sh
if ($Lang -or $Theme -or $Light -or $NoLight) {
  Step 'Settings (lua/local.lua)'
  $env:NVIM_INSTALL_LANGS = $Lang
  $env:NVIM_INSTALL_THEME = $Theme
  $env:NVIM_INSTALL_LIGHT = if ($Light) { '1' } elseif ($NoLight) { '0' } else { '' }
  $out = & nvim -u NONE --headless -l (Join-Path $Root 'scripts/install-local.lua') 2>&1
  $out | ForEach-Object {
    $line = "$_"
    if ($line.StartsWith('ERR ')) { Write-Error $line.Substring(4) }
    elseif ($line.StartsWith('WARN ')) { Write-Warning $line.Substring(5) }
    elseif ($line.StartsWith('OK ')) { Write-Host "  $($line.Substring(3))" }
  }
  if ($LASTEXITCODE -ne 0) { throw 'invalid settings (above)' }
}

if (-not $NoPlugins) {
  $log = Join-Path $env:TEMP 'nvim-config-install.log'
  Remove-Item $log -ErrorAction SilentlyContinue
  foreach ($job in @(
      @('Plugins (lazy.nvim, pinned versions)', '+Lazy! restore', '+qa'),
      @('LSPs, formatters and linters (Mason)', '-c', "luafile $RootU/scripts/install-mason.lua", '+qa'),
      @('Treesitter parsers', '-c', "luafile $RootU/scripts/install-treesitter.lua", '+qa'))) {
    Step $job[0]
    & nvim --headless @($job[1..($job.Length - 1)]) *>> $log
  }
  Write-Host "`n  (install log: $log)"
}

# AI agent (optional): -Agent auto (default) | claude/haiku | none
if ($Agent -ne 'none') {
  Step 'AI agent'
  if ($NoPlugins) {
    Write-Warning 'skipped with -NoPlugins: when you first open nvim, use <Space>am -> Setup'
  } else {
    $flags = if (-not $Agent) { '' } elseif ($Agent -eq 'auto') { "'--auto'" } else { "'--use','$Agent'" }
    & nvim --headless -c "lua vim.defer_fn(function() require('agent.setup').cli({ $flags }) end, 300)" 2>&1 | Write-Host
  }
}

Step 'Done'
Write-Host '  Open nvim: <Space> shows the menus; CHEATSHEET.md has all the keys.'
