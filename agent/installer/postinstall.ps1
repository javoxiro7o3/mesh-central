<#
  postinstall.ps1 - EnterpriseAgent_Setup.exe ichida, SYSTEM/admin huquqi bilan ishlaydi.
  Windows 10/11 Home va Pro, Server 2016+ (PowerShell 5.1) uchun.

  Bajaradi:
    1. Agent xizmati o'rnatilganini tekshiradi, EXE yo'lini aniqlaydi
    2. Service recovery: har qanday nosozlikda 5 soniyada qayta ishga tushirish (cheksiz)
    3. Watchdog: har 1 daqiqada (va yuklanishda) xizmat to'xtagan bo'lsa ishga tushiradi
    4. Quvvat: Sleep / Hibernate / Hybrid sleep / Fast Startup o'chiriladi (BARCHA sxemalarda),
       tarmoq adapteri "quvvatni tejash uchun o'chirish" o'chiriladi
    5. Firewall: agent EXE uchun server portiga chiquvchi TCP va WebRTC UDP qoidalari
    6. Xizmatni ishga tushirib, serverga ulanishni tekshiradi

  -Uninstall: firewall qoidalari va watchdog'ni olib tashlaydi (agentni NSIS o'chiradi)
  Exit: 0 OK, 1 xizmat topilmadi, 2 xizmat ishlamayapti
#>
param(
  [Parameter(Mandatory)] [string] $ServiceName,
  [string] $Brand = 'Enterprise',
  [string] $BrandKey = 'EnterpriseAgent',
  [Parameter(Mandatory)] [string] $ServerHost,
  [int]    $ServerPort = 443,
  [string] $LogFile = "$env:ProgramData\EnterpriseAgent\install.log",
  [switch] $Uninstall,
  [switch] $SkipBatteryPowerSettings
)
$ErrorActionPreference = 'Continue'
$RuleGroup   = "$Brand Agent"
$WatchdogTask = "$BrandKey-Watchdog"

function Log([string]$m) {
  $line = "{0:yyyy-MM-dd HH:mm:ss} [ps] {1}" -f (Get-Date), $m
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}
# Tashqi dasturni xom buyruq satri bilan ishga tushirish (PowerShell 5.1 qo'shtirnoq muammolarisiz)
function Run([string]$Exe, [string]$ArgLine) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath $Exe -ArgumentList $ArgLine -Wait -PassThru -NoNewWindow `
           -RedirectStandardOutput $o -RedirectStandardError $e
    $txt = ((Get-Content $o -Raw) + ' ' + (Get-Content $e -Raw)) -replace '\s+', ' '
    Log ("{0} {1} -> exit {2} {3}" -f (Split-Path $Exe -Leaf), $ArgLine, $p.ExitCode, $txt.Trim())
  } catch { Log "$Exe $ArgLine -> $($_.Exception.Message)" }
  finally { Remove-Item $o, $e -Force -ErrorAction SilentlyContinue }
}

function Remove-AgentFirewallRules {
  if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
    Get-NetFirewallRule -Group $RuleGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
  } else {
    foreach ($n in @("$RuleGroup - TCP out", "$RuleGroup - WebRTC UDP in", "$RuleGroup - WebRTC UDP out")) {
      Run "$env:SystemRoot\System32\netsh.exe" "advfirewall firewall delete rule name=`"$n`""
    }
  }
}

# ------------------------------------------------------------------ UNINSTALL
if ($Uninstall) {
  Log "uninstall: firewall qoidalari va watchdog olib tashlanmoqda"
  Remove-AgentFirewallRules
  Run "$env:SystemRoot\System32\schtasks.exe" "/Delete /TN `"$WatchdogTask`" /F"
  exit 0
}

# ------------------------------------------------------------------ 1. xizmat
$svc = $null
for ($i = 0; $i -lt 30 -and -not $svc; $i++) {
  $svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
  if (-not $svc) { Start-Sleep -Seconds 1 }
}
if (-not $svc) { Log "ERROR: '$ServiceName' xizmati topilmadi - agent o'rnatilmagan"; exit 1 }

$exe = $svc.PathName
if ($exe -match '^\s*"([^"]+)"') { $exe = $Matches[1] } elseif ($exe -match '^\s*(\S+\.exe)') { $exe = $Matches[1] }
Log "service: $ServiceName | exe: $exe | start: $($svc.StartMode)"

# ------------------------------------------------------------------ 2. recovery (5 s)
$sc = "$env:SystemRoot\System32\sc.exe"
Run $sc "config `"$ServiceName`" start= auto"
# 3 ta harakat: restart/5000ms; keyingi har qanday nosozlikda oxirgi harakat takrorlanadi.
# reset= 86400 - xatolar hisoblagichi 1 kunda nolga tushadi.
Run $sc "failure `"$ServiceName`" reset= 86400 actions= restart/5000/restart/5000/restart/5000"
# Xizmat xato kodi bilan "toza" to'xtasa ham (crash bo'lmasa ham) recovery ishlasin
Run $sc "failureflag `"$ServiceName`" 1"

# ------------------------------------------------------------------ 3. watchdog
# Recovery faqat nosozlikda ishlaydi; kimdir xizmatni qo'lda to'xtatsa - watchdog 1 daqiqada qaytaradi.
$wdCmd = "cmd.exe /c sc.exe query $ServiceName | find \`"RUNNING\`" >nul || sc.exe start $ServiceName"
try {
  $action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ("/c sc.exe query `"$ServiceName`" | find `"RUNNING`" >nul || sc.exe start `"$ServiceName`"")
  $tBoot     = New-ScheduledTaskTrigger -AtStartup
  $tRepeat   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
  $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                 -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew -Hidden
  Register-ScheduledTask -TaskName $WatchdogTask -Action $action -Trigger @($tBoot, $tRepeat) `
    -Principal $principal -Settings $settings -Description "$Brand agent watchdog" -Force | Out-Null
  Log "watchdog task: $WatchdogTask (har 1 daqiqa + startup)"
} catch {
  Log "watchdog (ScheduledTasks moduli) xato: $($_.Exception.Message) - schtasks.exe bilan"
  Run "$env:SystemRoot\System32\schtasks.exe" "/Create /TN `"$WatchdogTask`" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F /TR `"$wdCmd`""
}

