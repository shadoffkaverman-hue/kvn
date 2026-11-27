# Офлайн-установка podkop 0.2.5 с ПК

Скрипты ставят [podkop](https://github.com/itdoginfo/podkop) **v0.2.5** на роутер с OpenWrt **с компьютера по SSH**. Сам роутер ничего не скачивает — ни с GitHub, ни с downloads.openwrt.org. Это нужно, когда GitHub с роутера недоступен или режется белым списком.

Upstream: [itdoginfo/podkop](https://github.com/itdoginfo/podkop), лицензия [GPL-2.0](../LICENSE). Это неофициальный комплект.

Пакеты пользователей взяты с [downloads.openwrt.org](https://downloads.openwrt.org/) для последних точечных релизов веток: **23.05.6** и **24.10.8**. Модули ядра (`kmod-*`) положены для всех официальных точечных релизов 23.05.0–23.05.6 и 24.10.0–24.10.8 и типичных целей (target) каждой архитектуры.

## Что скачать

Один архив под архитектуру роутера (релиз [podkop-v0.2.5-offline](https://github.com/shadoffkaverman-hue/kvn/releases/tag/podkop-v0.2.5-offline)):

| Архив | Типичные устройства |
| --- | --- |
| `podkop-0.2.5-offline-mipsel_24kc.zip` | Xiaomi, Keenetic, TP-Link и др. на **MT7621 / MT76x8 / MT7620** |
| `podkop-0.2.5-offline-aarch64_cortex-a53.zip` | **Filogic** (MT7981/7986): Xiaomi AX3000T, GL-MT3000/MT6000, Cudy, Banana Pi R3; плюс ipq807x, MT7622 |
| `podkop-0.2.5-offline-aarch64_generic.zip` | **NanoPi / Rockchip** (R2S, R4S, R5S, R6S), armsr |
| `podkop-0.2.5-offline-arm_cortex-a7_neon-vfpv4.zip` | **ipq40xx** (многие Mesh/ASUS/Linksys), sunxi-a7 |
| `podkop-0.2.5-offline-x86_64.zip` | Мини-ПК и x86-роутеры |

Если не знаешь архитектуру — всё равно запусти скрипт: он подключится к роутеру, прочитает её и напишет, какой zip скачать.

Скрипты уже лежат внутри каждого архива. Проще всего скачать один zip, распаковать и запускать из этой папки.

Те же файлы есть в репозитории (`podkop/offline/`):

- `install-from-pc.ps1` — для Windows
- `install-from-pc.sh` — для Linux и macOS
- `install-on-router.sh` — ставится на роутер автоматически, вручную его запускать не нужно

## Установка с Windows

1. Скачай zip под свою архитектуру и распакуй, например в `Downloads\podkop`. (Скрипты уже внутри архива.)
2. Включи **OpenSSH Client**, если его ещё нет: *Параметры → Приложения → Дополнительные компоненты → OpenSSH Client*. В Windows 10 и 11 он обычно уже есть (`ssh` и `scp`).
3. Открой PowerShell в этой папке (в Проводнике: Shift+правый клик по пустому месту → «Открыть окно PowerShell здесь»).
4. Если Windows ругается на политику скриптов, один раз выполни:

   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   ```

5. Запусти (адрес роутера по умолчанию `192.168.1.1`):

   ```powershell
   .\install-from-pc.ps1
   ```

   Или явно:

   ```powershell
   .\install-from-pc.ps1 -Router 192.168.1.1
   ```

6. Введи пароль `root` роутера, когда спросит SSH. Подтверди установку буквой `y`.
7. Когда скрипт напишет «Готово», открой в браузере LuCI: **Services → Podkop**, адрес вида `http://192.168.1.1/cgi-bin/luci/admin/services/podkop`.

Другие ключи: `-User root`, `-Port 22`, `-IdentityFile путь\к\ключу`, `-Zip путь\к\архиву.zip`, `-NoRu` (без русского перевода), `-NoSingBox`, `-Yes` (без вопроса).

## Установка с Linux или macOS

```sh
chmod +x install-from-pc.sh install-on-router.sh
./install-from-pc.sh 192.168.1.1
# или
./install-from-pc.sh -z podkop-0.2.5-offline-mipsel_24kc.zip 192.168.1.1
```

## Что входит в комплект

- Сам **podkop 0.2.5**, **luci-app-podkop** и русский перевод **luci-i18n-podkop-ru**.
- **dnsmasq-full** и его зависимости (как в оригинальном `install.sh`: замена обычного `dnsmasq`, на 24.10 ещё выставляется `confdir=/tmp/dnsmasq.d`).
- **sing-box** из официальных фидов OpenWrt и его зависимости (`ca-bundle`, `kmod-tun`, `kmod-inet-diag` и т.д.).
- Зависимости самого podkop: `curl`, `jq`, `coreutils-base64`, `kmod-nft-tproxy` (и `kmod-nf-tproxy`).
- Уже установленные на роутере пакеты скрипт **не обновляет** и не перезаписывает (кроме замены `dnsmasq` → `dnsmasq-full` и установки/обновления самого podkop). `opkg update` не вызывается.

## Что не входит и что не поддерживается

- **OpenWrt 25.x** — нет. Там пакетный менеджер `apk`, а podkop 0.2.5 собран как `.ipk` для `opkg`.
- **ImmortalWrt**, снепшоты и сторонние сборки — набор kmod не подойдёт (другой vermagic ядра). Только официальный OpenWrt 23.05.x / 24.10.x.
- **WireGuard**, **AmneziaWG**, OpenVPN, OpenConnect — не входят. В оригинальном `install.sh` это отдельные пункты меню; для AmneziaWG пакеты ещё и сторонние, под конкретное ядро. При необходимости поставь их отдельно.
- Скрипт не зеркалирует списки доменов podkop. После установки сам podkop при обновлении списков по-прежнему ходит на GitHub (`itdoginfo/allow-domains`). Это уже не установка, а штатная работа пакета.

На роутерах с маленькой флеш-памятью (8–16 МБ) официальный `sing-box` может не влезть (на диске он занимает десятки мегабайт). Тогда либо освободите место, либо запустите установку с `-NoSingBox` / `--no-sing-box` и поставьте облегчённый клиент отдельно.
