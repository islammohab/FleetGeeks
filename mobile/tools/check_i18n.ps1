# Checks the English / Arabic text of the Flutter apps (packages/fg_core/lib/src/i18n.dart):
#   - every key exists in both maps, no key is duplicated, no value is empty,
#   - both languages use the same {0} {1} placeholders,
#   - every literal key used in the Dart code as s.t('key') exists.
# Windows PowerShell 5.1 compatible. Exit code 0 = pass, 1 = fail. (Hashtables are read through .PSBase: a text key
# such as "keys" would otherwise shadow the .Keys property.)
#   powershell -File mobile\tools\check_i18n.ps1
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'

$file = Join-Path $Root 'packages\fg_core\lib\src\i18n.dart'
if (-not (Test-Path $file)) { Write-Host "Not found: $file"; exit 1 }
$text = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)

function Get-DartMap([string]$source, [string]$name) {
    $start = $source.IndexOf("const Map<String, String> $name = {")
    if ($start -lt 0) { throw "Map '$name' not found" }
    $end = $source.IndexOf("`n};", $start)
    $block = $source.Substring($start, $end - $start)
    $entries = New-Object System.Collections.ArrayList
    $pattern = "^\s*'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\]|\\.)*)'\s*,?\s*$"
    foreach ($line in ($block -split "`n")) {
        $m = [regex]::Match($line.TrimEnd("`r"), $pattern)
        if ($m.Success) { [void]$entries.Add([pscustomobject]@{ Key = $m.Groups[1].Value; Value = $m.Groups[2].Value }) }
    }
    return , $entries
}

$problems = New-Object System.Collections.ArrayList
$maps = @{}
foreach ($lang in 'en', 'ar') {
    $entries = Get-DartMap $text $lang
    $dict = @{}
    foreach ($e in $entries) {
        if ($dict.ContainsKey($e.Key)) { [void]$problems.Add("[$lang] duplicate key '$($e.Key)'") } else { $dict[$e.Key] = $e.Value }
        if ([string]::IsNullOrWhiteSpace($e.Value)) { [void]$problems.Add("[$lang] empty value for '$($e.Key)'") }
    }
    $maps[$lang] = $dict
}

foreach ($key in $maps['en'].PSBase.Keys) {
    if (-not $maps['ar'].ContainsKey($key)) { [void]$problems.Add("[ar] missing key '$key'"); continue }
    $pe = ([regex]::Matches($maps['en'][$key], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object) -join ','
    $pa = ([regex]::Matches($maps['ar'][$key], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object) -join ','
    if ($pe -ne $pa) { [void]$problems.Add("placeholders differ for '$key' (en: $pe / ar: $pa)") }
}
foreach ($key in $maps['ar'].PSBase.Keys) {
    if (-not $maps['en'].ContainsKey($key)) { [void]$problems.Add("[en] missing key '$key'") }
}

# Literal keys used in the apps and the core package.
$used = @{}
$dartFiles = Get-ChildItem -Path $Root -Recurse -Filter '*.dart' | Where-Object { $_.FullName -notmatch '\\(build|\.dart_tool)\\' }
foreach ($f in $dartFiles) {
    $src = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $src = [regex]::Replace($src, '(?m)^\s*//.*$', '')   # whole-line comments (doc examples) are not usages
    foreach ($m in [regex]::Matches($src, "\.t\('([A-Za-z][A-Za-z0-9_]*)'")) {
        $k = $m.Groups[1].Value
        if (-not $used.ContainsKey($k)) { $used[$k] = $f.FullName.Substring($Root.Length + 1) }
    }
}
foreach ($k in $used.PSBase.Keys) {
    if (-not $maps['en'].ContainsKey($k)) { [void]$problems.Add("key '$k' used in $($used[$k]) is not defined") }
}

$enCount = $maps['en'].PSBase.Count
$arCount = $maps['ar'].PSBase.Count
$both = @($maps['en'].PSBase.Keys | Where-Object { $maps['ar'].ContainsKey($_) -and -not [string]::IsNullOrWhiteSpace($maps['ar'][$_]) -and -not [string]::IsNullOrWhiteSpace($maps['en'][$_]) }).Count
Write-Host "EN keys: $enCount  AR keys: $arCount  complete in both: $both  literal keys used in code: $($used.PSBase.Count)"
if ($problems.Count -gt 0) {
    Write-Host "FAIL ($($problems.Count) problems):"
    $problems | Sort-Object | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "PASS: $both/$enCount keys present and non-empty in English and Arabic."
exit 0
