# 공정3호기 Windows Wi-Fi 빈번한 연결 끊김 원인 분석 및 대응 방안

- **작성일:** 2026-10-15
- **대상:** 삼성전자 Metal A 공정3호기
- **분석 대상:** Windows Wi-Fi, Intel AX210, AP 로밍, 802.1X 인증, WSL2 네트워크
- **목적:** Windows Wi-Fi 연결이 빈번하게 끊기는 원인을 분석하고, WSL 및 Muscat/FRS 통신 장애와의 연관성을 확인한다.

---

## 1. 현재까지의 결론

공정3호기의 Windows Wi-Fi 연결이 빈번하게 끊기는 원인은 아직 확정되지 않았다.

다만 지금까지 확보한 로그와 네트워크 환경을 종합하면 다음 세 가지를 우선 의심할 수 있다.

1. **다수 AP 환경에서의 빈번한 로밍**
2. **802.1X 인증 또는 암호화 키 재협상 과정의 문제**
3. **Intel AX210 무선랜 드라이버의 연결 복구 또는 재설정 문제**

특히 공정3호기는 정지 상태에서도 동일 SSID의 AP가 약 20개 검색되는 것으로 파악되었다.

로봇이 움직이지 않더라도 AP별 신호 세기(RSSI), 간섭, 채널 혼잡도 등에 따라 로밍이 발생할 수 있다.

그러나 주변 AP가 많이 검색된다는 사실만으로 실제 로밍이 빈번하다고 단정할 수는 없다.

**Wi-Fi 연결 해제 직전에 BSSID가 변경되었는지, 인증 이벤트가 발생했는지, 드라이버가 재설정되었는지를 구분해야 한다.**

---

## 2. 시스템 환경

### 2.1 주요 구성

| 항목 | 내용 |
|---|---|
| 장비 | 공정3호기 |
| 운영체제 | Windows + WSL2 Ubuntu 22.04 |
| 무선랜 | Intel Wi-Fi 6E AX210 |
| Windows Wi-Fi IP | 10.249.138.60/24 |
| Wi-Fi Gateway | 10.249.138.1 |
| WSL 네트워크 | mirrored |
| FRS 서버 | 10.244.201.165:7447 |
| 주요 프로그램 | Muscat, Docker, Zenoh |

### 2.2 WSL 네트워크 설정

현재 `.wslconfig` 설정:

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
firewall=false
```

mirrored 모드는 Windows의 네트워크 인터페이스 구성을 WSL에 반영한다.

따라서 Windows Wi-Fi 인터페이스의 상태 변화가 WSL 네트워크 장치 처리에도 영향을 줄 수 있다.

단, Windows Wi-Fi 연결 해제가 반드시 WSL 커널 고착을 유발하는 것은 아니다.

---

## 3. 확인된 장애 현상

### 3.1 Windows Wi-Fi 이벤트

기존 로그 분석에서 다음 이벤트가 확인되었다.

| 일시 | 이벤트 | 내용 |
|---|---|---|
| 2026-10-04 11:47:29 | 4003 | Wi-Fi 연결 관련 이벤트 |
| 2026-10-04 11:47경 | 8000 | Wi-Fi 연결 관련 이벤트 |
| 2026-10-14 08:38:20 | 4003 / 8000 | Wi-Fi 연결 상태 변화 |
| 2026-10-14 08:38:22 | WSL `ip` 명령 정체 | 네트워크 조회 작업 D 상태 |

※ 4003 및 8000의 정확한 의미는 해당 이벤트의 공급자와 메시지 원문을 기준으로 해석해야 한다.

10월 14일에는 Windows Wi-Fi 이벤트 발생 약 2초 후 WSL 네트워크 조회 명령이 정체된 것으로 파악되었다.

이는 두 현상 사이에 시간적 연관성이 있음을 보여주지만, 직접적인 인과관계가 증명된 것은 아니다.

### 3.2 Windows와 WSL의 통신 상태 차이

장애 발생 중 다음 현상이 확인되었다.

**Windows:**

```powershell
Test-NetConnection 10.244.201.165 -Port 7447
```

결과:

```text
TcpTestSucceeded : True
```

**WSL:**

```bash
timeout -k 2s 5s bash -c \
'echo > /dev/tcp/10.244.201.165/7447'
```

결과:

```text
No route to host
```

즉, Windows에서는 FRS 서버에 접속할 수 있었지만 WSL에서는 접속할 수 없었다.

따라서 해당 시점의 FRS 통신 장애는 단순한 외부 Wi-Fi 단절만으로 설명하기 어렵다.

---

## 4. Windows Wi-Fi 연결이 자주 끊기는 원인 후보

### 4.1 원인 1 — 다수 AP 환경에서의 빈번한 로밍

**현재 우선 조사 대상**

공정3호기는 정지 상태에서도 주변에 동일 SSID의 AP가 약 20개 검색되는 것으로 파악되었다.

Wi-Fi 클라이언트는 로봇이 이동하지 않더라도 다음 조건에 따라 AP를 변경할 수 있다.

- 현재 AP의 RSSI 감소
- 다른 AP의 상대적인 신호 개선
- 주변 장비로 인한 전파 간섭
- 채널 혼잡도 변화
- AP의 로드 밸런싱 또는 스티어링 정책
- 무선랜 드라이버의 로밍 판단

예상 가능한 흐름:

```text
로봇 정지 상태
    |
    v
