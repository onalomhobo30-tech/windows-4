# HUSKAGENT WINDOWS 4 — WinPE installer foundation

This directory contains the Phase 1, x64 WinPE installer foundation for desktop PCs and laptops. It is intentionally separate from the browser desktop shell: the installer runs before Windows and prepares a target disk for a later Windows 4 deployment payload.

## Prerequisites

- A Windows technician machine (Windows 10/11).
- Windows Assessment and Deployment Kit (ADK), including **Deployment Tools**.
- Windows PE add-on for the ADK.
- Administrator PowerShell.
- A target USB drive with at least 8 GB. **The build script formats the selected USB drive.**

The ADK and WinPE add-on must be installed by the operator from Microsoft. This repository does not redistribute Microsoft binaries.

## Build the media

From an elevated PowerShell prompt on Windows:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\installer\\winpe\\Build-WinPE.ps1 -OutputDirectory C:\\HuskagentBuild\\WinPE
```

To create a USB installer, first list disks and then pass the disk number explicitly:

```powershell
Get-Disk | Format-Table Number, FriendlyName, Size, BusType
.\\installer\\winpe\\Build-WinPE.ps1 `
  -OutputDirectory C:\\HuskagentBuild\\WinPE `
  -UsbDiskNumber 3
```

The script requires `-UsbDiskNumber` for USB creation and refuses disks that are not USB unless `-Force` is supplied. It creates a GPT/UEFI FAT32 boot partition, applies the WinPE image, and copies the Phase 1 installer launcher.

## Boot flow

1. Boot a supported PC or laptop from the USB in UEFI mode.
2. The WinPE startup script launches `Start-Windows4Installer.ps1`.
3. The operator confirms the target disk and chooses **Inspect**, **Prepare**, or **Exit**.
4. Phase 1 only provides disk discovery, hardware inventory, logging, and an explicit preparation boundary. It does not claim to install an operating system until a signed deployment payload is added in a later phase.

> **Warning:** Disk preparation is destructive. The default path is inspection only. The preparation command requires the operator to type `PREPARE DISK <number>` and should only be used on a disposable or intentionally reimaged disk.

## Scope and next phase

Phase 1 establishes a repeatable, auditable WinPE boot surface. It does not include Microsoft Windows source files, product keys, drivers, activation, or a Windows 4 kernel. Phase 2 can add a signed payload manifest and deployment engine behind the existing `Invoke-Windows4Deployment` boundary.
