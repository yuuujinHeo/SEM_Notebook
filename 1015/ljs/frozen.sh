# P3 WSL 멈춘 상태 증거 수집 (netlink/RTNL을 건드리는 명령은 하나도 쓰지 않음)
# 실행: PowerShell(관리자)에서
#   wsl -d Ubuntu-22.04 -u root -e sh -c "tr -d '\r' < /mnt/c/Temp/frozen.sh | sh"
OUT=/mnt/c/Temp/frozen
mkdir -p $OUT
echo "[0] 기본 정보"; { date; uname -a; cat /proc/uptime; cat /proc/cmdline; } > $OUT/00_info.txt

echo "[1] 현재 dmesg 보존"; dmesg > $OUT/01_dmesg_before.txt

echo "[2] 전체 프로세스/스레드 (필터 없음)"
ps -eLo pid,tid,ppid,stat,lstart,wchan:40,comm,args > $OUT/02_ps_all.txt

echo "[3] 모든 프로세스/커널스레드의 커널 스택"
for t in /proc/[0-9]*/task/[0-9]*; do
  pid=$(echo $t | cut -d/ -f3); tid=$(echo $t | cut -d/ -f5)
  echo "=== pid=$pid tid=$tid comm=$(cat $t/comm 2>/dev/null) $(grep -m1 '^State' $t/status 2>/dev/null)"
  cat $t/stack 2>/dev/null
done > $OUT/03_all_stacks.txt

echo "[4] 기타 /proc 상태"
cat /proc/net/dev  > $OUT/04_net_dev.txt
cat /proc/locks    > $OUT/04_locks.txt
cat /proc/interrupts > $OUT/04_interrupts.txt
cat /proc/softirqs > $OUT/04_softirqs.txt
cat /proc/loadavg  > $OUT/04_loadavg.txt
cat /proc/meminfo  > $OUT/04_meminfo.txt

echo "[5] sysrq-t: 모든 태스크 + 작업 큐 상태"
dmesg -C
echo t > /proc/sysrq-trigger
sleep 5
dmesg > $OUT/05_sysrq_t.txt

echo "[6] sysrq-l: 각 CPU에서 지금 실행 중인 것"
dmesg -C
echo l > /proc/sysrq-trigger
sleep 3
dmesg > $OUT/06_sysrq_l.txt

echo "[7] vmbus 장치 목록 (sysfs 디렉터리 목록만)"
ls -la /sys/bus/vmbus/devices/ > $OUT/07_vmbus.txt 2>&1

echo "완료: C:\\Temp\\frozen"
