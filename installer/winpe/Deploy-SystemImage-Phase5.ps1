[CmdletBinding()]
param(
  [string] $ImagePath,
  [int] $ImageIndex = 1,
  [ValidateSet('UEFI','BIOS','Auto')] [string] $Firmware = 'Auto',
  [ValidateSet('x86','x64','Auto')] [string] $Architecture = 'Auto',
  [int] $DiskNumber = -1,
  [string] $OutputPath = 'X:\Huskagent-Phase5-Result.json',
  [switch] $Confirmed,
  [switch] $ListImages,
  [switch] $ListTargets,
  [switch] $VerifyOnly,
  [switch] $Deploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$logPath = 'X:\Huskagent-Phase5.log'

function Write-Log([string] $Message) {
  $stamp = Get-Date -Format o
  $line = "$stamp $Message"
  Write-Host $line
  try { Add-Content -Path $logPath -Value $line -Encoding UTF8 } catch { }
}

function Normalize-Architecture([string] $Value) {
  if ($null -eq $Value) { return 'Unknown' }
  $v = $Value.ToString().ToUpperInvariant()
  if ($v -match '64|AMD64|X64') { return 'x64' }
  if ($v -match '86|X86|IA32') { return 'x86' }
  if ($v -match 'ARM64') { return 'ARM64' }
  return 'Unknown'
}

function Detect-Firmware {
  try {
    $f = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'PEFirmwareType' -ErrorAction Stop
    if ($f -eq 2) { return 'UEFI' }
    if ($f -eq 1) { return 'BIOS' }
  } catch { }
  if ($env:firmware_type -match 'UEFI') { return 'UEFI' }
  return 'BIOS'
}

function Detect-Architecture {
  $chip = $env:PROCESSOR_ARCHITEW6432
  if ([string]::IsNullOrWhiteSpace($chip)) { $chip = $env:PROCESSOR_ARCHITECTURE }
  if ($chip -match '64|AMD64|IA64') { return 'x64' }
  return 'x86'
}

function Get-ImageCatalog {
  $roots = @(
    'X:\Sources',
    'X:\Images',
    'X:\Huskagent\Images',
    'C:\Sources',
    'C:\Images',
    'C:\Huskagent\Images',
    'D:\Sources',
    'D:\Images',
    'D:\Huskagent\Images',
    'E:\Sources',
    'E:\Images',
    'E:\Huskagent\Images'
  )
  $catalog = @()
  foreach ($root in $roots | Select-Object -Unique) {
    if (-not (Test-Path $root)) { continue }
    foreach ($file in @(Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.wim', '.esd' })) {
      try {
        $images = @(Get-WindowsImage -ImagePath $file.FullName -ErrorAction Stop)
        foreach ($image in $images) {
          $catalog += [pscustomobject]@{
            Path = $file.FullName
            Index = [int]$image.ImageIndex
            Name = [string]$image.ImageName
            Description = [string]$image.ImageDescription
            Edition = [string]$image.EditionId
            Architecture = Normalize-Architecture ([string]$image.Architecture)
            SizeGB = [math]::Round(([double]$file.Length / 1GB), 2)
          }
        }
      } catch {
        Write-Log "Skipped unreadable image at $($file.FullName): $($_.Exception.Message)"
      }
    }
  }
  return $catalog | Sort-Object Path, Index
}

function Get-TargetCatalog {
  return @(Get-Disk | ForEach-Object {
    $disk = $_
    $partitions = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        Number = [int]$_.PartitionNumber
        Letter = if ($_.DriveLetter) { [string]$_.DriveLetter } else { '' }
        Type = [string]$_.Type
        SizeGB = [math]::Round(([double]$_.Size / 1GB), 2)
        IsBoot = [bool]$_.IsBoot
        IsSystem = [bool]$_.IsSystem
      }
    })
    [pscustomobject]@{
      Number = [int]$disk.Number
      FriendlyName = [string]$disk.FriendlyName
      BusType = [string]$disk.BusType
      PartitionStyle = [string]$disk.PartitionStyle
      SizeGB = [math]::Round(([double]$disk.Size / 1GB), 2)
      IsBoot = [bool]$disk.IsBoot
      IsSystem = [bool]$disk.IsSystem
      IsReadOnly = [bool]$disk.IsReadOnly
      Partitions = $partitions
    }
  })
}