동일 SSID의 다수 AP 검색
    |
    v
신호 세기 또는 무선 환경 변화
    |
    v
AP 로밍 판단
    |
    v
기존 AP 연결 해제
    |
    v
다른 AP 연결 및 인증
```

정상적인 로밍이라면 연결 중단 시간이 짧고 자동 복구되어야 한다.

그러나 로밍 과정에서 인증이나 드라이버 문제가 발생하면 연결 복구가 지연될 수 있다.

**확인해야 할 사항:**

1. 장애 직전 BSSID 변경 여부
2. 동일 AP 사이를 반복적으로 이동하는지
3. 특정 BSSID에서 장애가 집중되는지
4. 로밍 직전 RSSI 및 채널 상태
5. AP 컨트롤러의 로밍 및 연결 해제 사유

**주의:** 주변 AP 20개 검색 = 실제 AP 20개 사이를 로밍한다는 뜻은 아니다.

---

### 4.2 원인 2 — 802.1X 인증 및 키 재협상 문제

**현재 우선 조사 대상**

기존 WLAN 로그에서 다음과 같은 보안 관련 이벤트 흐름이 관찰되었다.

```text
11004
  |
  v
11010
  |
  v
11005
  |
  v
일부 구간에서 7003 미확인
  |
  v
4003 / 8000
```

이벤트 ID는 공급자별로 의미가 다를 수 있으므로 실제 메시지를 함께 확인해야 한다.

기업용 Wi-Fi에서는 다음 과정이 연결 유지에 영향을 줄 수 있다.

- 802.1X 재인증
- RADIUS 인증
- PMK 캐시 또는 OKC 동작
- 802.11r Fast Transition
- 그룹 키(GTK) 갱신
- AP 간 보안 컨텍스트 전환

특히 공정3호기에서 일정한 주기로 문제가 반복된다면 재인증 또는 키 갱신 주기와의 연관성을 확인할 필요가 있다.

기존 분석에서는 약 74분 간격의 보안 이벤트 패턴이 의심되었으나, 실제 정책 주기와 일치하는지는 검증되지 않았다.

**확인해야 할 사항:**

1. Wi-Fi 인증 방식(WPA2/WPA3 Enterprise 등)
2. 802.1X 재인증 주기
3. RADIUS 서버의 인증 성공·실패 기록
4. AP 컨트롤러의 키 갱신 설정
5. 802.11r 및 OKC 적용 여부
6. 인증 이벤트와 4003/8000 발생 시각의 관계

---

### 4.3 원인 3 — Intel AX210 무선랜 드라이버 문제

**현재 우선 조사 대상**

공정3호기는 Intel Wi-Fi 6E AX210을 사용한다.

드라이버와 AP 컨트롤러 사이의 호환성, 무선 연결 복구 처리, 전원 관리 등이 불안정하면 로밍 또는 재인증 과정에서 연결이 끊길 수 있다.

가능한 원인은 다음과 같다.

- 오래된 무선랜 드라이버
- 특정 AP 펌웨어와의 호환성
- 로밍 처리 중 드라이버 오류
- 인증 실패 이후 연결 복구 오류
- 무선랜 절전 설정
- 드라이버 또는 장치 재설정

**중요:** Windows WLAN 이벤트 4003/8000만으로 AX210 드라이버 자체가 리셋되었다고 확정할 수 없다.

장치 재설정 여부는 Windows System 이벤트, WLAN 이벤트 메시지, Intel 드라이버 관련 이벤트를 함께 확인해야 한다.

---

### 4.4 원인 4 — 공정 구역의 RF 환경

공정 구역은 물류 구역보다 다음 조건의 영향을 더 크게 받을 수 있다.

- 금속 설비로 인한 반사 및 다중 경로
- AP 간 커버리지 중첩
- 주변 설비에 의한 간섭
- 채널 혼잡
- AP 출력 및 채널 설계 차이
- 특정 위치에서의 신호 품질 변동

기존 분석에서는 공정 PC에서 Wi-Fi 연결 관련 이벤트가 물류 PC보다 더 자주 발생하는 경향이 관찰되었다.

이 차이가 반복적으로 재현된다면 단순 PC 문제뿐 아니라 공정 구역의 무선 환경 또는 AP 설정도 확인해야 한다.

---

### 4.5 원인 5 — 무선랜 전원 관리

Windows 또는 Intel 무선랜 드라이버의 전원 관리 설정도 연결 안정성에 영향을 줄 수 있다.

다만 현재 로그에서는 전원 관리가 직접적인 원인이라는 증거가 부족하다.

따라서 설정을 바로 변경하기보다 현재 값을 확인한 뒤 다른 원인과 비교하는 것이 좋다.

---

## 5. 원인 구분 기준

| 장애 발생 시 확인 결과 | 우선 의심 원인 |
|---|---|
| 장애 직전 BSSID 변경 | AP 로밍 및 인증 전환 |
| BSSID 변경 없이 보안 이벤트 반복 | 802.1X 재인증 또는 키 갱신 |
| 인증 실패 없이 장치 재설정 | AX210 드라이버 또는 전원 관리 |
| 특정 BSSID에서만 반복 | 해당 AP 설정 또는 RF 환경 |
| 여러 PC에서 동일 시각 장애 | AP/WLC/RADIUS 등 공통 인프라 |
| Windows 통신 정상, WSL만 장애 | WSL/Hyper-V 네트워크 처리 문제 |

---

## 6. 공정3호기에서 실행할 진단 명령어

모든 명령어는 **Windows PowerShell**에서 실행한다.

### 6.1 현재 연결된 AP 확인

```powershell
netsh wlan show interfaces
```

확인 항목:

- SSID
- BSSID
- 신호 세기
- 채널
- 연결 상태
- 무선 규격

특히 **BSSID는 실제 연결된 AP를 구분하는 핵심 정보**이다.

### 6.2 주변 AP 목록 확인

```powershell
netsh wlan show networks mode=bssid
```

동일 SSID의 BSSID가 몇 개 검색되는지 확인한다.

이 명령어는 주변 AP 검색 결과이며 실제 로밍 이력은 아니다.

### 6.3 AX210 드라이버 버전 확인

```powershell
Get-CimInstance Win32_PnPSignedDriver |
Where-Object {
    $_.DeviceName -match 'AX210|Wi-Fi 6E'
} |
Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer
```

확인 항목:

- 드라이버 버전
- 드라이버 날짜
- 제조사

다른 공정 PC 및 물류 PC와 비교한다.

### 6.4 Wi-Fi 연결 보고서 생성

```powershell
netsh wlan show wlanreport
```

Windows가 생성한 WLAN 보고서에서 연결·해제·인증 실패 시각을 확인한다.

### 6.5 장애 시각 WLAN 이벤트 전체 확인

10월 14일 장애 시각 기준:

```powershell
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'
    StartTime = [datetime]'2026-10-14 08:37:00'
    EndTime = [datetime]'2026-10-14 08:39:30'
} |
Select-Object TimeCreated, Id, ProviderName, Message |
Format-List
```

이벤트 ID를 일부만 필터링하지 않고 장애 직전과 직후의 전체 흐름을 확인한다.

### 6.6 무선랜 고급 설정 확인

```powershell
Get-NetAdapterAdvancedProperty -Name "Wi-Fi" |
Where-Object {
    $_.DisplayName -match 'Roaming|로밍|Power|전원'
} |
Format-Table DisplayName, DisplayValue -AutoSize
```

Wi-Fi 어댑터 이름이 다르면 실제 이름으로 변경한다.

설정은 우선 확인만 진행하고, 변경 시에는 운영 승인 및 변경 전 설정값 백업이 필요하다.

---

## 7. 정지 상태에서 BSSID 변경 기록

로봇이 정지한 상태에서 실제 로밍이 발생하는지 확인한다.

PowerShell:

```powershell
$log = "$env:USERPROFILE\Desktop\wifi-bssid-history.csv"

