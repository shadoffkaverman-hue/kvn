#Requires -Version 5.1
<#
.SYNOPSIS
  Ставит podkop 0.2.5 на OpenWrt с Windows-ПК по SSH. Роутер ничего не качает.

.EXAMPLE
  .\install-from-pc.ps1
  .\install-from-pc.ps1 -Router 192.168.1.1
  .\install-from-pc.ps1 -Router 192.168.1.1 -Zip .\podkop-0.2.5-offline-mipsel_24kc.zip
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Router = "192.168.1.1",
    [string]$User = "root",
    [int]$Port = 22,
    [string]$IdentityFile,
    [string]$Zip,
    [string]$Dir,
    [switch]$NoRu,
    [switch]$NoSingBox,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Fail([string]$Message) {
    Write-Host "ОШИБКА: $Message" -ForegroundColor Red
    exit 1
}

function Info([string]$Message) {
    Write-Host ">>> $Message"
}

function Get-SshExe {
    $cmd = Get-Command ssh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:SystemRoot\System32\OpenSSH\ssh.exe",
        "$env:ProgramFiles\OpenSSH\ssh.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    Fail "Не найден ssh.exe. В Windows 10/11: Параметры → Приложения → Дополнительные компоненты → OpenSSH Client."
}

function Get-ScpExe($SshPath) {
    $dir = Split-Path $SshPath
    $scp = Join-Path $dir "scp.exe"
    if (Test-Path $scp) { return $scp }
    $cmd = Get-Command scp -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-TarExe {
    $cmd = Get-Command tar -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $tar = "$env:SystemRoot\System32\tar.exe"
    if (Test-Path $tar) { return $tar }
    return $null
}

$ssh = Get-SshExe
$scp = Get-ScpExe $ssh
$tar = Get-TarExe

$sshArgs = @("-p", "$Port", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new")
$scpArgs = @("-P", "$Port", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new")
if ($IdentityFile) {
    if (-not (Test-Path $IdentityFile)) { Fail "Нет файла ключа $IdentityFile" }
    $sshArgs += @("-i", $IdentityFile)
    $scpArgs += @("-i", $IdentityFile)
}

function Invoke-Router([string]$RemoteCmd) {
    $all = $sshArgs + @("${User}@${Router}", $RemoteCmd)
    & $ssh @all
    if ($LASTEXITCODE -ne 0) {
        throw "ssh exited $LASTEXITCODE"
    }
}

Info "Подключаюсь к ${User}@${Router}:${Port}…"
try {
    $detect = & $ssh @sshArgs "${User}@${Router}" "cat /etc/openwrt_release; echo ---UNAME---; uname -r; echo ---OPKG---; command -v opkg || true; echo ---APK---; command -v apk || true; echo ---KERNELPKG---; opkg list-installed 2>/dev/null | awk '`$1==`"kernel`"{print `$3}'; echo ---DF---; df -k /overlay /tmp /usr 2>/dev/null"
} catch {
    Fail "Не удалось подключиться по SSH. Проверь IP, что на роутере включён Dropbear/SSH, и пароль. $_"
}
if ($LASTEXITCODE -ne 0 -or -not $detect) {
    Fail "Не удалось подключиться по SSH. Проверь IP, что на роутере включён Dropbear/SSH, и пароль."
}

function Get-ReleaseVal([string]$Text, [string]$Key) {
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match ("^" + [regex]::Escape($Key) + "='?([^']*)'?\s*$")) {
            return $Matches[1].Trim("'")
        }
    }
    return ""
}

function Get-AfterMarker([string]$Text, [string]$Marker) {
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -eq $Marker) {
            if ($i + 1 -lt $lines.Length -and $lines[$i + 1] -notmatch "^---") {
                return $lines[$i + 1]
            }
            return ""
        }
    }
    return ""
}

$distribRelease = Get-ReleaseVal $detect "DISTRIB_RELEASE"
$distribTarget  = Get-ReleaseVal $detect "DISTRIB_TARGET"
$distribArch    = Get-ReleaseVal $detect "DISTRIB_ARCH"
$distribId      = Get-ReleaseVal $detect "DISTRIB_ID"
$distribRev     = Get-ReleaseVal $detect "DISTRIB_REVISION"
$kernelRelease  = Get-AfterMarker $detect "---UNAME---"
$kernelOpkg     = Get-AfterMarker $detect "---KERNELPKG---"
$hasOpkg        = Get-AfterMarker $detect "---OPKG---"
$hasApk         = Get-AfterMarker $detect "---APK---"

