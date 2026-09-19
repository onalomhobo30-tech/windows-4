[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ImagePath,
  [int] $ImageIndex = 1,
  [ValidateSet('UEFI','BIOS','Auto')] [string] $Firmware = 'Auto',
  [ValidateSet('x86','x64','Auto')] [string] $Architecture = 'Auto',
  [Parameter(Mandatory)] [int] $DiskNumber,
  [string] $OutputPath = 'X:\Huskagent-Phase5-plan.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$log = 'X:\Huskagent-Phase5-safe-test.log'

function Log([string] $Message) {
  $line = "$(Get-Date -Format o) $Message"
  Add-Content -Path $log -Value $line -Encoding UTF8
  Write-Host $line
}
function Arch([object] $Value) {
  $text = [string]$Value
  if ($text -match 'ARM64') { return 'ARM64' }
  if ($text -match '64|AMD64|X64') { return 'x64' }
  if ($text -match '86|X86|IA32') { return 'x86' }
  return 'Unknown'
}
function FirmwareMode {
  try {
    $value = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop
    if ($value -eq 2) { return 'UEFI' }
    if ($value -eq 1) { return 'BIOS' }
  } catch { }
  if ($env:firmware_type -match 'UEFI') { return 'UEFI' }
  return 'BIOS'
}
function SizeGB([object] $Value) { [math]::Round(([double]$Value / 1GB), 2) }
function Read-Image {
  if (-not (Test-Path $ImagePath -PathType Leaf)) { throw "Image not found: $ImagePath" }
  if ([IO.Path]::GetExtension($ImagePath).ToLowerInvariant() -notin @('.wim','.esd')) { throw 'Only .wim and .esd images are supported.' }
  $metadata = @(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop)
  if ($metadata.Count -eq 0) { throw 'The image contains no readable indexes.' }
  if ($ImageIndex -lt 1 -or $ImageIndex -gt $metadata.Count) { throw "Image index $ImageIndex is not valid; image count is $($metadata.Count)." }
  $selected = $metadata[$ImageIndex - 1]
  [pscustomobject]@{ Path=$ImagePath; Index=$ImageIndex; Name=[string]$selected.ImageName; Edition=[string]$selected.EditionId; Architecture=Arch $selected.Architecture; ImageCount=$metadata.Count }
}
function Read-Disk {
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $DiskNumber is the current boot/system disk." }
  if ($disk.BusType -eq 'USB') { throw "Disk $DiskNumber is USB and is not a valid OS target." }
  if ($disk.IsReadOnly) { throw "Disk $DiskNumber is read-only." }
  if ($disk.Size -lt 8GB) { throw "Disk $DiskNumber is below the 8 GB minimum." }
  $parts = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{ Number=$_.PartitionNumber; Type=[string]$_.Type; SizeGB=SizeGB $_.Size; DriveLetter=if($_.DriveLetter){[string]$_.DriveLetter}else{''}; IsBoot=[bool]$_.IsBoot; IsSystem=[bool]$_.IsSystem }
  })
  [pscustomobject]@{ Number=$DiskNumber; FriendlyName=[string]$disk.FriendlyName; BusType=[string]$disk.BusType; SizeGB=SizeGB $disk.Size; PartitionStyle=[string]$disk.PartitionStyle; Partitions=$parts }
}
function Validate-Tools {
  $tools = [ordered]@{}
  foreach ($name in 'dism.exe','bcdboot.exe','bootsect.exe') {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $command) { throw "Required deployment tool is unavailable: $name" }
    $tools[$name] = $command.Source
  }
  return [pscustomobject]$tools
}
function New-Plan([object] $Image, [object] $Disk, [object] $Tools) {
  $mode = if ($Firmware -eq 'Auto') { FirmwareMode } else { $Firmware }
  $targetArch = if ($Architecture -eq 'Auto') { Arch $env:PROCESSOR_ARCHITEW6432 } else { $Architecture }
  if ($targetArch -eq 'Unknown') { $targetArch = Arch $env:PROCESSOR_ARCHITECTURE }
  if ($Image.Architecture -eq 'ARM64') { throw 'ARM64 images are unsupported.' }
  if ($targetArch -eq 'x86' -and $Image.Architecture -eq 'x64') { throw 'An x64 image cannot target x86.' }
  $osRoot = '<OS>:\\'
  $systemRoot = if ($mode -eq 'UEFI') { '<EFI>:' } else { '<SYSTEM>:' }
  $mapping = if ($mode -eq 'UEFI') {
    [pscustomobject]@{ DiskStyle='GPT'; System='260 MB FAT32 EFI System Partition'; Reserved='16 MB GPT MSR'; OS='Remaining NTFS partition'; BootCommand="bcdboot $osRoot`Windows /s $systemRoot /f UEFI" }
  } else {
    [pscustomobject]@{ DiskStyle='MBR'; System='350 MB NTFS active System partition'; Reserved='None'; OS='Remaining NTFS partition'; BootCommand="bootsect /nt60 $systemRoot /mbr; bcdboot $osRoot`Windows /s $systemRoot /f BIOS" }
  }
  $commands = [ordered]@{
    ApplyImage = "dism.exe /Apply-Image /ImageFile:`"$($Image.Path)`" /Index:$($Image.Index) /ApplyDir:`"$osRoot`" /Quiet"
    BootConfiguration = $mapping.BootCommand
  }
  $verification = @(
    [pscustomobject]@{ Name='Windows directory'; Path="$osRoot`Windows"; Expected='Exists' },
    [pscustomobject]@{ Name='System32'; Path="$osRoot`Windows\\System32"; Expected='Exists' },
    [pscustomobject]@{ Name='Boot files'; Path="$systemRoot`bootmgr or EFI\\Microsoft\\Boot\\bootmgfw.efi"; Expected='Exists' },
    [pscustomobject]@{ Name='Deployment marker'; Path="$osRoot`HuskagentWindows4-Phase5.json"; Expected='Exists' }
  )
  [pscustomobject]@{
    Validated=$true; SafeMode='PlanOnly'; Image=$Image; Target=$Disk; Firmware=$mode; Architecture=$targetArch
    PartitionMapping=$mapping; Commands=$commands; Tools=$Tools; VerificationPlan=$verification
    Checks=[ordered]@{ ImageMetadata=$true; TargetDisk=$true; FirmwareMode=$true; Architecture=$true; DISM='available'; BCD='available'; RollbackBoundary='No mutation performed'; PostInstall='Not run: no image was applied' }
    CreatedAt=(Get-Date).ToUniversalTime().ToString('o')
  }
}

New-Item -Path $log -ItemType File -Force | Out-Null
Log 'Starting non-destructive Phase 5 deployment validation.'
try {
  $tools = Validate-Tools
  $image = Read-Image
  $disk = Read-Disk
  $plan = New-Plan $image $disk $tools
  $json = $plan | ConvertTo-Json -Depth 12
  Set-Content -Path $OutputPath -Value $json -Encoding UTF8
  Log "Validated image $($image.Path) index $($image.Index) against disk $DiskNumber without modifying storage."
  Log 'Generated DISM and BCD command plans without executing either command.'
  Log 'Safe validation completed. Partitioning, formatting, image application, bootloader writes, rollback cleanup, and post-install checks were not executed.'
  $json
} catch {
  Log "Safe validation failed: $($_.Exception.Message)"
  [pscustomobject]@{ Validated=$false; SafeMode='PlanOnly'; Error=$_.Exception.Message; CreatedAt=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -Path $OutputPath -Encoding UTF8
  throw
}
