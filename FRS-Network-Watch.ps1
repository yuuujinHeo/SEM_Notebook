# FRS Windows / WSL network watcher. PowerShell 5.1+
# IMPORTANT: Automatic WSL restart interrupts processes and Docker workloads in that distro.
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
    # Run WSL test as a child process with a Windows-side hard timeout.
    $command = "timeout 3 bash -c 'echo > /dev/tcp/$Server/$Port'"
    $out = Join-Path $LogDir ('probe-{0}.out' -f $PID)
    $err = Join-Path $LogDir ('probe-{0}.err' -f $PID)
    try {
        $argsLine = '-d "{0}" -- bash -lc "{1}"' -f $Distro, $command
        $p = Start-Process -FilePath 'wsl.exe' -ArgumentList $argsLine -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $p.WaitForExit(8000)) {
            try { $p.Kill() } catch {}
            return $false
        }
        return ($p.ExitCode -eq 0)
    } catch {
        Write-Log "WSL_PROBE_ERROR $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    }
}
function Recover-Wsl {
    # Terminating the distro stops ALL its Linux processes; Docker containers may not recover automatically.
    Write-Log "RECOVERY_START terminate_distro=$Distro"
    & wsl.exe --terminate $Distro 2>&1 | ForEach-Object { Write-Log "WSL: $_" }
    if ($LASTEXITCODE -ne 0) { Write-Log "RECOVERY_FAILED terminate_exit=$LASTEXITCODE"; return }
    Start-Sleep -Seconds 5
    & wsl.exe -d $Distro -- /bin/true 2>&1 | ForEach-Object { Write-Log "WSL: $_" }
    Write-Log "RECOVERY_END launch_exit=$LASTEXITCODE (verify Docker and zenoh separately)"
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
