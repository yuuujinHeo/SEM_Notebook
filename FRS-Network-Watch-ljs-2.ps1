# FRS Windows / WSL network watcher v3. PowerShell 5.1+
# IMPORTANT: Automatic WSL restart interrupts processes and Docker workloads in that distro.
#            v3 uses 'wsl --shutdown', which stops ALL WSL distros on this PC.
# WSL keeper uses flock to prevent duplicate keeper processes after recovery.
# UTF-8 (BOM 포함)으로 저장되어 있습니다. 한글 주석이 깨지지 않도록 인코딩을 유지하세요.
#
# 동작 요약
#  1) 10초마다 Windows→FRS, WSL→FRS TCP 연결 확인
#  2) Windows는 되는데 WSL만 안 되는 상태가 연속 N회면 자동 복구:
#     wsl --shutdown(커널까지 재시작) → WSL 다시 기동 → keeper/유지 작업 재시작 → 실제 연결 확인
#  3) 사람이 WSL을 종료/재시작해도 keeper가 사라진 것을 감지해 WSL을 다시 띄움
#  4) 하루 자동 복구 횟수 제한(파일에 기록, 스크립트가 다시 떠도 유지)
#  5) 유지보수 플래그 파일이 있으면 WSL 기동/복구를 하지 않음 (업데이트·진단 중 사용)
param(
    [string]$Server = '10.244.201.165',
    [int]$Port = 7447,
    [string]$Distro = '',                      # 비우면 현재 사용자의 기본 배포판 자동 감지. Confirm with: wsl -l -q
    [string]$KeepAliveTaskName = 'WSL-AutoStart', # WSL 유지용 작업 이름. 없으면 '' 로
    [int]$IntervalSeconds = 10,
    [int]$FailureThreshold = 6,                # WSL_ONLY_FAIL 연속 횟수 (약 2분)
    [int]$RecoveryCooldownMinutes = 30,
    [int]$MaxRecoveriesPerDay = 3,
    [int]$VerifyTimeoutSeconds = 180,          # 복구 후 WSL→FRS 연결 확인 대기 시간
    [bool]$EnableAutoRecovery = $true         # Change only with operational approval ($false = monitor-only)
)

$LogDir   = Join-Path $env:ProgramData 'FRSNetworkWatch'
$LogFile  = Join-Path $LogDir 'watch.log'
$CountFile = Join-Path $LogDir 'recovery-count.txt'
$MaintFlag = Join-Path $LogDir 'maintenance.flag'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$mutex = New-Object System.Threading.Mutex($false, 'Global\FRSNetworkWatch')
if (-not $mutex.WaitOne(0)) { Write-Host 'FRS watcher already running'; exit 2 }

function Write-Log([string]$Message) {
    try {
        if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 10MB)) {
            Move-Item -LiteralPath $LogFile -Destination ($LogFile + '.1') -Force
        }
    } catch {}
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# ---------- WSL 배포판 정보 ----------
function Get-WslDistroNames {
    $lx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lx)) { return @() }
    Get-ChildItem $lx | ForEach-Object { (Get-ItemProperty $_.PSPath).DistributionName } | Where-Object { $_ }
}
function Get-WslDefaultDistro {
    $lx = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lx)) { return $null }
    $guid = (Get-ItemProperty $lx -ErrorAction SilentlyContinue).DefaultDistribution
    if (-not $guid) { return $null }
    $key = Join-Path $lx $guid
    if (-not (Test-Path $key)) { return $null }
    return (Get-ItemProperty $key).DistributionName
}