function Validate-ImageSelection {
  if ([string]::IsNullOrWhiteSpace($ImagePath)) { throw 'An image path is required.' }
  if (-not (Test-Path $ImagePath)) { throw "Image file not found: $ImagePath" }
  $ext = [IO.Path]::GetExtension($ImagePath).ToLowerInvariant()
  if ($ext -notin '.wim', '.esd') { throw 'The deployment image must be a .wim or .esd file.' }

  $metadata = @(Get-WindowsImage -ImagePath $ImagePath -ErrorAction Stop)
  if ($metadata.Count -eq 0) { throw "No valid Windows images were found in $ImagePath." }

  if ($ImageIndex -lt 1 -or $ImageIndex -gt $metadata.Count) { throw "Image index $ImageIndex is out of range for $ImagePath." }

  $detail = $metadata[$ImageIndex - 1]
  $imageArch = Normalize-Architecture ([string]$detail.Architecture)
  $targetArch = if ($Architecture -eq 'Auto') { Detect-Architecture } else { $Architecture }

  if ($imageArch -eq 'ARM64') { throw 'ARM64 deployment is not supported by this phase.' }
  if ($targetArch -eq 'x86' -and $imageArch -eq 'x64') { throw 'x64 image cannot be applied to an x86 target.' }
  if ($targetArch -eq 'x64' -and $imageArch -eq 'x86') {
    Write-Log 'Image architecture is x86 while target architecture is x64; deployment will still proceed only when the target hardware is a 64-bit system and the selected image is explicitly approved.'
  }

  return $detail
}

function Validate-DiskTarget {
  if ($DiskNumber -lt 0) { throw 'A valid target disk number is required.' }
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop

  if ($disk.IsBoot -or $disk.IsSystem) {
    throw "Disk $DiskNumber is the current boot or system disk. Refusing destructive deployment."
  }
  if ($disk.BusType -eq 'USB') {
    throw "Disk $DiskNumber is a USB device. Refusing deployment to removable media."
  }
  if ($disk.IsReadOnly) {
    throw "Disk $DiskNumber is read-only. Refusing deployment."
  }
  if ($disk.Size -lt 8GB) {
    throw "Disk $DiskNumber is smaller than the 8 GB minimum supported target capacity."
  }

  return $disk
}

function Confirm-DestructiveAction {
  param([int] $TargetDisk)
  if (-not $Confirmed) { throw 'Destructive disk changes require -Confirmed and exact operator confirmation.' }
  $disk = Get-Disk -Number $TargetDisk -ErrorAction Stop
  $answer = Read-Host "Type DEPLOY DISK $TargetDisk to erase $($disk.FriendlyName) ($([math]::Round($disk.Size / 1GB, 1)) GB)"
  if ($answer -cne "DEPLOY DISK $TargetDisk") {
    throw 'Confirmation did not match. No disk changes were made.'
  }
}

