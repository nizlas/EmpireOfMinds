# Builds the Empire of Minds native GDExtension (native/) with MSVC + Ninja.
# Usage (from repo root, plain PowerShell — no VS developer shell needed):
#   .\scripts\build-native.ps1                        # Release (default)
#   .\scripts\build-native.ps1 windows-ninja-debug
# Output: native/build/<preset>/ plus deployed DLL + descriptor in game/bin/
# (both gitignored). See native/README.md.
param(
	[string]$Preset = "windows-ninja-release"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$NativeDir = Join-Path $RepoRoot "native"

foreach ($tool in @("cmake", "ninja")) {
	if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
		Write-Error "Required tool '$tool' not found on PATH."
	}
}

$VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $VsWhere)) {
	Write-Error "vswhere.exe not found; install Visual Studio with the C++ workload."
}
$VsPath = & $VsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $VsPath) {
	Write-Error "No Visual Studio installation with C++ (x86/x64) tools found."
}
$DevCmd = Join-Path $VsPath "Common7\Tools\VsDevCmd.bat"

# Configure + build inside an x64 MSVC developer environment so the Ninja
# generator finds cl.exe.
cmd /s /c "`"$DevCmd`" -arch=x64 -host_arch=x64 -no_logo && cd /d `"$NativeDir`" && cmake --preset $Preset && cmake --build --preset $Preset"
exit $LASTEXITCODE
