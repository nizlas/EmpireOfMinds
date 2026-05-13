# Phase 5.1.16f: keep **TileYieldOverlayView.visible** and **HudCanvas** **Yields** **CheckButton** in sync.
# Presentation-only; no domain state.
class_name YieldOverlayToggle
extends RefCounted


## Keyboard path: flip visibility and update the **CheckButton** without emitting **toggled**.
static func toggle_from_keyboard(overlay: Node2D, yields_check: CheckButton) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	var nv: bool = not overlay.visible
	overlay.visible = nv
	overlay.queue_redraw()
	if yields_check != null and is_instance_valid(yields_check):
		yields_check.set_pressed_no_signal(nv)


## **CheckButton** **toggled** handler: apply **pressed** to the map overlay (**button** state is already updated by Godot).
static func apply_from_button(overlay: Node2D, pressed: bool) -> void:
	if overlay == null or not is_instance_valid(overlay):
		return
	overlay.visible = pressed
	overlay.queue_redraw()
