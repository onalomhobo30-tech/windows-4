[CmdletBinding()]
param(
  [string[]] $Path = @(
    'installer/winpe/Test-Phase5Safe.ps1',
    'installer/winpe/Run-Phase5.ps1',
    'installer/winpe/Deploy-SystemImage-Phase5.ps1'
  )
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$failures = @()
foreach ($file in $Path) {
  if (-not (Test-Path $file -PathType Leaf)) { $failures += "Missing script: $file"; continue }
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { $failures += "Syntax errors in $file: $($errors | ForEach-Object Message -join '; ')" }
  else { Write-Host "PASS syntax: $file" -ForegroundColor Green }
}
$safe = Get-Content 'installer/winpe/Test-Phase5Safe.ps1' -Raw
foreach ($forbidden in 'Clear-Disk','Initialize-Disk','New-Partition','Remove-Partition','Format-Volume','Expand-WindowsImage','Apply-Image','bcdboot','bootsect') {
  if ($safe -match "(?im)^\s*[^#\r\n]*\b$forbidden\b") { $failures += "Unsafe command reference in safe dry-run script: $forbidden" }
}
if ($safe -match '(?im)^\s*&\s+(dism|bcdboot|bootsect)\.exe') { $failures += 'Safe dry-run invokes a deployment executable.' }
else { Write-Host 'PASS safety: safe script contains no executable deployment calls' -ForegroundColor Green }
if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Error $_ }; exit 1 }
Write-Host 'PASS: static Phase 5 dry-run validation completed. No WinPE image or physical disk was touched.' -ForegroundColor Cyan
