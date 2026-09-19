[CmdletBinding()]
param(
  [switch] $ListImages,
  [switch] $ListTargets,
  [switch] $Verify,
  [switch] $Deploy,
  [string] $ImagePath,
  [int] $ImageIndex = 1,
  [int] $DiskNumber = -1,
  [ValidateSet('UEFI','BIOS','Auto')] [string] $Firmware = 'Auto',
  [ValidateSet('x86','x64')] [string] $Architecture,
  [string] $OutputPath = 'X:\Huskagent-Deployment.json',
  [switch] $Confirmed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $env:SystemDrive 'Huskagent-Phase3.log'

function Write-DeploymentLog([string] $Message) { "$(Get-Date -Format o) $Message" | Add-Content -Path $log }
function SizeGB([object] $Value) { if ($null -eq $Value) { return 0 }; [math]::Round(([double]$Value / 1GB), 2) }
function Get-DetectedFirmware {
  try { $value = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop; if ($value -eq 2) { return 'UEFI' }; if ($value -eq 1) { return 'BIOS' } } catch { }
  if ($env:firmware_type -match 'UEFI') { return 'UEFI' }
  return 'BIOS'
}
function Get-DetectedArchitecture {
  $value = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  if ($value -in @('AMD64','IA64','ARM64')) { return 'x64' }
  return 'x86'
}
function Get-ImageRoots {
  @('X:\Sources','X:\Huskagent\Images','X:\Images','D:\Sources','D:\Huskagent\Images') | Where-Object { Test-Path $_ } | Select-Object -Unique
}
function Get-ImageCatalog {
  $images = @()
  foreach ($root in Get-ImageRoots) {
    foreach ($file in @(Get-ChildItem $root -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.wim','.esd') })) {
      try {
        $details = @(Get-WindowsImage -ImagePath $file.FullName -ErrorAction Stop)
        foreach ($detail in $details) {
          $images += [pscustomobject]@{ Path=$file.FullName; Name=[string]$detail.ImageName; Description=[string]$detail.ImageDescription; Index=[int]$detail.ImageIndex; Architecture=if([string]$detail.Architecture -match '64'){'x64'}else{'x86'}; SizeGB=SizeGB $file.Length }
        }
      } catch { Write-DeploymentLog "Unable to read image metadata from $($file.FullName): $($_.Exception.Message)" }
    }
  }
  return $images
}
function Get-TargetCatalog {
  @(Get-Disk | ForEach-Object {
    $disk = $_
    $parts = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Number=$_.PartitionNumber; Letter=if($_.DriveLetter){[string]$_.DriveLetter}else{''}; Type=[string]$_.Type; SizeGB=SizeGB $_.Size } })
    [pscustomobject]@{ Number=[int]$disk.Number; Name=[string]$disk.FriendlyName; BusType=[string]$disk.BusType; Style=[string]$disk.PartitionStyle; SizeGB=SizeGB $disk.Size; IsBoot=[bool]$disk.IsBoot; IsSystem=[bool]$disk.IsSystem; Partitions=$parts }
  })
}
function Write-Json([object] $Value) { $Value | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8; Write-Output ($Value | ConvertTo-Json -Depth 10) }
function Assert-Target([int] $Number, [string] $Mode) {
  $disk = Get-Disk -Number $Number -ErrorAction Stop
  if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $Number is the current boot/system disk; refusing deployment." }
  if ($disk.BusType -eq 'USB') { throw "Disk $Number is USB. Remove installer media or choose an internal target disk." }
  if ($disk.IsReadOnly) { throw "Disk $Number is read-only." }
  if ($Mode -eq 'UEFI' -and $disk.Size -lt 16GB) { throw 'UEFI target disk is smaller than the 16 GB minimum.' }
  if ($disk.Size -lt 8GB) { throw 'Target disk is smaller than the 8 GB minimum.' }
  return $disk
}
function Confirm-Destructive([int] $Number, [object] $Disk) {
  if (-not $Confirmed) { throw 'Deployment requires -Confirmed and the exact operator confirmation.' }
  $answer = Read-Host "Type DEPLOY DISK $Number to erase $($Disk.FriendlyName) ($([math]::Round($Disk.Size / 1GB, 1)) GB)"
  if ($answer -cne "DEPLOY DISK $Number") { throw 'Confirmation did not match; no disk changes were made.' }
}
function New-DeploymentPartitions([object] $Disk, [string] $Mode) {
  Clear-Disk -Number $Disk.Number -RemoveData -Confirm:$false
  if ($Mode -eq 'UEFI') {
    Initialize-Disk -Number $Disk.Number -PartitionStyle GPT
    $efi = New-Partition -DiskNumber $Disk.Number -Size 260MB -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel SYSTEM -Confirm:$false | Out-Null
    $msr = New-Partition -DiskNumber $Disk.Number -Size 16MB -GptType '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}'
    $os = New-Partition -DiskNumber $Disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel HUSKAGENT -Confirm:$false | Out-Null
    return [pscustomobject]@{ Mode=$Mode; System=$efi; OS=$os; MSR=$msr }
  }
  Initialize-Disk -Number $Disk.Number -PartitionStyle MBR
  $system = New-Partition -DiskNumber $Disk.Number -Size 500MB -IsActive
  Format-Volume -Partition $system -FileSystem NTFS -NewFileSystemLabel SYSTEM -Confirm:$false | Out-Null
  $osLegacy = New-Partition -DiskNumber $Disk.Number -UseMaximumSize -AssignDriveLetter
  Format-Volume -Partition $osLegacy -FileSystem NTFS -NewFileSystemLabel HUSKAGENT -Confirm:$false | Out-Null
  return [pscustomobject]@{ Mode=$Mode; System=$system; OS=$osLegacy }
}
function Invoke-Deployment {
  if ([string]::IsNullOrWhiteSpace($ImagePath) -or -not (Test-Path $ImagePath)) { throw 'Select an existing .wim or .esd image before deploying.' }
  $mode = if ($Firmware -eq 'Auto') { Get-DetectedFirmware } else { $Firmware }
  $arch = if ($Architecture) { $Architecture } else { Get-DetectedArchitecture }
  $disk = Assert-Target $DiskNumber $mode
  Confirm-Destructive $DiskNumber $disk
  $metadata = @(Get-WindowsImage -ImagePath $ImagePath -Index $ImageIndex -ErrorAction Stop)
  if ($metadata.Count -eq 0) { throw 'The selected image index could not be read.' }
  if ([string]$metadata[0].Architecture -match '64' -and $arch -eq 'x86') { throw 'An x64 image cannot be deployed by an x86 target environment.' }
  Write-DeploymentLog "Deploying $ImagePath index $ImageIndex to disk $DiskNumber using $mode/$arch"
  $parts = New-DeploymentPartitions $disk $mode
  $osLetter = [string]$parts.OS.DriveLetter
  if (-not $osLetter) { throw 'The OS partition did not receive a drive letter.' }
  Expand-WindowsImage -ImagePath $ImagePath -Index $ImageIndex -ApplyPath "$osLetter:\" -ErrorAction Stop
  $systemLetter = [string]$parts.System.DriveLetter
  if (-not $systemLetter) { $systemLetter = (Get-Volume -Partition $parts.System).DriveLetter }
  if (-not $systemLetter) { throw 'The system partition did not receive a drive letter.' }
  $bcdboot = Join-Path $env:SystemRoot 'System32\bcdboot.exe'
  & $bcdboot "$osLetter:\Windows" /s "$systemLetter`:" /f $mode
  if ($LASTEXITCODE -ne 0) { throw "bcdboot failed with exit code $LASTEXITCODE" }
  $marker = Join-Path "$osLetter:\" 'HuskagentWindows4-Deployment.json'
  [pscustomobject]@{ SchemaVersion=1; CompletedAt=(Get-Date).ToUniversalTime().ToString('o'); ImagePath=$ImagePath; ImageIndex=$ImageIndex; Firmware=$mode; Architecture=$arch; DiskNumber=$DiskNumber } | ConvertTo-Json | Set-Content $marker -Encoding UTF8
  Invoke-Verification -DiskNumber $DiskNumber -OSLetter $osLetter -SystemLetter $systemLetter -Firmware $mode
}
function Invoke-Verification([int] $DiskNumber, [string] $OSLetter, [string] $SystemLetter, [string] $Firmware) {
  $checks = @([pscustomobject]@{ Name='OS directory'; Passed=Test-Path "$OSLetter:\Windows" }, [pscustomobject]@{ Name='Deployment marker'; Passed=Test-Path "$OSLetter:\HuskagentWindows4-Deployment.json" }, [pscustomobject]@{ Name='Boot files'; Passed=(Test-Path "$SystemLetter:\Boot") -or ($Firmware -eq 'BIOS' -and (Test-Path "$SystemLetter:\bootmgr")) })
  $result = [pscustomobject]@{ Verified=($checks.Passed -notcontains $false); Firmware=$Firmware; DiskNumber=$DiskNumber; Checks=$checks; VerifiedAt=(Get-Date).ToUniversalTime().ToString('o') }
  Write-Json $result
  if (-not $result.Verified) { throw 'Installation verification failed.' }
}

New-Item -Path $log -ItemType File -Force | Out-Null
if ($ListImages) { Write-Json @(Get-ImageCatalog); exit 0 }
if ($ListTargets) { Write-Json @(Get-TargetCatalog); exit 0 }
if ($Verify) { if ($DiskNumber -lt 0) { throw 'A disk number is required for verification.' }; $disk=Get-Disk $DiskNumber; $os=Get-Partition -DiskNumber $DiskNumber | Where-Object DriveLetter | Select-Object -Last 1; Invoke-Verification $DiskNumber "$($os.DriveLetter):" '' (if($Firmware -eq 'Auto'){Get-DetectedFirmware}else{$Firmware}); exit 0 }
if ($Deploy) { Invoke-Deployment; exit 0 }
throw 'Specify -ListImages, -ListTargets, -Verify, or -Deploy.'