Write-Host ""
Write-Host "Роутер:          $Router"
Write-Host "Система:         $distribId $distribRelease"
Write-Host "Архитектура:     $distribArch"
Write-Host "Цель (target):   $distribTarget"
Write-Host "Ревизия:         $distribRev"
$kernelExtra = ""
if ($kernelOpkg) { $kernelExtra = "($kernelOpkg)" }
Write-Host "Ядро:            $kernelRelease $kernelExtra"
Write-Host ""

if ($hasApk -and -not $hasOpkg) {
    Fail "На роутере OpenWrt $distribRelease с пакетным менеджером apk. podkop 0.2.5 ставится только на OpenWrt 23.05 или 24.10 (opkg)."
}
if (-not $hasOpkg) { Fail "На роутере нет opkg." }
if (-not $distribArch) { Fail "Не удалось прочитать DISTRIB_ARCH." }

$series = $null
if ($distribRelease -like "23.05*") { $series = "23.05" }
elseif ($distribRelease -like "24.10*") { $series = "24.10" }
elseif ($distribRelease -like "25.*") {
    Fail "OpenWrt $distribRelease не поддерживается этим комплектом (apk, не opkg)."
}
else {
    Fail "Неподдерживаемая версия OpenWrt: $distribRelease. Нужны 23.05.x или 24.10.x."
}

$zipName = "podkop-0.2.5-offline-$distribArch.zip"
$wantDir = "podkop-0.2.5-offline-$distribArch"

