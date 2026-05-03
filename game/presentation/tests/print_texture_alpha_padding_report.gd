# One-shot: print **[TextureAlphaMetrics]** paddings for unit + tree symbol PNGs.
# Usage: godot --headless --path game -s res://presentation/tests/print_texture_alpha_padding_report.gd
extends SceneTree

const TextureAlphaMetricsScript = preload("res://presentation/texture_alpha_metrics.gd")
const UnitsViewScript = preload("res://presentation/units_view.gd")


func _terrain_symbol_path(idx_1: int) -> String:
	return "res://assets/prototype/terrain/tree_symbols/tree_symbol_%02d.png" % idx_1


func _init() -> void:
	print(
		"TextureAlphaMetrics alpha_threshold=%d (opaque if alpha*255 > threshold)"
		% TextureAlphaMetricsScript.DEFAULT_ALPHA_THRESHOLD
	)
	var u_paths: PackedStringArray = PackedStringArray(
		[
			UnitsViewScript.marker_texture_res_path("settler"),
			UnitsViewScript.marker_texture_res_path("warrior"),
		]
	)
	var pi: int = 0
	while pi < u_paths.size():
		var p: String = u_paths[pi]
		if p.is_empty():
			pi += 1
			continue
		var mu: Dictionary = TextureAlphaMetricsScript.metrics_for_res_path(p)
		print("UNIT %s -> %s" % [p, str(mu)])
		pi += 1
	var tt: int = 1
	while tt <= 20:
		var tp: String = _terrain_symbol_path(tt)
		var mtd: Dictionary = TextureAlphaMetricsScript.metrics_for_res_path(tp)
		print(
			"TREE %s -> bottom_pad=%s ok=%s"
			% [tp, str(mtd.get("bottom_padding_px", "?")), str(mtd.get("ok", false))]
		)
		tt += 1
	call_deferred("quit", 0)
