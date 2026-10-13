# Instala esta config de Neovim en Windows: junction en %LOCALAPPDATA%\nvim, hooks de git, plugins, LSP/formatters y parsers.
# Idempotente. Uso (PowerShell):  ./install.ps1 [-NoPlugins]
# Requisitos: Neovim >= 0.11, git y un compilador de C (por ejemplo `winget install -e --id MartinStorsjo.LLVM-MinGW.UCRT`
# o Visual Studio Build Tools). Opcionales: ripgrep, node, cmake.
param([switch]$NoPlugins)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootU = $Root.Replace('\', '/')
$Target = Join-Path $env:LOCALAPPDATA 'nvim'

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }

Step 'Requisitos'
foreach ($c in 'nvim', 'git') {
  if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { throw "falta $c (winget install Neovim.Neovim / Git.Git)" }
}
$v = [version](((nvim --version)[0]) -replace '[^\d\.]', '' -replace '\.$', '')
if ($v -lt [version]'0.11') { throw "necesito Neovim >= 0.11 (tienes $v)" }
if (-not ((Get-Command gcc, clang, cl -ErrorAction SilentlyContinue))) { Write-Warning 'no encuentro un compilador de C: treesitter no podrá compilar parsers' }

Step "Enlace $Target"
$want = Join-Path $Root 'nvim'
$item = Get-Item $Target -ErrorAction SilentlyContinue
if ($item -and $item.LinkType -and ($item.Target -eq $want)) {
  Write-Host '  ya apunta a este repo'
} else {
  if ($item) {
    $bak = "$Target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Write-Warning "ya existía una config: la guardo en $bak"
    Move-Item $Target $bak
  }
  New-Item -ItemType Junction -Path $Target -Target $want | Out-Null
  Write-Host "  $Target -> $want"
}

if (Test-Path (Join-Path $Root '.git')) {
  git -C $Root config core.hooksPath .githooks
  Write-Host '  git hooks activados (.githooks)'
}

if (-not $NoPlugins) {
  $log = Join-Path $env:TEMP 'nvim-config-install.log'
  Remove-Item $log -ErrorAction SilentlyContinue
  foreach ($job in @(
      @('Plugins (lazy.nvim)', '+Lazy! sync', '+qa'),
      @('LSP, formatters y linters (Mason)', '-c', "luafile $RootU/scripts/install-mason.lua", '+qa'),
      @('Parsers de treesitter', '-c', "luafile $RootU/scripts/install-treesitter.lua", '+qa'))) {
    Step $job[0]
    & nvim --headless @($job[1..($job.Length - 1)]) *>> $log
  }
  Write-Host "`n  (registro de la instalación: $log)"
}

Step 'Listo'
Write-Host '  Abre nvim: <Space> muestra los menus; CHEATSHEET.md tiene todas las teclas.'
