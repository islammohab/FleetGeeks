# Generates the Android platform folder of both apps (flutter create keeps the existing lib/ and pubspec.yaml)
# and adds the permissions and labels Fleet Geeks needs. Run once on the machine that has Flutter + Android SDK.
#   pwsh mobile/tools/prepare_android.ps1                 # HTTPS API (production / test)
#   pwsh mobile/tools/prepare_android.ps1 -AllowHttp      # also allow plain http (development API on the LAN only)
#   pwsh mobile/tools/prepare_android.ps1 -Brand          # also generate launcher icons + splash screens (brand PNGs in
#                                                         # assets/brand/png) and apply the vector adaptive icons
param([switch]$AllowHttp, [switch]$Brand)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$apps = @(
    @{ Dir = 'apps/workshop_app'; Name = 'workshop_app'; Label = 'FG Workshop' },
    @{ Dir = 'apps/customer_app'; Name = 'customer_app'; Label = 'Fleet Geeks' }
)
Push-Location $root
try {
    flutter pub get
    foreach ($app in $apps) {
        Push-Location (Join-Path $root $app.Dir)
        try {
            flutter create --platforms=android --org com.fleetgeeks --project-name $app.Name .
            # flutter create adds a counter-app widget test that does not apply to this app.
            if (Test-Path 'test/widget_test.dart') { Remove-Item 'test/widget_test.dart' }
            $manifest = 'android/app/src/main/AndroidManifest.xml'
            $xml = Get-Content $manifest -Raw
            foreach ($perm in 'android.permission.INTERNET', 'android.permission.CAMERA') {
                if ($xml -notmatch [regex]::Escape($perm)) {
                    $xml = $xml -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"$perm`"/>"
                }
            }
            $xml = $xml -replace 'android:label="[^"]*"', "android:label=`"$($app.Label)`""
            if ($AllowHttp -and $xml -notmatch 'usesCleartextTraffic') {
                $xml = $xml -replace '<application', '<application android:usesCleartextTraffic="true"'
            }
            if ($app.Name -eq 'customer_app') {
                # url_launcher (payment links) needs to see browsers on Android 11+.
                if ($xml -notmatch 'android:scheme="https"') {
                    $intent = '<intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>'
                    if ($xml -match '<queries>') { $xml = $xml -replace '<queries>', "<queries>`n        $intent" }
                    else { $xml = $xml -replace '</manifest>', "    <queries>`n        $intent`n    </queries>`n</manifest>" }
                }
                # open_filex declares media-read permissions the app does not need (it only opens its own PDFs).
                if ($xml -notmatch 'xmlns:tools=') { $xml = $xml -replace '<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ' }
                foreach ($perm in 'android.permission.READ_MEDIA_IMAGES', 'android.permission.READ_MEDIA_VIDEO', 'android.permission.READ_MEDIA_AUDIO', 'android.permission.READ_EXTERNAL_STORAGE') {
                    if ($xml -notmatch [regex]::Escape("$perm`" tools:node")) {
                        $xml = $xml -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"$perm`" tools:node=`"remove`"/>"
                    }
                }
            }
            # UTF-8 without BOM (Windows PowerShell 5's -Encoding utf8 writes a BOM)
            [IO.File]::WriteAllText((Resolve-Path $manifest), $xml, (New-Object Text.UTF8Encoding $false))
            # flutter_appauth needs the redirect scheme placeholder, otherwise the manifest merge fails
            $gradle = (Resolve-Path 'android/app/build.gradle.kts').Path
            $g = [IO.File]::ReadAllText($gradle)
            if ($g -notmatch 'appAuthRedirectScheme') {
                $scheme = if ($app.Name -eq 'customer_app') { 'com.fleetgeeks.customer' } else { 'com.fleetgeeks.workshop' }
                $g = [regex]::Replace($g, '(minSdk = flutter\.minSdkVersion)', "`$1`n        manifestPlaceholders[`"appAuthRedirectScheme`"] = `"$scheme`"", 1)
                [IO.File]::WriteAllText($gradle, $g, (New-Object Text.UTF8Encoding $false))
            }
            # flutter_appauth compiles against an old SDK while its AndroidX dependencies need compileSdk >= 34:
            # raise every Android library plugin to compileSdk 36 (before evaluationDependsOn in the root build file)
            $rootGradle = (Resolve-Path 'android/build.gradle.kts').Path
            $r = [IO.File]::ReadAllText($rootGradle)
            if ($r -notmatch 'LibraryExtension') {
                $raise = "subprojects {`n    afterEvaluate {`n        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let { lib ->`n            if ((lib.compileSdk ?: 0) < 36) {`n                lib.compileSdk = 36`n            }`n        }`n    }`n}`n"
                $r = [regex]::Replace($r, '(subprojects \{\r?\n\s*project\.evaluationDependsOn)', "$raise`$1", 1)
                [IO.File]::WriteAllText($rootGradle, $r, (New-Object Text.UTF8Encoding $false))
            }
            if ($Brand) {
                dart run flutter_launcher_icons
                dart run flutter_native_splash:create
            }
            Write-Host "Prepared $($app.Dir)"
        } finally { Pop-Location }
    }
    if ($Brand) { & (Join-Path $PSScriptRoot 'apply_vector_icons.ps1') }
} finally { Pop-Location }
