# P3(.60) 커널 작업자(kworker) 스택 수집 — 멈춘 상태 그대로 실행

**이 문서에는 WSL을 재시작·종료하는 명령이 없습니다. 분석이 끝날 때까지 WSL과 PC를 재시작하지 않습니다.**
WSL 안에서 `ip`, `ifconfig`, `hostname`, `sudo`, `nmcli` 사용 금지.
모든 명령은 **Windows PowerShell(관리자)** 에서 실행합니다. 기본 폴더는 `C:\Users\admin\Desktop\ALGN`입니다.

---

## 1. 실행

```powershell
$o='C:\Users\admin\Desktop\ALGN\frozen'
New-Item -ItemType Directory -Force $o | Out-Null
wsl -d Ubuntu-22.04 -u root -e sh -c "dmesg -C; echo w > /proc/sysrq-trigger; sleep 3; dmesg > /mnt/c/Users/admin/Desktop/ALGN/frozen/sysrq_w_now.txt"
Select-String -Path $o\sysrq_w_now.txt -Pattern 'kworker' -Context 0,45 | Out-File $o\kworker_now.txt
Select-String -Path C:\Users\admin\blocked_full.txt -Pattern 'kworker' -Context 0,45 | Out-File $o\kworker_yesterday.txt
```

## 2. 압축 후 업로드

```powershell
Compress-Archive $o\sysrq_w_now.txt,$o\kworker_now.txt,$o\kworker_yesterday.txt C:\Users\admin\Desktop\ALGN\P3_kworker.zip -Force
```

`P3_kworker.zip`을 GitHub `1015/ljs/`에 올립니다.

---

## 참고: 지금까지 확인된 사실

**1차 자료(P3_멈춤상태결과1/2, sysrq-t)**
- `hv_vmbus_rescind` 작업 큐에서 kworker/0:2(전역 pid 27078)가 `vmbus_onmessage_work` 처리 중 D 상태로 멈춰 있고, 그 뒤에 VMBus 메시지 **706개**가 대기 중입니다.
- 시작 시점은 10/14 08:38:20.984, Hyper-V가 Wi-Fi 미러 NIC를 Remove한 순간입니다. 08:38:22 Add 메시지도 대기열에 갇혀 반영되지 못했습니다.
- Windows/HNS 쪽 Remove/Add는 모두 성공(0x0)했습니다.

**2차 자료(P3_stacks.zip, /proc 스택)**
- WSL 배포판 안의 D 상태 스레드는 **59개이며, 전부 네트워크 잠금(RTNL)을 기다리는 중**입니다.
  - `rtnl_dumpit` 44개, `rtnetlink_rcv_msg` 13개, `rtnl_lock` 2개
  - 대상: ip, ifconfig, hostname, sudo, tcpdump, wget, http 등
- **zenoh-bridge(좀비)의 rx-5 스레드**도 종료하면서 멀티캐스트 소켓을 닫다가 잠금을 기다리는 중입니다(`ip_mc_drop_socket → rtnl_lock`). zenoh와 컨테이너는 **원인이 아니라 피해자**입니다.
- **잠금을 쥔 사용자 프로세스는 없습니다.** 따라서 잠금을 쥔 쪽은 커널 스레드이며, 1차 자료의 rescind 작업자가 가장 유력합니다.

**이번 수집이 필요한 이유**
- WSL 배포판은 별도의 PID 네임스페이스에서 동작하기 때문에 커널 스레드(kworker)가 `/proc`에 보이지 않습니다.
- 커널 작업자의 스택은 sysrq-w 커널 로그로만 얻을 수 있습니다.
- sysrq-w는 멈춘 작업만 출력하므로 sysrq-t보다 작아, 로그 버퍼에서 앞부분이 잘릴 가능성이 낮습니다.

## 결과에 따른 판단

| kworker 스택에서 보이는 것 | 판단 |
|---|---|
| `netvsc_remove` / `rndis_filter_device_remove` / `vmbus_close` 등에서 완료 신호(`wait_for_completion`)나 Hyper-V 응답을 기다림 | **WSL 커널(hv_netvsc/vmbus) 장치 제거 버그**로 확정 |
| `unregister_netdevice` / `netdev_wait_allrefs`에서 eth2 참조 해제를 기다림 | 장치 참조를 쥔 대상 추가 추적 필요 |
| `rtnl_lock` 자체를 기다림 | 잠금 보유자가 다른 커널 스레드 → sysrq_w_now.txt 전체에서 추가 확인 |
