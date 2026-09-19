# HUSKAGENT WINDOWS 4 — Phase 5 system-image deployment layer

Phase 5 adds the real deployment layer for an operator-supplied Windows image. It uses WinPE and DISM directly and never bundles Microsoft Windows binaries, licenses, product keys, or installation media. This repository carries the deployment tooling only; the actual image remains external and operator-provided.

## Supported deployment scenarios

- Image discovery from `X:\Sources`, `X:\Images`, `X:\Huskagent\Images`, and common removable drive paths.
- WIM/ESD discovery and image-index inspection through `Get-WindowsImage`.
- Edition and architecture validation before deployment.
- Target-disk validation before destructive operations.
- UEFI/GPT and Legacy BIOS/MBR partition creation.
- Image application with `dism.exe /Apply-Image`.
- Boot configuration with `bcdboot.exe` and `bootsect.exe`.
- Deployment logging to `X:\Huskagent-Phase5.log`.
- Rollback cleanup on failure.
- Post-install verification of the OS, boot files, and deployment marker.

## Example usage

Review available image catalog entries:

```powershell
.\installer\winpe\Deploy-SystemImage-Phase5.ps1 -ListImages -OutputPath X:\Huskagent-Phase5-Images.json
```

Review available target disks:

```powershell
.\installer\winpe\Deploy-SystemImage-Phase5.ps1 -ListTargets -OutputPath X:\Huskagent-Phase5-Targets.json
```

Deploy a selected image to disk 1:

```powershell
.\installer\winpe\Deploy-SystemImage-Phase5.ps1 `
  -ImagePath X:\Huskagent\Images\install.wim `
  -ImageIndex 1 `
  -Firmware UEFI `
  -Architecture x64 `
  -DiskNumber 1 `
  -Confirmed `
  -Deploy
```

For Legacy BIOS:

```powershell
.\installer\winpe\Deploy-SystemImage-Phase5.ps1 `
  -ImagePath X:\Huskagent\Images\install.wim `
  -ImageIndex 1 `
  -Firmware BIOS `
  -Architecture x64 `
  -DiskNumber 2 `
  -Confirmed `
  -Deploy
```

This phase preserves the earlier Phase 1–4 installer media and adds the actual system-image deployment layer. It does not change Windows licensing, bypass activation, or include a licensed installation image in the repository.
