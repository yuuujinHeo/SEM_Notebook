
# WSL2 Mirrored Networking 통신 장애 진단 가이드

Windows Wi-Fi 재연결 이후 WSL2 및 Docker(Muscat)에서 통신이 복구되지 않는 문제를 진단하기 위한 절차입니다.

> **주의**
> - `<TARGET_IP>`는 실제 통신 장애가 발생하는 대상 장비 IP로 변경합니다.
> - Wi-Fi 어댑터 재시작 및 `wsl --shutdown`은 통신을 중단시킵니다.
> - 장애 발생 시 복구 명령을 실행하기 전에 네트워크 상태를 먼저 기록합니다.

---

## 1. 기본 환경 확인

### 1.1 Windows 및 WSL 버전

**Windows PowerShell**

```powershell
wsl --version
wsl --status

Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber

Get-NetAdapter |
    Format-Table Name, InterfaceDescription, Status, LinkSpeed, MacAddress
```

### 1.2 WSL 설정 확인

**Windows PowerShell**

```powershell
Get-Content "$env:USERPROFILE\.wslconfig"
```

예상 설정:

```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
autoProxy=true
```

### 1.3 WSL 업데이트

**Windows PowerShell**

```powershell
wsl --update
wsl --shutdown
```

이후 WSL과 Muscat을 다시 실행합니다.

> 운영 중인 PC에서는 업데이트 및 재시작 전에 서비스 중단 가능성을 확인합니다.

---

## 2. 정상 상태 기록

장애가 발생하기 전에 Windows, WSL2, Docker의 정상적인 네트워크 상태를 기록합니다.

### 2.1 Windows

**Windows PowerShell**

```powershell
$target = "<TARGET_IP>"

ping.exe $target

Get-NetRoute -AddressFamily IPv4 |
    Sort-Object RouteMetric |
    Format-Table InterfaceAlias, DestinationPrefix, NextHop, RouteMetric
```

### 2.2 WSL2

**WSL Ubuntu**

```bash
TARGET_IP="<TARGET_IP>"

ip -br link
ip -br addr
ip route
ip route get "$TARGET_IP"
ip neigh show to "$TARGET_IP"

ping -c 5 "$TARGET_IP"
```

### 2.3 Muscat 컨테이너

**WSL Ubuntu**

```bash
docker exec muscat ping -c 5 <TARGET_IP>
```

### 2.4 정상 상태 판정

| Windows | WSL2 | Docker | 판단 |
|---|---|---|---|
| 성공 | 성공 | 성공 | 정상 |
| 성공 | 실패 | 실패 | WSL2 네트워크 계층 문제 의심 |
| 성공 | 성공 | 실패 | Docker 또는 컨테이너 네트워크 문제 의심 |
| 실패 | 실패 | 실패 | Windows 네트워크, 경로 또는 대상 장비 문제 의심 |

> Ping 결과만으로 원인을 확정할 수는 없습니다. 실제 서비스 장애를 확인하려면 FRS TCP 포트 연결 상태도 함께 점검해야 합니다.

---

## 3. Wi-Fi 재연결 반복 테스트

Wi-Fi 어댑터를 강제로 비활성화한 후 다시 활성화하여 WSL2의 네트워크 복구 동작을 확인합니다.

> **주의:** 이 테스트는 네트워크를 반복적으로 중단합니다. 운영 중인 로봇 PC에서는 실행하지 마세요.
>
> 또한 어댑터 강제 OFF/ON은 실제 802.1x 재협상, AP 로밍, 드라이버 자동 복구 이벤트와 동일하지 않습니다.

### 3.1 Wi-Fi 어댑터 이름 확인

**관리자 PowerShell**

```powershell
Get-NetAdapter
```

일반적인 인터페이스 이름은 `Wi-Fi`입니다.

### 3.2 반복 테스트 실행

**관리자 PowerShell**

```powershell
$adapter = "Wi-Fi"
$target = "<TARGET_IP>"

1..20 | ForEach-Object {
    $cycle = $_

    Write-Host "`n===== Cycle $cycle : DISABLE =====" -ForegroundColor Yellow

    Disable-NetAdapter -Name $adapter -Confirm:$false

    Start-Sleep -Seconds 3

    Write-Host "===== Cycle $cycle : ENABLE =====" -ForegroundColor Green

    Enable-NetAdapter -Name $adapter -Confirm:$false

    Start-Sleep -Seconds 10

    Write-Host "--- Windows ping ---"

    ping.exe -n 2 -w 2000 $target

    Write-Host "--- WSL route/ping ---"

    wsl -e bash -lc "date; ip -br addr; ip route get '$target'; ip neigh show to '$target'; ping -c 2 -W 2 '$target'"
}
```

테스트 중 다음 사항을 확인합니다.

- Wi-Fi 재연결 성공 여부
- Windows Ping 복구 여부
- WSL2 Ping 복구 여부
- Windows와 WSL2의 복구 시점 차이
- 재연결 후 라우팅 및 Neighbor 상태 변화

---

## 4. 장애 발생 순간 확인

Wi-Fi가 재연결되었지만 Muscat 통신이 복구되지 않는 경우, **WSL 종료 또는 컨테이너 재시작 전에** 아래 명령을 실행합니다.

### 4.1 Windows 상태 확인

**Windows PowerShell**

```powershell
$target = "<TARGET_IP>"

