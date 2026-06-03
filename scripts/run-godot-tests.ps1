# Runs Empire of Minds Godot headless tests. Non-zero exit if any test fails.
# Usage (from repo root):
#   .\scripts\run-godot-tests.ps1              # full suite (default)
#   .\scripts\run-godot-tests.ps1 full
#   .\scripts\run-godot-tests.ps1 smoke
#   .\scripts\run-godot-tests.ps1 cloud
#   .\scripts\run-godot-tests.ps1 presentation
#   .\scripts\run-godot-tests.ps1 slice c13a
#   .\scripts\run-godot-tests.ps1 slice c14a
# Profile policy: docs/TESTING.md (T2 — prefer slice for focused slices; full only when requested/deploy).
# Requires: GODOT_EXE, Godot on PATH, or install at the known path below.

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$GamePath = Join-Path $RepoRoot "game"

$KnownGodotPath = "C:\Users\nicla\tools\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"

$Script:SupportedSlices = @("c13a", "c14a", "c14c")

$Script:SliceTests = @{
	"c13a" = @(
		"res://cloud/tests/test_cloud_seat_token.gd"
	)
	"c14a" = @(
		"res://cloud/tests/test_cloud_credential_store.gd"
	)
	"c14c" = @(
		"res://cloud/tests/test_cloud_lobby_parsers.gd"
		"res://cloud/tests/test_cloud_front_door_boot_intent.gd"
		"res://cloud/tests/test_main_cloud_boot_intent_reconnect.gd"
		"res://cloud/tests/test_cloud_match_labels.gd"
		"res://cloud/tests/test_cloud_display_name.gd"
		"res://cloud/tests/test_cloud_saved_row_rename.gd"
		"res://cloud/tests/test_cloud_front_door_data_flow.gd"
		"res://cloud/tests/test_cloud_lobby_server_scoped.gd"
		"res://cloud/tests/test_cloud_match_name_identity.gd"
	)
}

$Script:SmokeTests = @(
	"res://cloud/tests/test_cloud_client_payloads.gd"
	"res://cloud/tests/test_main_default_cloud_base_url.gd"
	"res://presentation/tests/test_main_tscn_map_layer_sibling_order.gd"
)

# Full regression order (unchanged from pre-profile runner).
$Script:AllTests = @(
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
	"res://domain/tests/test_dump_prototype_play_map_script_loads.gd",
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
	"res://presentation/tests/test_map_visibility_boundary_feather.gd",
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
	"res://presentation/tests/test_city_territory_main_wiring.gd",
	"res://cloud/tests/test_server_snapshot_adapter.gd",
	"res://cloud/tests/test_server_snapshot_adapter_visibility.gd",
	"res://cloud/tests/test_cloud_client_payloads.gd",
	"res://cloud/tests/test_cloud_seat_token.gd",
	"res://cloud/tests/test_cloud_credential_store.gd",
	"res://cloud/tests/test_cloud_lobby_parsers.gd",
	"res://cloud/tests/test_cloud_front_door_boot_intent.gd",
	"res://cloud/tests/test_cloud_match_labels.gd",
	"res://cloud/tests/test_cloud_display_name.gd",
	"res://cloud/tests/test_cloud_saved_row_rename.gd",
	"res://cloud/tests/test_cloud_front_door_data_flow.gd",
	"res://cloud/tests/test_cloud_routing_pick.gd",
	"res://cloud/tests/test_cloud_turn_banner.gd",
	"res://cloud/tests/test_cloud_combat_animation.gd",
	"res://cloud/tests/test_main_default_cloud_base_url.gd",
	"res://cloud/tests/test_main_cloud_boot_no_local_session_before_server.gd",
	"res://cloud/tests/test_main_cloud_reconnect_get_match.gd",
	"res://cloud/tests/test_main_cloud_boot_intent_reconnect.gd"
)

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

function Show-GodotTestUsage {
	Write-Host @"
Usage (from repo root):
  .\scripts\run-godot-tests.ps1 [profile] [slice_id]

Profiles:
  full          Run all headless tests (default when no args)
  smoke         Fast sanity: cloud payloads, cloud URL default, main scene wiring
  cloud         All tests under res://cloud/tests/
  presentation  All tests under res://presentation/tests/
  slice <id>    Focused slice tests (supported: $($Script:SupportedSlices -join ', '))
"@
}

function Resolve-GodotProfile {
	param([string[]]$Argv)

	if ($Argv.Count -eq 0) {
		return @{ Name = "full"; Tests = $Script:AllTests }
	}
	if ($Argv.Count -eq 1) {
		$name = $Argv[0].ToLowerInvariant()
		switch ($name) {
			"full" { return @{ Name = "full"; Tests = $Script:AllTests } }
			"smoke" { return @{ Name = "smoke"; Tests = $Script:SmokeTests } }
			"cloud" {
				$cloud = @($Script:AllTests | Where-Object { $_ -like "res://cloud/tests/*" })
				return @{ Name = "cloud"; Tests = $cloud }
			}
			"presentation" {
				$pres = @($Script:AllTests | Where-Object { $_ -like "res://presentation/tests/*" })
				return @{ Name = "presentation"; Tests = $pres }
			}
			"slice" {
				Write-Host "ERROR: slice profile requires a slice id (e.g. slice c13a)." -ForegroundColor Red
				Show-GodotTestUsage
				exit 2
			}
			default {
				Write-Host "ERROR: unknown profile '$($Argv[0])'." -ForegroundColor Red
				Show-GodotTestUsage
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
		return @{ Name = "slice"; SliceId = $id; Tests = $Script:SliceTests[$id] }
	}

	Write-Host "ERROR: invalid arguments." -ForegroundColor Red
	Show-GodotTestUsage
	exit 2
}

$resolved = Resolve-GodotProfile -Argv $args
if ($resolved.SliceId) {
	$profileLabel = "slice $($resolved.SliceId)"
} else {
	$profileLabel = $resolved.Name
}

$Tests = $resolved.Tests

if (-not (Test-Path -LiteralPath $GamePath)) {
	Write-Host "Game project folder not found: $GamePath" -ForegroundColor Red
	exit 2
}

$GodotExe = Get-GodotExecutable

Write-Host "=== Empire of Minds Godot tests - profile: $profileLabel ===" -ForegroundColor Cyan
Write-Host "Using Godot: $GodotExe"
Write-Host "Project path:  $GamePath"
Write-Host "Resolved tests ($($Tests.Count)):" -ForegroundColor DarkGray
foreach ($t in $Tests) {
	Write-Host "  $t"
}
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

Write-Host "All $($Tests.Count) headless tests passed (profile: $profileLabel)." -ForegroundColor Green
exit 0
