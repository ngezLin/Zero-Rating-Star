extends StaticBody3D

## A dirty spot on the floor that players can clean by holding interact [E] for 2 seconds.

signal cleaned()

@export var spot_name: String = "Dirty Spot"
@export var hold_time_required: float = 2.0

var is_cleaned: bool = false
var current_hold_time: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 4 # Shift layer so player physics on layer 1 passes through smoothly without blocking!

func get_interaction_prompt() -> String:
	if is_cleaned:
		return ""
	if current_hold_time > 0.0:
		var pct = int((current_hold_time / hold_time_required) * 100)
		return "Cleaning %s... [%d%%]" % [spot_name, pct]
	return "Hold [E] to Clean " + spot_name

func process_hold_interaction(delta: float, player: Node = null) -> bool:
	if is_cleaned:
		return false
	current_hold_time += delta
	if current_hold_time >= hold_time_required:
		interact(player)
		return true
	return false

func reset_hold() -> void:
	current_hold_time = 0.0

func interact(player: Node = null) -> void:
	if is_cleaned:
		return
	is_cleaned = true
	cleaned.emit()

	if player and player.has_method("show_alert"):
		player.show_alert("🧹 Cleaned: " + spot_name, 2.0)

	# Fade out and remove
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.4)
	tween.tween_callback(queue_free)
