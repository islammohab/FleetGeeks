# Renders the brand SVGs (mobile/assets/brand/*.svg) to the PNG sizes the icon and splash generators need
# (mobile/assets/brand/png/*.png), with headless Microsoft Edge or Google Chrome. Run it after changing an SVG, then
# regenerate the launcher icons and splash screens (see mobile/README.md → App icon and splash).
#   powershell -File mobile\tools\render_brand.ps1
# Windows PowerShell 5.1 compatible.
param([string]$Browser)
$ErrorActionPreference = 'Stop'
$brand = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\brand'
$out = Join-Path $brand 'png'
New-Item -ItemType Directory -Force $out | Out-Null

if (-not $Browser) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    $Browser = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Browser) { throw 'Edge or Chrome is needed (or pass -Browser <path to a Chromium browser>).' }

# source svg, output png, size in px
$jobs = @(
    @('fleetgeeks-mark.svg', 'icon-customer.png', 1024),
    @('fleetgeeks-mark-workshop.svg', 'icon-workshop.png', 1024),
    @('fleetgeeks-foreground.svg', 'foreground-customer.png', 1024),
    @('fleetgeeks-foreground-workshop.svg', 'foreground-workshop.png', 1024),
    @('fleetgeeks-monochrome.svg', 'monochrome.png', 1024),
    @('fleetgeeks-splash.svg', 'splash.png', 768),
    @('fleetgeeks-splash-android12.svg', 'splash-android12.png', 1152)
)

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('fg-brand-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
try {
    foreach ($job in $jobs) {
        $svg = Join-Path $brand $job[0]
        $png = Join-Path $out $job[1]
        $size = $job[2]
        $svgUrl = 'file:///' + ($svg -replace '\\', '/')
        $html = Join-Path $work ($job[1] + '.html')
        $page = "<!doctype html><html><head><style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}img{display:block;width:${size}px;height:${size}px}</style></head><body><img src=`"$svgUrl`"></body></html>"
        [System.IO.File]::WriteAllText($html, $page, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path $png) { Remove-Item $png }
        $profileDir = Join-Path $work ('profile-' + $job[1])
        $browserArgs = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check', '--disable-extensions',
                  '--allow-file-access-from-files', '--default-background-color=00000000', "--user-data-dir=$profileDir",
                  "--window-size=$size,$size", "--screenshot=$png", ('file:///' + ($html -replace '\\', '/')))
        # Do not use -Wait: it also waits for helper processes (crash handler) that may outlive the screenshot.
        $p = Start-Process -FilePath $Browser -ArgumentList $browserArgs -PassThru -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds(60)
        while (-not $p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
        Start-Sleep -Milliseconds 500
        # Stop whatever this render left behind (only processes started with this job's profile directory).
        Get-CimInstance Win32_Process -Filter "Name='msedge.exe' OR Name='chrome.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($profileDir) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        if (-not (Test-Path $png)) { throw "Rendering $($job[0]) failed." }
        Write-Host "  $($job[1])  ${size}x${size}"
    }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
Write-Host "PNG files written to $out"
