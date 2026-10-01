@echo off
rem ============================================================
rem  World Clock launcher (the only file teammates need)
rem  - Downloads the latest WorldClock.ps1 from WC_SOURCE on every start
rem  - Offline or download failed: runs the last downloaded copy
rem  - Double-click again: closes the running widget and reopens the latest
rem ============================================================

rem ---- Address of the latest WorldClock.ps1 (web URL or shared folder path) ----
set "WC_LAUNCHER=%~f0"
set "WC_SOURCE=https://raw.githubusercontent.com/SUNNY-duck/my-dashboard/main/worldclock/WorldClock.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ([scriptblock]::Create(((Get-Content -LiteralPath '%~f0' -Raw) -split ('#PS'+'-START#'),2)[1]))"
exit /b

#PS-START#
$dir   = Join-Path $env:LOCALAPPDATA 'WorldClock'
$local = Join-Path $dir 'WorldClock.ps1'
$tmp   = "$local.download"
$src   = $env:WC_SOURCE
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# 1. Get the latest version
try {
    if ($src -match '^https?://') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $src -OutFile $tmp -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    } else {
        Copy-Item -LiteralPath $src -Destination $tmp -Force -ErrorAction Stop
    }
    # Replace only when the download is really the widget (not an error page)
    $head = Get-Content -LiteralPath $tmp -TotalCount 1
    if ($head -like '# World Clock widget*') {
        Move-Item -LiteralPath $tmp -Destination $local -Force
    } else {
        Remove-Item -LiteralPath $tmp -Force
    }
} catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $local)) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show("Could not download World Clock.`nCheck the network and try again.", 'World Clock')
    exit
}

# 2. Keep a copy of this launcher for "start with Windows"
$stable = Join-Path $dir 'WorldClock.bat'
$me = $env:WC_LAUNCHER
if ($me -and (Test-Path -LiteralPath $me) -and ($me -ne $stable)) {
    Copy-Item -LiteralPath $me -Destination $stable -Force -ErrorAction SilentlyContinue
}

# 3. Close a widget that is already running
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($local) } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 4. Start the widget with no console window
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$local`""
)
