# FRS Network Watcher v6 - Windows PowerShell 5.1
# WSL-AutoStart must run persistently under the same Windows account as Ubuntu-22.04.
# WARNING: wsl --shutdown stops ALL WSL distributions and their workloads.
param(
    [string]$Server = '10.244.201.165',
    [int]$Port = 7447,
    [string]$Distro = 'Ubuntu-22.04',
    [string]$KeepAliveTaskName = 'WSL-AutoStart',
    [int]$IntervalSeconds = 10,
    [int]$FailureThreshold = 6,
    [int]$RecoveryCooldownMinutes = 30,
    [int]$VerifyTimeoutSeconds = 180,
    [bool]$EnableAutoRecovery = $true
)
$ErrorActionPreference = 'Stop'
$LogDir = Join-Path $env:ProgramData 'FRSNetworkWatch'
$LogFile = Join-Path $LogDir 'watch.log'
$MaintFlag = Join-Path $LogDir 'maintenance.flag'
$CooldownFile = Join-Path $LogDir 'last-recovery.txt'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$mutex = New-Object System.Threading.Mutex($false, 'Global\FRSNetworkWatch')
$hasMutex = $false
try { $hasMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }
if (-not $hasMutex) { Write-Host 'FRS watcher already running'; $mutex.Dispose(); exit 2 }
function Write-Log([string]$Message) {
    try { if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 10MB) { Move-Item $LogFile ($LogFile + '.1') -Force } } catch {}
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}
function Test-WindowsTcp {
    $client = $null; $handle = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $ar = $client.BeginConnect($Server, $Port, $null, $null)
        $handle = $ar.AsyncWaitHandle
        if (-not $handle.WaitOne(3000, $false)) { return $false }
        $client.EndConnect($ar)
        return $true
    } catch { return $false } finally {
        if ($handle) { $handle.Close() }
        if ($client) { $client.Close() }
    }
}
function Test-WslTcp {
    # PowerShell 5.1 may promote native stderr to an error with Stop.
    $ErrorActionPreference = 'Continue'
    # IMPORTANT: use the known-working direct invocation, not Start-Process/CreateNoWindow.
    # nc -v supplies useful failure diagnostics. Exit -1 is a probe error, NOT a TCP failure.
    try {
        $output = @(& wsl.exe -d $Distro --exec /usr/bin/nc -vz -w 3 $Server $Port 2>&1)
        $code = $LASTEXITCODE
        $detail = (($output | Out-String).Trim() -replace '[\r\n]+', ' ')
        if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) }
        if ($code -eq 0) { return @{ Kind='OK'; Detail='' } }
        if ($code -eq 1 -and $detail -match 'Connection refused|timed out|No route to host|Network is unreachable|Host is unreachable|Connection reset|Operation now in progress|Name or service not known') {
            return @{ Kind='TCP_FAIL'; Detail="exit=$code $detail" }
        }
        return @{ Kind='PROBE_ERROR'; Detail="exit=$code $detail" }
    } catch {
        return @{ Kind='PROBE_ERROR'; Detail=$_.Exception.Message }
    }
}
function Ensure-KeepAliveTask([string]$Reason) {
    try {
        $task = Get-ScheduledTask -TaskName $KeepAliveTaskName -ErrorAction Stop
        if ($task.State -eq 'Disabled') { Write-Log "KEEPALIVE_DISABLED name=$KeepAliveTaskName"; return }
        if ($task.State -ne 'Running') {
            Start-ScheduledTask -TaskName $KeepAliveTaskName -ErrorAction Stop
            Write-Log "KEEPALIVE_STARTED reason=$Reason previousState=$($task.State)"
        }
    } catch { Write-Log "KEEPALIVE_ERROR $($_.Exception.Message)" }
}
function Get-LastRecovery {
    if (-not (Test-Path $CooldownFile)) { return [datetime]::MinValue }
    try { return [datetime]::ParseExact((Get-Content $CooldownFile -Raw).Trim(), 'o', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
    catch { return [datetime]::MinValue }
}
function Invoke-Recovery {
    $ErrorActionPreference = 'Continue'
    # Recheck immediately before disrupting WSL.
    if (-not (Test-WindowsTcp)) { Write-Log 'RECOVERY_ABORT windows_tcp_not_ok'; return }
    $confirm = Test-WslTcp
    if ($confirm.Kind -ne 'TCP_FAIL') { Write-Log "RECOVERY_ABORT recheck=$($confirm.Kind) detail=[$($confirm.Detail)]"; return }
    $now = Get-Date
    $last = Get-LastRecovery
    if (($now - $last).TotalMinutes -lt $RecoveryCooldownMinutes) {
        Write-Log "RECOVERY_COOLDOWN remainingMinutes=$([math]::Ceiling($RecoveryCooldownMinutes - ($now - $last).TotalMinutes))"
        return
    }
    # Persist cooldown BEFORE attempting shutdown to avoid restart loops across watcher restarts.
    $now.ToString('o') | Set-Content -LiteralPath $CooldownFile -Encoding ASCII
    Write-Log 'RECOVERY_START mode=shutdown all_wsl_distros_affected=true'
    try {
        $shutdownOutput = @(& wsl.exe --shutdown 2>&1)
        $shutdownCode = $LASTEXITCODE
        if ($shutdownCode -ne 0) { Write-Log "RECOVERY_FAILED shutdown_exit=$shutdownCode detail=[$($shutdownOutput -join ' ')]"; return }
        Start-Sleep -Seconds 8
        Ensure-KeepAliveTask 'after_shutdown'
        # Direct invocation also starts the distro if the scheduled task is one-shot.
        $launchOutput = @(& wsl.exe -d $Distro --exec /bin/true 2>&1)
        if ($LASTEXITCODE -ne 0) { Write-Log "RECOVERY_FAILED launch_exit=$LASTEXITCODE detail=[$($launchOutput -join ' ')]"; return }
        $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            $result = Test-WslTcp
            if ($result.Kind -eq 'OK') { Write-Log 'RECOVERY_OK wsl_tcp_restored'; return }
            Write-Log "RECOVERY_VERIFY kind=$($result.Kind) detail=[$($result.Detail)]"
            Start-Sleep -Seconds 10
        }
        Write-Log 'RECOVERY_FAILED verify_timeout'
    } catch { Write-Log "RECOVERY_ERROR $($_.Exception.Message)" }
}
$failures = 0
$lastStatus = ''
$lastProbeError = ''
$lastKeepAliveCheck = [datetime]::MinValue
$inMaintenance = $false
try {
    $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Log "START version=v6 user=$who distro=$Distro target=${Server}:${Port} interval=$IntervalSeconds threshold=$FailureThreshold autoRecovery=$EnableAutoRecovery"
    Ensure-KeepAliveTask 'startup'
    while ($true) {
        if (Test-Path $MaintFlag) {
            if (-not $inMaintenance) { Write-Log 'MAINTENANCE_ON'; $inMaintenance = $true }
            $failures = 0
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }
        if ($inMaintenance) { Write-Log 'MAINTENANCE_OFF'; $inMaintenance = $false }
        if (((Get-Date) - $lastKeepAliveCheck).TotalSeconds -ge 60) {
            Ensure-KeepAliveTask 'periodic'
            $lastKeepAliveCheck = Get-Date
        }
        $win = Test-WindowsTcp
        $probe = Test-WslTcp
        $status = if ($probe.Kind -eq 'PROBE_ERROR') { 'PROBE_ERROR' } elseif ($win -and $probe.Kind -eq 'OK') { 'BOTH_OK' } elseif (-not $win -and $probe.Kind -ne 'OK') { 'BOTH_FAIL' } elseif ($win -and $probe.Kind -eq 'TCP_FAIL') { 'WSL_ONLY_FAIL' } else { 'WINDOWS_ONLY_FAIL' }
        if ($status -eq 'WSL_ONLY_FAIL') { $failures++ } else { $failures = 0 }
        $errorSignature = if ($status -eq 'PROBE_ERROR') { $probe.Detail } else { '' }
        if ($status -ne $lastStatus -or $status -eq 'WSL_ONLY_FAIL' -or ($errorSignature -ne $lastProbeError)) {
            Write-Log "STATUS=$status windows=$win wsl=$($probe.Kind) consecutiveWslFailures=$failures detail=[$($probe.Detail)]"
        }
        $lastStatus = $status
        $lastProbeError = $errorSignature
        if ($failures -ge $FailureThreshold) {
            if ($EnableAutoRecovery) { Invoke-Recovery; $failures = 0 }
            elseif ($failures -eq $FailureThreshold) { Write-Log 'ALERT recovery_eligible monitor_only' }
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} catch { Write-Log "FATAL $($_.Exception.Message)"; throw }
finally { Write-Log 'STOP'; if ($hasMutex) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
