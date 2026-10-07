[CmdletBinding()]
param(
 [decimal]$AskingPrice=0,
 [switch]$Quick,
 [string]$OutputDirectory="$env:USERPROFILE\Desktop\SurfaceBook3-Diagnostic"
)
$ErrorActionPreference='Stop'
$scriptUrl='https://github.com/binesheb/config_check/raw/refs/heads/main/SurfaceBook3Check.ps1'
function Test-Administrator {
 $id=[Security.Principal.WindowsIdentity]::GetCurrent()
 $p=New-Object Security.Principal.WindowsPrincipal($id)
 return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$tempRoot=Join-Path $env:TEMP 'SurfaceBook3Check'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$scriptPath=Join-Path $tempRoot 'SurfaceBook3Check.ps1'
try {
 Write-Host 'Downloading current diagnostic...' -ForegroundColor Cyan
 Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing -OutFile $scriptPath
 if(-not (Test-Path $scriptPath)){throw 'Diagnostic script could not be downloaded.'}
 if(-not (Test-Administrator)){
  Write-Host 'Administrator privileges are required. Requesting elevation...' -ForegroundColor Yellow
  $argList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-AskingPrice',$AskingPrice.ToString([Globalization.CultureInfo]::InvariantCulture))
  if($Quick){$argList += '-Quick'}
  if($OutputDirectory){$argList += @('-OutputDirectory',$OutputDirectory)}
  $p=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $argList -Wait -PassThru
  exit $p.ExitCode
 }
 & $scriptPath -AskingPrice $AskingPrice -Quick:$Quick -OutputDirectory $OutputDirectory
 exit $LASTEXITCODE
}
catch {
 Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
 Write-Host 'The diagnostic did not complete.' -ForegroundColor Red
 exit 1
}