Write-Host "=== Windows ==="

ping.exe -n 4 -w 2000 $target

Get-NetAdapter |
    Format-Table Name, Status, LinkSpeed

Get-NetRoute -AddressFamily IPv4 |
    Sort-Object RouteMetric |
    Format-Table InterfaceAlias, DestinationPrefix, NextHop, RouteMetric
```

### 4.2 WSL2 상태 확인

**Windows PowerShell**

```powershell
$target = "<TARGET_IP>"

Write-Host "=== WSL ==="

wsl -e bash -lc "date; ip -br link; ip -br addr; ip route; ip route get '$target'; ip neigh show; ping -c 4 -W 2 '$target'"
```

### 4.3 WSL2 및 Muscat 비교

**WSL Ubuntu**

```bash
TARGET_IP="<TARGET_IP>"

echo "=== WSL ==="
ping -c 4 -W 2 "$TARGET_IP"

echo "=== Muscat ==="
docker exec muscat ping -c 4 -W 2 "$TARGET_IP"
```

---

## 5. 단계별 복구 테스트

복구는 영향 범위가 작은 작업부터 순서대로 수행합니다.

### 5.1 WSL2 Neighbor 캐시 초기화

**WSL Ubuntu**

```bash
TARGET_IP="<TARGET_IP>"

DEV="$(ip route get "$TARGET_IP" | awk '
{
    for (i = 1; i <= NF; i++) {
        if ($i == "dev") {
            print $(i+1)
            exit
        }
    }
}')"

echo "device=$DEV"

if [ -n "$DEV" ]; then
    sudo ip neigh flush dev "$DEV"
fi

sudo ip route flush cache

ping -c 5 -W 2 "$TARGET_IP"
```

> Neighbor 캐시 초기화는 기존 상태를 변경합니다. 실행 전 `ip neigh`와 `ip route get` 결과를 반드시 저장합니다.

### 5.2 WSL2 재시작

캐시 초기화로 복구되지 않는 경우 실행합니다.

**Windows PowerShell**

```powershell
wsl --shutdown
```

이 명령은 실행 중인 WSL 배포판과 해당 환경의 프로세스 및 컨테이너에 영향을 줄 수 있습니다.

### 5.3 WSL2 및 Muscat 재실행

**WSL Ubuntu**

```bash
TARGET_IP="<TARGET_IP>"

ping -c 5 "$TARGET_IP"

docker start muscat

