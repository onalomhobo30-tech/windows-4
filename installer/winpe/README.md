# Safe Phase 5 validation

The safe dry-run path has been corrected and can be checked without a WIM/ESD image or physical disk mutation.

## Static validation

From a PowerShell session in the repository root:

```powershell
.\installer\winpe\Test-Phase5Scripts.ps1
```

This parses the Phase 5 scripts with PowerShell's parser and checks that the safe validation script contains no disk-mutating or deployment-execution commands.

## Live WinPE dry-run

On WinPE, with an operator-supplied image and a real target disk selected for inspection:

```powershell
X:\Run-Phase5.ps1 `
  -PlanOnly `
  -ImagePath X:\Huskagent\Images\install.wim `
  -ImageIndex 1 `
  -Firmware Auto `
  -Architecture Auto `
  -DiskNumber 1 `
  -OutputPath X:\Huskagent-Phase5-plan.json
```

The live dry-run reads real WIM/ESD metadata, firmware, architecture, disk, and partition information. It records the planned DISM and BCD commands and post-install checks but does not execute them.

No `Clear-Disk`, `Initialize-Disk`, `New-Partition`, `Remove-Partition`, `Format-Volume`, image application, `bcdboot`, `bootsect`, or rollback operation is performed by `-PlanOnly`.
