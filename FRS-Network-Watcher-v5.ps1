# FRS Network Watcher v5 - Windows PowerShell 5.1
# WARNING: wsl --shutdown stops ALL WSL distributions, Docker containers and Linux processes.
# Keep WSL-AutoStart scheduled task. The internal keeper is a backup, not a replacement.
param(
    [string]$Server = '10.244.201.165',
    [int]$Port = 7447,
    [string]$Distro = 'Ubuntu-22.04',
    [string]$KeepAliveTaskName = 'WSL-AutoStart',
    [bool]$EnableKeeperBackup = $true,
    [int]$IntervalSeconds = 10,
    [int]$FailureThreshold = 6,
    [int]$RecoveryCooldownMinutes = 30,
    [int]$VerifyTimeoutSeconds = 180,
    [int]$WslProbeTimeoutMs = 12000,
    [bool]$EnableAutoRecovery = $true
)

$ErrorActionPreference = 'Stop'
$LogDir = Join-Path $env:ProgramData 'FRSNetworkWatch'
$LogFile = Join-Path $LogDir 'watch.log'
$MaintFlag = Join-Path $LogDir 'maintenance.flag'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$mutex = New-Object System.Threading.Mutex($false, 'Global\FRSNetworkWatch')
$hasMutex = $false
try { $hasMutex = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $hasMutex = $true }
if (-not $hasMutex) { Write-Host 'FRS watcher already running'; $mutex.Dispose(); exit 2 }

