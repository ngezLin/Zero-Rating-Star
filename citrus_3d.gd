extends CharacterBody3D

@export var speed := 2.0

var direction = Vector3.ZERO
var timer = 0.0

@onready var animation_player = $Citruswalk/AnimationPlayer

func _ready():
	randomize()
	_choose_direction()

func _physics_process(delta):
	timer -= delta

	if timer <= 0:
		_choose_direction()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)

	move_and_slide()

func _choose_direction():
	timer = randf_range(2.0, 5.0)

	var angle = randf() * TAU
	direction = Vector3(cos(angle), 0, sin(angle))

	if animation_player:
		if animation_player.has_animation("Armature|preset_biped_walk"):
			animation_player.play("Armature|preset_biped_walk")