docker exec muscat ping -c 5 "$TARGET_IP"
```

---

## 6. 최종 판정 기준

다음 조건이 관찰되면 **WSL2 mirrored networking의 복구 문제를 강하게 의심할 수 있습니다.**

1. Wi-Fi 재연결 후 Windows에서 대상 IP로 통신이 정상적으로 복구됩니다.
2. 같은 시점에 WSL2에서는 동일한 대상 IP로 통신이 실패합니다.
3. `ip route get`에서 비정상적인 경로가 확인되거나, 관련 Neighbor 항목이 `FAILED` 또는 `INCOMPLETE` 상태입니다.
4. Docker/Muscat 컨테이너 재시작만으로는 복구되지 않습니다.
5. `wsl --shutdown` 이후 통신이 정상적으로 복구됩니다.

> 위 조건은 WSL2 mirrored networking 문제를 의심할 수 있는 근거이며, WSL2 자체의 결함을 확정하는 증거는 아닙니다. Windows 방화벽, 인터페이스 경로, Hyper-V 네트워크 구성 등의 추가 확인이 필요할 수 있습니다.

---

## 7. 장애 분석 시 필수 확보 자료

- Windows 및 WSL 버전
- `.wslconfig` 설정
- Windows Wi-Fi 어댑터 및 드라이버 정보
- Windows 라우팅 테이블
- WSL2 IP 주소 및 라우팅 테이블
- WSL2 Neighbor 테이블
- Windows / WSL2 / Docker의 동일 대상 Ping 결과
- WLAN AutoConfig 이벤트 로그
- System 로그의 Wi-Fi 드라이버 관련 이벤트
- 장애 발생 시각 및 복구 시각
- `wsl --shutdown` 전후 통신 결과

### 주요 WLAN 이벤트

| 이벤트 ID | Provider | 의미 |
|---|---|---|
| 11004 | WLAN-AutoConfig | 무선 보안 중지 |
| 11010 | WLAN-AutoConfig | 무선 보안 시작 |
| 11005 | WLAN-AutoConfig | 무선 보안 성공 |
| 7003 | WLAN-AutoConfig | 로밍 완료 관련 |
| 4003 | WLAN-AutoConfig | 제한된 연결 자동 복구 관련 |
| 8000 | WLAN-AutoConfig | 무선 네트워크 연결 시작 |
| 8001 | WLAN-AutoConfig | 무선 네트워크 연결 성공 |
| 8003 | WLAN-AutoConfig | 무선 네트워크 연결 해제 |

> 이벤트 ID는 Provider와 함께 해석해야 합니다. 예를 들어 WLAN-AutoConfig의 8000과 Intel Wi-Fi 드라이버 Netwtw10의 8000은 의미가 다릅니다.

---

## 8. 핵심 주의사항

**장애 발생 시 `wsl --shutdown`을 실행하기 전에 Windows / WSL2 / Docker의 네트워크 상태를 반드시 저장합니다.**

WSL2를 종료하면 장애 당시의 라우팅, 인터페이스 및 Neighbor 상태가 사라질 수 있으므로, 복구 전에 증거를 확보하는 것이 원인 분석의 핵심입니다.

### 2.4 정상 상태 판정

| Windows | WSL2 | Docker | 판단 |
|---|---|---|---|
| 성공 | 성공 | 성공 | 정상 |
| 성공 | 실패 | 실패 | WSL2 네트워크 계층 문제 의심 |
| 성공 | 성공 | 실패 | Docker 또는 컨테이너 네트워크 문제 의심 |
| 실패 | 실패 | 실패 | Windows Wi-Fi, 라우팅, AP 또는 대상 장비 문제 의심 |
| 실패 | 성공 | 성공 | Windows와 WSL2/Docker의 경로 차이 또는 일시적 상태 차이 의심 |
| 성공 | 실패 | 성공 | WSL2와 Docker의 경로·네트워크 네임스페이스 차이 의심 |

> **주의:** Ping 성공/실패만으로 원인을 확정하지 않습니다.
>
> Windows, WSL2, Docker가 같은 대상 IP에 접근하는지 확인하고,
> 실제 서비스 TCP 포트도 함께 검사해야 합니다.
>
> 특히 대상 IP로 가는 트래픽이 Wi-Fi를 통과하는지 먼저 확인해야 합니다.

---

## 2.5 정상 3대와 장애 빈번 3대 비교

### 2.5.1 비교 목적

총 6대의 로봇 PC를 다음 두 그룹으로 구분합니다.

- **Group A:** 장애 발생 빈도가 낮은 기존 로봇 PC 3대
- **Group B:** 장애 발생 빈도가 높은 신규 로봇 PC 3대

다음 두 현상을 별도로 비교합니다.

1. Windows Wi-Fi 연결 끊김 및 드라이버 리셋 발생 빈도
2. Wi-Fi 재연결 이후 WSL2/Docker 통신 복구 실패 빈도

Wi-Fi 연결 끊김이 잦은 것과 WSL2가 복구되지 않는 것은 서로 다른 장애일 수 있습니다.

### 2.5.2 비교 항목

| 비교 항목 | 확인 목적 |
|---|---|
| Windows 빌드 | Windows 업데이트 차이 |
| WSL 버전 | WSL 네트워크 구현 차이 |
| `.wslconfig` | mirrored 등 설정 차이 |
| Docker 버전 | Docker 네트워크 구현 차이 |
| Wi-Fi 칩셋 | Intel AX210 등 하드웨어 차이 |
| Wi-Fi 드라이버 버전 | 드라이버 결함 또는 버전 차이 |
| Wi-Fi 드라이버 날짜 | 드라이버 배포 시점 차이 |
| Wi-Fi 절전 설정 | 전원 관리에 따른 연결 불안정 |
| SSID/BSSID | 연결된 AP 차이 |
| Wi-Fi 채널 | 주파수 및 채널 환경 차이 |
| RSSI/신호 품질 | 무선 신호 차이 |
| 802.1x 인증 방식 | 인증 및 재협상 조건 차이 |
| Windows IP/Gateway | 네트워크 주소 및 경로 차이 |
| Windows Route Metric | 잘못된 인터페이스 선택 여부 |
| WSL2 Route | mirrored 경로 동기화 여부 |
| Docker Network Mode | bridge/host 등 구성 차이 |
| WLAN 이벤트 발생 횟수 | 로밍·인증·자동 복구 빈도 |
| Wi-Fi 드라이버 이벤트 | 드라이버 재초기화 빈도 |

### 2.5.3 Windows 환경 정보 수집

**Windows PowerShell**

각 PC에서 동일한 명령을 실행합니다.

```powershell
$OutputDir = "$env:USERPROFILE\Desktop\network-diagnostic"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