function Find-Zip {
    if ($Zip) {
        if (-not (Test-Path $Zip)) { Fail "Нет файла $Zip" }
        return (Resolve-Path $Zip).Path
    }
    $candidates = @(
        (Join-Path $Here $zipName),
        (Join-Path (Get-Location) $zipName),
        (Join-Path $Here "zips\$zipName"),
        (Join-Path $Here "bundles\$zipName")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    $found = Get-ChildItem -Path $Here, (Get-Location) -Filter $zipName -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Find-Bundle {
    if ($Dir) {
        if (-not (Test-Path $Dir)) { Fail "Нет каталога $Dir" }
        return (Resolve-Path $Dir).Path
    }
    $candidates = @(
        (Join-Path $Here $wantDir),
        (Join-Path (Get-Location) $wantDir)
    )
    foreach ($c in $candidates) {
        if ((Test-Path (Join-Path $c "podkop")) -and (Test-Path (Join-Path $c "userspace"))) {
            return (Resolve-Path $c).Path
        }
    }
    return $null
}

$work = $null
$bundle = Find-Bundle
if (-not $bundle) {
    $z = Find-Zip
    if (-not $z) {
        Fail @"
Не найден $zipName
Скачай архив для архитектуры $distribArch из релиза podkop-v0.2.5-offline
и положи его в ту же папку, что и скрипт, либо укажи: -Zip путь\$zipName
"@
    }
    Info "Распаковываю $(Split-Path $z -Leaf)…"
    $work = Join-Path $env:TEMP ("podkop-offline-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $work | Out-Null
    Expand-Archive -LiteralPath $z -DestinationPath $work -Force
    $inner = Join-Path $work $wantDir
    if (Test-Path (Join-Path $inner "podkop")) {
        $bundle = $inner
    }
    elseif (Test-Path (Join-Path $work "podkop")) {
        $bundle = $work
    }
    else {
        $foundDir = Get-ChildItem $work -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName "podkop") } | Select-Object -First 1
        if ($foundDir) { $bundle = $foundDir.FullName }
    }
    if (-not $bundle) { Fail "Внутри архива нет ожидаемого каталога." }
}

$userspace = Join-Path $bundle "userspace\$series"
if (-not (Test-Path $userspace)) {
    Fail "В комплекте нет пакетов для $series."
}

$dashed = $distribTarget -replace "/", "-"
$kmodDir = Join-Path $bundle "kmods\$distribRelease\$dashed"
if (-not (Test-Path $kmodDir)) {
    $kmodDir = $null
    if ($kernelOpkg) {
        Get-ChildItem -Path (Join-Path $bundle "kmods") -Recurse -Filter "KERNEL" -ErrorAction SilentlyContinue | ForEach-Object {
            $k = (Get-Content -LiteralPath $_.FullName -Raw).Trim()
            if ($k -eq $kernelOpkg) { $script:kmodDir = $_.DirectoryName }
        }
    }
}

Write-Host "Комплект:        $bundle"
Write-Host "Пакеты OpenWrt:  userspace/$series"
if ($kmodDir) {
    Write-Host ("kmod:            " + $kmodDir.Substring($bundle.Length).TrimStart("\", "/"))
}
else {
    Write-Host "kmod:            в комплекте нет точного набора для $distribRelease / $distribTarget"
    Write-Host "                 (если модули уже стоят на роутере — это нормально)"
}
Write-Host ""

if (-not $Yes) {
    $ans = Read-Host "Ставить podkop 0.2.5 на $Router ? [y/N]"
    if ($ans -notmatch '^(y|Y|yes|да|Да)$') {
        Write-Host "Отменено."
        exit 0
    }
}

$stage = Join-Path $env:TEMP ("podkop-push-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    Copy-Item -Recurse -Force (Join-Path $bundle "podkop") (Join-Path $stage "podkop")
    New-Item -ItemType Directory -Path (Join-Path $stage "userspace\$series") -Force | Out-Null
    Copy-Item -Recurse -Force (Join-Path $userspace "*") (Join-Path $stage "userspace\$series")
    if ($kmodDir) {
        $rel = $kmodDir.Substring($bundle.Length).TrimStart("\", "/")
        $destK = Join-Path $stage $rel
        New-Item -ItemType Directory -Path $destK -Force | Out-Null
        Copy-Item -Recurse -Force (Join-Path $kmodDir "*") $destK
    }
    $routerScript = Join-Path $Here "install-on-router.sh"
    if (-not (Test-Path $routerScript)) {
        $routerScript = Join-Path $bundle "install-on-router.sh"
    }
    if (-not (Test-Path $routerScript)) { Fail "Рядом со скриптом нет install-on-router.sh" }
    Copy-Item -Force $routerScript (Join-Path $stage "install-on-router.sh")

    Info "Копирую пакеты на роутер в /tmp/podkop-offline (роутер ничего не качает)…"
    Invoke-Router "rm -rf /tmp/podkop-offline && mkdir -p /tmp/podkop-offline"

    $uploaded = $false
    if ($tar) {
        # tar.exe on Windows understands ./ paths; send to remote tar via ssh stdin.
        Push-Location $stage
        try {
            $remote = @($sshArgs) + @("${User}@${Router}", "tar -C /tmp/podkop-offline -xf -")
            & $tar -cf - . | & $ssh @remote
            if ($LASTEXITCODE -eq 0) { $uploaded = $true; Info "Файлы скопированы через tar+ssh" }
        } catch {
            Write-Host "tar+ssh не сработал, пробую scp…" -ForegroundColor Yellow
        } finally {
            Pop-Location
        }
    }

    if (-not $uploaded -and $scp) {
        $legacy = $scpArgs + @("-O", "-r") + @((Join-Path $stage "*"), "${User}@${Router}:/tmp/podkop-offline/")
        & $scp @legacy
        if ($LASTEXITCODE -eq 0) { $uploaded = $true; Info "Файлы скопированы через scp -O" }
    }
    if (-not $uploaded -and $scp) {
        $plain = $scpArgs + @("-r") + @((Join-Path $stage "*"), "${User}@${Router}:/tmp/podkop-offline/")
        & $scp @plain
        if ($LASTEXITCODE -eq 0) { $uploaded = $true; Info "Файлы скопированы через scp" }
    }
    if (-not $uploaded) {
        Fail "Не удалось скопировать файлы на роутер (не сработали ни tar+ssh, ни scp). На Windows 10 должен быть встроенный OpenSSH Client и tar.exe."
    }

    $ru = $(if ($NoRu) { "0" } else { "1" })
    $sb = $(if ($NoSingBox) { "0" } else { "1" })
    $installCmd = "INSTALL_RU=$ru INSTALL_SINGBOX=$sb RELEASE='$distribRelease' TARGET='$distribTarget' SERIES='$series' OFFLINE_DIR=/tmp/podkop-offline sh /tmp/podkop-offline/install-on-router.sh install"
    Info "Запускаю установку на роутере…"
    Invoke-Router $installCmd
    Info "Готово."
}
finally {
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    if ($work -and (Test-Path $work)) { Remove-Item -Recurse -Force $work }
}
