# Optional, after `dart run flutter_launcher_icons`: replaces the Android 8+ adaptive launcher icon of both apps with the
# PNG-less vector version (mobile/assets/brand/android/<app>/res: colour background, vector foreground, monochrome for
# Android 13 themed icons). The PNG icons generated for older Android versions stay as they are.
#   powershell -File mobile\tools\apply_vector_icons.ps1
# Windows PowerShell 5.1 compatible. Needs the android/ folders (tools/prepare_android.ps1).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($app in 'customer', 'workshop') {
    $source = Join-Path $root "assets\brand\android\$app\res"
    $target = Join-Path $root "apps\${app}_app\android\app\src\main\res"
    if (-not (Test-Path $target)) { throw "Missing $target - run tools/prepare_android.ps1 first." }
    Get-ChildItem $source -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($source.Length + 1)
        $destination = Join-Path $target $relative
        New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
        Copy-Item $_.FullName $destination -Force
        Write-Host "  ${app}: $relative"
    }
}
Write-Host 'Vector adaptive icons applied. Rebuild the APKs.'