wsl --version > "$OutputDir\wsl-version.txt"
wsl --status > "$OutputDir\wsl-status.txt"

Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber |
    Format-List |
    Out-File "$OutputDir\windows.txt"

Get-NetAdapter |
    Format-List * |
    Out-File "$OutputDir\adapters.txt"

Get-NetAdapter -Physical |
    Select-Object Name, InterfaceDescription, DriverVersion, DriverDate, Status |
    Format-List |
    Out-File "$OutputDir\drivers.txt"

Get-NetIPConfiguration |
    Format-List * |
    Out-File "$OutputDir\ip-configuration.txt"

Get-NetRoute -AddressFamily IPv4 |
    Sort-Object InterfaceIndex, DestinationPrefix |
    Format-Table -AutoSize |
    Out-File "$OutputDir\routes.txt" -Width 300

netsh wlan show interfaces > "$OutputDir\wifi-interface.txt"
netsh wlan show drivers > "$OutputDir\wifi-drivers.txt"
netsh wlan show profiles > "$OutputDir\wifi-profiles.txt"

if (Test-Path "$env:USERPROFILE\.wslconfig") {
    Copy-Item "$env:USERPROFILE\.wslconfig" "$OutputDir\wslconfig.txt"
}

Write-Host "Saved: $OutputDir"
```

수집된 파일을 정상 PC와 장애 PC별로 비교합니다.

**우선 확인할 차이**

1. Wi-Fi 어댑터 모델이 동일한가?
2. 드라이버 버전과 날짜가 동일한가?
3. Windows 및 WSL 버전이 동일한가?
4. `.wslconfig`의 `networkingMode`가 동일한가?
5. 동일한 SSID와 AP(BSSID)에 연결되어 있는가?
6. 기본 게이트웨이 및 Route Metric에 차이가 있는가?

> 설정 파일이 없거나 특정 명령 결과가 비어 있다면,
> 동일하다고 가정하지 말고 별도로 기록합니다.

### 2.5.4 WSL2 및 Docker 환경 비교

**WSL Ubuntu**

```bash
mkdir -p ~/network-diagnostic

uname -a > ~/network-diagnostic/kernel.txt

ip -br link > ~/network-diagnostic/interfaces.txt
ip -br addr > ~/network-diagnostic/addresses.txt
ip route show table all > ~/network-diagnostic/routes.txt
ip rule show > ~/network-diagnostic/rules.txt
ip neigh show > ~/network-diagnostic/neighbors.txt

docker version > ~/network-diagnostic/docker-version.txt
docker info > ~/network-diagnostic/docker-info.txt
docker network ls > ~/network-diagnostic/docker-networks.txt

docker inspect muscat \
    > ~/network-diagnostic/muscat-inspect.json
```

Muscat 컨테이너의 네트워크 모드 확인:

```bash
docker inspect muscat \
    --format '{{.HostConfig.NetworkMode}}'
```

확인할 항목:

- Docker Engine 버전
- Muscat 네트워크 모드
- 컨테이너 IP 주소
- 컨테이너 네트워크 네임스페이스
- WSL2 라우팅 테이블
- WSL2 인터페이스 상태

> Docker Desktop과 WSL 내부 Docker Engine은 네트워크 구성이 다를 수 있으므로 설치 방식도 기록합니다.

---

## 2.6 WLAN 및 Wi-Fi 드라이버 이벤트 비교

### 2.6.1 이벤트 로그 수집

**Windows PowerShell**

최근 7일간 WLAN 이벤트를 수집합니다.

```powershell
$Start = (Get-Date).AddDays(-7)
$Output = "$env:USERPROFILE\Desktop\wlan-events.csv"

$Ids = @(11004, 11010, 11005, 7003, 4003, 8000, 8001, 8003)

Get-WinEvent -FilterHashtable @{
    LogName = "Microsoft-Windows-WLAN-AutoConfig/Operational"
    StartTime = $Start
} -ErrorAction SilentlyContinue |
Where-Object { $_.Id -in $Ids } |
Select-Object TimeCreated, Id, ProviderName, Message |
Export-Csv $Output -NoTypeInformation -Encoding UTF8
```

Wi-Fi 드라이버 관련 System 이벤트도 별도로 수집합니다.

```powershell
$Start = (Get-Date).AddDays(-7)
$Output = "$env:USERPROFILE\Desktop\wifi-driver-events.csv"

