#!/bin/sh
# Offline installer for podkop 0.2.5. Runs on the OpenWrt router (ash/busybox).
# Expects packages already copied to $OFFLINE_DIR (default /tmp/podkop-offline).
# This script never calls opkg update and never downloads anything.
#
# Usage:
#   install-on-router.sh detect
#   install-on-router.sh install
#
# Environment:
#   OFFLINE_DIR        (default /tmp/podkop-offline)
#   INSTALL_RU         1/0, default 1
#   INSTALL_SINGBOX    1/0, default 1
#   SERIES             23.05 or 24.10 (optional; auto from /etc/openwrt_release)
#   RELEASE            e.g. 24.10.4 (optional)
#   TARGET             e.g. mediatek/filogic (optional)

set -e

OFFLINE_DIR="${OFFLINE_DIR:-/tmp/podkop-offline}"
INSTALL_RU="${INSTALL_RU:-1}"
INSTALL_SINGBOX="${INSTALL_SINGBOX:-1}"

die() {
    echo "ОШИБКА: $*" >&2
    exit 1
}

info() {
    echo ">>> $*"
}

is_installed() {
    opkg list-installed 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

load_os() {
    [ -f /etc/openwrt_release ] || die "это не OpenWrt: нет /etc/openwrt_release"
    # shellcheck disable=SC1091
    . /etc/openwrt_release
    KERNEL_RELEASE="$(uname -r 2>/dev/null || true)"
    KERNEL_OPKG="$(opkg list-installed 2>/dev/null | awk '$1=="kernel"{print $3; exit}')"
    if command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    else
        PKG_MANAGER="unknown"
    fi
    OVERLAY_FREE_KB="$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')"
    [ -n "$OVERLAY_FREE_KB" ] || OVERLAY_FREE_KB="$(df -k /usr 2>/dev/null | awk 'NR==2{print $4}')"
    TMP_FREE_KB="$(df -k /tmp | awk 'NR==2{print $4}')"
}

cmd_detect() {
    load_os
    echo "PODKOP_DETECT_BEGIN"
    echo "DISTRIB_ID=${DISTRIB_ID:-}"
    echo "DISTRIB_RELEASE=${DISTRIB_RELEASE:-}"
    echo "DISTRIB_REVISION=${DISTRIB_REVISION:-}"
    echo "DISTRIB_TARGET=${DISTRIB_TARGET:-}"
    echo "DISTRIB_ARCH=${DISTRIB_ARCH:-}"
    echo "DISTRIB_DESCRIPTION=${DISTRIB_DESCRIPTION:-}"
    echo "KERNEL_RELEASE=${KERNEL_RELEASE:-}"
    echo "KERNEL_OPKG=${KERNEL_OPKG:-}"
    echo "PKG_MANAGER=${PKG_MANAGER:-}"
    echo "OVERLAY_FREE_KB=${OVERLAY_FREE_KB:-}"
    echo "TMP_FREE_KB=${TMP_FREE_KB:-}"
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "OS_ID=${ID:-}"
        echo "OS_VERSION_ID=${VERSION_ID:-}"
        echo "OS_OPENWRT_RELEASE=${OPENWRT_RELEASE:-}"
    fi
    echo "INSTALLED_BEGIN"
    if [ "$PKG_MANAGER" = "opkg" ]; then
        opkg list-installed 2>/dev/null | awk '{print $1 " " $3}'
    elif [ "$PKG_MANAGER" = "apk" ]; then
        apk info -v 2>/dev/null | awk '{print $1}'
    fi
    echo "INSTALLED_END"
    echo "PODKOP_DETECT_END"
}

pkg_from_list() {
    # usage: pkg_from_list DIR NAME -> prints filename if present
    _dir="$1"
    _name="$2"
    [ -f "$_dir/packages.txt" ] || return 1
    awk -F '\t' -v n="$_name" '$1==n{print $2; exit}' "$_dir/packages.txt"
}

install_ipk() {
    _file="$1"
    [ -f "$_file" ] || die "нет файла $_file"
    info "Ставлю $(basename "$_file")"
    if ! opkg install "$_file"; then
        die "не удалось установить $(basename "$_file")"
    fi
}

install_if_needed() {
    # install_if_needed DIR PKGNAME
    _dir="$1"
    _name="$2"
    if is_installed "$_name"; then
        info "Уже установлено: $_name"
        return 0
    fi
    _fn="$(pkg_from_list "$_dir" "$_name" || true)"
    [ -n "$_fn" ] || die "в комплекте нет пакета $_name (каталог $_dir)"
    [ -f "$_dir/$_fn" ] || die "нет файла $_dir/$_fn"
    install_ipk "$_dir/$_fn"
}

install_missing_from_dir() {
    # Install every package listed in DIR/packages.txt that is not already installed.
    # Used for userspace deps. Never upgrades an already installed package.
    _dir="$1"
    [ -f "$_dir/packages.txt" ] || die "нет $_dir/packages.txt"
    while IFS="$(printf '\t')" read -r _name _fn || [ -n "$_name" ]; do
        [ -n "$_name" ] || continue
        case "$_name" in
            \#*) continue ;;
        esac
        # Skip sing-box here; handled separately so we can honour INSTALL_SINGBOX.
        if [ "$_name" = "sing-box" ]; then
            continue
        fi
        if is_installed "$_name"; then
            continue
        fi
        if [ -z "$_fn" ] || [ ! -f "$_dir/$_fn" ]; then die "нет файла для $_name"; fi
        install_ipk "$_dir/$_fn"
    done < "$_dir/packages.txt"
}

swap_dnsmasq() {
    _dir="$1"
    if is_installed dnsmasq-full; then
        info "dnsmasq-full уже установлен"
        return 0
    fi
    info "Меняю dnsmasq на dnsmasq-full"
    _fn="$(pkg_from_list "$_dir" "dnsmasq-full" || true)"
    if [ -z "$_fn" ] || [ ! -f "$_dir/$_fn" ]; then die "в комплекте нет dnsmasq-full"; fi
    if is_installed dnsmasq; then
        if ! opkg remove dnsmasq; then
            info "обычное удаление dnsmasq не прошло, пробую --force-depends"
            opkg remove dnsmasq --force-depends || die "не удалось удалить dnsmasq"
        fi
    fi
    install_ipk "$_dir/$_fn"
    if [ -f /etc/config/dhcp-opkg ]; then
        info "Восстанавливаю /etc/config/dhcp"
        [ -f /etc/config/dhcp ] && cp /etc/config/dhcp /etc/config/dhcp-old
        mv /etc/config/dhcp-opkg /etc/config/dhcp
    fi
}

maybe_set_confdir() {
    # Same logic as upstream install.sh for OpenWrt 24+.
    _maj="$(echo "${DISTRIB_RELEASE:-}" | awk -F. '{print $1}')"
    [ -n "$_maj" ] || return 0
    if [ "$_maj" -ge 24 ] 2>/dev/null; then
        if uci get dhcp.@dnsmasq[0].confdir 2>/dev/null | grep -q '/tmp/dnsmasq.d'; then
            info "confdir уже /tmp/dnsmasq.d"
        else
            info "Ставлю dhcp.@dnsmasq[0].confdir=/tmp/dnsmasq.d"
            uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
            uci commit dhcp
        fi
    fi
}

find_kmod_dir() {
    # Prefer exact RELEASE + TARGET, then match KERNEL file against KERNEL_OPKG.
    _rel="$1"
    _tgt="$2"
    _dashed="$(echo "$_tgt" | tr '/' '-')"
    _base="$OFFLINE_DIR/kmods"
    if [ -n "$_rel" ] && [ -n "$_dashed" ] && [ -d "$_base/$_rel/$_dashed" ]; then
        echo "$_base/$_rel/$_dashed"
        return 0
    fi
    # Fallback: walk kmods/*/*/KERNEL
    if [ -n "$KERNEL_OPKG" ] && [ -d "$_base" ]; then
        for _kernfile in "$_base"/*/*/KERNEL; do
            [ -f "$_kernfile" ] || continue
            _k="$(tr -d '\r\n' < "$_kernfile")"
            case "$KERNEL_OPKG" in
                "$_k"|$_k-*)
                    dirname "$_kernfile"
                    return 0
                    ;;
            esac
            # KERNEL file is like 6.6.144-1-50daf837..., opkg version similar
            if [ "$_k" = "$KERNEL_OPKG" ]; then
                dirname "$_kernfile"
                return 0
            fi
        done
    fi
    return 1
}