function Write-Log([string]$Message) {
    try {
        if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 10MB) {
            Move-Item -LiteralPath $LogFile -Destination ($LogFile + '.1') -Force
        }
    } catch {}
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# Executes wsl.exe with Windows-side timeout. Asynchronous stream reads avoid pipe deadlock.
function Invoke-Wsl([string]$ArgsLine, [int]$TimeoutMs) {
    # Start-Process mirrors the known working Windows invocation path.
    # Unique temporary files avoid redirected-pipe deadlocks and collisions.
    $token = [guid]::NewGuid().ToString('N')
    $outFile = Join-Path $LogDir "probe-$token.out"
    $errFile = Join-Path $LogDir "probe-$token.err"
    $p = $null
    try {
        $p = Start-Process -FilePath 'wsl.exe' -ArgumentList $ArgsLine `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile -ErrorAction Stop
        $null = $p.Handle
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill(); $p.WaitForExit(2000) | Out-Null } catch {}
            return @{ Kind='TIMEOUT'; Code=$null; Out=''; Err='wsl.exe did not exit before deadline' }
        }
        $p.Refresh()
        $stdout = (Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue) -replace "`0", ''
        $stderr = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) -replace "`0", ''
        return @{ Kind='EXIT'; Code=[int]$p.ExitCode; Out="$stdout".Trim(); Err="$stderr".Trim() }
    } catch {
        return @{ Kind='EXEC_ERROR'; Code=$null; Out=''; Err=$_.Exception.Message }
    } finally {
        if ($p) { $p.Dispose() }
        Remove-Item -LiteralPath $outFile,$errFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-WindowsTcp {
    $client = $null
    $waitHandle = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($Server, $Port, $null, $null)
        $waitHandle = $async.AsyncWaitHandle
        if (-not $waitHandle.WaitOne(3000, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally {
        if ($waitHandle) { $waitHandle.Close() }
        if ($client) { $client.Close() }
    }
}

# Result: OK, TCP_FAIL, PROBE_TIMEOUT, PROBE_ERROR.
# No nested bash quoting. nc -z -w 3 checks TCP and returns exit code 0 on success.
function Test-WslTcp {
    $argsLine = '-d "{0}" --exec /usr/bin/env LC_ALL=C /usr/bin/nc -vz -w 3 {1} {2}' -f $Distro, $Server, $Port
    $r = Invoke-Wsl $argsLine $WslProbeTimeoutMs
    if ($r.Kind -eq 'TIMEOUT') { return @{ Kind='PROBE_TIMEOUT'; Detail=$r.Err } }
    if ($r.Kind -ne 'EXIT') { return @{ Kind='PROBE_ERROR'; Detail=$r.Err } }
    if ($r.Code -eq 0) { return @{ Kind='OK'; Detail='' } }
    $detail = (($r.Err + ' ' + $r.Out).Trim() -replace '[\r\n]+', ' ')
    if ($detail.Length -gt 250) { $detail = $detail.Substring(0,250) }
    # Exit 127/126 and missing executable errors are NOT network failures.
    if ($r.Code -eq 126 -or $r.Code -eq 127 -or $detail -match 'not found|No such file|not recognized|execvpe|exec failed') {
        return @{ Kind='PROBE_ERROR'; Detail="exit=$($r.Code) $detail" }
    }
    # Only confirmed socket failures count toward destructive recovery.
    if ($detail -match 'Connection refused|timed out|No route to host|Network is unreachable|Host is unreachable|Connection reset|Operation now in progress') {
        return @{ Kind='TCP_FAIL'; Detail="exit=$($r.Code) $detail" }
    }
    return @{ Kind='PROBE_ERROR'; Detail="unclassified_exit=$($r.Code) $detail" }
}

function Get-WslDistroNames {
    $lx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lx)) { return @() }
    @(Get-ChildItem $lx | ForEach-Object { (Get-ItemProperty $_.PSPath).DistributionName } | Where-Object { $_ })
}

# WSL-AutoStart is the primary startup task. Don't repeatedly trigger a one-shot task.
function Start-KeepAliveTask([string]$Reason) {
    if (-not $KeepAliveTaskName) { return }
    try {
        $task = Get-ScheduledTask -TaskName $KeepAliveTaskName -ErrorAction Stop
        if ($task.State -eq 'Disabled') { Write-Log "KEEPALIVE_TASK_DISABLED name=$KeepAliveTaskName"; return }
        if ($task.State -ne 'Running') {
            Start-ScheduledTask -TaskName $KeepAliveTaskName
            Write-Log "KEEPALIVE_TASK_TRIGGERED reason=$Reason name=$KeepAliveTaskName previousState=$($task.State)"
        } else {
            Write-Log "KEEPALIVE_TASK_RUNNING reason=$Reason name=$KeepAliveTaskName"
        }
    } catch { Write-Log "KEEPALIVE_TASK_ERROR reason=$Reason $($_.Exception.Message)" }
}

$script:Keeper = $null
$script:KeeperRetryAt = [datetime]::MinValue
function Ensure-WslKeeper {
    if (-not $EnableKeeperBackup) { return }
    if ($script:Keeper) {
        try {
            $script:Keeper.Refresh()
            if (-not $script:Keeper.HasExited) { return }
            Write-Log "KEEPER_LOST exit=$($script:Keeper.ExitCode)"
        } catch { Write-Log "KEEPER_CHECK_ERROR $($_.Exception.Message)" }
        try { $script:Keeper.Dispose() } catch {}
        $script:Keeper = $null
    }
    if ((Get-Date) -lt $script:KeeperRetryAt) { return }
    $script:KeeperRetryAt = (Get-Date).AddSeconds(30)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wsl.exe'
        $psi.Arguments = '-d "{0}" --exec /usr/bin/flock -n /tmp/frs-network-watch-keeper.lock /bin/sleep infinity' -f $Distro
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Seconds 2
        $p.Refresh()
        if ($p.HasExited) {
            Write-Log "KEEPER_EXITED exit=$($p.ExitCode) (lock held, missing flock, or startup error; verify manually)"
            $p.Dispose()
        } else {
            $script:Keeper = $p
            Write-Log "KEEPER_RUNNING windowsPid=$($p.Id)"
        }
    } catch { Write-Log "KEEPER_ERROR $($_.Exception.Message)" }
}

