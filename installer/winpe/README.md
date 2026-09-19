# Safe Phase 5 validation

Phase 5 now includes a non-destructive validation path. It uses the real WinPE host, real WIM/ESD metadata, real firmware detection, real target-disk information, and real availability of DISM/BCDBoot/Bootsect. It does not call `Clear-Disk`, `Initialize-Disk`, `New-Partition`, `Format-Volume`, image application, BCD writes, or rollback cleanup.

## Run the safe plan

Boot the Phase 5 WinPE media, attach an operator-supplied image, then run:

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

The command validates:

- WIM/ESD extension and file existence
- real image indexes, edition metadata, and architecture
- real BIOS/UEFI mode
- real x86/x64 host compatibility
- real target disk existence, capacity, bus type, read-only state, boot/system flags, and current partitions
- planned UEFI/GPT or BIOS/MBR partition mapping
- availability of DISM, BCDBoot, and Bootsect
- safe rollback boundary and verification status

It writes a JSON plan and `X:\Huskagent-Phase5-safe-test.log`. The output explicitly reports that image application, partition mutation, bootloader writes, rollback cleanup, and post-install verification were not executed.

## Testing guarantees

- No disk is erased.
- No partition is created, formatted, or removed.
- No image is applied.
- No BCD store is changed.
- No rollback cleanup is invoked.
- No mock hardware, image metadata, or disk data is used.

The existing deployment path remains available through `Deploy-SystemImage-Phase5.ps1 -Deploy`; it still requires the existing explicit `DEPLOY DISK <number>` confirmation. Phase 1–4 files and behavior are preserved.