# ---------- 공통: wsl.exe를 타임아웃과 함께 실행 ----------
function New-WslStartInfo([string]$ArgsLine, [bool]$Redirect) {
    # Start-Process -PassThru 는 빨리 끝나는 프로세스의 ExitCode 를 $null 로 돌려주는 경우가 있어
    # .NET Process 를 직접 사용함 (ExitCode 를 항상 정확히 읽기 위해).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wsl.exe'
    $psi.Arguments = $ArgsLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $Redirect
    $psi.RedirectStandardError = $Redirect
    return $psi
}
function Invoke-Wsl([string]$ArgsLine, [int]$TimeoutMs, [switch]$Capture) {
    $p = $null
    try {
        $p = [System.Diagnostics.Process]::Start((New-WslStartInfo $ArgsLine $true))
        $so = $p.StandardOutput.ReadToEndAsync()
        $se = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch {}
            return @{ Code = $null; Out = '' }
        }
        $p.WaitForExit()
        $text = ''
        if ($Capture) { $text = ($so.Result -replace "`0", '') }
        return @{ Code = $p.ExitCode; Out = $text }
    } catch {
        Write-Log "WSL_EXEC_ERROR args=[$ArgsLine] $($_.Exception.Message)"
        return @{ Code = -1; Out = '' }
    } finally {
        if ($p) { $p.Dispose() }
    }
}

