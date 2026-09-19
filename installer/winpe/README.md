# Safe Phase 5 validation

Phase 5 includes a non-destructive dry-run path for validating the deployment layer on real WinPE hardware. It reads real WIM/ESD metadata and real disk information but does not mutate storage.

## Dry-run command

```powershell
.\Run-Phase5.ps1 `
  -PlanOnly `
  -ImagePath X:\Huskagent\Images\install.wim `
  -ImageIndex 1 `
  -Firmware Auto `
  -Architecture Auto `
  -DiskNumber 1 `
  -OutputPath X:\Huskagent-Phase5-plan.json
```

The dry-run validates:

- PowerShell parameters and execution flow
- `.wim`/`.esd` existence and extension
- real image indexes, names, editions, and architecture metadata
- real BIOS/UEFI firmware detection
- real x86/x64 host architecture detection
- real target-disk existence, capacity, bus type, read-only state, boot/system flags, and partitions
- planned UEFI/GPT or Legacy BIOS/MBR partition mapping
- availability of `dism.exe`, `bcdboot.exe`, and `bootsect.exe`
- generated DISM image-application command
- generated UEFI and BIOS boot-configuration commands
- planned post-install verification paths
- logging and failure-result output

The resulting JSON contains `PartitionMapping`, `Commands`, `Tools`, `VerificationPlan`, and a `Checks` object. Commands are recorded only; they are never invoked by the dry-run.

## Safety guarantee

`-PlanOnly` never calls `Clear-Disk`, `Initialize-Disk`, `New-Partition`, `Remove-Partition`, `Format-Volume`, `Expand-WindowsImage`, `dism /Apply-Image`, `bcdboot`, `bootsect`, or rollback cleanup. No physical disk is erased, formatted, partitioned, or otherwise modified.

The regular deployment path remains available through `Deploy-SystemImage-Phase5.ps1 -Deploy` and retains explicit `DEPLOY DISK <number>` confirmation. Microsoft binaries, licenses, product keys, and installation images are not included.
