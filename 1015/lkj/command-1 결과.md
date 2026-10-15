PS C:\Users\admin> $path = 'C:\Users\admin\blocked_full.txt'
PS C:\Users\admin> $out = 'C:\Users\admin\blocked_holder.txt'
PS C:\Users\admin>
PS C:\Users\admin> $raw = Get-Content -LiteralPath $path -Raw
PS C:\Users\admin> $parts = [regex]::Split($raw, 'Show Blocked State')
PS C:\Users\admin> $t = $parts[$parts.Length - 1]
PS C:\Users\admin>
PS C:\Users\admin> $blocks = [regex]::Split($t, '(?=task:)')
PS C:\Users\admin>
PS C:\Users\admin> $result = @(
>>     foreach ($block in $blocks) {
>>         if ($block -match '^\s*task:\s*(GnsEngine|kworker\S*|rx-5)\s') {
>>             ($block -split '\r?\n' | Select-Object -First 30) -join "`n"
>>             '-----'
>>         }
>>     }
>> )
PS C:\Users\admin>
PS C:\Users\admin> $result | Out-File -LiteralPath $out -Encoding utf8
PS C:\Users\admin>
PS C:\Users\admin> Write-Host "추출된 블록 수: $(($result | Where-Object { $_ -eq '-----' }).Count)"
추출된 블록 수: 4
PS C:\Users\admin> Write-Host "저장 위치: $out"
저장 위치: C:\Users\admin\blocked_holder.txt
PS C:\Users\admin> Get-Content C:\Users\admin\blocked_holder.txt
task:kworker/u64:0   state:D stack:0     pid:12    tgid:12    ppid:2      task_flags:0x4208060 flags:0x00080000
[97574.507107] Workqueue: ipv6_addrconf addrconf_verify_work
[97574.507113] Call Trace:
[97574.507115]  <TASK>
[97574.507118]  __schedule+0x546/0xc20
[97574.507122]  schedule+0x2b/0xf0
[97574.507124]  schedule_preempt_disabled+0x19/0x30
[97574.507125]  __mutex_lock.constprop.0+0x521/0x9c0
[97574.507127]  ? _raw_spin_unlock+0x12/0x30
[97574.507129]  __mutex_lock_slowpath+0x13/0x20
[97574.507130]  mutex_lock+0x39/0x50
[97574.507132]  rtnl_lock+0x19/0x20
[97574.507134]  addrconf_verify_work+0x16/0x40
[97574.507135]  process_one_work+0x19b/0x3c0
[97574.507138]  worker_thread+0x1a3/0x320
[97574.507140]  ? __pfx_worker_thread+0x10/0x10
[97574.507141]  kthread+0x111/0x240
[97574.507143]  ? _raw_spin_unlock_irq+0x12/0x40
[97574.507145]  ? __pfx_kthread+0x10/0x10
[97574.507146]  ret_from_fork+0x13c/0x1a0
[97574.507149]  ? __pfx_kthread+0x10/0x10
[97574.507150]  ret_from_fork_asm+0x1a/0x30
[97574.507153]  </TASK>
[97574.507182]
-----
task:GnsEngine       state:D stack:0     pid:192   tgid:192   ppid:1      task_flags:0x400100 flags:0x00080000
[97574.507184] Call Trace:
[97574.507184]  <TASK>
[97574.507185]  __schedule+0x546/0xc20
[97574.507187]  schedule+0x2b/0xf0
[97574.507189]  schedule_preempt_disabled+0x19/0x30
[97574.507191]  __mutex_lock.constprop.0+0x521/0x9c0
[97574.507192]  ? cred_has_capability.isra.0+0x78/0x120
[97574.507196]  __mutex_lock_slowpath+0x13/0x20
[97574.507197]  mutex_lock+0x39/0x50
[97574.507198]  rtnl_lock+0x19/0x20
[97574.507199]  dev_ioctl+0x270/0x5a0
[97574.507201]  sock_do_ioctl+0xa8/0xf0
[97574.507203]  sock_ioctl+0x26d/0x2e0
[97574.507205]  ? selinux_file_ioctl+0xb0/0x160
[97574.507207]  __x64_sys_ioctl+0xa1/0xf0
[97574.507210]  x64_sys_call+0x102c/0x20f0
[97574.507211]  do_syscall_64+0x73/0x990
[97574.507214]  ? mntput_no_expire+0x50/0x2a0
[97574.507216]  ? putname+0x63/0x80
[97574.507218]  ? do_readlinkat.part.0+0xa6/0x160
[97574.507219]  ? __x64_sys_readlink+0x29/0x40
[97574.507221]  ? x64_sys_call+0x1f7f/0x20f0
[97574.507222]  ? do_syscall_64+0x73/0x990
[97574.507223]  ? exc_page_fault+0x7f/0x170
[97574.507224]  entry_SYSCALL_64_after_hwframe+0x76/0x7e
[97574.507225] RIP: 0033:0x3b7276
[97574.507227] RSP: 002b:00007ffc39cba820 EFLAGS: 00000206 ORIG_RAX: 0000000000000010
[97574.507229] RAX: ffffffffffffffda RBX: 00007ffc39cbaa90 RCX: 00000000003b7276
[97574.507230] RDX: 00007ffc39cbaa90 RSI: 0000000000008914 RDI: 0000000000000013
-----
task:rx-5            state:D stack:0     pid:9240  tgid:1943  ppid:1403   task_flags:0x40044c flags:0x00080003
[97574.507335] Call Trace:
[97574.507336]  <TASK>
[97574.507337]  __schedule+0x546/0xc20
[97574.507339]  schedule+0x2b/0xf0
[97574.507341]  schedule_preempt_disabled+0x19/0x30
[97574.507342]  __mutex_lock.constprop.0+0x521/0x9c0
[97574.507344]  __mutex_lock_slowpath+0x13/0x20
[97574.507345]  mutex_lock+0x39/0x50
[97574.507346]  rtnl_lock+0x19/0x20
[97574.507347]  ip_mc_drop_socket+0x30/0xc0
[97574.507350]  inet_release+0x2f/0x90
[97574.507351]  __sock_release+0x40/0xc0
[97574.507354]  sock_close+0x19/0x30
[97574.507355]  __fput+0xed/0x2c0
[97574.507357]  ____fput+0x19/0x20
[97574.507358]  task_work_run+0x64/0xa0
[97574.507359]  do_exit+0x2f4/0xad0
[97574.507361]  ? __remove_hrtimer+0x40/0x90
[97574.507364]  ? _raw_spin_unlock_irqrestore+0x12/0x40
[97574.507366]  do_group_exit+0x38/0x90
[97574.507367]  get_signal+0x89a/0x8a0
[97574.507369]  ? __pfx_hrtimer_wakeup+0x10/0x10
[97574.507371]  arch_do_signal_or_restart+0x32/0x240
[97574.507373]  ? do_futex+0xcd/0x1a0
[97574.507375]  ? __x64_sys_futex+0x111/0x1d0
[97574.507377]  exit_to_user_mode_loop+0x86/0x100
[97574.507379]  do_syscall_64+0x266/0x990
[97574.507380]  ? do_syscall_64+0x28a/0x990
[97574.507382]  ? __x64_sys_mmap+0x37/0x50
-----
task:kworker/0:2     state:D stack:0     pid:27078 tgid:27078 ppid:2      task_flags:0x4288060 flags:0x00080000
[97574.507412] Workqueue: hv_vmbus_rescind vmbus_onmessage_work
[97574.507414] Call Trace:
[97574.507415]  <TASK>
[97574.507416]  __schedule+0x546/0xc20
[97574.507418]  schedule+0x2b/0xf0
[97574.507420]  rndis_filter_device_remove+0x130/0x240
[97574.507423]  ? __pfx_autoremove_wake_function+0x10/0x10
[97574.507426]  netvsc_remove+0x89/0x140
[97574.507428]  vmbus_remove+0x2b/0x40
[97574.507429]  device_remove+0x43/0x70
[97574.507432]  device_release_driver_internal+0x1ad/0x210
[97574.507439]  device_release_driver+0x16/0x20
[97574.507440]  bus_remove_device+0xee/0x190
[97574.507441]  ? device_remove_attrs+0xa4/0xf0
[97574.507443]  device_del+0x166/0x3b0
[97574.507444]  ? sysfs_remove_dir+0x53/0x60
[97574.507448]  device_unregister+0x1b/0x60
[97574.507449]  vmbus_device_unregister+0x28/0x60
[97574.507450]  vmbus_onoffer_rescind+0x20d/0x240
[97574.507452]  vmbus_onmessage+0x29/0x80
[97574.507452]  vmbus_onmessage_work+0x29/0x40
[97574.507454]  process_one_work+0x19b/0x3c0
[97574.507455]  worker_thread+0x1a3/0x320
[97574.507457]  ? __pfx_worker_thread+0x10/0x10
[97574.507458]  kthread+0x111/0x240
[97574.507459]  ? _raw_spin_unlock_irq+0x12/0x40
[97574.507461]  ? __pfx_kthread+0x10/0x10
[97574.507463]  ret_from_fork+0x13c/0x1a0
[97574.507464]  ? __pfx_kthread+0x10/0x10
-----
PS C:\Users\admin>
