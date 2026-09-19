# HUSKAGENT WINDOWS 4 — Phase 3 deployment engine

Phase 3 preserves the Phase 1/2 WinPE foundation and adds a real image-based deployment engine. It does not include Microsoft Windows binaries, product keys, or licenses.

## Added capabilities

- Discovers `.wim` and `.esd` files from `X:\Sources`, `X:\Huskagent\Images`, `X:\Images`, and common mounted media paths.
- Reads image indexes and architecture through the WinPE image servicing API.
- Validates target disks before destructive work:
  - refuses current boot/system disks
  - refuses USB disks as deployment targets
  - checks read-only state and minimum capacity
  - validates x86/x64 compatibility
- Creates partitions for both firmware modes:
  - UEFI: GPT, EFI System Partition, MSR, NTFS OS partition
  - Legacy BIOS: MBR, active NTFS System Reserved partition, NTFS OS partition
- Applies an operator-selected image with `Expand-WindowsImage`.
- Configures boot files with `bcdboot` using UEFI or BIOS mode.
- Writes a deployment marker and verifies the OS directory, marker, and boot files.
- Requires the exact destructive confirmation `DEPLOY DISK <number>` before `Clear-Disk`.

## Build media

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\installer\\winpe\\Build-WinPE.ps1 -OutputDirectory C:\\HuskagentBuild\\WinPE -Architecture amd64
```

For a 32-bit WinPE build:

```powershell
.\\installer\\winpe\\Build-WinPE.ps1 -OutputDirectory C:\\HuskagentBuild\\WinPE-x86 -Architecture x86
```

Add a licensed, operator-supplied `.wim` or `.esd` under `X:\Huskagent\Images` after booting the media, then select its index in the Phase 3 UI. The USB creation safety rules from earlier phases remain unchanged.

## Safety and limitations

Inspection and image discovery never modify disks. Deployment is destructive only after disk validation and the exact confirmation phrase. The engine does not bypass Secure Boot, activate Windows, provide drivers, or claim that an arbitrary image is a Huskagent Windows 4 OS. Image signing, driver injection, product licensing, recovery workflows, and unattended deployment policy remain future work.
