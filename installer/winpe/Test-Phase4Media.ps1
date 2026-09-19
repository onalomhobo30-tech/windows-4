[CmdletBinding()]
param([Parameter(Mandatory)][string]$MediaRoot,[Parameter(Mandatory)][ValidateSet('amd64','x86')][string]$Architecture,[string]$ManifestPath)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$required=@('bootmgr','boot\BCD','boot\etfsboot.com','efi\microsoft\boot\efisys.bin','efi\microsoft\boot\BCD','sources\boot.wim')
foreach($name in $required){$path=Join-Path $MediaRoot $name;if(-not(Test-Path $path -PathType Leaf)){throw "Missing boot file: $name"}}
$payload=@('Start-Windows4Installer.ps1','Get-HardwareInventory.ps1','DeploymentEngine.ps1','HuskagentInstaller.hta','HuskagentDeployment.hta','Windows4Installer.cmd')
foreach($name in $payload){if(-not(Test-Path (Join-Path $MediaRoot $name) -PathType Leaf)){throw "Missing installer payload: $name"}}
$wim=Get-Item (Join-Path $MediaRoot 'sources\boot.wim');if($wim.Length -le 0){throw 'boot.wim is empty.'}
$files=Get-ChildItem $MediaRoot -Recurse -File|Sort-Object FullName|ForEach-Object{[pscustomobject]@{Path=$_.FullName.Substring($MediaRoot.Length).TrimStart('\').Replace('\','/');Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}}
$result=[pscustomobject]@{SchemaVersion=1;Architecture=$Architecture;BootFilesValid=$true;PayloadFilesValid=$true;ValidatedAt=(Get-Date).ToUniversalTime().ToString('o');Files=$files}
if($ManifestPath){$result|ConvertTo-Json -Depth 8|Set-Content $ManifestPath -Encoding UTF8};$result|ConvertTo-Json -Depth 8
