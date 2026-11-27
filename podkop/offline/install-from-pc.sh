#!/usr/bin/env bash
# Offline podkop 0.2.5 installer: run on a Linux or macOS PC, packages go
# to the OpenWrt router over SSH. The router itself downloads nothing.
set -euo pipefail

ROUTER="192.168.1.1"
USER_NAME="root"
PORT="22"
IDENTITY=""
ZIP_PATH=""
BUNDLE_DIR=""
INSTALL_RU=1
INSTALL_SINGBOX=1
SKIP_CONFIRM=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Установка podkop 0.2.5 на OpenWrt с ПК. Роутер ничего не качает из интернета.

Использование:
  ./install-from-pc.sh [ключ] [адрес_роутера]

Ключи:
  -H, --host ADDR       IP или имя роутера (по умолчанию 192.168.1.1)
  -u, --user NAME       SSH-пользователь (по умолчанию root)
  -p, --port PORT       SSH-порт (по умолчанию 22)
  -i, --identity FILE   Приватный ключ SSH
  -z, --zip FILE        Архив podkop-0.2.5-offline-<архитектура>.zip
  -d, --dir DIR         Уже распакованный комплект
  --no-ru               Не ставить русский перевод LuCI
  --no-sing-box         Не ставить sing-box
  -y                    Не спрашивать подтверждение
  -h, --help            Справка

Примеры:
  ./install-from-pc.sh 192.168.1.1
  ./install-from-pc.sh -z podkop-0.2.5-offline-mipsel_24kc.zip 192.168.1.1
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -H|--host) ROUTER="$2"; shift 2 ;;
    -u|--user) USER_NAME="$2"; shift 2 ;;
    -p|--port) PORT="$2"; shift 2 ;;
    -i|--identity) IDENTITY="$2"; shift 2 ;;
    -z|--zip) ZIP_PATH="$2"; shift 2 ;;
    -d|--dir) BUNDLE_DIR="$2"; shift 2 ;;
    --no-ru) INSTALL_RU=0; shift ;;
    --no-sing-box) INSTALL_SINGBOX=0; shift ;;
    -y) SKIP_CONFIRM=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Неизвестный ключ: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      ROUTER="$1"
      shift
      ;;
  esac
done

die() { echo "ОШИБКА: $*" >&2; exit 1; }
info() { echo ">>> $*"; }

SSH_OPTS=(-p "$PORT" -o "ConnectTimeout=10")
SCP_OPTS=(-P "$PORT" -o "ConnectTimeout=10")
if [ -n "$IDENTITY" ]; then
  SSH_OPTS+=(-i "$IDENTITY")
  SCP_OPTS+=(-i "$IDENTITY")
fi
# Prefer accepting a new host key on first connect (OpenSSH 7.6+).
if ssh -o StrictHostKeyChecking=accept-new -V 2>&1 | grep -q .; then
  :
fi
SSH_OPTS+=(-o StrictHostKeyChecking=accept-new)
SCP_OPTS+=(-o StrictHostKeyChecking=accept-new)

ssh_r() { ssh "${SSH_OPTS[@]}" "${USER_NAME}@${ROUTER}" "$@"; }
# raw remote command as a single string
ssh_s() { ssh "${SSH_OPTS[@]}" "${USER_NAME}@${ROUTER}" "$1"; }

info "Подключаюсь к ${USER_NAME}@${ROUTER}:${PORT}…"
DETECT="$(ssh_s "cat /etc/openwrt_release; echo ---UNAME---; uname -r; echo ---OPKG---; command -v opkg || true; echo ---APK---; command -v apk || true; echo ---KERNELPKG---; opkg list-installed 2>/dev/null | awk '\$1==\"kernel\"{print \$3}'; echo ---DF---; df -k /overlay /tmp /usr 2>/dev/null; echo ---INSTALLED---; opkg list-installed 2>/dev/null | awk '{print \$1}'")" || die "не удалось подключиться по SSH. Проверь IP, что на роутере включён Dropbear/SSH, и пароль."

parse_val() {
  echo "$DETECT" | awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,""); gsub(/'\''/,""); print; exit}'
}

DISTRIB_RELEASE="$(parse_val DISTRIB_RELEASE)"
DISTRIB_TARGET="$(parse_val DISTRIB_TARGET)"
DISTRIB_ARCH="$(parse_val DISTRIB_ARCH)"
DISTRIB_ID="$(parse_val DISTRIB_ID)"
DISTRIB_REVISION="$(parse_val DISTRIB_REVISION)"
KERNEL_RELEASE="$(echo "$DETECT" | awk '/^---UNAME---$/{getline; print; exit}')"
KERNEL_OPKG="$(echo "$DETECT" | awk '/^---KERNELPKG---$/{getline; if($0 !~ /^---/) print; exit}')"
HAS_OPKG="$(echo "$DETECT" | awk '/^---OPKG---$/{getline; if($0 !~ /^---/) print; exit}')"
HAS_APK="$(echo "$DETECT" | awk '/^---APK---$/{getline; if($0 !~ /^---/) print; exit}')"