while ($true) {
    $raw = netsh wlan show interfaces

    $ssid = (
        $raw |
        Select-String '^\s*SSID\s*:' |
        Select-Object -First 1
    )

    $bssid = (
        $raw |
        Select-String '^\s*BSSID\s*:' |
        Select-Object -First 1
    )

    $signal = (
        $raw |
        Select-String '^\s*(Signal|신호)\s*:' |
        Select-Object -First 1
    )

    $channel = (
        $raw |
        Select-String '^\s*(Channel|채널)\s*:' |
        Select-Object -First 1
    )

    [PSCustomObject]@{
        Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        SSID = if ($ssid) {
            ($ssid.ToString() -split ':',2)[1].Trim()
        } else {
            ""
        }

        BSSID = if ($bssid) {
            ($bssid.ToString() -split ':',2)[1].Trim()
        } else {
            ""
        }

        Signal = if ($signal) {
            ($signal.ToString() -split ':',2)[1].Trim()
        } else {
            ""
        }

        Channel = if ($channel) {
            ($channel.ToString() -split ':',2)[1].Trim()
        } else {
            ""
        }
    } |
    Export-Csv $log -NoTypeInformation -Append -Encoding UTF8

    Start-Sleep -Seconds 5
}
```

- 기록 간격: 5초
- 권장 관찰 시간: 1~2시간 이상
- 저장 위치: 바탕화면 `wifi-bssid-history.csv`
- 종료: `Ctrl + C`

**주의:** 5초보다 짧은 로밍은 누락될 수 있으므로 Windows WLAN 이벤트와 함께 분석해야 한다.

### 7.1 BSSID 변경 시점만 추출

```powershell
$rows = Import-Csv "$env:USERPROFILE\Desktop\wifi-bssid-history.csv"

