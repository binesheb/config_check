[CmdletBinding()]
param(
 [decimal]$AskingPrice=0,
 [switch]$Quick,
 [string]$OutputDirectory="$env:USERPROFILE\Desktop\SurfaceBook3-Diagnostic"
)
$ErrorActionPreference='SilentlyContinue'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$Results=@();$Critical=@();$Warnings=@()
function Add-Check {
 param([string]$Category,[string]$Test,[string]$Status,[string]$Value,[string]$Details='')
 $script:Results += [pscustomobject]@{Category=$Category;Test=$Test;Status=$Status;Value=$Value;Details=$Details}
 Write-Host ("[{0}] {1}: {2}" -f $Status,$Test,$Value)
 if($Status -eq 'FAIL'){$script:Critical += "$Category / $Test : $Details"}
 elseif($Status -eq 'WARN'){$script:Warnings += "$Category / $Test : $Details"}
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
$admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$cs=Get-CimInstance Win32_ComputerSystem
$bios=Get-CimInstance Win32_BIOS
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$os=Get-CimInstance Win32_OperatingSystem
Add-Check Identity Model $(if($cs.Model -match 'Surface Book 3'){'PASS'}else{'FAIL'}) $cs.Model 'Expected Surface Book 3'
Add-Check Identity Serial 'INFO' $bios.SerialNumber
$ram=[math]::Round($cs.TotalPhysicalMemory/1GB,1)
Add-Check Identity RAM $(if($ram -ge 31){'PASS'}elseif($ram -ge 15){'WARN'}else{'FAIL'}) "$ram GB" 'Target 32 GB'
$cpuName=$cpu.Name.Trim()
Add-Check CPU Processor $(if($cpuName -match 'i7-1065G7'){'PASS'}else{'WARN'}) $cpuName 'Target i7-1065G7'
$gpus=Get-CimInstance Win32_VideoController
$gpuText=($gpus | ForEach-Object {"$($_.Name) [$([math]::Round($_.AdapterRAM/1GB,1)) GB]"}) -join '; '
Add-Check GPU Adapter $(if($gpus.Name -match 'GTX 1660 Ti'){'PASS'}elseif($gpus.Name -match 'NVIDIA'){'WARN'}else{'FAIL'}) $gpuText 'Target GTX 1660 Ti 6 GB'
$display=$gpus | Sort-Object CurrentHorizontalResolution -Descending | Select-Object -First 1
$resolution="$($display.CurrentHorizontalResolution)x$($display.CurrentVerticalResolution) @ $($display.CurrentRefreshRate)Hz"
Add-Check Display Resolution $(if($display.CurrentHorizontalResolution -eq 3240 -and $display.CurrentVerticalResolution -eq 2160){'PASS'}else{'WARN'}) $resolution '15-inch reference 3240x2160'
Add-Check Display PhysicalAndTouch 'MANUAL' 'CHECKLIST' 'Run manual checks'
$disks=Get-PhysicalDisk
foreach($disk in $disks){
 $status=if($disk.HealthStatus -eq 'Healthy'){'PASS'}elseif($disk.HealthStatus -eq 'Warning'){'WARN'}else{'FAIL'}
 Add-Check Storage $disk.FriendlyName $status "$($disk.MediaType) / $([math]::Round($disk.Size/1GB)) GB / $($disk.HealthStatus)" ($disk.OperationalStatus -join ',')
}
$c=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$free=if($c.Size){[math]::Round(100*$c.FreeSpace/$c.Size,1)}else{0}
Add-Check Storage 'C: free space' $(if($free -ge 20){'PASS'}elseif($free -ge 10){'WARN'}else{'FAIL'}) "$free%"
if($admin -and -not $Quick){
 $scan=chkdsk C: /scan 2>&1 | Out-String
 $scan | Set-Content "$OutputDirectory\chkdsk-scan.txt" -Encoding UTF8
 Add-Check Windows CHKDSK $(if($scan -match 'found problems|corrupt|cannot continue'){'FAIL'}else{'PASS'}) 'Completed' 'See chkdsk-scan.txt'
 $dism=dism /online /cleanup-image /checkhealth 2>&1 | Out-String
 $dism | Set-Content "$OutputDirectory\dism.txt" -Encoding UTF8
 Add-Check Windows DISM $(if($dism -match 'No component store corruption detected'){'PASS'}else{'WARN'}) 'Completed' 'See dism.txt'
 $sfc=sfc /verifyonly 2>&1 | Out-String
 $sfc | Set-Content "$OutputDirectory\sfc.txt" -Encoding UTF8
 Add-Check Windows SFC $(if($sfc -match 'did not find any integrity violations'){'PASS'}elseif($sfc -match 'found integrity violations'){'FAIL'}else{'WARN'}) 'Completed' 'See sfc.txt'
}else{
 Add-Check Windows ElevatedChecks 'WARN' 'Skipped' 'Run PowerShell as Administrator'
}
$static=Get-CimInstance -Namespace root\wmi -Class BatteryStaticData
$full=Get-CimInstance -Namespace root\wmi -Class BatteryFullChargedCapacity
$cycle=Get-CimInstance -Namespace root\wmi -Class BatteryCycleCount
$batteryHealth=@()
if($static){
 foreach($b in $static){
  $f=$full | Where-Object {$_.Tag -eq $b.Tag} | Select-Object -First 1
  $cy=$cycle | Where-Object {$_.Tag -eq $b.Tag} | Select-Object -First 1
  $health=if($b.DesignedCapacity -and $f.FullChargedCapacity){[math]::Round(100*$f.FullChargedCapacity/$b.DesignedCapacity,1)}else{$null}
  if($null -ne $health){$batteryHealth += [double]$health}
  $status=if($null -eq $health){'WARN'}elseif($health -ge 80){'PASS'}elseif($health -ge 60){'WARN'}else{'FAIL'}
  Add-Check Battery $b.Tag $status "$health% / $($cy.CycleCount) cycles" "Design $([math]::Round($b.DesignedCapacity/1000)) Wh; Full $([math]::Round($f.FullChargedCapacity/1000)) Wh"
 }
}else{
 Add-Check Battery 'Battery WMI data' 'WARN' 'Unavailable' 'Firmware did not expose Surface battery details'
}
$minBattery=if($batteryHealth.Count){($batteryHealth | Measure-Object -Minimum).Minimum}else{0}
$batteryReport="$OutputDirectory\battery-report.html"
powercfg /batteryreport /output $batteryReport | Out-Null
Add-Check Battery 'Minimum health' $(if($minBattery -ge 80){'PASS'}elseif($minBattery -ge 60){'WARN'}else{'FAIL'}) "$minBattery%"
Add-Check Battery Report $(if(Test-Path $batteryReport){'PASS'}else{'WARN'}) $batteryReport
$pnp=@(Get-PnpDevice | Where-Object {$_.Status -ne 'OK'})
Add-Check Devices PnPErrors $(if(!$pnp.Count){'PASS'}else{'FAIL'}) "$($pnp.Count) non-OK devices"
if($pnp.Count){$pnp | Select-Object Status,Class,FriendlyName,InstanceId | Export-Csv "$OutputDirectory\device-errors.csv" -NoTypeInformation}
$events=@()
$since=(Get-Date).AddDays(-14)
foreach($log in 'System','Application'){
 $events += @(Get-WinEvent -FilterHashtable @{LogName=$log;StartTime=$since;Level=1,2} -MaxEvents 100)
}
Add-Check Stability 'Critical/error events 14d' $(if($events.Count -lt 10){'PASS'}elseif($events.Count -lt 30){'WARN'}else{'FAIL'}) "$($events.Count) events"
if($events.Count){$events | Select-Object TimeCreated,LogName,ProviderName,Id,LevelDisplayName,Message | Export-Csv "$OutputDirectory\critical-events.csv" -NoTypeInformation}
$score=0
if($cs.Model -match 'Surface Book 3'){$score+=10}
if($cpuName -match 'i7-1065G7'){$score+=8}
if($ram -ge 31){$score+=7}
if($gpus.Name -match 'GTX 1660 Ti'){$score+=15}elseif($gpus.Name -match 'NVIDIA'){$score+=8}
if($minBattery -ge 90){$score+=20}elseif($minBattery -ge 80){$score+=17}elseif($minBattery -ge 70){$score+=13}elseif($minBattery -ge 60){$score+=7}else{$score+=2}
if($disks.Count -and @($disks | Where-Object {$_.HealthStatus -eq 'Healthy'}).Count -eq $disks.Count){$score+=12}
if($free -ge 20){$score+=5}elseif($free -ge 10){$score+=3}
if(!$pnp.Count){$score+=8}elseif($pnp.Count -lt 3){$score+=4}
if($events.Count -lt 10){$score+=7}elseif($events.Count -lt 30){$score+=3}
if($resolution -like '3240x2160*'){$score+=8}else{$score+=4}
$score=[math]::Min(100,$score)
$ceiling=if($score -ge 90){54000}elseif($score -ge 80){50000}elseif($score -ge 70){44000}elseif($score -ge 60){37000}else{30000}
if($minBattery -lt 60){$ceiling-=8000}elseif($minBattery -lt 70){$ceiling-=5000}elseif($minBattery -lt 80){$ceiling-=2500}
$ceiling=[math]::Max(20000,[math]::Round($ceiling,-3))
if(-not $AskingPrice){
 $priceText=Read-Host 'Seller asking price in INR (Enter to skip)'
 $parsed=0
 if($priceText -and [decimal]::TryParse(($priceText -replace '[₹,\s]',''),[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)){$AskingPrice=$parsed}
}
$verdict=if($Critical.Count){'WALK AWAY / FIX ISSUES'}elseif($AskingPrice -and $score -ge 85 -and $AskingPrice -le $ceiling){'BUY'}elseif($score -lt 60 -or ($AskingPrice -and $AskingPrice -gt ($ceiling+8000))){'WALK AWAY'}else{'NEGOTIATE'}
$summary=[pscustomobject]@{Timestamp=(Get-Date).ToString('s');Model=$cs.Model;Serial=$bios.SerialNumber;CPU=$cpuName;RAM_GB=$ram;GPU=$gpuText;Resolution=$resolution;MinBatteryHealth=$minBattery;FreeSpacePercent=$free;PnPErrorCount=$pnp.Count;CriticalErrorEvents14d=$events.Count;HealthScore=$score;AskingPrice=$AskingPrice;PriceCeiling=$ceiling;Verdict=$verdict}
$summary | ConvertTo-Json | Set-Content "$OutputDirectory\summary.json" -Encoding UTF8
$Results | Export-Csv "$OutputDirectory\results.csv" -NoTypeInformation -Encoding UTF8
@'
# Surface Book 3 Manual Checklist
- [ ] No battery swelling or display lifting
- [ ] No cracked display
- [ ] Black/white/red/green/blue pixel test
- [ ] Touch works across full screen; no ghost touch
- [ ] Keyboard every key
- [ ] Trackpad click and gestures
- [ ] Front/rear cameras and Windows Hello
- [ ] Speakers and microphones
- [ ] Wi-Fi and Bluetooth
- [ ] USB-A x2, USB-C, SD, 3.5mm
- [ ] Surface Connect base and tablet charging
- [ ] Detach and reattach twice
- [ ] GTX 1660 Ti returns after reattach
- [ ] Charging remains stable while hinge moves
- [ ] Serial matches seller paperwork
- [ ] No BIOS password / organization lock
- [ ] Seller permits full testing and return
## Walk away
Swelling, display lifting, missing GPU, detach failure, intermittent charging, SSD failure, repeated WHEA/storage/display errors, unexplained shutdowns.
'@ | Set-Content "$OutputDirectory\MANUAL-CHECKLIST.md" -Encoding UTF8
Write-Host ''
Write-Host '============= RESULT =============' -ForegroundColor Cyan
Write-Host "Model:         $($cs.Model)"
Write-Host "CPU:           $cpuName"
Write-Host "RAM:           $ram GB"
Write-Host "GPU:           $gpuText"
Write-Host "Display:       $resolution"
Write-Host "Min battery:   $minBattery%"
Write-Host "Health score:  $score / 100"
if($AskingPrice){Write-Host "Asking:        ₹$AskingPrice"}
Write-Host "Price ceiling: ₹$ceiling"
Write-Host "VERDICT:       $verdict" -ForegroundColor $(if($verdict -eq 'BUY'){'Green'}elseif($verdict -eq 'NEGOTIATE'){'Yellow'}else{'Red'})
Write-Host "Reports:       $OutputDirectory" -ForegroundColor Green