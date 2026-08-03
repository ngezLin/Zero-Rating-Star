extends Control

# Custom Radial Progress Ring drawn around the crosshair

var progress: float = 0.0

func set_progress(val: float) -> void:
	if abs(progress - val) > 0.001:
		progress = clamp(val, 0.0, 1.0)
		queue_redraw()

func _draw() -> void:
	if progress <= 0.0:
		return
	var center = size / 2.0
	var radius = 22.0
	var start_angle = -PI / 2.0
	var end_angle = start_angle + (progress * TAU)
	
	# Background dim guide ring
	draw_arc(center, radius, 0, TAU, 36, Color(0, 0, 0, 0.35), 3.0, true)
	# Glowing progress arc
	draw_arc(center, radius, start_angle, end_angle, 36, Color(1, 0.85, 0.25, 0.95), 3.5, true)
