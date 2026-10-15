PS C:\Users\admin> netsh wlan show interfaces

시스템에 1 인터페이스가 있습니다.

    이름                   : Wi-Fi
    설명                   : Intel(R) Wi-Fi 6E AX210 160MHz
    GUID                   : c7f7ce3b-8159-4b72-b897-598abdde9d00
    물리적 주소            : 40:d1:33:cd:46:69
    인터페이스 유형         : 기본
    상태                   : 연결됨
    SSID                   : sWave_works_shared
    AP BSSID               : b8:3a:5a:cc:b7:31
    밴드                   : 5GHz
    채널                : 116
    연결된 Akm-cipher : [ akm = 00-0f-ac:01, 암호 = 00-0f-ac:04 ]
    네트워크 종류          : 인프라
    송수신 장치 종류       : 802.11 ax
    인증                   : WPA2-엔터프라이즈
    암호                 : CCMP
    연결 모드        : 자동 연결
    수신 속도(Mbps)        : 229
    전송 속도(Mbps)        : 287
    신호                   : 75%
    Rssi                   : -67
    프로필                : sWave_works_shared

    QoS MSCS 구성됨         : 0
    QoS 맵 구성됨          : 0
    정책에서 허용하는 QoS 맵    : 0

PS C:\Users\admin> netsh wlan show networks mode=bssid

인터페이스 이름: Wi-Fi
현재 1개 네트워크를 볼 수 있습니다.

SSID 1 : sWave_works_shared
    네트워크 종류            : 인프라
    인증          : WPA2-엔터프라이즈
    암호화              : CCMP
    BSSID 1                 : b8:3a:5a:d1:56:91
         신호             : 82%
         무선 송수신 장치 유형         : 802.11 ax
         밴드               : 5GHz
         채널            : 132
         QoS MSCS 지원됨    : 0
         QoS Map 지원됨     : 0
         기본 속도(Mbps): 18 24 36 48 54

PS C:\Users\admin> Get-CimInstance Win32_PnPSignedDriver |
>> Where-Object {
>>     $_.DeviceName -match 'AX210|Wi-Fi 6E'
>> } |
>> Select-Object DeviceName, DriverVersion, DriverDate, Manufacturer

DeviceName                     DriverVersion DriverDate              Manufacturer
----------                     ------------- ----------              ------------
Intel(R) Wi-Fi 6E AX210 160MHz 24.70.0.3     2026-07-29 오전 9:00:00 Intel Corporation