cmd_install() {
    load_os

    if [ "$PKG_MANAGER" = "apk" ]; then
        die "OpenWrt 25.x (apk) не поддерживается. podkop 0.2.5 ставится только через opkg на OpenWrt 23.05 или 24.10."
    fi
    [ "$PKG_MANAGER" = "opkg" ] || die "нужен opkg (официальный OpenWrt 23.05 или 24.10)"

    case "${DISTRIB_ID:-}" in
        OpenWrt|openwrt) ;;
        *)
            echo "ВНИМАНИЕ: DISTRIB_ID=${DISTRIB_ID:-unknown}. Сборка рассчитана на официальный OpenWrt, не ImmortalWrt и не сторонние форки."
            ;;
    esac

    [ -d "$OFFLINE_DIR" ] || die "нет каталога $OFFLINE_DIR — сначала скопируйте пакеты с ПК"

    _rel="${RELEASE:-$DISTRIB_RELEASE}"
    _tgt="${TARGET:-$DISTRIB_TARGET}"
    _series="$SERIES"
    if [ -z "$_series" ]; then
        case "$_rel" in
            23.05*) _series="23.05" ;;
            24.10*) _series="24.10" ;;
            25.*)
                die "OpenWrt $_rel использует apk, podkop 0.2.5 для него не собран"
                ;;
            *)
                die "неподдерживаемая версия OpenWrt: ${_rel:-unknown}. Нужны 23.05.x или 24.10.x"
                ;;
        esac
    fi

    _user_dir="$OFFLINE_DIR/userspace/$_series"
    [ -d "$_user_dir" ] || die "в комплекте нет userspace/$_series (вижу: $(ls "$OFFLINE_DIR/userspace" 2>/dev/null | tr '\n' ' '))"

    _pod_dir="$OFFLINE_DIR/podkop"
    [ -d "$_pod_dir" ] || die "в комплекте нет каталога podkop/"

    # Rough space check: sing-box is the heavy one (~15–40 MB installed).
    if [ -n "$OVERLAY_FREE_KB" ] && [ "$OVERLAY_FREE_KB" -lt 20480 ] 2>/dev/null; then
        echo "ВНИМАНИЕ: свободно около $((OVERLAY_FREE_KB/1024)) МБ во flash. Для sing-box часто нужно 20–40 МБ. Если установка упадёт — освободите место или пропустите sing-box."
    fi

    info "Устанавливаю недостающие зависимости из комплекта (без opkg update)"
    install_missing_from_dir "$_user_dir"
    swap_dnsmasq "$_user_dir"

    if [ "$INSTALL_SINGBOX" = "1" ]; then
        if is_installed sing-box; then
            info "sing-box уже установлен"
        else
            _fn="$(pkg_from_list "$_user_dir" "sing-box" || true)"
            if [ -z "$_fn" ] || [ ! -f "$_user_dir/$_fn" ]; then die "в комплекте нет sing-box"; fi
            install_ipk "$_user_dir/$_fn"
        fi
    else
        info "sing-box пропускаю (INSTALL_SINGBOX=0)"
    fi

    _kdir="$(find_kmod_dir "$_rel" "$_tgt" || true)"
    if [ -n "$_kdir" ] && [ -f "$_kdir/packages.txt" ]; then
        info "Ставлю kmod из $(echo "$_kdir" | sed "s|^$OFFLINE_DIR/||")"
        while IFS="$(printf '\t')" read -r _name _fn || [ -n "$_name" ]; do
            [ -n "$_name" ] || continue
            if is_installed "$_name"; then
                info "Уже установлено: $_name"
                continue
            fi
            if ! opkg install "$_kdir/$_fn"; then
                die "не удалось установить $_name. Модуль должен точно совпадать с ядром (vermagic). Официальный OpenWrt ${_rel}, цель ${_tgt}."
            fi
        done < "$_kdir/packages.txt"
    else
        _need_kmod=0
        if ! is_installed kmod-nft-tproxy; then
            _need_kmod=1
        fi
        if [ "$INSTALL_SINGBOX" = "1" ]; then
            is_installed kmod-tun || _need_kmod=1
            is_installed kmod-inet-diag || _need_kmod=1
        fi
        if [ "$_need_kmod" -eq 1 ]; then
            die "нет kmod-пакетов для OpenWrt ${_rel}, цель ${_tgt}, ядро ${KERNEL_OPKG:-$KERNEL_RELEASE}. Нужен официальный OpenWrt 23.05.x или 24.10.x. Если kmod-nft-tproxy уже есть в прошивке — этого быть не должно."
        fi
        info "Нужные kmod уже стоят, отдельный комплект не понадобился"
    fi

    maybe_set_confdir

    info "Ставлю podkop 0.2.5"
    _fn="$(pkg_from_list "$_pod_dir" "podkop" || true)"
    [ -n "$_fn" ] || _fn="podkop_0.2.5-1_all.ipk"
    install_ipk "$_pod_dir/$_fn"

    _fn="$(pkg_from_list "$_pod_dir" "luci-app-podkop" || true)"
    [ -n "$_fn" ] || _fn="luci-app-podkop_0.2.5_all.ipk"
    install_ipk "$_pod_dir/$_fn"

    if [ "$INSTALL_RU" = "1" ]; then
        _fn="$(pkg_from_list "$_pod_dir" "luci-i18n-podkop-ru" || true)"
        [ -n "$_fn" ] || _fn="luci-i18n-podkop-ru_0.2.5.ipk"
        install_ipk "$_pod_dir/$_fn"
    fi

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload 2>/dev/null || true
    fi
    rm -f /var/luci-indexcache* /tmp/luci-indexcache* 2>/dev/null || true

    LAN_IP="$(uci -q get network.lan.ipaddr 2>/dev/null || true)"
    [ -n "$LAN_IP" ] || LAN_IP="${DISTRIB_ID:+}"
    [ -n "$LAN_IP" ] || LAN_IP="192.168.1.1"

    echo
    echo "=========================================="
    echo "Готово. podkop 0.2.5 установлен офлайн."
    echo "Открой LuCI → Services → Podkop"
    echo "Адрес: http://${LAN_IP}/cgi-bin/luci/admin/services/podkop"
    echo
    echo "Важно: списки доменов podkop при обновлении всё ещё качает с GitHub"
    echo "(itdoginfo/allow-domains). Это уже не установка, а работа самого podkop."
    echo "=========================================="
}

case "${1:-install}" in
    detect) cmd_detect ;;
    install) cmd_install ;;
    *)
        echo "Usage: $0 detect|install" >&2
        exit 2
        ;;
esac