function Invoke-WslRecovery {
    if (Test-Path $MaintFlag) { Write-Log 'RECOVERY_SKIPPED maintenance'; return }
    # Recheck immediately before destructive action.
    if (-not (Test-WindowsTcp)) { Write-Log 'RECOVERY_CANCELLED windows_tcp_failed_on_recheck'; return }
    $pre = Test-WslTcp
    if ($pre.Kind -ne 'TCP_FAIL') { Write-Log "RECOVERY_CANCELLED wsl_recheck=$($pre.Kind) $($pre.Detail)"; return }
    $others = @(Get-WslDistroNames | Where-Object { $_ -ne $Distro })
    Write-Log "RECOVERY_START wsl_shutdown ALL_DISTROS others=[$($others -join ',')]"
    $r = Invoke-Wsl '--shutdown' 120000
    if ($r.Kind -ne 'EXIT' -or $r.Code -ne 0) {
        Write-Log "RECOVERY_FAILED shutdown kind=$($r.Kind) exit=$($r.Code) err=$($r.Err)"
        return
    }
    if ($script:Keeper) { try { $script:Keeper.Dispose() } catch {}; $script:Keeper = $null }
    Start-Sleep -Seconds 8
    Start-KeepAliveTask 'recovery'
    Ensure-WslKeeper
    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    do {
        if (Test-Path $MaintFlag) { Write-Log 'RECOVERY_VERIFY_STOP maintenance'; return }
        $test = Test-WslTcp
        if ($test.Kind -eq 'OK') {
            Write-Log 'RECOVERY_TCP_OK (Docker/Muscat/Zenoh health NOT verified)'
            $d = Invoke-Wsl ('-d "{0}" --exec /usr/bin/docker ps --format "{{.Names}}:{{.Status}}"' -f $Distro) 20000
            if ($d.Kind -eq 'EXIT' -and $d.Code -eq 0) { Write-Log "DOCKER_AFTER_RECOVERY $($d.Out -replace '[\r\n]+',' | ')" }
            else { Write-Log "DOCKER_CHECK_FAILED kind=$($d.Kind) exit=$($d.Code) err=$($d.Err)" }
            return
        }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    Write-Log "RECOVERY_FAILED verify_timeout=${VerifyTimeoutSeconds}s lastProbe=$($test.Kind) $($test.Detail)"
}

try {
    $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($who -match '(^|\\)SYSTEM$') { throw 'Run as the Windows user owning the WSL distribution, not SYSTEM.' }
    if ((Get-WslDistroNames) -notcontains $Distro) { throw "WSL distro '$Distro' not registered for $who" }
    Write-Log "START version=v5 user=$who distro=$Distro target=${Server}:${Port} interval=$IntervalSeconds threshold=$FailureThreshold autoRecovery=$EnableAutoRecovery keeperBackup=$EnableKeeperBackup"
    Start-KeepAliveTask 'startup'
    Ensure-WslKeeper
    # Verify that nc exists. Missing nc must never be counted as a TCP outage.
    $nc = Invoke-Wsl ('-d "{0}" --exec /usr/bin/test -x /usr/bin/nc' -f $Distro) $WslProbeTimeoutMs
    if ($nc.Kind -ne 'EXIT' -or $nc.Code -ne 0) {
        Write-Log "FATAL nc_unavailable_or_wsl_unresponsive kind=$($nc.Kind) code=$($nc.Code) err=$($nc.Err); install netcat-openbsd in Ubuntu and retry"
        throw 'WSL TCP probe prerequisite failed'
    }
    $failures = 0
    $lastStatus = ''
    $lastDetail = ''
    $lastRecovery = [datetime]::MinValue
    $inMaint = $false
    while ($true) {
        if (Test-Path $MaintFlag) {
            if (-not $inMaint) { Write-Log 'MAINTENANCE_ON keeper/probe/recovery paused'; $inMaint = $true }
            $failures = 0
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }
        if ($inMaint) { Write-Log 'MAINTENANCE_OFF'; $inMaint = $false }
        Ensure-WslKeeper
        $win = Test-WindowsTcp
        $wsl = Test-WslTcp
        $status = if ($wsl.Kind -eq 'PROBE_TIMEOUT' -or $wsl.Kind -eq 'PROBE_ERROR') {
            'PROBE_UNKNOWN'
        } elseif ($win -and $wsl.Kind -eq 'OK') { 'BOTH_OK' }
        elseif (-not $win -and $wsl.Kind -eq 'TCP_FAIL') { 'BOTH_FAIL' }
        elseif ($win -and $wsl.Kind -eq 'TCP_FAIL') { 'WSL_ONLY_FAIL' }
        else { 'WINDOWS_ONLY_FAIL' }
        if ($status -eq 'WSL_ONLY_FAIL') { $failures++ } else { $failures = 0 }
        $detail = $wsl.Detail
        if ($status -ne $lastStatus -or ($status -ne 'BOTH_OK' -and $detail -ne $lastDetail)) {
            Write-Log "STATUS=$status windows=$win wsl=$($wsl.Kind) consecutive=$failures detail=$detail"
        }
        $lastStatus = $status
        $lastDetail = $detail
        if ($failures -ge $FailureThreshold) {
            if (-not $EnableAutoRecovery) {
                if ($failures -eq $FailureThreshold) { Write-Log 'ALERT recovery eligible, monitor-only' }
            } elseif ((Get-Date) - $lastRecovery -ge [timespan]::FromMinutes($RecoveryCooldownMinutes)) {
                $lastRecovery = Get-Date
                Invoke-WslRecovery
                $failures = 0
            }
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} catch {
    Write-Log "FATAL $($_.Exception.Message)"
} finally {
    Write-Log 'STOP'
    if ($script:Keeper) { try { $script:Keeper.Dispose() } catch {} }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
