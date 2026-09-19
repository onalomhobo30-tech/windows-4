[CmdletBinding()]
param(
  [string] $ImagePath,
  [int] $ImageIndex = 1,
  [ValidateSet('UEFI','BIOS','Auto')] [string] $Firmware = 'Auto',
  [ValidateSet('x86','x64','Auto')] [string] $Architecture = 'Auto',
  [int] $DiskNumber = -1,
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
  if ([string]::IsNullOrWhiteSpace($ImagePath)) { throw '-ImagePath is required with -PlanOnly.' }
  if ($DiskNumber -lt 0) { throw '-DiskNumber must identify a disk for -PlanOnly.' }
  & (Join-Path $PSScriptRoot 'Test-Phase5Safe.ps1') -ImagePath $ImagePath -ImageIndex $ImageIndex -Firmware $Firmware -Architecture $Architecture -DiskNumber $DiskNumber -OutputPath $OutputPath
  exit $LASTEXITCODE
}
$params = @{}
foreach ($name in 'ImagePath','ImageIndex','Firmware','Architecture','DiskNumber','OutputPath','Confirmed','ListImages','ListTargets','VerifyOnly','Deploy') {
  $value = Get-Variable -Name $name -ValueOnly
  if ($value -is [switch]) { if ($value.IsPresent) { $params[$name] = $true } }
  elseif ($name -eq 'ImagePath' -and -not [string]::IsNullOrWhiteSpace($value)) { $params[$name] = $value }
  elseif ($name -eq 'DiskNumber' -and $value -ge 0) { $params[$name] = $value }
  elseif ($name -notin @('ImagePath','DiskNumber','OutputPath') -and $null -ne $value) { $params[$name] = $value }
  elseif ($name -eq 'OutputPath') { $params[$name] = $value }
}
& $phase5 @params
exit $LASTEXITCODE
