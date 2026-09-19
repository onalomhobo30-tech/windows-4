# HUSKAGENT WINDOWS 4 — Phase 2 installer UI

Phase 2 preserves the Phase 1 WinPE foundation and adds a live installer UI. It does not use mock hardware data.

The WinPE UI reads its inventory from `Get-HardwareInventory.ps1`, which queries the running machine using WinPE/Windows management APIs:

- firmware mode: BIOS or UEFI
- processor architecture: x86 or x64 (and reports unsupported ARM64)
- installed RAM
- physical disks and their bus, size, status, and partition style
- partitions, drive letters, boot/system flags, offsets, and sizes
- USB disk devices and PnP identifiers

`HuskagentInstaller.hta` is an HTA graphical interface. `Start-Windows4Installer.ps1` launches it when `mshta.exe` is available and falls back to the Phase 1 console when it is not. The build script mounts `boot.wim`, adds the WinPE HTA optional component, copies the UI and inventory scripts, and updates WinPE startup.

## Build

From an elevated PowerShell prompt on a Windows technician system with the ADK Deployment Tools and Windows PE add-on installed:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\installer\\winpe\\Build-WinPE.ps1 -OutputDirectory C:\\HuskagentBuild\\WinPE
```

Use `-UsbDiskNumber N` only after identifying the removable target with `Get-Disk`. The build script refuses non-USB targets unless `-Force` is supplied.

## Safety

Inspection is the default. **Prepare target disk** is destructive: it requires a disk number and the exact confirmation `PREPARE DISK <number>`. Phase 2 still does not install an operating system, activate Windows, bypass Secure Boot, or bundle Microsoft binaries.
