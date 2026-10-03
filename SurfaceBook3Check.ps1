[CmdletBinding()]param([decimal]$AskingPrice=0,[switch]$Quick,[string]$OutputDirectory="$env:USERPROFILEDesktopSurfaceBook3-Diagnostic")
$ErrorActionPreference='SilentlyContinue'
New-Item -ItemType Directory -Force $OutputDirectory|Out-Null
$R=@();$Critical=@();$Warnings=@()
function T($c,$t,$s,$v,$d=''){ $script:R+=[pscustomobject]@{Category=$c;Test=$t;Status=$s;Value=$v;Details=$d};Write-Host ("[{0}] {1}: {2}"-f $s,$t,$v);if($s-eq'FAIL'){$script:Critical+="$c / $t : $d"}elseif($s-eq'WARN'){$script:Warnings+="$c / $t : $d"}}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$cs=Get-CimInstance Win32_ComputerSystem;$bios=Get-CimInstance Win32_BIOS;$cpu=Get-CimInstance Win32_Processor|select -First 1;$os=Get-CimInstance Win32_OperatingSystem
T Identity Model ($(if($cs.Model-match'Surface Book 3'){'PASS'}else{'FAIL'})) $cs.Model 'Expected Surface Book 3'
T Identity Serial INFO $bios.SerialNumber
$ram=[math]::Round($cs.TotalPhysicalMemory/1GB,1);T Identity RAM ($(if($ram-ge31){'PASS'}elseif($ram-ge15){'WARN'}else{'FAIL'})) "$ram GB" 'Target 32 GB'
$cpuName=$cpu.Name.Trim();T CPU Processor ($(if($cpuName-match'i7-1065G7'){'PASS'}else{'WARN'})) $cpuName 'Target i7-1065G7'
$g=Get-CimInstance Win32_VideoController;$gt=($g|%{"$($_.Name) [$([math]::Round($_.AdapterRAM/1GB,1)) GB]"})-join '; ';T GPU Adapter ($(if($g.Name-match'GTX 1660 Ti'){'PASS'}elseif($g.Name-match'NVIDIA'){'WARN'}else{'FAIL'})) $gt 'Target GTX 1660 Ti 6 GB'
$d=$g|sort CurrentHorizontalResolution -Descending|select -First 1;$res="$($d.CurrentHorizontalResolution)x$($d.CurrentVerticalResolution) @ $($d.CurrentRefreshRate)Hz";T Display Resolution ($(if($d.CurrentHorizontalResolution-eq3240-and$d.CurrentVerticalResolution-eq2160){'PASS'}else{'WARN'})) $res '15-inch reference 3240x2160';T Display Physical/Touch MANUAL 'CHECKLIST' 'Test manually'
$pd=Get-PhysicalDisk;foreach($x in $pd){T Storage $x.FriendlyName ($(if($x.HealthStatus-eq'Healthy'){'PASS'}elseif($x.HealthStatus-eq'Warning'){'WARN'}else{'FAIL'})) "$($x.MediaType) / $([math]::Round($x.Size/1GB)) GB / $($x.HealthStatus)"}
$c=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'";$free=[math]::Round(100*$c.FreeSpace/$c.Size,1);T Storage 'C: free' ($(if($free-ge20){'PASS'}elseif($free-ge10){'WARN'}else{'FAIL'})) "$free%"
if($admin-and-not$Quick){$scan=chkdsk C: /scan 2>&1|Out-String;$scan|Set-Content "$OutputDirectorychkdsk-scan.txt";T Windows CHKDSK ($(if($scan-match'found problems|corrupt|cannot continue'){'FAIL'}else{'PASS'})) Completed
$dism=dism /online /cleanup-image /checkhealth 2>&1|Out-String;$dism|Set-Content "$OutputDirectorydism.txt";T Windows DISM ($(if($dism-match'No component store corruption detected'){'PASS'}else{'WARN'})) Completed
$sfc=sfc /verifyonly 2>&1|Out-String;$sfc|Set-Content "$OutputDirectorysfc.txt";T Windows SFC ($(if($sfc-match'did not find any integrity violations'){'PASS'}elseif($sfc-match'found integrity violations'){'FAIL'}else{'WARN'})) Completed}else{T Windows ElevatedChecks WARN Skipped 'Run as Administrator without -Quick'}
$st=Get-CimInstance -Namespace rootwmi -Class BatteryStaticData;$fc=Get-CimInstance -Namespace rootwmi -Class BatteryFullChargedCapacity;$cc=Get-CimInstance -Namespace rootwmi -Class BatteryCycleCount;$bh=@()
if($st){foreach($b in $st){$f=$fc|? Tag-eq$b.Tag|select -First 1;$cy=$cc|? Tag-eq$b.Tag|select -First 1;$h=if($b.DesignedCapacity-and$f.FullChargedCapacity){[math]::Round(100*$f.FullChargedCapacity/$b.DesignedCapacity,1)}else{$null};$bh+=$h;T Battery $b.Tag ($(if($null-eq$h){'WARN'}elseif($h-ge80){'PASS'}elseif($h-ge60){'WARN'}else{'FAIL'})) "$h% / $($cy.CycleCount) cycles"}}
else{foreach($b in Get-CimInstance Win32_Battery){$h=if($b.DesignCapacity){[math]::Round(100*$b.FullChargeCapacity/$b.DesignCapacity,1)}else{$null};$bh+=$h;T Battery $b.DeviceID ($(if($h-ge80){'PASS'}elseif($h-ge60){'WARN'}else{'FAIL'})) "$h%"}}
$min=if($bh.Count){($bh|measure -Minimum).Minimum}else{0};$br="$OutputDirectoryattery-report.html";powercfg /batteryreport /output $br|Out-Null;T Battery MinimumHealth ($(if($min-ge80){'PASS'}elseif($min-ge60){'WARN'}else{'FAIL'})) "$min%";T Battery Report ($(if(Test-Path$br){'PASS'}else{'WARN'})) $br
$pnp=@(Get-PnpDevice|? Status-ne'OK');T Devices PnPErrors ($(if(!$pnp.Count){'PASS'}else{'FAIL'})) "$($pnp.Count) non-OK devices";if($pnp.Count){$pnp|select Status,Class,FriendlyName,InstanceId|Export-Csv "$OutputDirectorydevice-errors.csv" -NoTypeInformation}
$ev=@();$since=(Get-Date).AddDays(-14);foreach($l in 'System','Application'){$ev+=@(Get-WinEvent -FilterHashtable @{LogName=$l;StartTime=$since;Level=1,2}-MaxEvents 100)};T Stability ErrorEvents14d ($(if($ev.Count-lt10){'PASS'}elseif($ev.Count-lt30){'WARN'}else{'FAIL'})) "$($ev.Count)"
if($ev.Count){$ev|select TimeCreated,LogName,ProviderName,Id,LevelDisplayName,Message|Export-Csv "$OutputDirectorycritical-events.csv" -NoTypeInformation}
$score=0;if($cs.Model-match'Surface Book 3'){$score+=10};if($cpuName-match'i7-1065G7'){$score+=8};if($ram-ge31){$score+=7};if($g.Name-match'GTX 1660 Ti'){$score+=15}elseif($g.Name-match'NVIDIA'){$score+=8};if($min-ge90){$score+=20}elseif($min-ge80){$score+=17}elseif($min-ge70){$score+=13}elseif($min-ge60){$score+=7}else{$score+=2};if($pd.Count-and@($pd|? HealthStatus-eq'Healthy').Count-eq$pd.Count){$score+=12};if($free-ge20){$score+=5}elseif($free-ge10){$score+=3};if(!$pnp.Count){$score+=8}elseif($pnp.Count-lt3){$score+=4};if($ev.Count-lt10){$score+=7}elseif($ev.Count-lt30){$score+=3};if($res-like'3240x2160*'){$score+=8}else{$score+=4};$score=[math]::Min(100,$score)
$cap=if($score-ge90){54000}elseif($score-ge80){50000}elseif($score-ge70){44000}elseif($score-ge60){37000}else{30000};if($min-lt60){$cap-=8000}elseif($min-lt70){$cap-=5000}elseif($min-lt80){$cap-=2500};$cap=[math]::Max(20000,[math]::Round($cap,-3))
$p=if($AskingPrice){$AskingPrice}else{0};$verdict=if($Critical.Count){'WALK AWAY / FIX ISSUES'}elseif($p-and$score-ge85-and$p-le$cap){'BUY'}elseif($score-lt60-or($p-and$p-gt($cap+8000))){'WALK AWAY'}else{'NEGOTIATE'}
$sum=[pscustomobject]@{Timestamp=(Get-Date).ToString('s');Model=$cs.Model;Serial=$bios.SerialNumber;CPU=$cpuName;RAM_GB=$ram;GPU=$gt;Resolution=$res;MinBatteryHealth=$min;FreeSpacePercent=$free;PnPErrorCount=$pnp.Count;CriticalErrorEvents14d=$ev.Count;HealthScore=$score;AskingPrice=$p;PriceCeiling=$cap;Verdict=$verdict}
$sum|ConvertTo-Json|Set-Content "$OutputDirectorysummary.json";$R|Export-Csv "$OutputDirectoryesults.csv" -NoTypeInformation
@'
# Surface Book 3 Manual Checklist
- [ ] No battery swelling or display lifting
- [ ] No cracked display
- [ ] Test black/white/red/green/blue full-screen images for dead/stuck pixels
- [ ] Touch works across the full panel; no ghost touch
- [ ] Keyboard every key / trackpad
- [ ] Cameras / Windows Hello / speakers / microphones
- [ ] Wi-Fi / Bluetooth
- [ ] USB-A x2 / USB-C / SD / 3.5mm
- [ ] Surface Connect base and tablet
- [ ] Detach and reattach twice; GPU returns
- [ ] Charger stable while hinge moves
- [ ] Serial matches paperwork
- [ ] No BIOS/organization lock
- [ ] Seller permits full test/return
## Walk away
Swelling, display lifting, missing GPU, detach failure, intermittent charging, SSD failure, repeated WHEA/storage/display errors or unexplained shutdowns.
'@|Set-Content "$OutputDirectoryMANUAL-CHECKLIST.md"
Write-Host "";Write-Host "VERDICT: $verdict" -ForegroundColor Cyan;Write-Host "SCORE: $score/100";Write-Host "PRICE CEILING: ₹$cap";Write-Host "REPORTS: $OutputDirectory"