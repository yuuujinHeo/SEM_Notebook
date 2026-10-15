# FRS-Network-Watch v3 적용 안내

## 1. v3에서 바뀐 동작

| 상황 | v1/fixed | v3 |
|---|---|---|
| Windows는 되는데 WSL만 안 됨 (약 2분 지속) | `--terminate` (문제 1의 커널 잠금은 복구 불가) | **`wsl --shutdown` → WSL 재기동 → keeper·`WSL-AutoStart` 작업 재시작 → WSL→FRS 연결 확인** |
| 복구 후 확인 | `/bin/true` 실행 여부만 확인 | **WSL→FRS:7447 실제 연결 확인(최대 180초)**, 결과를 `RECOVERY_OK` / `RECOVERY_FAILED`로 기록, docker 컨테이너 상태도 기록 |
| 사람이 WSL을 종료하거나 재시작함 | keeper 없음 → WSL이 꺼진 채 유지될 수 있음 | **keeper가 사라진 것을 10초 안에 감지(`KEEPER_LOST`)하고 WSL과 `WSL-AutoStart` 작업을 다시 띄움** |
| 하루 복구 횟수 | 제한 없음 (30분 대기만, 스크립트 재시작 시 초기화) | **하루 3회**(파일에 기록, 스크립트가 다시 떠도 유지). 넘으면 `ALERT`만 기록 |
| Wi-Fi 일시 끊김 (Windows와 WSL 둘 다 실패) | 복구 안 함 | 복구 안 함 (동일) |
| 업데이트·진단 등 일부러 WSL을 꺼 둬야 할 때 | 방법 없음 | **유지보수 플래그 파일**이 있으면 기동과 복구를 멈춤 |
| 배포판 이름 | `Ubuntu-22.04` 고정 | 자동 감지 |
| 장기 운영 | 프로세스 객체 미해제, 로그 무한 증가 | 객체 해제, 로그 10MB에서 교체 |

자동 복구는 **기본으로 켜져 있습니다**(`$EnableAutoRecovery = $true`). 끄려면 작업 인수에 `-EnableAutoRecovery $false`를 추가합니다.

## 2. 주의 사항

- `wsl --shutdown`은 그 PC의 **모든 WSL 배포판**을 내립니다. 다른 배포판이 있으면 `RECOVERY_START` 로그의 `otherDistrosAffected`에 표시됩니다.
- 복구할 때 Docker, muscat, zenoh가 모두 재시작됩니다. 컨테이너가 다시 올라왔는지는 `DOCKER_AFTER_RECOVERY` 로그로 확인합니다.
- 파일은 **UTF-8(BOM 포함)** 으로 저장돼 있습니다. 메모장 등으로 편집할 때 인코딩을 바꾸지 마세요(한글 주석이 깨질 수 있음).
- PowerShell에서 실제로 실행해 검증하지는 못했습니다. **한 대에 먼저 적용**해 로그를 확인한 뒤 배포하세요.

## 2-1. 기존 `WSL 자동실행` 작업을 영어 이름 `WSL-AutoStart`로 바꾸기 (PC마다 1회)

작업 스케줄러는 이름 변경 기능이 없어서, **같은 설정으로 새 이름 작업을 만들고 기존 작업을 지웁니다.** 새 작업을 먼저 띄운 뒤 기존 작업을 정리하므로 WSL은 계속 유지됩니다.

```powershell
$old = Get-ScheduledTask -TaskName 'WSL 자동실행'
$old.Actions | Format-List Execute,Arguments      # 실행 내용 확인 (wsl.exe -d Ubuntu-22.04)

Register-ScheduledTask -TaskName 'WSL-AutoStart' -Action $old.Actions -Trigger $old.Triggers -Principal $old.Principal -Settings $old.Settings
Start-ScheduledTask -TaskName 'WSL-AutoStart'
Get-ScheduledTask -TaskName 'WSL-AutoStart' | Select TaskName,State   # Running 확인

Stop-ScheduledTask -TaskName 'WSL 자동실행'
Unregister-ScheduledTask -TaskName 'WSL 자동실행' -Confirm:$false
```

