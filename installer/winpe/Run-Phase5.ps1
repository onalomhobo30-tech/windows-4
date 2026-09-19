[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ImagePath,
  [int] $ImageIndex = 1,
  [ValidateSet('UEFI','BIOS','Auto')] [string] $Firmware = 'Auto',
  [ValidateSet('x86','x64','Auto')] [string] $Architecture = 'Auto',
  [Parameter(Mandatory)] [int] $DiskNumber,
  [string] $OutputPath = 'X:\Huskagent-Phase5-plan.json',
  [switch] $PlanOnly,
  [switch] $Confirmed,
  [switch] $ListImages,
  [switch] $ListTargets,
  [switch] $VerifyOnly,
  [switch] $Deploy
)

$phase5 = Join-Path $PSScriptRoot 'Deploy-SystemImage-Phase5.ps1'
if ($PlanOnly) {
  & (Join-Path $PSScriptRoot 'Test-Phase5Safe.ps1') -ImagePath $ImagePath -ImageIndex $ImageIndex -Firmware $Firmware -Architecture $Architecture -DiskNumber $DiskNumber -OutputPath $OutputPath
  exit $LASTEXITCODE
}
& $phase5 @PSBoundParameters