Get-WinEvent -FilterHashtable @{
    LogName = "System"
    StartTime = $Start
} -ErrorAction SilentlyContinue |
Where-Object {
    $_.ProviderName -match "Netwtw|Intel|MediaTek|WLAN"
} |
Select-Object TimeCreated, Id, ProviderName, Message |
Export-Csv $Output -NoTypeInformation -Encoding UTF8
```

> 드라이버 이벤트는 이벤트 ID만으로 판단하지 않습니다.
> Provider와 Message를 함께 확인합니다.
>
> WLAN-AutoConfig의 8000과 Netwtw10의 8000은 다른 이벤트입니다.

### 2.6.2 비교 방법

각 PC에서 다음 항목을 집계합니다.

| 항목 | 정상 3대 | 장애 빈번 3대 |
|---|---|---|
| 11004 발생 횟수 | 측정 | 측정 |
| 11010 발생 횟수 | 측정 | 측정 |
| 11005 발생 횟수 | 측정 | 측정 |
| 7003 발생 횟수 | 측정 | 측정 |
| 4003 발생 횟수 | 측정 | 측정 |
| 드라이버 Halt/Reset 발생 횟수 | 측정 | 측정 |
| Windows 통신 복구 실패 횟수 | 측정 | 측정 |
| WSL2 통신 복구 실패 횟수 | 측정 | 측정 |
| Docker 통신 복구 실패 횟수 | 측정 | 측정 |

가능하면 동일한 7일 또는 14일 기간을 비교합니다.

가동시간이 다르면 단순 발생 횟수 대신
**24시간당 발생 횟수**로 비교합니다.

### 2.6.3 결과 해석

**A. 신규 3대에서 4003 및 드라이버 리셋이 더 많음**

우선 의심할 원인:

- Wi-Fi 드라이버 차이
- Wi-Fi 어댑터 하드웨어 차이
- AP 연결 환경 차이
- 802.1x 인증 재협상 문제
- Wi-Fi 절전 설정
- 무선 신호 또는 로밍 문제

**B. Wi-Fi 이벤트 빈도는 비슷하지만 신규 3대에서 WSL2 복구 실패가 더 많음**

우선 의심할 원인:

- WSL 버전 차이
- Windows 빌드 차이
- mirrored 네트워크 동기화 문제
- 라우팅 및 인터페이스 우선순위 차이
- Docker 네트워크 구성 차이

**C. Windows와 WSL2는 정상인데 Docker만 실패함**

우선 의심할 원인:

- 컨테이너 네트워크 설정
- Docker bridge 또는 host 네트워크 경로
- 컨테이너 내부 라우팅
- Docker 방화벽/NAT 규칙
- Muscat 애플리케이션의 연결 재시도 동작

---

## 2.7 장애 유형별 원인 분석 및 해결 방법

### CASE 1. Windows 성공 / WSL2 실패 / Docker 실패

**판정:** Windows 네트워크는 복구됐지만 WSL2 네트워크가 복구되지 않은 상황을 의심합니다.

#### 1) 장애 발생 시 확인

**Windows PowerShell**

```powershell
$target = "<TARGET_IP>"

ping.exe -n 4 $target

Find-NetRoute -RemoteIPAddress $target

Get-NetAdapter |
    Format-Table Name, Status, InterfaceDescription
```

**WSL Ubuntu**

```bash
TARGET_IP="<TARGET_IP>"

ip -br addr
ip route
ip rule
ip route get "$TARGET_IP"
ip neigh show

ping -c 4 -W 2 "$TARGET_IP"
```

#### 2) 정상 PC 3대와 비교

- WSL 버전
- Windows 빌드
- `.wslconfig`
- WSL 인터페이스 개수
- WSL IP 주소
- 대상 IP에 대한 라우팅 경로
- Windows와 WSL의 네트워크 인터페이스 매핑
- Wi-Fi 재연결 전후 경로 변화

#### 3) 가능한 원인과 해결 방법

| 가능한 원인 | 확인 방법 | 해결 방법 |
|---|---|---|
| WSL mirrored 경로 동기화 이상 | Windows와 WSL `route get` 비교 | 로그 확보 후 `wsl --shutdown`으로 복구 여부 확인 |
| WSL 라우팅 오류 | `ip route get` | 정상 PC와 설정 비교, 잘못된 경로의 생성 원인 수정 |
| Neighbor 상태 이상 | `ip neigh` | 관련 Neighbor 항목 확인 후 필요한 경우 캐시 초기화 |
| WSL 버전 차이 | `wsl --version` | 검증된 동일 버전으로 통일 |
| Windows 빌드 차이 | `Get-ComputerInfo` | 검증된 Windows 업데이트 수준으로 통일 |
| 방화벽/Hyper-V 정책 차이 | Windows 방화벽 및 Hyper-V 구성 비교 | 정책을 비교하여 차이 수정 |

#### 4) 복구 순서

1. Windows/WSL 네트워크 상태 저장
2. WSL 라우팅 및 Neighbor 상태 비교
3. 필요한 경우 Neighbor 캐시 초기화
4. 그래도 실패하면 `wsl --shutdown`
5. 재시작 후 통신 복구 여부 확인

> `wsl --shutdown`으로 복구된다고 해서 WSL 자체 결함이 확정되는 것은 아닙니다.
> WSL 재시작 과정에서 가상 네트워크 상태가 함께 재구성되기 때문입니다.

---

### CASE 2. Windows 성공 / WSL2 성공 / Docker 실패

**판정:** Docker 또는 컨테이너 네트워크 문제를 우선 의심합니다.

#### 1) 장애 발생 시 확인

**WSL Ubuntu**

```bash
TARGET_IP="<TARGET_IP>"