$prev = $null

$rows | ForEach-Object {
    if ($_.BSSID -ne $prev) {
        $_
        $prev = $_.BSSID
    }
} | Format-Table -AutoSize
```

정지 상태에서 BSSID가 여러 번 변경된다면 실제 AP 로밍이 발생했다는 근거가 된다.

---

## 8. WSL 및 FRS 장애와의 관계

기존 WSL 커널 진단 자료 `blocked_full.txt`에서 다음 스택이 확인되었다.

```text
Workqueue: hv_vmbus_rescind vmbus_onmessage_work

schedule
rndis_filter_device_remove
netvsc_remove
vmbus_remove
vmbus_onoffer_rescind
```

동시에 다음 프로세스들이 `rtnl_lock()`에서 대기하고 있었다.

```text
GnsEngine
rx-5
kworker/u64:0
```

다수의 `ip` 프로세스 역시 RTNETLINK 관련 작업에서 대기하였다.

이 결과는 **WSL/Hyper-V 가상 네트워크 장치 제거 작업과 RTNL 락 정체가 동시에 발생했음**을 보여준다.

그러나 RTNL 락을 실제로 점유한 태스크와 장치 제거 작업의 정확한 대기 원인은 아직 확인되지 않았다.

### 8.1 현재 가장 유력한 장애 시나리오

```text
공정 구역의 무선 환경 / AP 로밍 / 802.1X 재인증
                      |
                      v
           Windows Wi-Fi 연결 변화
                      |
                      v
           Windows 네트워크 재구성
                      |
                      v
       WSL2 mirrored 네트워크 변경 처리
                      |
                      v
       Hyper-V VMBus/netvsc 장치 처리 정체
                      |
                      v
             RTNL 관련 작업 정체
                      |
                      v
           WSL 네트워크 조회 및 통신 장애
                      |
                      v
             Muscat → FRS 연결 실패
