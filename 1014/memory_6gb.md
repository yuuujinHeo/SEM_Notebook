# 로봇 Muscat 메모리 상한을 6GiB로 설정하기

## 목차

- [환경변수 주입](#환경변수-주입)
- [임시 주입](#임시-주입)

현재 `muscat` 컨테이너에만 적용하려면 **임시 주입**, 이후 재생성에도 유지하려면 **환경변수 주입** 절차를 사용한다.

<br>

## 환경변수 주입

호스트 설정 파일을 배포 스크립트에서 읽어, 컨테이너 생성 시 메모리 옵션에 전달하는 방법이다.

현재 `muscat` 컨테이너의 메모리 상한을 6GiB로 변경하고, 이후 컨테이너 재생성 때도 유지한다.

모든 명령은 **로봇 호스트 터미널**에서 실행한다. 컨테이너 내부에서 실행하지 않는다.

### 1. 호스트 설정 파일 생성

```bash
mkdir -p ~/rainbow-deploy-kit/config
nano ~/rainbow-deploy-kit/config/muscat.env
```

다음 내용을 입력한다.

```bash
MUSCAT_DEV_MEMORY=6g
MUSCAT_DEV_MEMORY_SWAP=6g
```

`Ctrl+O` → `Enter`로 저장하고 `Ctrl+X`로 종료한다.

`--memory-swap`은 RAM과 swap의 합계 제한이다. 두 값을 모두 `6g`로 설정하면 컨테이너의 swap 사용을 허용하지 않는다.

### 2. 배포 스크립트 백업

```bash
cp -p ~/rainbow-deploy-kit/muscat/muscat-update.sh \
  ~/rainbow-deploy-kit/muscat/muscat-update.sh.bak
```

기존 백업이 있다면 다른 백업 이름을 사용한다.

### 3. 배포 스크립트에서 설정 파일 읽기

```bash
nano +46 ~/rainbow-deploy-kit/muscat/muscat-update.sh
```

기존 `MUSCAT_DEV_CPUS` 기본값 설정 **바로 위에** 파일을 읽는 코드를 추가한다. 최종 순서는 다음과 같다. 행 번호는 수정에 따라 달라질 수 있다.

```bash
if [ -f "$HOME/rainbow-deploy-kit/config/muscat.env" ]; then
  set -a
  source "$HOME/rainbow-deploy-kit/config/muscat.env"
  set +a
fi

MUSCAT_DEV_CPUS="${MUSCAT_DEV_CPUS:-2}"
MUSCAT_DEV_MEMORY="${MUSCAT_DEV_MEMORY:-3g}"
MUSCAT_DEV_MEMORY_SWAP="${MUSCAT_DEV_MEMORY_SWAP:-$MUSCAT_DEV_MEMORY}"
```

추가 코드가 이미 있다면 중복 추가하지 않는다. `source`할 설정 파일에는 위의 변수 대입만 넣는다.

기존 기본값 `3g`는 유지해도 된다. 설정 파일에서 먼저 읽은 `6g`가 사용된다.

`Ctrl+O` → `Enter` → `Ctrl+X`로 저장·종료한다.

확인한 `start_muscat_container()`의 기존 옵션은 그대로 사용한다.

```bash
--memory="${MUSCAT_DEV_MEMORY}" \
--memory-swap="${MUSCAT_DEV_MEMORY_SWAP}" \
```

기존 볼륨, 포트, 이미지, 기타 실행 옵션은 유지한다.

### 4. 문법과 설정 확인

```bash
bash -n ~/rainbow-deploy-kit/muscat/muscat-update.sh
cat ~/rainbow-deploy-kit/config/muscat.env
```

첫 명령에 오류가 없고, 두 번째 명령에서 두 변수 모두 `6g`로 나오면 된다. 문법 검사는 실제 배포 실행을 대신하지 않는다.

### 5. 현재 컨테이너에 적용

```bash
docker update --memory 6g --memory-swap 6g muscat
```

이미 적용했다면 생략한다. 재시작이나 컨테이너 삭제는 필요 없다.

### 6. 최종 확인

```bash
docker stats muscat --no-stream
```

`MEM USAGE / LIMIT`에 `/ 6GiB`가 표시되는지 확인한다.

```bash
docker inspect muscat --format \
  'Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}}'
```

두 값 모두 `6442450944`이면 6GiB 설정이다.

### 유지 범위와 환경변수의 역할

- `docker update` 설정은 해당 컨테이너의 재시작 후에도 유지된다.
- 컨테이너를 삭제하고 재생성할 때는 수정한 배포 스크립트가 설정 파일을 읽어 6GiB를 적용한다.
- 배포 스크립트를 실행하는 사용자와 `HOME`이 같아야 위 설정 파일을 찾는다. 다른 사용자로 실행한다면 설정 파일 경로를 실제 절대 경로로 지정한다.
- 배포 도구 업데이트로 스크립트가 교체되면 추가한 파일 읽기 코드가 유지됐는지 확인한다.
- `MUSCAT_DEV_MEMORY`는 여기서 **호스트 배포 스크립트가 Docker 옵션에 전달하는 값**이다. 컨테이너 내부 환경변수 주입이나 `/root/.bashrc` 수정은 메모리 상한 설정에 필요하지 않다.
- 기존 `--env-file "$MUSCAT_ENV_FILE"`은 컨테이너 내부 환경변수 주입용이며, 호스트가 Docker 메모리 옵션을 결정하는 위 과정과 별개다.
- 상한을 늘리는 것은 메모리 예산 변경이며, 누수나 캐시 사용 원인을 해결하는 조치는 아니다.


<br>

## 임시 주입

환경변수나 배포 스크립트를 수정하지 않고, **현재 존재하는 `muscat` 컨테이너의 메모리 상한만 바로 변경**하는 방법이다. 환경변수를 실제로 주입하는 명령은 아니다.

### 1. 로봇 호스트에서 실행

```bash
docker update --memory 6g --memory-swap 6g muscat
```

재시작이나 컨테이너 삭제는 필요 없다. 두 제한을 같은 값으로 지정하므로 컨테이너의 swap 사용을 허용하지 않는다.

### 2. 적용 확인

```bash
docker stats muscat --no-stream
```

`MEM USAGE / LIMIT`에 `/ 6GiB`가 나오면 적용된 것이다.

```bash
docker inspect muscat --format \
  'Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}}'
```

두 값 모두 `6442450944`이면 6GiB 설정이다.

### 유지 범위

- 해당 `muscat` 컨테이너에만 적용된다.
- `docker restart` 또는 `docker stop/start` 후에도 유지된다. “임시”는 셸 종료 시 사라진다는 의미가 아니라, 배포 설정에는 저장하지 않는다는 의미다.
- 컨테이너 삭제 후 재생성하면 기존 배포 설정을 따른다. 재생성 이후에도 6GiB를 유지하려면 위 **환경변수 주입** 절차를 적용한다.
- 컨테이너 내부의 `export MUSCAT_DEV_MEMORY=6g`나 `.bashrc` 저장만으로는 Docker 메모리 상한이 바뀌지 않는다.
