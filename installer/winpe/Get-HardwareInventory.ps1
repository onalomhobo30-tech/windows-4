[CmdletBinding()]
param(
  [ValidateSet('Json','Display')][string] $OutputMode = 'Json',
  [string] $OutputPath = 'X:\Huskagent-Hardware.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FirmwareMode {
  try {
    $firmware = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -ErrorAction Stop
    if ($firmware -eq 2) { return 'UEFI' }
    if ($firmware -eq 1) { return 'BIOS' }
  } catch { }
  if ($env:firmware_type -match 'UEFI') { return 'UEFI' }
  return 'Unknown'
}

function Get-Architecture {
  $value = $env:PROCESSOR_ARCHITEW6432
  if ([string]::IsNullOrWhiteSpace($value)) { $value = $env:PROCESSOR_ARCHITECTURE }
  switch ($value.ToUpperInvariant()) {
    'AMD64' { 'x64 (64-bit)' ; break }
    'IA64' { 'x64 (64-bit)' ; break }
    'ARM64' { 'ARM64 (not supported by this media)' ; break }
    default { 'x86 (32-bit)' }
  }
}

function Convert-Size([object] $value) {
  if ($null -eq $value) { return 0 }
  return [math]::Round(([double]$value / 1GB), 2)
}

$computer = Get-CimInstance Win32_ComputerSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$disks = @(Get-Disk | ForEach-Object {
  $disk = $_
  $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | ForEach-Object {
    $partition = $_
    [pscustomobject]@{
      Number = $partition.PartitionNumber
      DriveLetter = if ($partition.DriveLetter) { [string]$partition.DriveLetter } else { '' }
      Type = [string]$partition.Type
      SizeGB = Convert-Size $partition.Size
      OffsetGB = Convert-Size $partition.Offset
      IsBoot = [bool]$partition.IsBoot
      IsSystem = [bool]$partition.IsSystem
    }
  })
  [pscustomobject]@{
    Number = [int]$disk.Number
    FriendlyName = [string]$disk.FriendlyName
    BusType = [string]$disk.BusType
    PartitionStyle = [string]$disk.PartitionStyle
    SizeGB = Convert-Size $disk.Size
    OperationalStatus = [string]$disk.OperationalStatus
    IsBoot = [bool]$disk.IsBoot
    IsSystem = [bool]$disk.IsSystem
    IsReadOnly = [bool]$disk.IsReadOnly
    Partitions = $partitions
  }
})

$usb = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object {
  $_.InterfaceType -eq 'USB' -or $_.PNPDeviceID -like 'USB*'
} | ForEach-Object {
  [pscustomobject]@{
    Model = [string]$_.Model
    DeviceId = [string]$_.DeviceID
    Interface = [string]$_.InterfaceType
    SizeGB = Convert-Size $_.Size
    PnpDeviceId = [string]$_.PNPDeviceID
  }
})

$result = [pscustomobject]@{
  SchemaVersion = 1
  CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
  Firmware = Get-FirmwareMode
  Architecture = Get-Architecture
  Computer = [pscustomobject]@{
    Manufacturer = [string]$computer.Manufacturer
    Model = [string]$computer.Model
    MemoryGB = [math]::Round(([double]$computer.TotalPhysicalMemory / 1GB), 2)
    Processor = [string]$processor.Name
    LogicalProcessors = [int]$processor.NumberOfLogicalProcessors
  }
  Disks = $disks
  UsbDevices = $usb
}

$json = $result | ConvertTo-Json -Depth 8
if ($OutputMode -eq 'Display') { $result | Format-List; $result.Disks | Format-Table -AutoSize; return }
Set-Content -Path $OutputPath -Value $json -Encoding UTF8
Write-Output $json