```

위 흐름은 현재 증거와 부합하는 **유력 가설**이며, 모든 단계의 인과관계가 확정된 것은 아니다.

---

## 9. 대응 방향

### 9.1 1차 — Windows Wi-Fi 연결 불안정 원인 조사

우선순위:

1. 장애 직전 BSSID 변경 여부 확인
2. WLAN 이벤트와 802.1X 인증 이벤트 비교
3. AX210 드라이버 버전 및 설정 비교
4. AP/WLC/RADIUS 로그 확인
5. 공정 PC와 물류 PC의 차이 분석

네트워크 담당자에게 요청할 자료:

- 장애 시각의 클라이언트 로밍 이력
- 연결 해제 사유(Disassociation/Deauthentication reason)
- 802.1X 재인증 결과
- RADIUS 인증 로그
- 802.11r 및 OKC 설정
- AP별 RSSI/SNR 및 채널 상태

### 9.2 2차 — WSL mirrored → NAT 시험

공정3호기를 우선 대상으로 NAT 모드 전환을 검토한다.

**기대 효과:**

- Windows Wi-Fi 인터페이스 변경이 WSL 가상 NIC에 직접 반영되는 경로 감소
- mirrored 네트워크의 장치 변경 처리 문제를 우회할 가능성

**한계:**

- Windows Wi-Fi 자체의 연결 해제는 해결하지 못함
- Wi-Fi 연결이 끊긴 동안 외부 FRS 통신은 중단될 수 있음
- NAT에서도 다른 원인으로 WSL 네트워크 장애가 발생할 수 있음
- 외부에서 WSL 또는 Docker 컨테이너로 먼저 접속하는 통신은 별도 검증 필요

전환 전 확인 항목:

- FMS → 로봇 PC 연결
- FRS/Zenoh 통신 방향
- Muscat API 포트
- TCP/UDP 사용 여부
- mDNS 및 브로드캐스트 의존성
- Docker 네트워크 구성
- 포트 포워딩 필요 여부

### 9.3 3차 — Windows Watcher 기반 복구

Windows에서 WSL 통신 상태를 감시하는 Watcher를 검토한다.

권장 판정 흐름:

```text
Windows → FRS TCP 확인
          |
          +-- 실패
          |     |
          |     v
          |  외부 네트워크 장애로 분류
          |  WSL 재시작하지 않음
          |
          +-- 성공
                |
                v
          WSL → FRS TCP 확인
                |
                +-- 성공: 정상
                |
                +-- 반복 실패
                       |
                       v
                WSL 상태 및 안전 조건 확인
                       |
                       v
                진단 로그 확보
                       |
                       v
                승인된 복구 절차 수행
                       |
                       v
                Muscat/Zenoh/FRS 재연결 검증
