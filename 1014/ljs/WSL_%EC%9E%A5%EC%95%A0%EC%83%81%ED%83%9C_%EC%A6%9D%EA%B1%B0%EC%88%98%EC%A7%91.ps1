$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$dir = Join-Path $env:USERPROFILE "Desktop\WSL_Evidence_$stamp"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
function Save-Block($name, [scriptblock]$block) {
  try { & $block 2>&1 | Out-String -Width 4096 | Set-Content -Path (Join-Path $dir "$name.txt") -Encoding UTF8 }
  catch { $_ | Out-String | Set-Content -Path (Join-Path $dir "$name.txt") -Encoding UTF8 }
}
Save-Block '00_versions' { Get-Date; wsl --version; wsl --status; Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsBuildNumber }
Save-Block '01_adapters' { Get-NetAdapter -IncludeHidden | Format-List * }
Save-Block '02_ip_addresses' { Get-NetIPAddress | Format-List * }
Save-Block '03_routes' { Get-NetRoute | Sort-Object InterfaceIndex,DestinationPrefix | Format-Table -AutoSize }
Save-Block '04_neighbors' { Get-NetNeighbor | Format-Table -AutoSize }
Save-Block '05_vswitch' { Get-VMSwitch | Format-List * }
Save-Block '06_net_ipconfig' { Get-NetIPConfiguration -Detailed | Format-List * }
Save-Block '07_net_comp' { Get-NetAdapterBinding -Name '*' -ErrorAction SilentlyContinue | Format-Table -AutoSize }
Save-Block '08_hns' { if (Get-Command Get-HnsNetwork -ErrorAction SilentlyContinue) { Get-HnsNetwork | ConvertTo-Json -Depth 12 }; if (Get-Command Get-HnsEndpoint -ErrorAction SilentlyContinue) { Get-HnsEndpoint | ConvertTo-Json -Depth 12 } }
Save-Block '09_process' { Get-Process -Name 'vmmemWSL','wslhost','wslservice','vmcompute' -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,CPU,WorkingSet64,StartTime | Format-List }
Save-Block '10_wslconfig' { if(Test-Path "$env:USERPROFILE\.wslconfig"){ Get-Content "$env:USERPROFILE\.wslconfig" } }
$from=[datetime]'2026-10-14 07:30:00'
$logs=@('System','Microsoft-Windows-Hyper-V-Compute-Operational','Microsoft-Windows-Hyper-V-Compute-Admin','Microsoft-Windows-Hyper-V-VmSwitch-Operational','Microsoft-Windows-NetworkProfile/Operational','Microsoft-Windows-WLAN-AutoConfig/Operational')
foreach($log in $logs){
  $safe=($log -replace '[^a-zA-Z0-9-]','_')
  try {
    Get-WinEvent -FilterHashtable @{LogName=$log;StartTime=$from} -ErrorAction Stop |
      Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message |
      Format-List | Out-String -Width 4096 |
      Set-Content (Join-Path $dir "event_$safe.txt") -Encoding UTF8
  } catch { "${log}: $_" | Set-Content (Join-Path $dir "event_$safe.txt") }
}
# WSL commands are deliberately excluded: multiple Linux commands are stuck in uninterruptible D state.
Compress-Archive -Path (Join-Path $dir '*') -DestinationPath "$dir.zip" -Force
Write-Host "Saved: $dir.zip"