echo
echo "Роутер:          $ROUTER"
echo "Система:         ${DISTRIB_ID:-?} ${DISTRIB_RELEASE:-?}"
echo "Архитектура:     ${DISTRIB_ARCH:-?}"
echo "Цель (target):   ${DISTRIB_TARGET:-?}"
echo "Ревизия:         ${DISTRIB_REVISION:-?}"
echo "Ядро:            ${KERNEL_RELEASE:-?} ${KERNEL_OPKG:+($KERNEL_OPKG)}"
echo

if [ -n "$HAS_APK" ] && [ -z "$HAS_OPKG" ]; then
  die "На роутере OpenWrt ${DISTRIB_RELEASE:-25.x} с пакетным менеджером apk. podkop 0.2.5 ставится только на OpenWrt 23.05 или 24.10 (opkg)."
fi
[ -n "$HAS_OPKG" ] || die "на роутере нет opkg"
[ -n "$DISTRIB_ARCH" ] || die "не удалось прочитать DISTRIB_ARCH"

case "$DISTRIB_RELEASE" in
  23.05*) SERIES="23.05" ;;
  24.10*) SERIES="24.10" ;;
  25.*) die "OpenWrt ${DISTRIB_RELEASE} не поддерживается этим комплектом (apk, не opkg)." ;;
  *) die "Неподдерживаемая версия OpenWrt: ${DISTRIB_RELEASE:-unknown}. Нужны 23.05.x или 24.10.x." ;;
esac

ZIP_NAME="podkop-0.2.5-offline-${DISTRIB_ARCH}.zip"

find_zip() {
  local cand
  if [ -n "$ZIP_PATH" ]; then
    [ -f "$ZIP_PATH" ] || die "нет файла $ZIP_PATH"
    echo "$ZIP_PATH"
    return
  fi
  for cand in \
      "$HERE/$ZIP_NAME" \
      "$PWD/$ZIP_NAME" \
      "$HERE/../zips/$ZIP_NAME" \
      "$HERE/zips/$ZIP_NAME" \
      "$HERE/bundles/$ZIP_NAME"
  do
    if [ -f "$cand" ]; then
      echo "$cand"
      return
    fi
  done
  # any matching zip nearby
  cand="$(find "$HERE" "$PWD" -maxdepth 2 -type f -name "$ZIP_NAME" 2>/dev/null | head -n1 || true)"
  [ -n "$cand" ] && echo "$cand"
}

find_extracted() {
  local cand want="podkop-0.2.5-offline-${DISTRIB_ARCH}"
  if [ -n "$BUNDLE_DIR" ]; then
    [ -d "$BUNDLE_DIR" ] || die "нет каталога $BUNDLE_DIR"
    echo "$BUNDLE_DIR"
    return
  fi
  for cand in \
      "$HERE/$want" \
      "$PWD/$want" \
      "$HERE/../staging/$want" \
      "/workspace/podkop-offline-work/staging/$want"
  do
    if [ -d "$cand/podkop" ] && [ -d "$cand/userspace" ]; then
      echo "$cand"
      return
    fi
  done
}

WORK=""
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

BUNDLE="$(find_extracted || true)"
if [ -z "$BUNDLE" ]; then
  Z="$(find_zip || true)"
  if [ -z "$Z" ]; then
    die "не найден $ZIP_NAME
Скачай архив для архитектуры ${DISTRIB_ARCH} (релиз podkop-v0.2.5-offline) и положи его рядом со скриптом, либо укажи: $0 -z /путь/$ZIP_NAME $ROUTER"
  fi
  info "Распаковываю $(basename "$Z")…"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/podkop-offline.XXXXXX")"
  if command -v unzip >/dev/null; then
    unzip -q "$Z" -d "$WORK"
  else
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$Z" "$WORK"
  fi
  if [ -d "$WORK/podkop-0.2.5-offline-${DISTRIB_ARCH}" ]; then
    BUNDLE="$WORK/podkop-0.2.5-offline-${DISTRIB_ARCH}"
  elif [ -d "$WORK/podkop" ]; then
    BUNDLE="$WORK"
  else
    BUNDLE="$(find "$WORK" -type d -name "podkop-0.2.5-offline-${DISTRIB_ARCH}" | head -n1 || true)"
  fi
  if [ -z "$BUNDLE" ] || [ ! -d "$BUNDLE/podkop" ]; then die "внутри архива нет ожидаемого каталога"; fi
fi