```

Watcher는 처음에는 모니터링 전용으로 운영하고, 자동 재시작은 로봇 안전 상태 확인 및 운영 승인 후 적용한다.

`wsl --shutdown`은 다른 WSL 배포판과 관련 서비스에도 영향을 줄 수 있으므로 주의해야 한다.

---

## 10. 공정4호기 비교 분석

공정4호기는 공정3호기와 일부 네트워크 설정이 다른 것으로 파악되었다.

| 비교 항목 | 공정3호기 | 공정4호기 |
|---|---|---|
| Windows Wi-Fi | 사용 | 사용 |
| WSL 네트워크 모드 | mirrored | 확인 필요 |
| 유선 게이트웨이 | 설정됨 | 없음 |
| 유선 DNS 설정 | 존재 | 차이 있음 |
| AX210 드라이버 | 버전 재확인 | 버전 확인 필요 |
| Wi-Fi 이벤트 빈도 | 높음 | 비교 필요 |

공정4호기의 WSL 네트워크 모드와 드라이버, AP 연결 이력을 확인하면 공정3호기 문제를 구분하는 데 도움이 될 수 있다.

---

## 11. 최종 판단

### 확인된 사실

- 공정3호기에서 Windows Wi-Fi 연결 관련 이벤트가 반복 발생한다.
- Windows Wi-Fi 이벤트와 WSL 네트워크 정체 사이에 시간적 연관성이 있다.
- 장애 중 Windows는 FRS에 접속 가능했지만 WSL은 접속하지 못했다.
- WSL에서 다수의 RTNL 관련 작업이 D 상태로 대기했다.
- Hyper-V 가상 네트워크 장치 제거 작업도 대기 상태였다.

### 유력한 원인 후보

1. 다수 AP 환경에서의 로밍
2. 802.1X 재인증 또는 키 재협상
3. Intel AX210 드라이버의 연결 복구 문제
4. WSL mirrored 네트워크의 장치 변경 처리 문제

### 아직 확정되지 않은 사항

- 실제 로밍 빈도와 BSSID 변경 이력
- Wi-Fi 연결 해제의 직접적인 원인
- AX210 드라이버 자체의 재설정 여부
- RTNL 락 실제 점유자
- NAT 전환으로 WSL 고착이 예방되는지

---

## 12. 보고용 요약

공정3호기의 Windows Wi-Fi 연결이 빈번하게 끊기는 원인은 아직 확정되지 않았으나, 다수 AP 환경에서의 로밍, 802.1X 인증·키 재협상, Intel AX210 무선랜 드라이버 문제를 우선 조사할 필요가 있다.

기존 로그에서는 Wi-Fi 연결 관련 이벤트 발생 직후 WSL 네트워크 조회가 정체되었고, 커널 진단 결과 Hyper-V 가상 네트워크 장치 제거 작업과 RTNL 락 대기가 동시에 확인되었다.

따라서 장애를 다음 두 영역으로 나누어 대응할 예정이다.

**① Windows Wi-Fi 연결 불안정 원인 개선**

BSSID 변경 이력, WLAN 이벤트, AX210 드라이버, AP/WLC/RADIUS 로그를 비교하여 Wi-Fi 연결 해제 원인을 조사한다.

**② Wi-Fi 연결 변화에 따른 WSL 장애 예방 및 복구**

공정3호기에서 WSL mirrored → NAT 전환을 시험하고, 통신 호환성을 확인한다. 또한 WSL 네트워크 고착 발생 시 Windows Watcher를 통한 통제된 복구 방안을 검토한다.

**최종 결론: Windows Wi-Fi의 빈번한 연결 변화가 WSL 장애의 트리거일 가능성이 높으며, Wi-Fi 불안정 원인 분석과 WSL 네트워크 구조 개선을 병행하는 것이 현재 가장 합리적인 대응 방향이다.**