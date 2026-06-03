# Empire of Minds — server pytest runner with optional profiles.
# Usage (from repo root):
#   .\scripts\run-server-tests.ps1              # full suite (same as pytest -q in server/)
#   .\scripts\run-server-tests.ps1 full
#   .\scripts\run-server-tests.ps1 smoke
#   .\scripts\run-server-tests.ps1 cloud
#   .\scripts\run-server-tests.ps1 slice c13a
#   .\scripts\run-server-tests.ps1 presentation  # Godot-only; exits 0 with message
# Profile policy: docs/TESTING.md (T2 — prefer slice for focused slices; full only when requested/deploy).

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ServerDir = Join-Path $RepoRoot "server"

$Script:SupportedSlices = @("c13a", "c14b")

$Script:SliceTests = @{
	"c13a" = @(
		"tests/test_seats.py"
		"tests/test_seat_token_flow.py"
	)
	"c14b" = @(
		"tests/test_lobby_list.py"
		"tests/test_seat_claim.py"
		"tests/test_seats.py"
		"tests/test_display_name.py"
	)
}

$Script:SmokeTests = @(
	"tests/test_end_turn_flow.py"
	"tests/test_legal_actions_endpoint.py"
)

$Script:CloudTests = @(
	"tests/test_api_create_match_v2.py"
	"tests/test_move_unit_flow.py"
	"tests/test_end_turn_flow.py"
	"tests/test_found_city_flow.py"
	"tests/test_set_city_production_flow.py"
	"tests/test_attack_unit_flow.py"
	"tests/test_combat_rules.py"
	"tests/test_legal_actions_endpoint.py"
	"tests/test_production_tick_flow.py"
	"tests/test_food_growth_tick_flow.py"
	"tests/test_science_tick_flow.py"
	"tests/test_snapshot_v2.py"
	"tests/test_player_visibility.py"
	"tests/test_player_visibility_flow.py"
	"tests/test_seats.py"
	"tests/test_seat_token_flow.py"
	"tests/test_lobby_list.py"
	"tests/test_seat_claim.py"
)

function Show-ServerTestUsage {
	Write-Host @"
Usage (from repo root):
  .\scripts\run-server-tests.ps1 [profile] [slice_id]

Profiles:
  full          Run all server tests (default when no args)
  smoke         Fast sanity: health/create, legal-actions
  cloud         Cloud authority / API integration tests
  slice <id>    Focused slice tests (supported: $($Script:SupportedSlices -join ', '))
  presentation  Not supported on server (use run-godot-tests.ps1 presentation)
"@
}

function Resolve-ServerProfile {
	param([string[]]$Argv)

	if ($Argv.Count -eq 0) {
		return @{ Name = "full"; Paths = $null }
	}
	if ($Argv.Count -eq 1) {
		$name = $Argv[0].ToLowerInvariant()
		switch ($name) {
			"full" { return @{ Name = "full"; Paths = $null } }
			"smoke" { return @{ Name = "smoke"; Paths = $Script:SmokeTests } }
			"cloud" { return @{ Name = "cloud"; Paths = $Script:CloudTests } }
			"presentation" { return @{ Name = "presentation"; Paths = @() } }
			"slice" {
				Write-Host "ERROR: slice profile requires a slice id (e.g. slice c13a)." -ForegroundColor Red
				Show-ServerTestUsage
				exit 2
			}
			default {
				Write-Host "ERROR: unknown profile '$($Argv[0])'." -ForegroundColor Red
				Show-ServerTestUsage
				exit 2
			}
		}
	}
	if ($Argv.Count -eq 2 -and $Argv[0].ToLowerInvariant() -eq "slice") {
		$id = $Argv[1].ToLowerInvariant()
		if (-not $Script:SliceTests.ContainsKey($id)) {
			Write-Host "ERROR: unknown slice id '$id'. Supported: $($Script:SupportedSlices -join ', ')" -ForegroundColor Red
			exit 2
		}
		return @{ Name = "slice"; SliceId = $id; Paths = $Script:SliceTests[$id] }
	}

	Write-Host "ERROR: invalid arguments." -ForegroundColor Red
	Show-ServerTestUsage
	exit 2
}

if (-not (Test-Path -LiteralPath $ServerDir)) {
	Write-Host "Server folder not found: $ServerDir" -ForegroundColor Red
	exit 2
}

$resolved = Resolve-ServerProfile -Argv $args
$profileName = $resolved.Name
if ($resolved.SliceId) {
	$profileLabel = "slice $($resolved.SliceId)"
} else {
	$profileLabel = $profileName
}

Write-Host "=== Empire of Minds server tests - profile: $profileLabel ===" -ForegroundColor Cyan

if ($profileName -eq "presentation") {
	Write-Host "presentation profile is Godot-only. Use: .\scripts\run-godot-tests.ps1 presentation"
	exit 0
}

$pytest = Get-Command pytest -ErrorAction SilentlyContinue
if (-not $pytest) {
	Write-Host "ERROR: pytest not found on PATH. Install server deps: cd server; pip install -r requirements.txt" -ForegroundColor Red
	exit 2
}

Push-Location $ServerDir
try {
	if ($null -eq $resolved.Paths) {
		Write-Host "Running: pytest -q (all tests under tests/)" -ForegroundColor DarkGray
		& pytest -q
	} else {
		Write-Host "Resolved test files ($($resolved.Paths.Count)):" -ForegroundColor DarkGray
		foreach ($p in $resolved.Paths) {
			Write-Host "  $p"
		}
		& pytest -q $resolved.Paths
	}
	$code = $LASTEXITCODE
} finally {
	Pop-Location
}

if ($code -ne 0) {
	Write-Host ""
	Write-Host "Server tests FAILED (profile: $profileLabel, exit $code)" -ForegroundColor Red
	exit $code
}

Write-Host ""
Write-Host "Server tests passed (profile: $profileLabel)." -ForegroundColor Green
exit 0