[ -d "$BUNDLE/userspace/$SERIES" ] || die "в комплекте нет пакетов для $SERIES (есть: $(ls "$BUNDLE/userspace" 2>/dev/null | tr '\n' ' '))"

KMOD_DIR=""
DASHED="$(echo "$DISTRIB_TARGET" | tr '/' '-')"
if [ -d "$BUNDLE/kmods/${DISTRIB_RELEASE}/${DASHED}" ]; then
  KMOD_DIR="$BUNDLE/kmods/${DISTRIB_RELEASE}/${DASHED}"
else
  # fallback by kernel string
  if [ -n "$KERNEL_OPKG" ]; then
    while IFS= read -r kfile; do
      k="$(tr -d '\r\n' < "$kfile")"
      if [ "$k" = "$KERNEL_OPKG" ]; then
        KMOD_DIR="$(dirname "$kfile")"
        break
      fi
    done < <(find "$BUNDLE/kmods" -type f -name KERNEL 2>/dev/null || true)
  fi
fi

echo "Комплект:        $BUNDLE"
echo "Пакеты OpenWrt:  userspace/$SERIES"
if [ -n "$KMOD_DIR" ]; then
  echo "kmod:            ${KMOD_DIR#"$BUNDLE/"}"
else
  echo "kmod:            в комплекте нет точного набора для ${DISTRIB_RELEASE} / ${DISTRIB_TARGET}"
  echo "                 (если модули уже стоят на роутере — это нормально)"
fi
echo

if [ "$SKIP_CONFIRM" != "1" ]; then
  printf "Ставить podkop 0.2.5 на %s? [y/N] " "$ROUTER"
  read -r ans
  case "$ans" in
    y|Y|yes|да|Да) ;;
    *) echo "Отменено."; exit 0 ;;
  esac
fi

# Build a staging tree with only the needed slices (don't upload every kmod).
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/podkop-push.XXXXXX")"
trap 'rm -rf "${WORK:-}" "${STAGE:-}"' EXIT
mkdir -p "$STAGE/podkop" "$STAGE/userspace/$SERIES"
cp -a "$BUNDLE/podkop/." "$STAGE/podkop/"
cp -a "$BUNDLE/userspace/$SERIES/." "$STAGE/userspace/$SERIES/"
if [ -n "$KMOD_DIR" ]; then
  rel="${KMOD_DIR#"$BUNDLE/"}"
  mkdir -p "$STAGE/$rel"
  cp -a "$KMOD_DIR/." "$STAGE/$rel/"
fi
cp -a "$HERE/install-on-router.sh" "$STAGE/install-on-router.sh"
chmod +x "$STAGE/install-on-router.sh"
# if scripts were inside the zip
if [ ! -f "$STAGE/install-on-router.sh" ] && [ -f "$BUNDLE/install-on-router.sh" ]; then
  cp -a "$BUNDLE/install-on-router.sh" "$STAGE/install-on-router.sh"
fi

info "Копирую пакеты на роутер в /tmp/podkop-offline (роутер ничего не качает)…"
ssh_s "rm -rf /tmp/podkop-offline && mkdir -p /tmp/podkop-offline"

upload_ok=0
# 1) tar over ssh — most reliable with Dropbear
if [ "$upload_ok" -eq 0 ]; then
  if tar -C "$STAGE" -cf - . | ssh_s "tar -C /tmp/podkop-offline -xf -"; then
    upload_ok=1
    info "Файлы скопированы через tar+ssh"
  else
    echo "tar+ssh не сработал, пробую scp…" >&2
  fi
fi
# 2) scp -O (legacy SCP, needed for some Dropbear versions)
if [ "$upload_ok" -eq 0 ]; then
  if scp "${SCP_OPTS[@]}" -O -r "$STAGE/." "${USER_NAME}@${ROUTER}:/tmp/podkop-offline/" 2>/dev/null; then
    upload_ok=1
    info "Файлы скопированы через scp -O"
  fi
fi
# 3) plain scp (SFTP)
if [ "$upload_ok" -eq 0 ]; then
  if scp "${SCP_OPTS[@]}" -r "$STAGE/." "${USER_NAME}@${ROUTER}:/tmp/podkop-offline/"; then
    upload_ok=1
    info "Файлы скопированы через scp"
  fi
fi
[ "$upload_ok" -eq 1 ] || die "не удалось скопировать файлы на роутер (не сработали ни tar+ssh, ни scp)"

info "Запускаю установку на роутере…"
ssh_s "INSTALL_RU=${INSTALL_RU} INSTALL_SINGBOX=${INSTALL_SINGBOX} RELEASE='${DISTRIB_RELEASE}' TARGET='${DISTRIB_TARGET}' SERIES='${SERIES}' OFFLINE_DIR=/tmp/podkop-offline sh /tmp/podkop-offline/install-on-router.sh install"

info "Готово."
