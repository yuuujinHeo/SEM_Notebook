# 문제 2 — P2 candidates 요청 타임아웃 (10/15 09:50경, 이후 자연 회복)

이 문서에는 WSL 재시작·종료 명령이 없습니다.

## 1. 지금까지 확인된 사실

| 항목 | 내용 |
|---|---|
| 증상 | Windows의 호출 프로그램이 FRS `POST /api/v1/amrs/candidates` 호출 시 `http client timeout` |
| 호출 주체 | WSL/muscat이 아니라 **Windows 프로그램** (muscat은 정상) |
| FRS 수신 여부 | 해당 시간대 FRS 로그에 **P2의 candidates 요청이 없음**. 요청이 FRS에 도착하지 않았음 |
| 다른 API | 정상 호출됨 (같은 프로그램이 같은 시각에 호출한 것인지 확인 필요) |
| 경과 | 현장 확인 시점에는 이미 정상. 직접 호출해도 정상 |
| 참고 | FRS의 candidates 응답 시간은 10/5~10/8 3,061건 기준 중앙값 약 50ms, 최대 152ms. 무응답 0건 |

**지금 확인할 질문: Wi-Fi 끊김 때문에 요청이 나가지 못한 것인가?**

## 2. P2에서 Wi-Fi 끊김 시각 뽑기 (P2 PowerShell 관리자)

```powershell
$A='C:\Users\admin\Desktop\ALGN'; $o="$A\p2_0950"
New-Item -ItemType Directory -Force $o | Out-Null
$s=[datetime]'2026-10-15 09:00'; $e=[datetime]'2026-10-15 10:30'

Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$s;EndTime=$e} -ErrorAction SilentlyContinue |
  ? { $_.Id -in 4003,8000 -and $_.ProviderName -match 'WLAN|Netwtw' } |
  select @{n='T';e={$_.TimeCreated.ToString('HH:mm:ss')}},ProviderName,Id | Sort-Object T |
  Out-File $o\wifi_reset.txt

Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-WLAN-AutoConfig/Operational';StartTime=$s;EndTime=$e} -ErrorAction SilentlyContinue |
  ? Id -in 8003,8001,11004,11005 |
  select @{n='T';e={$_.TimeCreated.ToString('HH:mm:ss')}},Id | Sort-Object T |
  Out-File $o\wifi_conn.txt

Get-Content $o\wifi_reset.txt, $o\wifi_conn.txt
```

| 이벤트 | 의미 |
|---|---|
| 4003 / 8000 | Windows가 Wi-Fi 드라이버를 리셋함 (문제 1의 15초 통신 불가 → 리셋) |
| 8003 | 연결 끊김 |
| 8001 | 다시 연결됨 |
| 11004 → 11005 | 보안 재설정 (문제 1의 "정체불명 재연결"이면 15초 뒤 4003으로 이어짐) |

## 3. FRS에서 P2(.206) 요청을 분 단위로 세기 (FRS 서버)

```bash
grep '\[HttpRequest\]' logs/gateway-api/2026-10-15/gateway-api/application.log \
 | grep '"ip":"10.249.138.206"' | cut -c2-17 \
 | awk '$2>="09:00" && $2<="10:30"' | uniq -c
```
- 1분 단위로 P2 요청 건수가 출력됩니다. 요청이 없던 분은 목록에 나오지 않습니다.
- candidates만 따로 보려면 첫 줄 뒤에 `| grep candidates`를 추가합니다.

## 4. 판단 기준

| 결과 | 판단 |
|---|---|
| 타임아웃 시각에 P2 Wi-Fi 이벤트(4003/8003)가 있고, 그 시각 FRS에 .206 요청이 **전혀 없음** | **Wi-Fi 끊김 때문** |
| 타임아웃 시각에 Wi-Fi 이벤트가 없고, FRS에 .206의 다른 요청이 **계속 들어옴** | **Wi-Fi 문제 아님** → 호출 프로그램 쪽 문제 |
| 타임아웃이 **몇 분 이상** 지속됐는데 Wi-Fi 이벤트는 **한두 번**뿐 | Wi-Fi가 계기였을 수는 있으나, 지속된 원인은 프로그램이 끊긴 연결을 계속 재사용한 것 |

참고: Wi-Fi 끊김 한 번은 보통 15~20초이고, 리셋이 연달아 나도 몇 분 안에 끝납니다.

## 5. 함께 알려 줄 것

- 호출 프로그램의 **타임아웃 발생 시각** (첫 실패 ~ 마지막 실패)
- "다른 API 정상"이 **같은 프로그램이 같은 시각에 호출한 것**인지, 나중에 직접 호출한 결과인지
- 호출 프로그램 이름, 개발 언어/HTTP 라이브러리, 타임아웃 값, 연결 재사용(keep-alive) 설정
- P2의 IP가 10.249.138.206이 맞는지

## 6. 다시 발생하면 바로 실행 (그 순간의 연결 상태 기록)

```powershell
Get-NetTCPConnection -RemoteAddress 10.244.201.165 -ErrorAction SilentlyContinue |
  Select LocalAddress,LocalPort,RemotePort,State,OwningProcess,@{n='Proc';e={(Get-Process -Id $_.OwningProcess).ProcessName}},CreationTime |
  ft -AutoSize | Out-File C:\Users\admin\Desktop\ALGN\tcp_to_frs_fail.txt
Find-NetRoute -RemoteIPAddress 10.244.201.165 | Out-File C:\Users\admin\Desktop\ALGN\route_to_frs_fail.txt
```
FRS로 향한 연결이 몇 개 열려 있는지, 상태가 어떤지, 어느 프로세스의 것인지와, 요청이 어느 NIC로 나가는지를 기록합니다.
