# Patches for the Windows on ARM64 (windows-arm64) build.
#
# A few pub-cache plugins still assume an x86_64 Windows host:
#   * media_kit_libs_windows_video hard-codes x86_64 libmpv / ANGLE download
#     URLs and extracts archives with CMake's liblzma, which cannot open the
#     ARM64 archives ("Lzma library error: Invalid options").
#     windows/packaging/media_kit holds an arch-aware replacement for that
#     plugin's CMakeLists.txt which is copied over the pub-cache copy.
#   * flutter_inappwebview_windows passes /arch:AVX2 to MSVC.
#
# Run it AFTER `flutter pub get` (lib/scripts/patch.ps1 already runs that).

$ErrorActionPreference = 'Stop'

$RepoRoot = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }
$PackageConfig = Join-Path $RepoRoot '.dart_tool/package_config.json'

if (-not (Test-Path $PackageConfig)) {
    throw "'$PackageConfig' not found, run 'flutter pub get' first."
}

function Get-PackagePath([string]$Name) {
    $Config = Get-Content $PackageConfig -Raw | ConvertFrom-Json
    $Package = $Config.packages | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $Package) {
        throw "package '$Name' is not listed in $PackageConfig"
    }
    $RootUri = [System.Uri]::new([System.Uri]::new($PackageConfig), $Package.rootUri)
    return $RootUri.LocalPath.TrimEnd('/', '\')
}

function Update-FileContent([string]$Path, [string]$Old, [string]$New, [string]$Label) {
    if (-not (Test-Path $Path)) {
        throw "patch target is missing: $Path ($Label)"
    }
    # Normalise line endings (the checkout may be CRLF, the patterns below LF)
    # so the comparison is independent of git's eol conversion.
    $Old = $Old -replace "`r`n", "`n"
    $New = $New -replace "`r`n", "`n"
    $Text = (Get-Content $Path -Raw) -replace "`r`n", "`n"
    if ($Text.Contains($New)) {
        Write-Host "already patched: $Label"
        return
    }
    if (-not $Text.Contains($Old)) {
        throw "unexpected file content, cannot patch $Label ($Path)"
    }
    $Text = $Text.Replace($Old, $New)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "patched: $Label"
}

# ---------------------------------------------------------------------------
# media_kit_libs_windows_video: arm64 libmpv + arm64 ANGLE.
# ---------------------------------------------------------------------------
$MediaKitLibs = Get-PackagePath 'media_kit_libs_windows_video'
$MediaKitCmake = Join-Path $MediaKitLibs 'windows/CMakeLists.txt'
$MediaKitTemplate = Join-Path $RepoRoot 'windows/packaging/media_kit/media_kit_libs_windows_video_CMakeLists.txt'

if (-not (Test-Path $MediaKitTemplate)) {
    throw "missing template: $MediaKitTemplate"
}
Copy-Item $MediaKitTemplate $MediaKitCmake -Force
Write-Host 'replaced: media_kit_libs_windows_video: windows/CMakeLists.txt (arm64 aware)'

# ---------------------------------------------------------------------------
# flutter_inappwebview_windows: /arch:AVX2 is x86-only.
# ---------------------------------------------------------------------------
$InAppWebView = Get-PackagePath 'flutter_inappwebview_windows'
$InAppWebViewCmake = Join-Path $InAppWebView 'windows/CMakeLists.txt'

$AvxOld = @'
  # Enable AVX2 for pixel buffer conversions
  if(MSVC)
    target_compile_options(${PLUGIN_NAME} PRIVATE "/arch:AVX2")
  endif()
'@

$AvxNew = @'
  # Enable AVX2 for pixel buffer conversions (x86-only, arm64 has no AVX2)
  if(MSVC AND NOT "${FLUTTER_TARGET_PLATFORM}" STREQUAL "windows-arm64")
    target_compile_options(${PLUGIN_NAME} PRIVATE "/arch:AVX2")
  endif()
'@

Update-FileContent -Path $InAppWebViewCmake -Old $AvxOld -New $AvxNew -Label 'flutter_inappwebview_windows: /arch:AVX2 guard'

Write-Host 'Windows ARM64 patches applied.'