echo "=== WSL ==="
ip route get "$TARGET_IP"
ping -c 4 -W 2 "$TARGET_IP"

echo "=== Docker ==="
docker inspect muscat \
    --format '{{.HostConfig.NetworkMode}}'

docker exec muscat ip route

docker exec muscat ping -c 4 -W 2 "$TARGET_IP"
```

컨테이너에 `ip` 또는 `ping` 명령이 없다면
진단용 컨테이너를 동일 네트워크 네임스페이스에 연결하여 확인합니다.

```bash
docker run --rm \
    --network container:muscat \
    nicolaka/netshoot \
    sh -c 'ip route; ping -c 4 <TARGET_IP>'
```

#### 2) 정상 PC 3대와 비교

- Docker 버전
- Docker Engine 설치 방식
- Muscat 네트워크 모드
- Docker 네트워크 목록
- Docker bridge 설정
- 컨테이너 라우팅 테이블
- 컨테이너 DNS 설정
- 컨테이너 네트워크 관련 방화벽 규칙

#### 3) 가능한 원인과 해결 방법

| 가능한 원인 | 확인 방법 | 해결 방법 |
|---|---|---|
| Docker 네트워크 모드 차이 | `docker inspect` | 정상 PC와 네트워크 모드 통일 |
| 컨테이너 라우팅 오류 | 컨테이너 `ip route` | 네트워크 생성 및 라우팅 설정 수정 |
| Docker NAT/방화벽 문제 | Docker 네트워크 및 방화벽 규칙 비교 | 잘못된 규칙 수정 후 네트워크 재구성 |
| Docker 버전 차이 | `docker version` | 검증된 동일 버전으로 통일 |
| Muscat 연결 재시도 문제 | Muscat 로그 확인 | 연결 끊김 이후 재접속 로직 점검 |

#### 4) 복구 순서

1. 컨테이너 네트워크 상태 저장
2. Docker 네트워크 모드 확인
3. Muscat 프로세스의 재접속 동작 확인
4. 필요한 경우 Muscat 컨테이너 재시작
5. 그래도 실패하면 Docker 네트워크 계층 조사

> Docker 컨테이너 재시작만으로 복구되는 경우에는
> WSL 전체 재시작보다 컨테이너 네트워크 또는 애플리케이션 상태를 우선 조사합니다.

---

### CASE 3. Windows 실패 / WSL2 실패 / Docker 실패

**판정:** Windows Wi-Fi, AP, 인증, 라우팅 또는 대상 장비 문제를 우선 의심합니다.

#### 1) 장애 발생 시 확인

**Windows PowerShell**

```powershell
$target = "<TARGET_IP>"

Get-NetAdapter |
    Format-Table Name, Status, InterfaceDescription

Get-NetIPConfiguration

Find-NetRoute -RemoteIPAddress $target

netsh wlan show interfaces

