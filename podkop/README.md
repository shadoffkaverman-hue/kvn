# podkop v0.2.5 (зеркало)

Зеркало релиза [itdoginfo/podkop](https://github.com/itdoginfo/podkop) **v0.2.5** и скрипта установки с коммита [`a6a171e`](https://github.com/itdoginfo/podkop/blob/a6a171ef47d0ea91d046a9d613570b2a7c952b0d/install.sh).

Upstream распространяется под [GNU GPL-2.0](https://github.com/itdoginfo/podkop/blob/v0.2.5/LICENSE). Копия лицензии: [LICENSE](LICENSE). Это неофициальное зеркало, исходный проект — [itdoginfo/podkop](https://github.com/itdoginfo/podkop).

## Установка на OpenWrt

```sh
sh <(wget -O - https://raw.githubusercontent.com/shadoffkaverman-hue/kvn/main/podkop/install.sh)
```

Скрипт ставит пакеты **v0.2.5** с этого репозитория (`podkop/v0.2.5/` или, если raw недоступен, из GitHub Release [podkop-v0.2.5](https://github.com/shadoffkaverman-hue/kvn/releases/tag/podkop-v0.2.5)). Остальная логика как у оригинала.

Оригинальный скрипт без правок: [install.orig.sh](install.orig.sh). Он по умолчанию тянет *latest* с `itdoginfo/podkop`; для v0.2.5 его нужно было бы вызывать так:

```sh
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/podkop/a6a171ef47d0ea91d046a9d613570b2a7c952b0d/install.sh | sed 's|https://api.github.com/repos/itdoginfo/podkop/releases/latest|https://api.github.com/repos/itdoginfo/podkop/releases/tags/v0.2.5|g')
```

## Файлы релиза v0.2.5

| Файл | Размер | SHA-256 |
| --- | ---: | --- |
| `podkop_0.2.5-1_all.ipk` | 10303 | `b641c82e389806cb628e845ae4c9b024316f1fad11b1e3a692e83af06ee34ebc` |
| `luci-app-podkop_0.2.5_all.ipk` | 5971 | `3d7459397e6ca67f93ea3221fb2dc11bf641ebcd5773d0cf013e2569ce7ba98f` |
| `luci-i18n-podkop-ru_0.2.5.ipk` | 4120 | `eabc3862fb684f9cd0b73e8af5d631c69a6b0f5c0183e5ae1fbc387c931bf16e` |

Контрольные суммы также в [v0.2.5/SHA256SUMS](v0.2.5/SHA256SUMS).

## Что скрипт по-прежнему берёт не из этого зеркала

- Каталоги пакетов OpenWrt через `opkg update` / `opkg install`: `dnsmasq-full`, `sing-box`, `wireguard-tools`, `luci-proto-wireguard`, `luci-app-wireguard`, `openvpn-openssl`, `luci-app-openvpn`, `openconnect`, `luci-proto-openconnect`.
- Если выбрать AmneziaWG — пакеты с [Slava-Shchipunov/awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt) (`https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/`).
- Справки по ручной настройке на [itdog.info](https://itdog.info): [WireGuard](https://itdog.info/nastrojka-klienta-wireguard-na-openwrt/), [OpenVPN](https://itdog.info/nastrojka-klienta-openvpn-na-openwrt/), [OpenConnect](https://itdog.info/nastrojka-klienta-openconnect-na-openwrt/).


## Офлайн-установка с ПК

Если с роутера нельзя качать GitHub, ставь с компьютера по SSH: роутер ничего не скачивает.

Инструкция и скрипты: [offline/README.md](offline/README.md). Архивы под архитектуру — в релизе [podkop-v0.2.5-offline](https://github.com/shadoffkaverman-hue/kvn/releases/tag/podkop-v0.2.5-offline).

На Windows, из распакованной папки архива:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-from-pc.ps1 -Router 192.168.1.1
```
