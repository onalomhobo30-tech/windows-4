# HUSKAGENT WINDOWS 4 — Phase 4 media pipeline

Phase 4 preserves Phases 1–3 and adds a real, reproducible media pipeline. It does not store or redistribute Microsoft Windows binaries, licenses, product keys, or installation images. WinPE binaries are supplied at build time by the operator's locally installed Microsoft ADK and Windows PE add-on.

## Build ISO media

Run from an elevated PowerShell prompt on a Windows technician machine with ADK Deployment Tools and the Windows PE add-on installed:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\installer\\winpe\\Build-WinPE-Phase4.ps1 `
  -OutputDirectory C:\\HuskagentBuild\\Phase4-amd64 `
  -Architecture amd64 `
  -Media ISO
```

The pipeline mounts the ADK-generated `boot.wim`, adds the HTA component, copies the Phase 1–3 installer payload, validates BIOS and UEFI boot files, generates a SHA-256 manifest, and creates an ISO with both BIOS (`etfsboot.com`) and UEFI (`efisys.bin`) boot entries. A fixed ISO timestamp and sorted manifest make repeated builds auditable; ADK-generated files are still expected to vary when the ADK changes.

For x86:

```powershell
.\\installer\\winpe\\Build-WinPE-Phase4.ps1 -OutputDirectory C:\\HuskagentBuild\\Phase4-x86 -Architecture x86 -Media ISO
```

## Prepare USB media

First inspect disks and identify the removable device. The command below erases the selected USB device through `MakeWinPEMedia`; non-USB disks are refused unless `-Force` is deliberately supplied.

```powershell
Get-Disk | Format-Table Number,FriendlyName,BusType,Size
.\\installer\\winpe\\Build-WinPE-Phase4.ps1 `
  -OutputDirectory C:\\HuskagentBuild\\Phase4-amd64 `
  -Architecture amd64 `
  -Media USB `
  -UsbDiskNumber 3
```

`MakeWinPEMedia /UFD` creates the bootable USB layout from the same validated media tree. The generated UEFI and BIOS boot files are validated before USB creation.

## Validate existing media

```powershell
.\\installer\\winpe\\Test-Phase4Media.ps1 `
  -MediaRoot C:\\HuskagentBuild\\Phase4-amd64\\media `
  -Architecture amd64 `
  -ManifestPath C:\\HuskagentBuild\\Phase4-amd64\\validation.json
```

Validation checks the real `bootmgr`, BIOS BCD, `etfsboot.com`, UEFI `efisys.bin`, UEFI BCD, `boot.wim`, and every Phase 1–3 installer file. It does not invent hardware or deployment payloads.

## Outputs and safety

- `Phase4-manifest.json`: sorted SHA-256 file inventory.
- `Phase4-build-result.json`: build metadata and output paths.
- `logs/phase4-build.log`: timestamped build log.
- `HuskagentWindows4-Phase4-<architecture>.iso`: ISO output when requested.

The USB target is destructive. The pipeline never silently selects a disk and requires an explicit disk number. Phase 3 still requires `DEPLOY DISK <number>` before deployment. Microsoft image payloads remain operator-supplied and are not included in this repository.
