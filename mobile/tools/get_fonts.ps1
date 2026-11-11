# Downloads the brand fonts into mobile/packages/fg_core/fonts (both SIL Open Font License 1.1; licence texts are saved
# next to the font files). The repository already contains them; run this to restore or update them.
#   powershell -File mobile\tools\get_fonts.ps1
#   - IBM Plex Sans Arabic 400/500/600/700: Google Fonts repository (github.com/google/fonts, ofl/ibmplexsansarabic)
#   - Inter 400/500/600/700 static TTF: the official Inter repository release (github.com/rsms/inter). Google Fonts only
#     ships Inter as a variable font, and Flutter does not map FontWeight to the variable "wght" axis by itself.
# Windows PowerShell 5.1 compatible.
param([string]$InterVersion = '4.1')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$fonts = Join-Path (Split-Path $PSScriptRoot -Parent) 'packages\fg_core\fonts'
New-Item -ItemType Directory -Force $fonts | Out-Null
$weights = 'Regular', 'Medium', 'SemiBold', 'Bold'

function Get-File([string]$url, [string]$path) {
    Write-Host "  $url"
    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
    if ((Get-Item $path).Length -lt 1000) { throw "Download looks wrong: $url" }
}

Write-Host 'IBM Plex Sans Arabic (google/fonts)'
$plex = 'https://raw.githubusercontent.com/google/fonts/main/ofl/ibmplexsansarabic'
foreach ($w in $weights) { Get-File "$plex/IBMPlexSansArabic-$w.ttf" (Join-Path $fonts "IBMPlexSansArabic-$w.ttf") }
Get-File "$plex/OFL.txt" (Join-Path $fonts 'IBMPlexSansArabic-OFL.txt')

Write-Host "Inter $InterVersion (rsms/inter)"
$zip = Join-Path ([System.IO.Path]::GetTempPath()) "Inter-$InterVersion.zip"
Get-File "https://github.com/rsms/inter/releases/download/v$InterVersion/Inter-$InterVersion.zip" $zip
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    foreach ($w in $weights) {
        $entry = $archive.Entries | Where-Object { $_.FullName -eq "extras/ttf/Inter-$w.ttf" } | Select-Object -First 1
        if (-not $entry) { throw "Inter-$w.ttf not found in the release archive" }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $fonts "Inter-$w.ttf"), $true)
    }
    $licence = $archive.Entries | Where-Object { $_.FullName -eq 'LICENSE.txt' } | Select-Object -First 1
    if ($licence) { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($licence, (Join-Path $fonts 'Inter-OFL.txt'), $true) }
} finally {
    $archive.Dispose()
    Remove-Item $zip -ErrorAction SilentlyContinue
}
Get-ChildItem $fonts | Select-Object Name, Length | Format-Table -AutoSize
Write-Host "Fonts ready in $fonts (declared in packages/fg_core/pubspec.yaml)."