function New-PartitionLayout {
  param(
    [System.Object] $Disk,
    [ValidateSet('UEFI','BIOS')] [string] $Mode
  )

  if ($Mode -eq 'UEFI') {
    Clear-Disk -Number $Disk.Number -RemoveData -Confirm:$false
    Initialize-Disk -Number $Disk.Number -PartitionStyle GPT

    $efi = New-Partition -DiskNumber $Disk.Number -Size 260MB -GptType '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}'
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Confirm:$false | Out-Null

    $msr = New-Partition -DiskNumber $Disk.Number -Size 16MB -GptType '{E3C9E316-0B5C-4DB8-817D-F92DF00215AE}'
    $os = New-Partition -DiskNumber $Disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'HUSKAGENT' -Confirm:$false | Out-Null

    return [pscustomobject]@{ Efi = $efi; Msr = $msr; Os = $os; Mode = 'UEFI' }
  }

  Clear-Disk -Number $Disk.Number -RemoveData -Confirm:$false
  Initialize-Disk -Number $Disk.Number -PartitionStyle MBR

  $system = New-Partition -DiskNumber $Disk.Number -Size 350MB -IsActive
  Format-Volume -Partition $system -FileSystem NTFS -NewFileSystemLabel 'SYSTEM' -Confirm:$false | Out-Null

  $os = New-Partition -DiskNumber $Disk.Number -UseMaximumSize -AssignDriveLetter
  Format-Volume -Partition $os -FileSystem NTFS -NewFileSystemLabel 'HUSKAGENT' -Confirm:$false | Out-Null

  return [pscustomobject]@{ System = $system; Os = $os; Mode = 'BIOS' }
}

function Invoke-Rollback {
  param([int] $DiskNumber)

  Write-Log "Rollback requested for disk $DiskNumber. Best effort cleanup is in progress."
  try {
    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    if ($disk.PartitionStyle -eq 'GPT') {
      foreach ($partition in @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)) {
        Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber -Confirm:$false
      }
    }
    if ($disk.PartitionStyle -eq 'MBR') {
      foreach ($partition in @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)) {
        Remove-Partition -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber -Confirm:$false
      }
    }
    Clear-Disk -Number $DiskNumber -RemoveData -Confirm:$false
  } catch {
    Write-Log "Rollback cleanup could not complete: $($_.Exception.Message)"
  }
}

