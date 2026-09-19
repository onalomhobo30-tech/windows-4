[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $OutputDirectory,
  [ValidateSet('amd64','x86')] [string] $Architecture = 'amd64',
  [ValidateSet('ISO','USB','Both')] [string] $Media = 'ISO',
  [ValidateRange(0,255)] [int] $UsbDiskNumber = -1,
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$buildStarted = Get-Date
$logDirectory = Join-Path $OutputDirectory 'logs'
$logPath = Join-Path $logDirectory 'phase4-build.log'

function Write-Log([string] $Message) {
  $line = "$(Get-Date -Format o) $Message"
  Write-Host $line
  if (Test-Path $logDirectory) { Add-Content -Path $logPath -Value $line }
}
function Require-Command([string] $Name) {
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) { throw "Required tool '$Name' was not found. Install the Windows ADK/Deployment Tools." }
  return $command.Source
}
function Find-AdkTool([string] $Name) {
  $roots = @(${env:ProgramFiles(x86)}, ${env:ProgramFiles}) | Where-Object { $_ }
  foreach ($root in $roots) {
    $candidate = Join-Path $root "Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$Name"
    if (Test-Path $candidate) { return $candidate }
  }
  throw "Could not find $Name. Install the Windows ADK Deployment Tools first."
}
function Find-HtaPackage([string] $Arch) {
  $roots = @(${env:ProgramFiles(x86)}, ${env:ProgramFiles}) | Where-Object { $_ }
  foreach ($root in $roots) {
    $candidate = Join-Path $root "Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\$Arch\WinPE_OCs\WinPE-HTA-Package.cab"
    if (Test-Path $candidate) { return $candidate }
  }
  throw 'WinPE-HTA-Package.cab was not found. Install the Windows PE add-on for the ADK.'
}
function Assert-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script from an elevated PowerShell window.' }
}
function Invoke-Native([string] $File, [string[]] $Arguments) {
  Write-Log "$File $($Arguments -join ' ')"
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}
function Test-RequiredPayload([string] $MountDirectory) {
  $required = @('Start-Windows4Installer.ps1','Get-HardwareInventory.ps1','DeploymentEngine.ps1','HuskagentInstaller.hta','HuskagentDeployment.hta','Windows4Installer.cmd')
  foreach ($name in $required) {
    $path = Join-Path $MountDirectory $name
    if (-not (Test-Path $path -PathType Leaf)) { throw "Installer payload validation failed: missing $name" }
  }
  $forbidden = Get-ChildItem $MountDirectory -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(install|boot|winre)\.(wim|esd|swm)$' }
  if ($forbidden) { throw "Installer payload validation failed: Microsoft OS image found in payload: $($forbidden[0].FullName)" }
  return $required | ForEach-Object {
    $file = Get-Item (Join-Path $MountDirectory $_)
    [pscustomobject]@{ Path=$_.Replace('\','/'); Bytes=$file.Length; SHA256=(Get-FileHash $file.FullName -Algorithm SHA256).Hash }
  }
}
function Test-BootLayout([string] $SourceDirectory, [string] $Architecture) {
  $checks = @(
    (Join-Path $SourceDirectory 'media\sources\boot.wim'),
    (Join-Path $SourceDirectory 'media\bootmgr'),
    (Join-Path $SourceDirectory 'media\boot\BCD'),
    (Join-Path $SourceDirectory 'media\efi\microsoft\boot\efisys.bin'),
    (Join-Path $SourceDirectory 'media\efi\microsoft\boot\BCD')
  )
  foreach ($path in $checks) { if (-not (Test-Path $path -PathType Leaf)) { throw "Boot-file validation failed for $Architecture media: $path" } }
  Write-Log "Boot validation passed for $Architecture: BIOS bootmgr/BCD and UEFI efisys/BCD present."
}
function New-ReproducibilityManifest([string] $MediaRoot, [string] $ManifestPath, [object] $Payload) {
  $files = Get-ChildItem $MediaRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    [pscustomobject]@{ Path=$_.FullName.Substring($MediaRoot.Length).TrimStart('\').Replace('\','/'); Bytes=$_.Length; SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash }
  }
  [pscustomobject]@{ SchemaVersion=1; Product='HuskagentWindows4'; Phase=4; Architecture=$Architecture; CreatedBy='Build-WinPE-Phase4.ps1'; FixedTimestamp='2024-01-01T00:00:00Z'; Payload=$Payload; Files=$files } | ConvertTo-Json -Depth 8 | Set-Content $ManifestPath -Encoding UTF8
}

Assert-Administrator
New-Item $OutputDirectory,$logDirectory -ItemType Directory -Force | Out-Null
New-Item $logPath -ItemType File -Force | Out-Null
try {
  Write-Log "Phase 4 build started. Architecture=$Architecture Media=$Media USB=$UsbDiskNumber"
  $copype = Find-AdkTool 'copype.cmd'; $makeWinMedia = Find-AdkTool 'MakeWinPEMedia.cmd'; $dism = Require-Command 'dism.exe'; $oscdimg = Find-AdkTool 'Oscdimg\oscdimg.exe'
  $source = Join-Path $OutputDirectory 'source'; $mount = Join-Path $OutputDirectory 'mount'; $mediaRoot = Join-Path $OutputDirectory 'media'; $iso = Join-Path $OutputDirectory "HuskagentWindows4-Phase4-$Architecture.iso"
  if (Test-Path $source) { if (-not $Force) { throw "Output already contains source files. Use -Force: $OutputDirectory" }; Remove-Item $source,$mount,$mediaRoot -Recurse -Force -ErrorAction SilentlyContinue }
  New-Item $mount,$mediaRoot -ItemType Directory -Force | Out-Null
  Invoke-Native $copype @($Architecture,$source)
  $bootWim = Join-Path $source 'media\sources\boot.wim'
  Invoke-Native $dism @('/Mount-Image', "/ImageFile:$bootWim", '/Index:1', "/MountDir:$mount")
  $committed = $false
  try {
    Invoke-Native $dism @('/Image:' + $mount, '/Add-Package', "/PackagePath:$(Find-HtaPackage $Architecture)")
    $files = @('Start-Windows4Installer.ps1','Get-HardwareInventory.ps1','DeploymentEngine.ps1','HuskagentInstaller.hta','HuskagentDeployment.hta','Windows4Installer.cmd')
    foreach ($file in $files) { Copy-Item (Join-Path $PSScriptRoot $file) $mount -Force }
    Add-Content (Join-Path $mount 'Windows\System32\Startnet.cmd') "`r`n wpeinit`r`n powershell.exe -ExecutionPolicy Bypass -File X:\Start-Windows4Installer.ps1`r`n"
    $payload = Test-RequiredPayload $mount
    Invoke-Native $dism @('/Unmount-Image', "/MountDir:$mount", '/Commit'); $committed = $true
  } finally { if (-not $committed) { & $dism /Unmount-Image /MountDir:$mount /Discard | Out-Null } }
  Copy-Item (Join-Path $source 'media\*') $mediaRoot -Recurse -Force
  Test-BootLayout $source $Architecture
  $payload = Test-RequiredPayload (Join-Path $source 'mount')
  New-ReproducibilityManifest $mediaRoot (Join-Path $OutputDirectory 'Phase4-manifest.json') $payload
  if ($Media -in @('ISO','Both')) {
    $bootData = '-bootdata:2#p0,e,b' + (Join-Path $source 'media\boot\etfsboot.com') + '#pEF,e,b' + (Join-Path $source 'media\efi\microsoft\boot\efisys.bin')
    Invoke-Native $oscdimg @('-u2','-udfver102','-h','-m','-o','-t010100002024',$bootData,$mediaRoot,$iso)
    if (-not (Test-Path $iso)) { throw 'ISO validation failed: oscdimg did not create the output file.' }
    Write-Log "ISO created: $iso"
  }
  if ($Media -in @('USB','Both')) {
    if ($UsbDiskNumber -lt 0) { throw 'USB or Both media requires -UsbDiskNumber.' }
    $disk = Get-Disk -Number $UsbDiskNumber -ErrorAction Stop
    if ($disk.BusType -ne 'USB' -and -not $Force) { throw "Disk $UsbDiskNumber is $($disk.BusType), not USB. Use -Force only after verifying the disk." }
    if (-not $PSCmdlet.ShouldProcess("Disk $UsbDiskNumber ($($disk.FriendlyName))", 'Erase and create Phase 4 USB')) { return }
    Invoke-Native $makeWinMedia @('/UFD',$source,("\\.\PhysicalDrive$UsbDiskNumber"))
    Write-Log "USB created on disk $UsbDiskNumber. MakeWinMedia provides UEFI/BIOS boot sectors from the validated media tree."
  }
  $buildResult = [pscustomobject]@{ Product='HuskagentWindows4'; Phase=4; Architecture=$Architecture; Media=$Media; ISO=if(Test-Path $iso){$iso}else{$null}; UsbDiskNumber=$UsbDiskNumber; CompletedAt=(Get-Date).ToUniversalTime().ToString('o'); Manifest=(Join-Path $OutputDirectory 'Phase4-manifest.json'); Log=$logPath }
  $buildResult | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'Phase4-build-result.json') -Encoding UTF8
  Write-Log 'Phase 4 build completed successfully.'
} catch { Write-Log "BUILD FAILED: $($_.Exception.Message)"; throw }