# ---------- 연결 확인 ----------
function Test-WindowsTcp {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($Server, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(3000, $false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { if ($client) { $client.Close() } }
}
function Test-WslTcp {
    # 로그인 셸을 쓰지 않음(프로필 스크립트 영향 제거). Windows 쪽 8초 하드 타임아웃.
    $cmd = "timeout 3 bash -c 'echo > /dev/tcp/$Server/$Port'"
    $r = Invoke-Wsl ('-d "' + $Distro + '" --exec /bin/bash -c "' + $cmd + '"') 8000
    return ($r.Code -eq 0)
}

# ---------- WSL 유지(keeper) ----------
$script:Keeper = $null
function Ensure-WslKeeper {
    if ($script:Keeper) {
        $script:Keeper.Refresh()
        if (-not $script:Keeper.HasExited) { return $true }
        Write-Log "KEEPER_LOST exit=$($script:Keeper.ExitCode) (WSL stopped or restarted manually) -> restarting keeper"
        $script:Keeper.Dispose(); $script:Keeper = $null
    }
    $keeperArgs = '-d "' + $Distro + '" --exec /bin/sh -c "exec flock -n /tmp/frs-network-watch-keeper.lock sleep infinity"'
    try {
        $k = [System.Diagnostics.Process]::Start((New-WslStartInfo $keeperArgs $false))
        Start-Sleep -Seconds 3
        $k.Refresh()
        if ($k.HasExited) {
            # exit=1: 다른 keeper가 이미 lock 보유(정상). 그 외는 기동 실패.
            Write-Log "KEEPER_NOT_STARTED exit=$($k.ExitCode) (1=another keeper already holds the lock)"
            $ok = ($k.ExitCode -eq 1); $k.Dispose(); return $ok
        }
        $script:Keeper = $k
        Write-Log "KEEPER_RUNNING windowsPid=$($k.Id)"
        return $true
    } catch {
        Write-Log "KEEPER_ERROR $($_.Exception.Message)"
        return $false
    }
}
function Ensure-KeepAliveTask {
    if (-not $KeepAliveTaskName) { return }
    try {
        $t = Get-ScheduledTask -TaskName $KeepAliveTaskName -ErrorAction Stop
        if ($t.State -ne 'Running') {
            Start-ScheduledTask -TaskName $KeepAliveTaskName
            Write-Log "KEEPALIVE_TASK_STARTED name='$KeepAliveTaskName' prevState=$($t.State)"
        }
    } catch {
        if (-not $script:KeepAliveTaskMissingLogged) {
            Write-Log "KEEPALIVE_TASK_NOT_FOUND name='$KeepAliveTaskName' (ignored; keeper still active)"
            $script:KeepAliveTaskMissingLogged = $true
        }
    }
}

# ---------- 하루 복구 횟수 (파일 기록) ----------
function Get-TodayRecoveryCount {
    $today = Get-Date -Format 'yyyy-MM-dd'
    try {
        if (Test-Path $CountFile) {
            $raw = Get-Content $CountFile -Raw
            if ($raw) {
                $parts = $raw.Trim() -split '\s+'
                if ($parts.Count -ge 2 -and $parts[0] -eq $today) { return [int]$parts[1] }
            }
        }
    } catch {}
    return 0
}
function Add-TodayRecoveryCount {
    $n = (Get-TodayRecoveryCount) + 1
    Set-Content -LiteralPath $CountFile -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd'), $n) -Encoding ASCII
    return $n
}

# ---------- 복구: shutdown → 재기동 → 확인 ----------
function Invoke-WslRecovery {
    $used = Get-TodayRecoveryCount
    if ($used -ge $MaxRecoveriesPerDay) {
        Write-Log "ALERT recovery_limit_reached today=$used max=$MaxRecoveriesPerDay -> no restart, manual check required"
        return
    }
    $n = Add-TodayRecoveryCount
    $others = @(Get-WslDistroNames | Where-Object { $_ -ne $Distro })
    Write-Log "RECOVERY_START mode=shutdown distro=$Distro todayCount=$n/$MaxRecoveriesPerDay otherDistrosAffected=[$($others -join ',')]"

    # 1) WSL VM 전체 종료 (커널 잠금은 shutdown으로만 풀림)
    $r = Invoke-Wsl '--shutdown' 120000
    if ($null -eq $r.Code) { Write-Log 'RECOVERY_FAILED shutdown_timeout_120s (manual action required)'; return }
    if ($r.Code -ne 0) { Write-Log "RECOVERY_FAILED shutdown_exit=$($r.Code)"; return }
    if ($script:Keeper) { try { $script:Keeper.Dispose() } catch {}; $script:Keeper = $null }
    Start-Sleep -Seconds 8

    # 2) WSL 다시 기동 + 유지
    if (-not (Ensure-WslKeeper)) { Write-Log 'RECOVERY_FAILED keeper_not_running'; return }
    Ensure-KeepAliveTask

    # 3) 실제로 WSL→FRS 연결이 살아났는지 확인
    $deadline = (Get-Date).AddSeconds($VerifyTimeoutSeconds)
    $start = Get-Date
    while ((Get-Date) -lt $deadline) {
        if (Test-WslTcp) {
            $sec = [int]((Get-Date) - $start).TotalSeconds
            Write-Log "RECOVERY_OK wsl_tcp_ok_after=${sec}s"
            $d = Invoke-Wsl ('-d "' + $Distro + '" --exec /bin/sh -c "docker ps --format {{.Names}}:{{.Status}}"') 20000 -Capture
            Write-Log ("DOCKER_AFTER_RECOVERY " + (($d.Out -split "`r?`n" | Where-Object { $_ }) -join ' | '))
            return
        }
        Start-Sleep -Seconds 10
    }
    Write-Log "RECOVERY_FAILED wsl_tcp_still_failing_after_${VerifyTimeoutSeconds}s"
}

# ---------- 시작 점검 ----------
$who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($who -match 'SYSTEM$') {
    Write-Log "FATAL running as $who : WSL distros are per-user. Run the task as the distro owner."
    $mutex.ReleaseMutex(); $mutex.Dispose(); exit 3
}
$names = @(Get-WslDistroNames)
if (-not $Distro) { $Distro = Get-WslDefaultDistro }
if (-not $Distro -or ($names -notcontains $Distro)) {
    Write-Log "FATAL distro not found. requested='$Distro' available='$($names -join ',')' user=$who"
    $mutex.ReleaseMutex(); $mutex.Dispose(); exit 4
}

$failures = 0
$lastRecovery = [datetime]::MinValue
$lastStatus = ''
$inMaint = $false
Write-Log "START user=$who server=${Server}:${Port} distro=$Distro interval=${IntervalSeconds}s threshold=$FailureThreshold autoRecovery=$EnableAutoRecovery maxPerDay=$MaxRecoveriesPerDay keepAliveTask='$KeepAliveTaskName'"

try {
    while ($true) {
        # 유지보수 모드: WSL 업데이트·진단 중에는 기동/복구하지 않음
        if (Test-Path $MaintFlag) {
            if (-not $inMaint) { Write-Log "MAINTENANCE_ON ($MaintFlag exists) -> keeper/recovery paused"; $inMaint = $true }
            $failures = 0
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }
        if ($inMaint) { Write-Log 'MAINTENANCE_OFF'; $inMaint = $false }

        # 수동 종료/재시작 감지 시 WSL을 다시 띄움
        [void](Ensure-WslKeeper)
        Ensure-KeepAliveTask

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
                Invoke-WslRecovery
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
