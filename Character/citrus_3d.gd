extends CharacterBody3D

enum State { WANDERING, IDLE }
var current_state: State = State.WANDERING

# Movement configuration
@export var speed := 2.0
const GRAVITY_MULTIPLIER = 4.0
const WANDER_MIN_X = -25.0
const WANDER_MAX_X = 25.0
const WANDER_MIN_Z = -25.0
const WANDER_MAX_Z = 25.0

# Animation names
const ANIM_WALK = "Armature|preset_biped_walk"
const ANIM_IDLE = "Armature|preset_biped_wait"

# NPC state variables
var wander_target: Vector3 = Vector3.ZERO
var idle_timer: float = 0.0

# Animation
var anim_player: AnimationPlayer = null
var anim_ready: bool = false

@onready var citrus_model = $Player1 if has_node("Player1") else ($Citruswalk if has_node("Citruswalk") else null)

func _ready():
	randomize()
	_setup_animation()
	_choose_new_wander_target()

func _setup_animation():
	if citrus_model:
		anim_player = citrus_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim_player:
		return

	# Remove unwanted Armature|Armature static animation
	if anim_player.has_animation("Armature|Armature"):
		var anim_lib = anim_player.get_animation_library("")
		if anim_lib and anim_lib.has_animation("Armature|Armature"):
			anim_lib.remove_animation("Armature|Armature")

	# Set both walk and idle animations to loop
	for anim_name in [ANIM_WALK, ANIM_IDLE]:
		if anim_player.has_animation(anim_name):
			var anim = anim_player.get_animation(anim_name)
			if anim and anim.loop_mode != Animation.LOOP_LINEAR:
				var anim_lib = anim_player.get_animation_library("")
				if anim_lib:
					anim = anim.duplicate()
					anim.loop_mode = Animation.LOOP_LINEAR
					anim_lib.add_animation(anim_name, anim)

	anim_ready = true
	# Start with idle
	_play_anim(ANIM_IDLE)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity += (get_gravity() * GRAVITY_MULTIPLIER) * delta

	match current_state:
		State.WANDERING:
			_process_wandering(delta)
		State.IDLE:
			_process_idle(delta)

	# Wall avoidance — pick a new target
	if is_on_wall():
		_choose_new_wander_target()

	move_and_slide()

func _process_wandering(delta: float) -> void:
	var to_target = wander_target - global_position
	to_target.y = 0.0

	# Arrived at target — pause briefly
	if to_target.length() < 1.0:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		current_state = State.IDLE
		idle_timer = randf_range(1.5, 4.0)
		_play_anim(ANIM_IDLE)
		return

	# Move toward target
	var dir = to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	# Smooth rotation — model is 180° rotated so flip atan2 signs
	var target_rotation_y = atan2(dir.x, dir.z)
	rotation.y = rotate_toward(rotation.y, target_rotation_y, delta * 5.0)

	# Play walk animation
	_play_anim(ANIM_WALK, clamp(velocity.length() / 4.0, 0.9, 1.8))

func _process_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.z = move_toward(velocity.z, 0, speed)

	idle_timer -= delta
	if idle_timer <= 0.0:
		current_state = State.WANDERING
		_choose_new_wander_target()
		_play_anim(ANIM_WALK)

func _choose_new_wander_target() -> void:
	wander_target = Vector3(
		randf_range(WANDER_MIN_X, WANDER_MAX_X),
		global_position.y,
		randf_range(WANDER_MIN_Z, WANDER_MAX_Z)
	)

func _play_anim(anim_name: String, speed_scale: float = 1.0) -> void:
	if not anim_ready or not anim_player:
		return
	if not anim_player.has_animation(anim_name):
		return
	# Only call play() if we're switching to a different animation
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name)
	anim_player.speed_scale = speed_scale