# ------------------------------------------------------------------ 4. quvvat
$pc = "$env:SystemRoot\System32\powercfg.exe"
$schemes = (& $pc /list) | Select-String -Pattern '([0-9a-fA-F-]{36})' | ForEach-Object { $_.Matches[0].Groups[1].Value }
foreach ($g in $schemes) {
  foreach ($mode in @('/setacvalueindex') + $(if ($SkipBatteryPowerSettings) { @() } else { @('/setdcvalueindex') })) {
    Run $pc "$mode $g SUB_SLEEP STANDBYIDLE 0"   # Sleep after: never
    Run $pc "$mode $g SUB_SLEEP HIBERNATEIDLE 0" # Hibernate after: never
    Run $pc "$mode $g SUB_SLEEP HYBRIDSLEEP 0"   # Hybrid sleep: off
    Run $pc "$mode $g SUB_SLEEP RTCWAKE 1"       # Wake timers: enable
  }
}
Run $pc "/setactive SCHEME_CURRENT"
Run $pc "/hibernate off"                          # hiberfil.sys + Fast Startup o'chadi
# Fast Startup (HiberbootEnabled) - alohida ham o'chiramiz
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled `
  -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null

if (Get-Command Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue) {
  Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop
      Log "NIC power-saving off: $($_.Name)"
    } catch { Log "NIC $($_.Name): $($_.Exception.Message)" }
  }
}

# ------------------------------------------------------------------ 5. firewall
Remove-AgentFirewallRules
$isIp = [System.Net.IPAddress]::TryParse($ServerHost, [ref]$null)
if (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue) {
  $common = @{ Group = $RuleGroup; Program = $exe; Profile = 'Any'; Action = 'Allow'; Enabled = 'True' }
  $tcp = @{ DisplayName = "$RuleGroup - TCP out"; Direction = 'Outbound'; Protocol = 'TCP'; RemotePort = "$ServerPort" }
  if ($isIp) { $tcp.RemoteAddress = $ServerHost }
  New-NetFirewallRule @common @tcp | Out-Null
  New-NetFirewallRule @common -DisplayName "$RuleGroup - WebRTC UDP in"  -Direction Inbound  -Protocol UDP -EdgeTraversalPolicy Allow | Out-Null
  New-NetFirewallRule @common -DisplayName "$RuleGroup - WebRTC UDP out" -Direction Outbound -Protocol UDP | Out-Null
  Log "firewall: '$RuleGroup' guruhida 3 ta qoida (TCP $ServerPort out, UDP in/out)"
} else {
  $ns = "$env:SystemRoot\System32\netsh.exe"
  $ra = $(if ($isIp) { " remoteip=$ServerHost" } else { "" })
  Run $ns "advfirewall firewall add rule name=`"$RuleGroup - TCP out`" dir=out action=allow program=`"$exe`" protocol=TCP remoteport=$ServerPort$ra profile=any enable=yes"
  Run $ns "advfirewall firewall add rule name=`"$RuleGroup - WebRTC UDP in`" dir=in action=allow program=`"$exe`" protocol=UDP edge=yes profile=any enable=yes"
  Run $ns "advfirewall firewall add rule name=`"$RuleGroup - WebRTC UDP out`" dir=out action=allow program=`"$exe`" protocol=UDP profile=any enable=yes"
}

# ------------------------------------------------------------------ 6. ishga tushirish va tekshiruv
Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
$running = $false
for ($i = 0; $i -lt 30; $i++) {
  if ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -eq 'Running') { $running = $true; break }
  Start-Sleep -Seconds 1
}
if (-not $running) { Log "ERROR: '$ServiceName' ishga tushmadi"; exit 2 }

$procId = (Get-CimInstance Win32_Service -Filter "Name='$ServiceName'").ProcessId
$connected = $false
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
  for ($i = 0; $i -lt 30; $i++) {
    if (Get-NetTCPConnection -OwningProcess $procId -RemotePort $ServerPort -State Established -ErrorAction SilentlyContinue) { $connected = $true; break }
    Start-Sleep -Seconds 1
  }
}
if ($connected) { Log "OK: agent ishlayapti (PID $procId) va ${ServerHost}:$ServerPort ga ulangan" }
else            { Log "WARN: agent ishlayapti (PID $procId), lekin 30s ichida ${ServerHost}:$ServerPort ga ulanish ko'rinmadi (tarmoq/VPN ni tekshiring; agent o'zi qayta urinadi)" }
exit 0
