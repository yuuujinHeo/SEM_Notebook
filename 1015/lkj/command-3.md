netstat -ano | findstr :8180

docker ps --format "{{.Names}} {{.Ports}}"