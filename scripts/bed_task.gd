extends Area3D

signal bed_tidied

var is_tidied: bool = false
var tidy_progress: float = 0.0

@onready var mattress_mesh: MeshInstance3D = $MattressMesh
@onready var dust_particles: CPUParticles3D = $CPUParticles3D

var clean_mat: StandardMaterial3D

func _ready() -> void:
	clean_mat = StandardMaterial3D.new()
	clean_mat.albedo_color = Color(0.92, 0.92, 0.95)
	clean_mat.roughness = 0.7

func tidy(amount: float) -> void:
	if is_tidied:
		return
		
	tidy_progress += amount
	dust_particles.emitting = true
	
	if tidy_progress >= 1.0:
		is_tidied = true
		dust_particles.emitting = false
		
		# Snap mattress straight and apply clean white sheet material
		mattress_mesh.rotation.y = 0.0
		mattress_mesh.set_surface_override_material(0, clean_mat)
		emit_signal("bed_tidied")
