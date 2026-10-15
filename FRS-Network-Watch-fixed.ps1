# FRS Windows / WSL network watcher. PowerShell 5.1+
# IMPORTANT: Automatic WSL restart interrupts processes and Docker workloads in that distro.
# WSL keeper uses flock to prevent duplicate keeper processes after recovery.
$Server = '10.244.201.165'
$Port = 7447
$Distro = 'Ubuntu-22.04' # Confirm with: wsl -l -q
$IntervalSeconds = 10
$FailureThreshold = 5
$RecoveryCooldownMinutes = 30
$EnableAutoRecovery = $false # Change to $true only with operational approval
$LogDir = Join-Path $env:ProgramData 'FRSNetworkWatch'
$LogFile = Join-Path $LogDir 'watch.log'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$mutex = New-Object System.Threading.Mutex($false, 'Global\FRSNetworkWatch')
if (-not $mutex.WaitOne(0)) { Write-Host 'FRS watcher already running'; exit 2 }

function Write-Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}
function Test-WindowsTcp {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $async = $client.BeginConnect($Server, $Port, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne(3000, $false)) { return $false }
            $client.EndConnect($async)
            return $true
        } finally { $client.Close() }
    } catch { return $false }
}
function Test-WslTcp {
    $out = Join-Path $LogDir ('probe-{0}.out' -f $PID)
    $err = Join-Path $LogDir ('probe-{0}.err' -f $PID)

    try {
        $argsLine = '-d "{0}" --exec /bin/bash -c "echo > /dev/tcp/{1}/{2}"' -f $Distro, $Server, $Port

        $p = Start-Process -FilePath 'wsl.exe' `
            -ArgumentList $argsLine `
            -WindowStyle Hidden `
            -PassThru `
            -RedirectStandardOutput $out `
            -RedirectStandardError $err `
            -ErrorAction Stop

        if (-not $p.WaitForExit(8000)) {
            try { $p.Kill() } catch {}
            Write-Log 'WSL_PROBE_TIMEOUT'
            return $false
        }

        $exitCode = $p.ExitCode

        if ($exitCode -ne 0) {
            $detail = Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue
            Write-Log "WSL_PROBE_FAILED exit=$exitCode detail=$detail"
        }

        return ($exitCode -eq 0)
    }
    catch {
        Write-Log "WSL_PROBE_ERROR $($_.Exception.Message)"
        return $false
    }
    finally {
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    }
}
function Start-WslKeeper {
    # A Linux flock makes the keeper singleton even if multiple scheduled tasks try to start it.
    # Do not pipe this long-running wsl.exe through ForEach-Object: that would block the watcher.
    $keeperCommand = 'exec flock -n /tmp/frs-network-watch-keeper.lock sleep infinity'
    $keeperArgs = '-d "{0}" --exec /bin/sh -c "{1}"' -f $Distro, $keeperCommand
    try {
        $keeper = Start-Process -FilePath 'wsl.exe' -ArgumentList $keeperArgs `
            -WindowStyle Hidden -PassThru -ErrorAction Stop
        Start-Sleep -Seconds 3
        $keeper.Refresh()
        if ($keeper.HasExited) {
            Write-Log "KEEPER_NOT_STARTED exit=$($keeper.ExitCode) (existing keeper, startup error, or scheduled-task cleanup)"
            return $false
        }
        Write-Log "KEEPER_RUNNING windowsPid=$($keeper.Id)"
        return $true
    } catch {
        Write-Log "KEEPER_ERROR $($_.Exception.Message)"
        return $false
    }
}
function Recover-Wsl {
    # Terminating the distro stops ALL its Linux processes, including any existing keeper.
    # Docker containers and Zenoh may not recover automatically.
    Write-Log "RECOVERY_START terminate_distro=$Distro"
    & wsl.exe --terminate $Distro 2>&1 | ForEach-Object { Write-Log "WSL: $_" }
    $terminateExit = $LASTEXITCODE
    if ($terminateExit -ne 0) {
        Write-Log "RECOVERY_FAILED terminate_exit=$terminateExit"
        return
    }
    Start-Sleep -Seconds 5

    $keeperStarted = Start-WslKeeper
    if (-not $keeperStarted) {
        Write-Log 'RECOVERY_FAILED keeper_not_running'
        return
    }

    # A short probe checks launch success; the separate keeper holds an active WSL session.
    & wsl.exe -d $Distro -- /bin/true 2>&1 | ForEach-Object { Write-Log "WSL: $_" }
    $launchExit = $LASTEXITCODE
    if ($launchExit -ne 0) {
        Write-Log "RECOVERY_FAILED launch_exit=$launchExit"
        return
    }
    Write-Log 'RECOVERY_END launch_exit=0 keeper_running=true (verify Docker and zenoh separately)'
}

$failures = 0
$lastRecovery = [datetime]::MinValue
$lastStatus = ''
Write-Log "START server=${Server}:${Port} distro=$Distro interval=${IntervalSeconds}s threshold=$FailureThreshold autoRecovery=$EnableAutoRecovery"
try {
    while ($true) {
        $win = Test-WindowsTcp
        $wsl = Test-WslTcp
        $status = if ($win -and $wsl) { 'BOTH_OK' } elseif (-not $win -and -not $wsl) { 'BOTH_FAIL' } elseif ($win -and -not $wsl) { 'WSL_ONLY_FAIL' } else { 'WINDOWS_ONLY_FAIL' }
        if ($status -eq 'WSL_ONLY_FAIL') { $failures++ } else { $failures = 0 }
        if ($status -ne $lastStatus -or $status -ne 'BOTH_OK') {
            Write-Log "STATUS=$status windows=$win wsl=$wsl consecutiveWslFailures=$failures"
        }
        $lastStatus = $status
        if ($failures -ge $FailureThreshold) {
            if (-not $EnableAutoRecovery) {
                if ($failures -eq $FailureThreshold) { Write-Log 'ALERT WSL recovery eligible; monitor-only mode' }
            } elseif ((Get-Date) - $lastRecovery -ge [timespan]::FromMinutes($RecoveryCooldownMinutes)) {
                $lastRecovery = Get-Date
                Recover-Wsl
                $failures = 0
            }
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    Write-Log 'STOP'
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
