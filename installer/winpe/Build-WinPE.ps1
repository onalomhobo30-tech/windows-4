[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $OutputDirectory,
  [ValidateRange(0, 255)] [int] $UsbDiskNumber = -1,
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Find-AdkTool([string] $Name) {
  $candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$Name"),
    (Join-Path ${env:ProgramFiles} "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$Name")
  )
  $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $found) { throw "Could not find $Name. Install the Windows ADK Deployment Tools first." }
  return $found
}

function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window.'
  }
}

Assert-Administrator
$copype = Find-AdkTool 'copype.cmd'
$makeWinMedia = Find-AdkTool 'MakeWinPEMedia.cmd'
$sourceDirectory = Join-Path $OutputDirectory 'source'
$mediaDirectory = Join-Path $OutputDirectory 'media'

if (Test-Path $OutputDirectory) {
  if (-not $Force) { throw "Output directory already exists. Remove it or use -Force: $OutputDirectory" }
  Remove-Item $OutputDirectory -Recurse -Force
}
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null

Write-Host 'Creating amd64 WinPE working files...' -ForegroundColor Cyan
& $copype amd64 $sourceDirectory
if ($LASTEXITCODE -ne 0) { throw "copype failed with exit code $LASTEXITCODE" }

New-Item $mediaDirectory -ItemType Directory -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Start-Windows4Installer.ps1') (Join-Path $sourceDirectory 'Start-Windows4Installer.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'Windows4Installer.cmd') (Join-Path $sourceDirectory 'Windows4Installer.cmd') -Force
$startup = Join-Path $sourceDirectory 'mount\Windows\System32\Startnet.cmd'
if (-not (Test-Path $startup)) { throw "WinPE startup file not found: $startup" }
Add-Content -Path $startup -Value "`r`n wpeinit`r`n powershell.exe -ExecutionPolicy Bypass -File X:\Start-Windows4Installer.ps1`r`n"

$usb = $UsbDiskNumber -ge 0
if ($usb) {
  $disk = Get-Disk -Number $UsbDiskNumber
  if ($disk.BusType -ne 'USB' -and -not $Force) { throw "Disk $UsbDiskNumber is $($disk.BusType), not USB. Use -Force only when you have verified the disk." }
  if (-not $PSCmdlet.ShouldProcess("Disk $UsbDiskNumber ($($disk.FriendlyName))", 'Erase and create WinPE USB media')) { return }
  & $makeWinMedia /UFD $sourceDirectory ("\\.\PhysicalDrive$UsbDiskNumber")
} else {
  & $makeWinMedia /ISO $sourceDirectory (Join-Path $mediaDirectory 'HuskagentWindows4-Phase1-amd64.iso')
}
if ($LASTEXITCODE -ne 0) { throw "MakeWinPEMedia failed with exit code $LASTEXITCODE" }
Write-Host "Phase 1 WinPE media created under $OutputDirectory" -ForegroundColor Green
