# Patches for the Windows on ARM64 (windows-arm64) build.
#
# A few pub-cache plugins still assume an x86_64 Windows host:
#   * media_kit_libs_windows_video hard-codes x86_64 libmpv / ANGLE download URLs.
#   * flutter_inappwebview_windows passes /arch:AVX2 to MSVC.
# This script rewrites those spots so that the same source tree also produces a
# native arm64 build, while keeping the x64 build working unchanged.
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
    # Normalise line endings (the checkout may be CRLF, the patterns below LF) so
    # the comparison below is independent of git's eol conversion.
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
# media_kit_libs_windows_video: bundle arm64 libmpv + arm64 ANGLE.
# ---------------------------------------------------------------------------
$MediaKitLibs = Get-PackagePath 'media_kit_libs_windows_video'
$MediaKitCmake = Join-Path $MediaKitLibs 'windows/CMakeLists.txt'

$LibmpvOld = @'
# libmpv archive containing the pre-built shared libraries & headers.
set(LIBMPV "mpv-dev-x86_64-20260607-git-43b14a4.7z")

# Download URL & MD5 hash of the libmpv archive.
set(LIBMPV_URL "https://github.com/bggRGjQaUbCoE/mpv-winbuild-cmake/releases/download/20260607/${LIBMPV}")
set(LIBMPV_MD5 "b84900bbc6fcb995ca6a24f62bee671f")
'@

$LibmpvNew = @'
# libmpv archive containing the pre-built shared libraries & headers.
# windows-arm64 support: an x86_64 libmpv cannot be loaded by an arm64 process.
set(LIBMPV_RELEASE "20260607")
set(LIBMPV_TAG "43b14a4")
if("${FLUTTER_TARGET_PLATFORM}" STREQUAL "windows-arm64")
  set(LIBMPV "mpv-dev-aarch64-${LIBMPV_RELEASE}-git-${LIBMPV_TAG}.7z")
  set(LIBMPV_MD5 "e4c49712b9cf0d77e1ae8e1a9c8e3ed7")
else()
  set(LIBMPV "mpv-dev-x86_64-${LIBMPV_RELEASE}-git-${LIBMPV_TAG}.7z")
  set(LIBMPV_MD5 "b84900bbc6fcb995ca6a24f62bee671f")
endif()

# Download URL of the libmpv archive.
set(LIBMPV_URL "https://github.com/bggRGjQaUbCoE/mpv-winbuild-cmake/releases/download/${LIBMPV_RELEASE}/${LIBMPV}")
'@

Update-FileContent -Path $MediaKitCmake -Old $LibmpvOld -New $LibmpvNew -Label 'media_kit_libs_windows_video: libmpv archive'

$AngleOld = @'
# ANGLE archive containing the pre-built shared libraries & headers.
set(ANGLE "ANGLE.7z")

# Download URL & MD5 hash of the ANGLE archive.
set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")
'@

$AngleNew = @'
# ANGLE archive containing the pre-built shared libraries & headers.
# windows-arm64 support: alexmercerind/flutter-windows-ANGLE-OpenGL-ES v1.0.1
# only ships x86_64 DLLs; the arm64 build lives in talynone's fork.
if("${FLUTTER_TARGET_PLATFORM}" STREQUAL "windows-arm64")
  set(ANGLE "ANGLE_WINARM64.7z")
  set(ANGLE_URL "https://github.com/talynone/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE_WINARM64.7z")
  set(ANGLE_MD5 "b56aaae894ccf6c8ee90b59ee642a787")
else()
  set(ANGLE "ANGLE.7z")
  set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
  set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")
endif()
'@

Update-FileContent -Path $MediaKitCmake -Old $AngleOld -New $AngleNew -Label 'media_kit_libs_windows_video: ANGLE archive'

$BundledOld = @'
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
'@

$BundledNew = @'
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)

# The arm64 ANGLE build additionally depends on its own libc++ runtime.
if("${FLUTTER_TARGET_PLATFORM}" STREQUAL "windows-arm64")
  list(APPEND media_kit_libs_windows_video_bundled_libraries "${ANGLE_SRC}/libc++.dll")
endif()
'@

Update-FileContent -Path $MediaKitCmake -Old $BundledOld -New $BundledNew -Label 'media_kit_libs_windows_video: bundled ANGLE libs'

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
