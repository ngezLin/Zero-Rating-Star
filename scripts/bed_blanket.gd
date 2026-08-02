extends StaticBody3D

## Messy Bed Blanket task synced across multiplayer peers via RPC.
## Requires holding [E] for 5 seconds to fix/clean.
## Emits a dust particle effect while the player is cleaning it.

signal cleaned()

@export var spot_name: String = "Messy Blanket"
@export var hold_time_required: float = 5.0

var is_cleaned: bool = false
var current_hold_time: float = 0.0

@onready var dust_particles: GPUParticles3D = $DustParticles
@onready var blanket_mesh: MeshInstance3D = $MeshInstance3D

# Clean white bedsheet material
var clean_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 4 # Shift layer so player doesn't collide physically

	# Initialize clean sheet material
	clean_material = StandardMaterial3D.new()
	clean_material.albedo_color = Color(0.95, 0.95, 0.93, 1.0)
	clean_material.roughness = 0.85

func get_interaction_prompt() -> String:
	if is_cleaned:
		return ""
	if current_hold_time > 0.0:
		var pct = int((current_hold_time / hold_time_required) * 100)
		return "Fixing %s... [%d%%]" % [spot_name, pct]
	return "Hold [E] to Fix " + spot_name

func process_hold_interaction(delta: float, player: Node = null) -> bool:
	if is_cleaned:
		return false

	current_hold_time += delta

	# Enable dust particle effect while cleaning
	if dust_particles and not dust_particles.emitting:
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_set_dust", true)
		else:
			_sync_set_dust(true)

	if current_hold_time >= hold_time_required:
		interact(player)
		return true
	return false

func reset_hold() -> void:
	current_hold_time = 0.0
	if dust_particles and dust_particles.emitting:
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_set_dust", false)
		else:
			_sync_set_dust(false)

func interact(player: Node = null) -> void:
	if is_cleaned:
		return

	if multiplayer.has_multiplayer_peer():
		rpc("_sync_clean")
	else:
		_sync_clean()

	if player and player.has_method("show_alert"):
		player.show_alert("✨ Fixed: " + spot_name + "! Bed made.", 2.5)

@rpc("any_peer", "call_local", "reliable")
func _sync_set_dust(emitting: bool) -> void:
	if dust_particles:
		dust_particles.emitting = emitting

@rpc("any_peer", "call_local", "reliable")
func _sync_clean() -> void:
	if is_cleaned:
		return
	is_cleaned = true

	if dust_particles:
		dust_particles.emitting = false

	# Change blanket visual to clean white sheet
	if blanket_mesh:
		blanket_mesh.material_override = clean_material

	cleaned.emit()
