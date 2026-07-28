extends Node3D

signal cleaned

var clean_progress: float = 0.0
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var mat: StandardMaterial3D

func _ready() -> void:
	# Duplicate material to adjust alpha independently
	var base_mat = mesh_instance.get_surface_override_material(0)
	if base_mat:
		mat = base_mat.duplicate()
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.18, 0.1, 0.85)
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.set_surface_override_material(0, mat)

func clean(amount: float) -> void:
	clean_progress += amount
	if mat:
		mat.albedo_color.a = clamp(0.85 * (1.0 - clean_progress), 0.0, 0.85)
	
	if clean_progress >= 1.0:
		emit_signal("cleaned")
		queue_free()