function Verify-Deployment {
  param(
    [string] $OsDrive,
    [string] $BootDrive,
    [string] $Mode
  )

  $checks = @(
    [pscustomobject]@{ Name = 'Windows directory'; Passed = Test-Path (Join-Path $OsDrive 'Windows') },
    [pscustomobject]@{ Name = 'System32'; Passed = Test-Path (Join-Path $OsDrive 'Windows\System32') },
    [pscustomobject]@{ Name = 'Boot files'; Passed = Test-Path (Join-Path $BootDrive 'bootmgr') -or (Test-Path (Join-Path $BootDrive 'EFI\Microsoft\Boot\bootmgfw.efi')) },
    [pscustomobject]@{ Name = 'Deployment marker'; Passed = Test-Path (Join-Path $OsDrive 'HuskagentWindows4-Phase5.json') }
  )

  $allPassed = ($checks | Where-Object { -not $_.Passed }).Count -eq 0
  $result = [pscustomobject]@{
    Verified = $allPassed
    Mode = $Mode
    OsDrive = $OsDrive
    BootDrive = $BootDrive
    Checks = $checks
    VerifiedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  return $result
}

function Deploy-SystemImage {
  if (-not $Deploy) { return }
  if ($DiskNumber -lt 0) { throw 'A target disk number is required for deployment.' }

  $mode = if ($Firmware -eq 'Auto') { Detect-Firmware } else { $Firmware }
  $targetArch = if ($Architecture -eq 'Auto') { Detect-Architecture } else { $Architecture }
  $image = Validate-ImageSelection
  $disk = Validate-DiskTarget

  Write-Log "Selected image: $($image.Path) index $ImageIndex edition $($image.Edition) architecture $($image.Architecture)"
  Write-Log "Target disk: $($disk.Number) $($disk.FriendlyName) ($($disk.SizeGB) GB) mode=$mode target_arch=$targetArch"

  Confirm-DestructiveAction -TargetDisk $DiskNumber

  $layout = New-PartitionLayout -Disk $disk -Mode $mode
  $osLetter = [string]$layout.Os.DriveLetter
  if (-not $osLetter) { throw 'The OS partition did not receive a drive letter.' }

  $osRoot = "$osLetter:\"
  try {
    Write-Log "Applying Windows image $ImagePath index $ImageIndex to $osRoot"
    & dism.exe /Apply-Image /ImageFile:"$ImagePath" /Index:$ImageIndex /ApplyDir:"$osRoot" /Quiet
    if ($LASTEXITCODE -ne 0) { throw "DISM apply-image failed with exit code $LASTEXITCODE." }

    if ($mode -eq 'UEFI') {
      $efiDrive = [string]$layout.Efi.DriveLetter
      if (-not $efiDrive) {
        $efiDrive = (Get-Volume -Partition $layout.Efi).DriveLetter
      }
      if ([string]::IsNullOrWhiteSpace($efiDrive)) { throw 'The UEFI system partition did not receive a drive letter.' }
      & bcdboot.exe "$osRoot\Windows" /s "$efiDrive:" /f UEFI
      if ($LASTEXITCODE -ne 0) { throw "bcdboot UEFI failed with exit code $LASTEXITCODE." }
      $bootDrive = "$efiDrive:"
    } else {
      $systemDrive = [string]$layout.System.DriveLetter
      if (-not $systemDrive) { $systemDrive = (Get-Volume -Partition $layout.System).DriveLetter }
      if ([string]::IsNullOrWhiteSpace($systemDrive)) { throw 'The BIOS system partition did not receive a drive letter.' }
      & bootsect.exe /nt60 "$systemDrive:" /mbr | Out-Null
      & bcdboot.exe "$osRoot\Windows" /s "$systemDrive:" /f BIOS
      if ($LASTEXITCODE -ne 0) { throw "bcdboot BIOS failed with exit code $LASTEXITCODE." }
      $bootDrive = "$systemDrive:"
    }

    $marker = Join-Path $osRoot 'HuskagentWindows4-Phase5.json'
    [pscustomobject]@{
      SchemaVersion = 1
      DeployedAt = (Get-Date).ToUniversalTime().ToString('o')
      ImagePath = $ImagePath
      ImageIndex = $ImageIndex
      Firmware = $mode
      Architecture = $targetArch
      DiskNumber = $DiskNumber
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $marker -Encoding UTF8

    $verification = Verify-Deployment -OsDrive $osRoot -BootDrive $bootDrive -Mode $mode
    $verification | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Log "Deployment verification: $($verification.Verified)"

    if (-not $verification.Verified) {
      throw 'Post-install verification failed.'
    }

    Write-Log "Phase 5 deployment completed successfully. Result saved to $OutputPath"
  } catch {
    Write-Log "Deployment failed: $($_.Exception.Message)"
    Invoke-Rollback -DiskNumber $DiskNumber
    $payload = [pscustomobject]@{
      Status = 'Failed'
      Error = $_.Exception.Message
      Firmware = $mode
      Architecture = $targetArch
      DiskNumber = $DiskNumber
      Image = $ImagePath
      ImageIndex = $ImageIndex
      RolledBack = $true
      Timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding UTF8
    throw
  }
}

New-Item -Path $logPath -ItemType File -Force | Out-Null
Write-Log 'Phase 5 deployment layer started.'

if ($ListImages) {
  $items = Get-ImageCatalog
  $items | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
  $items | Format-Table -AutoSize
  exit 0
}

if ($ListTargets) {
  $items = Get-TargetCatalog
  $items | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
  $items | Format-Table -AutoSize
  exit 0
}

if ($VerifyOnly) {
  if ($DiskNumber -lt 0) { throw 'A target disk number is required for verification.' }
  $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
  $osLetters = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -ExpandProperty DriveLetter)
  if (-not $osLetters) { throw 'No OS partition was found.' }
  $osDrive = "$($osLetters[0]):\"
  $bootDrive = if ((Get-Item 'X:\') -and (Test-Path 'X:\EFI')) { 'X:' } else { $osDrive }
  $verification = Verify-Deployment -OsDrive $osDrive -BootDrive $bootDrive -Mode (if ($Firmware -eq 'Auto') { Detect-Firmware } else { $Firmware })
  $verification | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
  $verification | Format-List
  exit 0
}

if ($Deploy) {
  Deploy-SystemImage
  exit 0
}

throw 'Specify -Deploy, -ListImages, -ListTargets, or -VerifyOnly.'
