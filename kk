Write-Host "=== ROUTE TO FRS ==="
Find-NetRoute -RemoteIPAddress 10.244.201.165 |
    Format-List *

Write-Host "=== IP INTERFACES ==="
Get-NetIPInterface -AddressFamily IPv4 |
    Sort-Object InterfaceMetric |
    Format-Table InterfaceAlias,InterfaceIndex,ConnectionState,Dhcp,InterfaceMetric -AutoSize

Write-Host "=== IPV4 ROUTES ==="
Get-NetRoute -AddressFamily IPv4 |
    Sort-Object DestinationPrefix,RouteMetric |
    Format-Table DestinationPrefix,NextHop,InterfaceAlias,RouteMetric -AutoSize

Write-Host "=== WIFI DRIVER ==="
Get-NetAdapter -Name "Wi-Fi" |
    Format-List Name,InterfaceDescription,DriverVersion,DriverDate,DriverInformation
