$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$log = 'X:\Windows4-Phase1.log'
Start-Transcript -Path $log -Append | Out-Null

function Show-Header {
  Clear-Host
  Write-Host 'HUSKAGENT WINDOWS 4 — PHASE 1 INSTALLER' -ForegroundColor Cyan
  Write-Host 'WinPE foundation for desktop PCs and laptops' -ForegroundColor DarkCyan
  Write-Host "Log: $log`n"
}

function Get-HardwareSummary {
  Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer, Model, TotalPhysicalMemory
  Get-CimInstance Win32_BIOS | Select-Object SerialNumber, SMBIOSBIOSVersion
  Get-CimInstance Win32_Processor | Select-Object Name, NumberOfLogicalProcessors
}

function Show-Disks {
  Get-Disk | Select-Object Number, FriendlyName, BusType, PartitionStyle, @{Name='SizeGB';Expression={[math]::Round($_.Size / 1GB, 1)}, IsBoot, IsSystem | Format-Table -AutoSize
}

function Invoke-PrepareDisk {
  $raw = Read-Host 'Enter the target disk number (or blank to cancel)'
  if ($raw -notmatch '^\d+$') { Write-Warning 'Cancelled.'; return }
  $number = [int]$raw
  $disk = Get-Disk -Number $number -ErrorAction Stop
  Show-Disks
  $confirmation = Read-Host "Type PREPARE DISK $number to erase disk $number ($($disk.FriendlyName), $([math]::Round($disk.Size / 1GB, 1)) GB)"
  if ($confirmation -cne "PREPARE DISK $number") { Write-Warning 'Confirmation did not match; no changes made.'; return }
  Write-Warning 'Phase 1 preparation will erase partitions on the selected disk.'
  Clear-Disk -Number $number -RemoveData -Confirm:$false
  Initialize-Disk -Number $number -PartitionStyle GPT
  $efi = New-Partition -DiskNumber $number -Size 260MB -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
  Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Confirm:$false | Out-Null
  $os = New-Partition -DiskNumber $number -UseMaximumSize -AssignDriveLetter
  Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'HUSKAGENT' -Confirm:$false | Out-Null
  Write-Host "Disk $number prepared as GPT/UEFI staging media. No operating system was installed." -ForegroundColor Green
}

try {
  Show-Header
  Get-HardwareSummary | Format-List
  Show-Disks
  Write-Host "`nCommands: [I] inspect again  [P] prepare a target disk  [E] exit"
  while ($true) {
    $choice = (Read-Host 'Choose an action').ToUpperInvariant()
    switch ($choice) {
      'I' { Show-Disks }
      'P' { Invoke-PrepareDisk }
      'E' { break }
      default { Write-Warning 'Choose I, P, or E.' }
    }
    if ($choice -eq 'E') { break }
  }
} finally {
  Stop-Transcript | Out-Null
}
