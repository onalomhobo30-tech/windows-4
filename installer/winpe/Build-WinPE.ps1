[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $OutputDirectory,
  [ValidateRange(0, 255)] [int] $UsbDiskNumber = -1,
  [switch] $Force
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Find-AdkTool([string] $Name) {
  $roots = @(${env:ProgramFiles(x86)}, ${env:ProgramFiles}) | Where-Object { $_ }
  foreach ($root in $roots) { $candidate = Join-Path $root "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$Name"; if (Test-Path $candidate) { return $candidate } }
  throw "Could not find $Name. Install the Windows ADK Deployment Tools first."
}
function Find-HtaPackage([string] $Architecture) {
  $roots = @(${env:ProgramFiles(x86)}, ${env:ProgramFiles}) | Where-Object { $_ }
  foreach ($root in $roots) { $candidate = Join-Path $root "Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\$Architecture\WinPE_OCs\WinPE-HTA-Package.cab"; if (Test-Path $candidate) { return $candidate } }
  throw 'WinPE-HTA-Package.cab was not found. Install the Windows PE add-on for the ADK.'
}
function Assert-Administrator { $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity);if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run this script from an elevated PowerShell window.'} }
Assert-Administrator
$copype=Find-AdkTool 'copype.cmd';$makeWinMedia=Find-AdkTool 'MakeWinPEMedia.cmd';$dism=(Get-Command dism.exe).Source
$source=Join-Path $OutputDirectory 'source';$mount=Join-Path $OutputDirectory 'mount';$media=Join-Path $OutputDirectory 'media'
if(Test-Path $OutputDirectory){if(-not $Force){throw "Output directory already exists. Remove it or use -Force: $OutputDirectory"};Remove-Item $OutputDirectory -Recurse -Force}
New-Item $OutputDirectory,$mount,$media -ItemType Directory -Force | Out-Null
& $copype amd64 $source;if($LASTEXITCODE-ne 0){throw "copype failed with exit code $LASTEXITCODE"}
$boot=Join-Path $source 'media\sources\boot.wim';& $dism /Mount-Image /ImageFile:$boot /Index:1 /MountDir:$mount;if($LASTEXITCODE-ne 0){throw 'Unable to mount boot.wim.'}
try {
  $hta=Find-HtaPackage 'amd64';& $dism /Image:$mount /Add-Package /PackagePath:$hta;if($LASTEXITCODE-ne 0){throw 'Unable to add WinPE HTA optional component.'}
  Copy-Item (Join-Path $PSScriptRoot 'Start-Windows4Installer.ps1'),(Join-Path $PSScriptRoot 'Get-HardwareInventory.ps1'),(Join-Path $PSScriptRoot 'HuskagentInstaller.hta'),(Join-Path $PSScriptRoot 'Windows4Installer.cmd') $mount -Force
  $startup=Join-Path $mount 'Windows\System32\Startnet.cmd';Add-Content $startup "`r`n wpeinit`r`n powershell.exe -ExecutionPolicy Bypass -File X:\Start-Windows4Installer.ps1`r`n"
} finally { & $dism /Unmount-Image /MountDir:$mount /Commit;if($LASTEXITCODE-ne 0){throw 'Unable to commit boot.wim changes.'} }
if($UsbDiskNumber-ge 0){$disk=Get-Disk -Number $UsbDiskNumber;if($disk.BusType-ne 'USB' -and -not $Force){throw "Disk $UsbDiskNumber is $($disk.BusType), not USB. Use -Force only after verifying the disk."};if(-not $PSCmdlet.ShouldProcess("Disk $UsbDiskNumber ($($disk.FriendlyName))",'Erase and create WinPE USB media')){return};& $makeWinMedia /UFD $source ("\\.\PhysicalDrive$UsbDiskNumber")}else{& $makeWinMedia /ISO $source (Join-Path $media 'HuskagentWindows4-Phase2-amd64.iso')};if($LASTEXITCODE-ne 0){throw "MakeWinPEMedia failed with exit code $LASTEXITCODE"};Write-Host "Phase 2 WinPE media created under $OutputDirectory" -ForegroundColor Green
