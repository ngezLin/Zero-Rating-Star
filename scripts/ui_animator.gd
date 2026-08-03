extends Node

# Autoload helper for smooth UI micro-animations and button styling

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

func setup_node_buttons(parent_node: Node) -> void:
	if not parent_node:
		return
	for child in parent_node.get_children():
		if child is Button:
			animate_button(child)
		setup_node_buttons(child)

func animate_button(btn: Button) -> void:
	if not btn or btn.has_meta("ui_animated"):
		return
	btn.set_meta("ui_animated", true)
	
	btn.pivot_offset = btn.size / 2.0
	btn.resized.connect(func():
		btn.pivot_offset = btn.size / 2.0
	)
	
	btn.mouse_entered.connect(func():
		var tween = btn.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.12)
	)
	
	btn.mouse_exited.connect(func():
		var tween = btn.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12)
	)
	
	btn.button_down.connect(func():
		var tween = btn.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.08)
	)
	
	btn.button_up.connect(func():
		var tween = btn.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.04, 1.04), 0.1)
	)
