[CmdletBinding()]
param(
  [ValidateSet('Ui','Prepare','Inspect','Deploy')][string] $Action = 'Ui',
  [int] $DiskNumber = -1,
  [string] $ImagePath,
  [int] $ImageIndex = 1,
  [ValidateSet('UEFI','BIOS','Auto')][string] $Firmware = 'Auto',
  [ValidateSet('x86','x64')][string] $Architecture,
  [switch] $Confirmed
)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$inventory = Join-Path $env:SystemDrive 'Huskagent-Hardware.json'
function Start-Inventory { & (Join-Path $scriptRoot 'Get-HardwareInventory.ps1') -OutputPath $inventory | Out-Null }
function Start-Phase1Prepare([int] $Number) {
  if ($Number -lt 0) { throw 'A target disk number is required.' }; $disk=Get-Disk -Number $Number -ErrorAction Stop
  $confirmation=Read-Host "Type PREPARE DISK $Number to erase disk $Number ($($disk.FriendlyName))"; if($confirmation -cne "PREPARE DISK $Number"){Write-Warning 'Confirmation did not match; no changes made.';return}
  Clear-Disk -Number $Number -RemoveData -Confirm:$false;Initialize-Disk -Number $Number -PartitionStyle GPT;$efi=New-Partition -DiskNumber $Number -Size 260MB -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}';Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel SYSTEM -Confirm:$false|Out-Null;$os=New-Partition -DiskNumber $Number -UseMaximumSize -AssignDriveLetter;Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel HUSKAGENT -Confirm:$false|Out-Null
}
Start-Inventory
switch($Action){'Inspect'{& (Join-Path $scriptRoot 'Get-HardwareInventory.ps1') -OutputMode Display};'Prepare'{Start-Phase1Prepare $DiskNumber;Start-Inventory};'Deploy'{& (Join-Path $scriptRoot 'DeploymentEngine.ps1') -Deploy -ImagePath $ImagePath -ImageIndex $ImageIndex -DiskNumber $DiskNumber -Firmware $Firmware -Architecture $Architecture -Confirmed};default{$hta=Join-Path $scriptRoot 'HuskagentDeployment.hta';if(Get-Command mshta.exe -ErrorAction SilentlyContinue){Start-Process mshta.exe -ArgumentList $hta -Wait}else{Write-Warning 'mshta.exe is unavailable; falling back to the Phase 1 console.';& (Join-Path $scriptRoot 'Start-Windows4Installer.ps1') -Action Inspect}}}
