# P3 핵심 스레드 스택 수집 (상태를 바꾸지 않음, RTNL 미사용)
OUT=/mnt/c/Users/admin/Desktop/ALGN/frozen
mkdir -p $OUT

echo "[1] 핵심 스레드 스택"
for p in 27078 12 9240 23589 30341 1629 1943; do
  for t in /proc/$p/task/*; do
    echo "=== pid=$p tid=${t##*/} comm=$(cat $t/comm 2>/dev/null) $(grep -m1 State $t/status 2>/dev/null)"
    cat $t/stack 2>/dev/null
  done
done > $OUT/key_stacks.txt

echo "[2] 전체 프로세스 목록"
ps -eLo pid,tid,ppid,stat,lstart,wchan:40,comm,args > $OUT/02_ps_all.txt

echo "[3] 전체 스레드 스택"
for t in /proc/[0-9]*/task/[0-9]*; do
  pid=${t#/proc/}; pid=${pid%%/*}
  echo "=== pid=$pid tid=${t##*/} comm=$(cat $t/comm 2>/dev/null) $(grep -m1 State $t/status 2>/dev/null)"
  cat $t/stack 2>/dev/null
done > $OUT/03_all_stacks.txt

echo "[4] 현재 커널 로그"
dmesg > $OUT/01_dmesg_now.txt

ls -la $OUT
echo "완료"
