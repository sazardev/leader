# Installs this Neovim config on Windows: junction at %LOCALAPPDATA%\nvim, git hooks, plugins, LSPs/formatters and parsers.
# Idempotent. Usage (PowerShell):
#   ./install.ps1 [-NoPlugins] [-Lang go,typescript] [-Theme catppuccin] [-Light | -NoLight] [-Agent auto|none|claude/haiku]
# Same options as install.sh (-Lang/-Theme/-Light are written to lua/local.lua with scripts/install-local.lua; -Agent
# configures the AI agent with its `agent.setup` module).
# Requirements: Neovim >= 0.11, git and a C compiler (for example `winget install -e --id MartinStorsjo.LLVM-MinGW.UCRT`
# or Visual Studio Build Tools). Optional: ripgrep, node, cmake.
param([switch]$NoPlugins, [string]$Lang = '', [string]$Theme = '', [switch]$Light, [switch]$NoLight, [string]$Agent = '')
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
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
      @('Plugins (lazy.nvim)', '+Lazy! sync', '+qa'),
      @('LSPs, formatters and linters (Mason)', '-c', "luafile $RootU/scripts/install-mason.lua", '+qa'),
      @('Treesitter parsers', '-c', "luafile $RootU/scripts/install-treesitter.lua", '+qa'))) {
    Step $job[0]
    & nvim --headless @($job[1..($job.Length - 1)]) *>> $log
  }
  Write-Host "`n  (install log: $log)"
}

# AI agent (optional): -Agent auto | claude/haiku | none; without the option it only shows what it detects
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
