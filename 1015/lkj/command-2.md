<!-- 확인 -->
type %USERPROFILE%\.wslconfig
curl.exe -v http://localhost:8180/muscat/
curl.exe -v --noproxy "*" http://<자기IP>:8180/muscat/
netsh interface portproxy show all

