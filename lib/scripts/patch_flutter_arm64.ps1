# Make the bundled Flutter SDK target windows-arm64 from the arm64 runner.
#
# Flutter 3.47.x derives the Windows build target from the ABI the flutter tool
# itself was compiled for (OperatingSystemUtils.hostPlatform -> _currentAbi).
# The Windows SDK that Flutter ships is x64-only, so even on an arm64 host
# `flutter build windows` selects windows-x64 and downloads x86_64 engine
# artifacts. Newer Flutter versions read FLUTTER_HOST_ARCH from the environment
# instead; this script backports that behaviour (Windows only) and rebuilds the
# tool snapshot so the SDK reports a windows-arm64 host.
#
# Requires FLUTTER_ROOT and FLUTTER_HOST_ARCH (arm64) in the environment.

$ErrorActionPreference = 'Stop'

if (-not $env:FLUTTER_ROOT) { throw 'FLUTTER_ROOT is not set' }

$OsDart = Join-Path $env:FLUTTER_ROOT 'packages\flutter_tools\lib\src\base\os.dart'
if (-not (Test-Path $OsDart)) { throw "not found: $OsDart" }

$Text = (Get-Content $OsDart -Raw) -replace "`r`n", "`n"

$Old = @'
  HostPlatform get hostPlatform {
    return switch (_currentAbi) {
'@

$New = @'
  HostPlatform get hostPlatform {
    if (_platform.isWindows) {
      switch (_platform.environment['FLUTTER_HOST_ARCH']) {
        case 'arm64':
          return HostPlatform.windows_arm64;
        case 'x64':
          return HostPlatform.windows_x64;
      }
    }
    return switch (_currentAbi) {
'@

if ($Text.Contains($New)) {
    Write-Host 'os.dart is already patched'
} else {
    if (-not $Text.Contains($Old)) {
        throw 'os.dart: hostPlatform getter not found (unsupported Flutter version)'
    }
    $Text = $Text.Replace($Old, $New)
    [System.IO.File]::WriteAllText($OsDart, $Text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'patched os.dart: hostPlatform honours FLUTTER_HOST_ARCH'
}

# Drop the prebuilt tool snapshot so the next `flutter` call rebuilds it from
# the patched sources (bin/internal/shared.bat does this automatically).
$Snapshot = Join-Path $env:FLUTTER_ROOT 'bin\cache\flutter_tools.snapshot'
$Stamp = Join-Path $env:FLUTTER_ROOT 'bin\cache\flutter_tools.stamp'
foreach ($File in @($Snapshot, $Stamp)) {
    if (Test-Path $File) {
        Remove-Item $File -Force
        Write-Host "removed $File"
    }
}

Write-Host 'rebuilding the flutter tool snapshot...'
flutter --version
if ($LASTEXITCODE -ne 0) { throw 'failed to rebuild the flutter tool snapshot' }

Write-Host 'flutter tool rebuilt with windows-arm64 host support'
