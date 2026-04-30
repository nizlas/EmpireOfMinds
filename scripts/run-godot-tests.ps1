# Runs all Empire of Minds Godot headless tests. Non-zero exit if any test fails.
# Usage (from repo root): .\scripts\run-godot-tests.ps1
# Requires: set GODOT_EXE, or Godot on PATH, or install at the known path below.

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$GamePath = Join-Path $RepoRoot "game"

$KnownGodotPath = "C:\Users\nicla\tools\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"

function Get-GodotExecutable {
	if ($env:GODOT_EXE -and $env:GODOT_EXE.Trim().Length -gt 0) {
		$p = $env:GODOT_EXE.Trim()
		if (Test-Path -LiteralPath $p) {
			return (Resolve-Path -LiteralPath $p).Path
		}
		Write-Host "GODOT_EXE is set but file not found: $p" -ForegroundColor Red
		exit 2
	}
	if (Test-Path -LiteralPath $KnownGodotPath) {
		return (Resolve-Path -LiteralPath $KnownGodotPath).Path
	}
	$cmd = Get-Command godot -ErrorAction SilentlyContinue
	if ($cmd -and $cmd.Source) {
		return $cmd.Source
	}
	Write-Host @"
ERROR: Godot executable not found.

Do one of the following:
  - Set environment variable GODOT_EXE to the full path of Godot (console build recommended for headless), or
  - Add Godot to your PATH as 'godot', or
  - Install or extract Godot to:
      $KnownGodotPath

Then run this script again.
"@ -ForegroundColor Red
	exit 2
}

$GodotExe = Get-GodotExecutable

$Tests = @(
	"res://domain/tests/test_hex_coord.gd",
	"res://domain/tests/test_hex_map.gd",
	"res://domain/tests/test_unit.gd",
	"res://domain/tests/test_unit_definitions.gd",
	"res://domain/tests/test_terrain_rule_definitions.gd",
	"res://domain/tests/test_city_project_definitions.gd",
	"res://domain/tests/test_progress_definitions.gd",
	"res://domain/tests/test_faction_definitions.gd",
	"res://domain/tests/test_progress_state.gd",
	"res://domain/tests/test_progress_unlock_resolver.gd",
	"res://domain/tests/test_game_state_progress_state.gd",
	"res://domain/tests/test_legal_actions_progress_gating.gd",
	"res://domain/tests/test_complete_progress.gd",
	"res://domain/tests/test_complete_progress_flow.gd",
	"res://domain/tests/test_progress_detector.gd",
	"res://domain/tests/test_progress_candidate_filter.gd",
	"res://domain/tests/test_scenario.gd",
	"res://domain/tests/test_movement_rules.gd",
	"res://domain/tests/test_move_unit.gd",
	"res://domain/tests/test_move_unit_preserves_scenario_state.gd",
	"res://domain/tests/test_found_city.gd",
	"res://domain/tests/test_found_city_flow.gd",
	"res://domain/tests/test_set_city_production.gd",
	"res://domain/tests/test_set_city_production_flow.gd",
	"res://domain/tests/test_production_tick.gd",
	"res://domain/tests/test_production_delivery.gd",
	"res://domain/tests/test_end_turn_production_flow.gd",
	"res://domain/tests/test_action_log.gd",
	"res://domain/tests/test_game_state.gd",
	"res://domain/tests/test_turn_state.gd",
	"res://domain/tests/test_end_turn.gd",
	"res://domain/tests/test_turn_flow.gd",
	"res://presentation/tests/test_map_view_draw.gd",
	"res://presentation/tests/test_units_view_draw.gd",
	"res://presentation/tests/test_selection_state.gd",
	"res://presentation/tests/test_selection_view_draw.gd",
	"res://presentation/tests/test_turn_label.gd",
	"res://presentation/tests/test_faction_asset_paths.gd",
	"res://presentation/tests/test_faction_banner_gallery.gd",
	"res://domain/tests/test_legal_actions.gd",
	"res://ai/tests/test_rule_based_ai_player.gd",
	"res://ai/tests/test_rule_based_ai_policy.gd",
	"res://ai/tests/test_ai_turn_flow.gd",
	"res://ai/tests/test_core_loop_ai_smoke.gd",
	"res://presentation/tests/test_log_view.gd",
	"res://domain/tests/test_city.gd",
	"res://domain/tests/test_scenario_cities.gd",
	"res://presentation/tests/test_cities_view_draw.gd"
)

if (-not (Test-Path -LiteralPath $GamePath)) {
	Write-Host "Game project folder not found: $GamePath" -ForegroundColor Red
	exit 2
}

Write-Host "Using Godot: $GodotExe"
Write-Host "Project path:  $GamePath"
Write-Host ""

foreach ($test in $Tests) {
	Write-Host "--- Running: $test ---"
	& $GodotExe --headless --path $GamePath -s $test
	if ($LASTEXITCODE -ne 0) {
		Write-Host ""
		Write-Host "FAILED: $test (exit code $LASTEXITCODE)" -ForegroundColor Red
		exit $LASTEXITCODE
	}
	Write-Host ""
}

Write-Host "All $($Tests.Count) headless tests passed." -ForegroundColor Green
exit 0