이름을 다르게 쓰려면 v3 실행 인수에 `-KeepAliveTaskName '원하는이름'`을 추가하면 됩니다.

## 3. 적용 (PowerShell 관리자)

```powershell
# 1) 백업 후 덮어쓰기 (작업 이름/경로 그대로)
Copy-Item C:\Scripts\FRS-Network-Watch.ps1 C:\Scripts\FRS-Network-Watch.ps1.bak -Force
Copy-Item .\FRS-Network-Watch.ps1 C:\Scripts\FRS-Network-Watch.ps1 -Force

# 2) 작업 설정: 창 숨김, 재시작 횟수 늘림, 5분마다 되살리는 실행 조건 추가
$t = Get-ScheduledTask -TaskName 'FRS-Network-Watch'
$t.Actions[0].Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Scripts\FRS-Network-Watch.ps1"'
$t.Settings.RestartCount = 999
$t.Settings.ExecutionTimeLimit = 'PT0S'
$t.Settings.MultipleInstances = 'IgnoreNew'
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$t.Triggers = @($t.Triggers) + $repeat
Set-ScheduledTask -InputObject $t

# 3) 확인
Get-ScheduledTask -TaskName 'FRS-Network-Watch' | Select TaskName,State,@{n='User';e={$_.Principal.UserId}},@{n='Args';e={$_.Actions.Arguments}} | Format-List

# 4) 이미 실행 중인 이전 감시 스크립트가 있으면 먼저 정지한 뒤 시작
Stop-ScheduledTask -TaskName 'FRS-Network-Watch'
Start-ScheduledTask -TaskName 'FRS-Network-Watch'
Get-Content C:\ProgramData\FRSNetworkWatch\watch.log -Tail 20 -Wait
```

로그에서 확인할 것:
- `START user=<admin 계정> ... distro=Ubuntu-22.04 ... autoRecovery=True maxPerDay=3`
- `KEEPER_RUNNING` 또는 `KEEPER_NOT_STARTED exit=1`(이미 keeper 있음, 정상)
- 이후 `STATUS=BOTH_OK`

## 4. 일부러 WSL을 꺼 둬야 할 때 (업데이트, 멈춤 상태 진단 등)

감시 스크립트가 WSL을 곧바로 다시 띄우므로, **작업 전에 유지보수 플래그를 만들고, 끝나면 지웁니다.**

```powershell
# 시작 전 (로그에 MAINTENANCE_ON 확인)
New-Item -ItemType File -Force C:\ProgramData\FRSNetworkWatch\maintenance.flag

# 작업 후 (로그에 MAINTENANCE_OFF → KEEPER_RUNNING 확인)
Remove-Item C:\ProgramData\FRSNetworkWatch\maintenance.flag
```

문제 1처럼 **멈춘 상태를 진단해야 할 때도** 먼저 이 플래그를 만들어 두세요. 그래야 자동 복구가 증거를 지우지 않습니다.

## 5. 로그 키워드

| 키워드 | 의미 |
|---|---|
| `KEEPER_LOST` | WSL이 꺼졌거나 사람이 재시작함 → keeper 재기동 시도 |
| `KEEPALIVE_TASK_STARTED` | `WSL-AutoStart` 작업이 멈춰 있어 다시 시작함 |
| `RECOVERY_START mode=shutdown` | 자동 복구 시작 (오늘 몇 번째인지 표시) |
| `RECOVERY_OK wsl_tcp_ok_after=Ns` | 복구 성공 |
| `RECOVERY_FAILED ...` | 복구 실패. 수동 확인 필요 |
| `ALERT recovery_limit_reached` | 하루 한도 초과로 자동 복구 중단. 수동 확인 필요 |
| `MAINTENANCE_ON / OFF` | 유지보수 플래그 감지 / 해제 |
