<!-- 확인 -->
type %USERPROFILE%\.wslconfig
curl.exe -v http://localhost:8180/muscat/
curl.exe -v --noproxy "*" http://<자기IP>:8180/muscat/
netsh interface portproxy show all

type %USERPROFILE%.wslconfig curl.exe -v http://localhost:8180/muscat/ curl.exe -v --noproxy "*" http://10.249.138.206:8180/muscat/ netsh interface portproxy show all

type %USERPROFILE%.wslconfig curl.exe -v http://localhost:8180/muscat/ curl.exe -v --noproxy "*" http://10.249.138.60:8180/muscat/ netsh interface portproxy show all

type %USERPROFILE%.wslconfig curl.exe -v http://localhost:8180/muscat/ curl.exe -v --noproxy "*" http://10.249.138.143:8180/muscat/ netsh interface portproxy show all

type %USERPROFILE%.wslconfig curl.exe -v http://localhost:8180/muscat/ curl.exe -v --noproxy "*" http://10.249.138.140:8180/muscat/ netsh interface portproxy show all

type %USERPROFILE%.wslconfig curl.exe -v http://localhost:8180/muscat/ curl.exe -v --noproxy "*" http://10.249.138.141:8180/muscat/ netsh interface portproxy show all
