# C14d-4a: front door / staging auto-refresh policy (no network; scenes own Timer wiring).
extends RefCounted

const StagingParsersScript = preload("res://cloud/cloud_staging_parsers.gd")


static func front_door_should_run_poll(
	poll_stopped: bool,
	lobby_fetch_in_flight: bool,
	ui_busy: bool,
) -> bool:
	return (not poll_stopped) and (not lobby_fetch_in_flight) and (not ui_busy)


static func front_door_should_begin_fetch(lobby_fetch_in_flight: bool) -> bool:
	return not lobby_fetch_in_flight


static func staging_should_run_poll(
	poll_stopped: bool,
	refresh_in_flight: bool,
	ui_busy: bool,
	match_status: String,
) -> bool:
	if poll_stopped or refresh_in_flight or ui_busy:
		return false
	return str(match_status).strip_edges() != StagingParsersScript.STATUS_ONGOING


static func staging_should_begin_refresh(refresh_in_flight: bool) -> bool:
	return not refresh_in_flight


static func staging_stop_poll_on_status(status: String) -> bool:
	return str(status).strip_edges() == StagingParsersScript.STATUS_ONGOING
