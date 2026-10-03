$u='https://raw.githubusercontent.com/binesheb/config_check/main/SurfaceBook3Check.ps1'
$c=Invoke-RestMethod -Uri $u -UseBasicParsing
& ([scriptblock]::Create($c)) @args