ping.exe -n 4 $target
```

FRS TCP 포트 확인:

```powershell
Test-NetConnection <TARGET_IP> -Port 7447 -InformationLevel Detailed
```

#### 2) 정상 PC 3대와 비교

- Wi-Fi 칩셋
- Wi-Fi 드라이버 버전
- Wi-Fi 드라이버 날짜
- Wi-Fi 절전 설정
- SSID/BSSID
- AP 채널
- 신호 품질
- 802.1x 인증 설정
- 기본 게이트웨이
- Route Metric
- Windows WLAN 이벤트
- Wi-Fi 드라이버 재시작 이벤트

#### 3) 가능한 원인과 해결 방법

| 가능한 원인 | 확인 방법 | 해결 방법 |
|---|---|---|
| Wi-Fi 드라이버 불안정 | System 로그의 드라이버 리셋 | 제조사 권장 드라이버로 업데이트 또는 검증된 버전 적용 |
| AP 로밍 문제 | BSSID 변화, 7003 및 주변 이벤트 | AP 로밍 설정 및 커버리지 점검 |
| 802.1x 인증 문제 | 11004/11010/11005 및 인증 실패 로그 | RADIUS/AP/클라이언트 인증 설정 점검 |
| Wi-Fi 절전 문제 | 전원 관리 설정 비교 | 절전 기능 변경 후 안정성 비교 |
| 무선 신호 문제 | 신호 품질 및 채널 확인 | AP 배치, 출력, 채널 및 간섭 환경 점검 |
| Windows 라우팅 문제 | `Find-NetRoute`, `Get-NetRoute` | 잘못된 게이트웨이 또는 인터페이스 우선순위 수정 |
| 대상 장비 장애 | 다른 PC에서 동일 대상 테스트 | 대상 장비 및 중간 네트워크 점검 |

#### 4) 해결 우선순위

1. 정상 PC와 Wi-Fi 드라이버 버전 비교
2. Windows WLAN 및 드라이버 이벤트 빈도 비교
3. 동일 SSID에서 BSSID/AP 차이 확인
4. Wi-Fi 절전 설정 비교
5. 802.1x 인증 및 로밍 설정 확인
6. Windows 라우팅 및 게이트웨이 확인
7. 검증된 드라이버 또는 AP 설정 변경 후 재측정

> 현장 보고서에서 관찰된 `4003` 및 드라이버 리셋이 신규 3대에 집중된다면
> WSL2보다 먼저 Windows Wi-Fi 계층의 차이를 조사합니다.

---

### CASE 4. Windows 실패 / WSL2 성공 / Docker 성공

**판정:** Windows와 WSL2/Docker가 서로 다른 경로를 사용하거나,
측정 시점이 달랐을 가능성을 확인합니다.

#### 확인 사항

- Windows의 대상 IP 경로
- WSL2의 대상 IP 경로
- Windows에서 선택한 인터페이스
- Docker 네트워크 모드
- Windows 방화벽
- 측정 시각

**Windows PowerShell**

```powershell
Find-NetRoute -RemoteIPAddress <TARGET_IP>
```

**WSL Ubuntu**

```bash
ip route get <TARGET_IP>
```

#### 해결 방법

1. 실제 트래픽이 Wi-Fi를 사용하는지 확인
2. Windows와 WSL2의 경로 차이 확인
3. 방화벽 및 인터페이스 우선순위 확인
4. 동일 시점에 재측정

> 이 결과만으로 Windows Wi-Fi 장애라고 단정하지 않습니다.

---

### CASE 5. Windows 성공 / WSL2 실패 / Docker 성공

**판정:** WSL2 기본 네트워크 경로와 Docker 컨테이너의
네트워크 경로가 다른지 확인합니다.

#### 확인 사항

- Docker가 `host` 모드인지 `bridge` 모드인지
- Docker Desktop 사용 여부
- WSL2의 기본 경로
- Docker 네트워크 네임스페이스
- Windows/WSL/Docker의 실제 대상 경로

#### 해결 방법

1. WSL2 및 Docker의 라우팅 테이블 비교
2. 컨테이너 네트워크 모드 확인
3. 정상 PC와 Docker 설치 방식 비교
4. 서로 다른 경로를 사용하는 원인 확인

---

## 2.8 정상 3대와 장애 빈번 3대의 차이를 좁히는 절차

### STEP 1. 소프트웨어 및 하드웨어 비교

먼저 다음 항목을 6대 모두 수집합니다.

- Windows 빌드
- WSL 버전
- Docker 버전
- Wi-Fi 칩셋
- Wi-Fi 드라이버 버전
- `.wslconfig`
- Docker 네트워크 모드

**판정:**

신규 3대에서만 동일하게 다른 설정이 발견되면
해당 항목을 우선 검증합니다.

단, 설정이 다르다는 사실만으로 장애 원인이라고 확정하지 않습니다.

### STEP 2. Wi-Fi 이벤트 발생 빈도 비교

동일 기간의 이벤트를 비교합니다.

**판정 A: 신규 3대에서 4003/드라이버 리셋이 더 많음**

- Wi-Fi 드라이버
- AP
- 인증
- 로밍
- 절전
- 신호 품질

순서로 조사합니다.

**판정 B: Wi-Fi 이벤트 빈도는 비슷함**

Wi-Fi 자체보다 WSL2/Docker 복구 동작 차이를 추가 조사합니다.

### STEP 3. 설치 위치와 PC 환경 구분

정상 3대와 장애 빈번 3대의 설치 위치가 다르다면
다음 두 요인을 구분해야 합니다.

1. PC 하드웨어/소프트웨어 차이
2. 설치 위치/AP/무선 환경 차이

가능하면 동일한 AP 또는 유사한 무선 환경에서
정상 PC와 장애 PC의 연결 안정성을 비교합니다.

장비 교체나 위치 이동은 운영 영향이 없는 조건에서만 수행합니다.

**판정:**

- 장애가 특정 PC를 따라감 → PC/드라이버/OS 설정 의심
- 장애가 특정 위치나 AP를 따라감 → 무선 인프라 의심
- 두 조건 모두 영향을 줌 → 복합 원인 가능성

### STEP 4. 장애 발생 순간 3계층 통신 비교

동일한 대상 IP에 대해 다음 결과를 확보합니다.

| 항목 | 정상 PC | 장애 PC |
|---|---|---|
| Windows Ping | 기록 | 기록 |
| WSL2 Ping | 기록 | 기록 |
| Docker Ping | 기록 | 기록 |
| Windows TCP 7447 | 기록 | 기록 |
| WSL2 TCP 7447 | 기록 | 기록 |
| Docker TCP 7447 | 기록 | 기록 |
| Windows Route | 기록 | 기록 |
| WSL2 Route | 기록 | 기록 |
| Docker Route | 기록 | 기록 |

TCP 포트 확인 예시:

**Windows PowerShell**

```powershell
Test-NetConnection <TARGET_IP> -Port 7447
```

**WSL Ubuntu**

```bash
nc -vz -w 3 <TARGET_IP> 7447
```

**Muscat 컨테이너**

```bash
docker exec muscat nc -vz -w 3 <TARGET_IP> 7447
```

> `nc`가 설치되지 않았다면 다른 TCP 연결 검사 도구를 사용합니다.
> Ping은 정상이어도 TCP 연결이 실패할 수 있습니다.

### STEP 5. 복구 방법에 따른 원인 범위 확인

| 복구 동작 | 결과 | 우선 조사 대상 |
|---|---|---|
| Wi-Fi 재연결 | 정상 복구 | Wi-Fi/AP/인증/경로 |
| Muscat 프로세스 재시작 | 정상 복구 | Muscat 연결 관리 |
| Docker 컨테이너 재시작 | 정상 복구 | 컨테이너 네트워크/프로세스 |
| WSL 종료 및 재시작 | 정상 복구 | WSL 가상 네트워크/경로 동기화 |
| Windows 재부팅 | 정상 복구 | Windows 드라이버/네트워크 스택/WSL 등 |

> 복구 성공은 원인 범위를 좁히는 단서이지,
> 특정 구성 요소의 결함을 확정하는 증거는 아닙니다.

---

## 2.9 최종 분석 우선순위

현재 현장 상황에서 우선순위는 다음과 같습니다.

### 1순위: Wi-Fi 드라이버 및 자동 복구 이벤트

**이유:** 장애가 빈번한 PC에서 Wi-Fi 자동 복구 및 드라이버 리셋 이벤트가 더 자주 발생하는지 확인해야 합니다.

확인 항목:

- Intel Wi-Fi 드라이버 버전
- Netwtw 계열 이벤트
- WLAN 4003 이벤트
- 802.1x 재협상 이벤트
- AP/BSSID 변화

### 2순위: 정상 PC와 장애 PC의 환경 차이

확인 항목:

- Windows 빌드
- WSL 버전
- Docker 버전
- Wi-Fi 칩셋 및 드라이버
- 네트워크 설정
- 설치 위치/AP

### 3순위: Wi-Fi 복구 이후 WSL2 네트워크 상태

확인 항목:

- Windows는 정상인지
- WSL2는 정상인지
- Docker는 정상인지
- 라우팅이 변경되었는지
- `wsl --shutdown`으로 복구되는지

### 4순위: Muscat 연결 재시도 동작

확인 항목:

- TCP 연결 끊김 감지
- zenoh 재접속 동작
- 재시도 주기
- 네트워크 복구 이후 재접속 성공 여부

---

## 2.10 결론

6대의 로봇 PC에서 장애 발생 빈도가 다르다면,
단순히 WSL2 mirrored networking 문제로 판단해서는 안 됩니다.

우선 다음 두 질문에 대한 증거를 확보해야 합니다.

**Q1. 장애 빈번 3대는 Windows Wi-Fi 연결 끊김 및 드라이버 리셋 자체가 더 자주 발생하는가?**

그렇다면 Wi-Fi 드라이버, AP, 802.1x 인증, 로밍 및 무선 환경을 우선 조사합니다.

**Q2. Wi-Fi 연결 끊김 빈도는 비슷하지만 WSL2/Docker만 복구에 실패하는가?**

그렇다면 WSL2 mirrored networking, Docker 네트워크 구성, 라우팅 동기화 및 Muscat 재접속 동작을 우선 조사합니다.

가장 중요한 것은 장애 발생 시점의
**Windows / WSL2 / Docker 통신 상태와 이벤트 로그를 동시에 확보하는 것**입니다.
