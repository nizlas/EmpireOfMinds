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
	"res://domain/tests/test_player_visibility_state.gd",
	"res://domain/tests/test_player_visibility_reveal.gd",
	"res://domain/tests/test_hex_map.gd",
	"res://domain/tests/test_hex_map_landform.gd",
	"res://domain/tests/test_hex_map_woods.gd",
	"res://domain/tests/test_city_yields.gd",
	"res://domain/tests/test_city_population.gd",
	"res://domain/tests/test_city_yields_worked_tiles.gd",
	"res://domain/tests/test_city_yields_breakdown.gd",
	"res://domain/tests/test_prototype_play_map_distribution.gd",
	"res://domain/tests/test_prototype_rectangular_water_shell.gd",
	"res://domain/tests/test_prototype_lightning_tree_hex.gd",
	"res://domain/tests/test_unit.gd",
	"res://domain/tests/test_unit_definitions.gd",
	"res://domain/tests/test_terrain_rule_definitions.gd",
	"res://domain/tests/test_city_project_definitions.gd",
	"res://domain/tests/test_progress_definitions.gd",
	"res://domain/tests/test_science_availability.gd",
	"res://domain/tests/test_faction_definitions.gd",
	"res://domain/tests/test_progress_state.gd",
	"res://domain/tests/test_progress_state_science_progress.gd",
	"res://domain/tests/test_progress_state_current_research.gd",
	"res://domain/tests/test_set_current_research.gd",
	"res://domain/tests/test_progress_unlock_resolver.gd",
	"res://domain/tests/test_game_state_progress_state.gd",
	"res://domain/tests/test_legal_actions_progress_gating.gd",
	"res://domain/tests/test_effective_rules.gd",
	"res://domain/tests/test_legal_actions_effective_rules.gd",
	"res://domain/tests/test_settler_unlock_flow.gd",
	"res://domain/tests/test_settler_production_flow.gd",
	"res://domain/tests/test_complete_progress.gd",
	"res://domain/tests/test_complete_progress_flow.gd",
	"res://domain/tests/test_progress_detector.gd",
	"res://domain/tests/test_progress_candidate_filter.gd",
	"res://domain/tests/test_lightning_tree_trigger.gd",
	"res://domain/tests/test_scenario.gd",
	"res://domain/tests/test_movement_rules.gd",
	"res://domain/tests/test_combat_rules.gd",
	"res://domain/tests/test_attack_unit.gd",
	"res://domain/tests/test_attack_unit_flow.gd",
	"res://domain/tests/test_move_unit.gd",
	"res://domain/tests/test_unit_movement_points_v0.gd",
	"res://domain/tests/test_move_unit_science_observation_bonus.gd",
	"res://domain/tests/test_move_unit_preserves_scenario_state.gd",
	"res://domain/tests/test_found_city.gd",
	"res://domain/tests/test_found_city_flow.gd",
	"res://domain/tests/test_set_city_production.gd",
	"res://domain/tests/test_set_city_production_flow.gd",
	"res://domain/tests/test_set_city_worked_tiles.gd",
	"res://domain/tests/test_production_tick.gd",
	"res://domain/tests/test_production_delivery.gd",
	"res://domain/tests/test_end_turn_production_flow.gd",
	"res://domain/tests/test_end_turn_growth_flow.gd",
	"res://domain/tests/test_growth_play_loop_smoke.gd",
	"res://domain/tests/test_end_turn_science_flow.gd",
	"res://domain/tests/test_science_tick.gd",
	"res://domain/tests/test_action_log.gd",
	"res://domain/tests/test_game_state.gd",
	"res://domain/tests/test_turn_state.gd",
	"res://domain/tests/test_end_turn.gd",
	"res://domain/tests/test_turn_flow.gd",
	"res://presentation/tests/test_map_view_draw.gd",
	"res://presentation/tests/test_prototype_forest_clusters.gd",
	"res://presentation/tests/test_prototype_woods_presentation_domain_agreement.gd",
	"res://presentation/tests/test_map_plane_projection.gd",
	"res://presentation/tests/test_map_camera.gd",
	"res://presentation/tests/test_units_view_draw.gd",
	"res://presentation/tests/test_unit_nameplate_view.gd",
	"res://presentation/tests/test_combat_clash_burst_view.gd",
	"res://presentation/tests/test_city_nameplate_view.gd",
	"res://presentation/tests/test_city_nameplate_shared_hex_banner.gd",
	"res://presentation/tests/test_city_nameplate_shared_hex_runtime_clearance.gd",
	"res://presentation/tests/test_selection_state.gd",
	"res://presentation/tests/test_selection_shared_hex_pick.gd",
	"res://presentation/tests/test_selection_post_move_unit.gd",
	"res://presentation/tests/test_city_production_panel.gd",
	"res://presentation/tests/test_city_production_panel_button_deferred.gd",
	"res://presentation/tests/test_main_hud_city_panel.gd",
	"res://presentation/tests/test_hotseat_endturn_selection_clear.gd",
	"res://presentation/tests/test_player_contact_strip.gd",
	"res://presentation/tests/test_playtest_player_display.gd",
	"res://presentation/tests/test_main_hud_discovery_popup.gd",
	"res://presentation/tests/test_main_hud_science_completed_popup.gd",
	"res://presentation/tests/test_main_hud_science_panel.gd",
	"res://presentation/tests/test_lightning_tree_view_draw.gd",
	"res://presentation/tests/test_discovery_action_panel.gd",
	"res://presentation/tests/test_discovery_action_panel_button_deferred.gd",
	"res://presentation/tests/test_main_hud_discovery_action_panel.gd",
	"res://presentation/tests/test_discovery_popup.gd",
	"res://presentation/tests/test_discovery_popup_run_engine_popups.gd",
	"res://presentation/tests/test_empire_border_view.gd",
	"res://presentation/tests/test_science_completed_popup.gd",
	"res://presentation/tests/test_science_panel.gd",
	"res://presentation/tests/test_science_panel_button.gd",
	"res://presentation/tests/test_selection_view_draw.gd",
	"res://presentation/tests/test_terrain_edge_blend_view.gd",
	"res://presentation/tests/test_turn_label.gd",
	"res://presentation/tests/test_turn_start_banner_view.gd",
	"res://presentation/tests/test_turn_status_panel.gd",
	"res://presentation/tests/test_turn_view_sync.gd",
	"res://presentation/tests/test_map_visibility_view.gd",
	"res://presentation/tests/test_presentation_visibility.gd",
	"res://presentation/tests/test_tile_yield_overlay_view_visibility.gd",
	"res://presentation/tests/test_lightning_tree_view_visibility.gd",
	"res://presentation/tests/test_terrain_foreground_view_visibility.gd",
	"res://presentation/tests/test_city_nameplate_view_visibility.gd",
	"res://presentation/tests/test_unit_nameplate_view_visibility.gd",
	"res://presentation/tests/test_faction_asset_paths.gd",
	"res://presentation/tests/test_faction_banner_gallery.gd",
	"res://domain/tests/test_legal_actions.gd",
	"res://ai/tests/test_rule_based_ai_player.gd",
	"res://ai/tests/test_rule_based_ai_policy.gd",
	"res://ai/tests/test_ai_turn_flow.gd",
	"res://ai/tests/test_core_loop_ai_smoke.gd",
	"res://presentation/tests/test_log_view.gd",
	"res://domain/tests/test_city.gd",
	"res://domain/tests/test_food_growth_tick.gd",
	"res://domain/tests/test_scenario_cities.gd",
	"res://domain/tests/test_scenario_city_territory.gd",
	"res://presentation/tests/test_cities_view_draw.gd",
	"res://presentation/tests/test_tfv_depth_merge_city_unit_sort_keys.gd",
	"res://presentation/tests/test_main_hud_yields_toggle.gd",
	"res://presentation/tests/test_main_tscn_map_layer_sibling_order.gd",
	"res://presentation/tests/test_city_view_state.gd",
	"res://presentation/tests/test_city_worked_tiles_view.gd",
	"res://presentation/tests/test_tile_yield_overlay_view.gd",
	"res://presentation/tests/test_city_territory_view.gd",
	"res://presentation/tests/test_city_territory_main_wiring.gd"
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
