# FRS Network Watcher v4 - Windows PowerShell 5.1
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
    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wsl.exe'
        $psi.Arguments = $ArgsLine
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        if (-not $p.Start()) { return @{ Kind='EXEC_ERROR'; Code=$null; Out=''; Err='process not started' } }
        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return @{ Kind='TIMEOUT'; Code=$null; Out=''; Err='wsl.exe did not exit before deadline' }
        }
        $p.WaitForExit()
        $out = ($stdoutTask.Result -replace "`0", '').Trim()
        $err = ($stderrTask.Result -replace "`0", '').Trim()
        return @{ Kind='EXIT'; Code=[int]$p.ExitCode; Out=$out; Err=$err }
    } catch {
        return @{ Kind='EXEC_ERROR'; Code=$null; Out=''; Err=$_.Exception.Message }
    } finally { if ($p) { $p.Dispose() } }
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
    $argsLine = '-d "{0}" --exec /usr/bin/nc -vz -w 3 {1} {2}' -f $Distro, $Server, $Port
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
