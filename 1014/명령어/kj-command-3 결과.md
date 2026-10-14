PS C:\Users\admin> wsl -d Ubuntu-22.04 -u root -e sh -c "echo w > /proc/sysrq-trigger; dmesg | tail -300 > /mnt/c/Users/admin/blocked.txt"

PS C:\Users\admin> Get-Content C:\Users\admin\blocked.txt -Tail 20
[48429.343067]  ? vmf_insert_pfn+0x16/0x20
[48429.343069]  ? vvar_fault+0x9f/0x110
[48429.343070]  ? special_mapping_fault+0x25/0xd0
[48429.343071]  ? __do_fault+0x39/0x190
[48429.343072]  ? do_fault+0x2cf/0x590
[48429.343074]  ? __handle_mm_fault+0x6ed/0x910
[48429.343075]  ? count_memcg_events+0xbd/0x170
[48429.343077]  ? handle_mm_fault+0xc3/0x2c0
[48429.343078]  ? do_user_addr_fault+0x233/0x710
[48429.343080]  ? irqentry_exit+0x3f/0x50
[48429.343080]  ? exc_page_fault+0x7f/0x170
[48429.343081]  entry_SYSCALL_64_after_hwframe+0x76/0x7e
[48429.343082] RIP: 0033:0x7e029f1278f0
[48429.343082] RSP: 002b:00007fffbb09c0d8 EFLAGS: 00000246 ORIG_RAX: 000000000000002c
[48429.343083] RAX: ffffffffffffffda RBX: 00007fffbb09c1c0 RCX: 00007e029f1278f0
[48429.343083] RDX: 0000000000000020 RSI: 00007fffbb09c0e0 RDI: 0000000000000003
[48429.343084] RBP: 00005635df9d0040 R08: 0000000000000000 R09: 0000000000000000
[48429.343084] R10: 0000000000000000 R11: 0000000000000246 R12: 0000000000000000
[48429.343084] R13: 00005635df9d0040 R14: 00007fffbb09c430 R15: 00007fffbb09c448
[48429.343085]  </TASK>
