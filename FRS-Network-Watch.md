# 명령 실행
Start-ScheduledTask -TaskName "FRS-Network-Watch"

# 실행 상태 확인
Get-ScheduledTask -TaskName "FRS-Network-Watch" | Select-Object TaskName, State

# 로그 찍히는지
Get-Content "C:\ProgramData\FRSNetworkWatch\watch.log" -Tail 30 -Wait
