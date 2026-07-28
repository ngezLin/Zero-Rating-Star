extends CharacterBody3D

enum State { WANDERING, TALKING }
var current_state: State = State.WANDERING

# Movement configuration
const SPEED = 3.5
const GRAVITY_MULTIPLIER = 4.0
const WANDER_MIN_X = -10.0
const WANDER_MAX_X = 10.0
const WANDER_MIN_Z = -15.0
const WANDER_MAX_Z = 4.0

# Animation constants
const BOB_FREQ = 2.4
var t_bob = 0.0

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var left_shoulder: Node3D = $BodyMesh/LeftShoulder
@onready var right_shoulder: Node3D = $BodyMesh/RightShoulder
@onready var left_foot: MeshInstance3D = $LeftFoot
@onready var right_foot: MeshInstance3D = $RightFoot
@onready var left_eye: MeshInstance3D = $BodyMesh/LeftEye
@onready var right_eye: MeshInstance3D = $BodyMesh/RightEye

@onready var default_left_foot_pos: Vector3 = left_foot.position
@onready var default_right_foot_pos: Vector3 = right_foot.position

# NPC state variables
var wander_target: Vector3 = Vector3.ZERO
var talking_partner: CharacterBody3D = null
var talking_timer: float = 0.0
var talk_cooldown: float = 0.0

func _ready() -> void:
	# Initialize first wander target
	_choose_new_wander_target()
	# Stagger the talk cooldowns initially
	talk_cooldown = randf_range(0.0, 5.0)

func _physics_process(delta: float) -> void:
	# Snappy physics gravity
	if not is_on_floor():
		velocity += (get_gravity() * GRAVITY_MULTIPLIER) * delta

	# Process State Machine
	match current_state:
		State.WANDERING:
			_process_wandering(delta)
		State.TALKING:
			_process_talking(delta)

	move_and_slide()

func _process_wandering(delta: float) -> void:
	# Decrement talk cooldown
	if talk_cooldown > 0.0:
		talk_cooldown -= delta

	# Move toward wander target
	var to_target = wander_target - global_position
	to_target.y = 0.0 # Ignore height differences for direction calculation
	
	if to_target.length() < 1.0:
		_choose_new_wander_target()
		return

	var dir = to_target.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED

	# Rotate smoothly towards movement direction
	var target_rotation_y = atan2(-dir.x, -dir.z)
	rotation.y = rotate_toward(rotation.y, target_rotation_y, delta * 5.0)

	# --- Wandering Walk Animations ---
	t_bob += delta * velocity.length()
	
	# Rotate shoulders to swing arms back and forth
	var sway_amp = 0.4
	var left_sway = sin(t_bob * BOB_FREQ * 0.5) * sway_amp
	var right_sway = -left_sway
	
	left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, left_sway, delta * 8.0)
	right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, right_sway, delta * 8.0)
	
	left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.15 - abs(left_sway * 0.2), delta * 8.0)
	right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.15 + abs(right_sway * 0.2), delta * 8.0)
	
	left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, left_sway * 0.3, delta * 8.0)
	right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, right_sway * 0.3, delta * 8.0)

	# Step feet
	var step_amp_y = 0.08
	var step_amp_z = 0.15
	
	var left_foot_swing = sin(t_bob * BOB_FREQ * 0.5) * step_amp_z
	var right_foot_swing = -left_foot_swing
	
	left_foot.position.z = default_left_foot_pos.z + left_foot_swing
	right_foot.position.z = default_right_foot_pos.z + right_foot_swing
	
	var left_lift = max(0.0, cos(t_bob * BOB_FREQ * 0.5)) * step_amp_y
	var right_lift = max(0.0, -cos(t_bob * BOB_FREQ * 0.5)) * step_amp_y
	
	left_foot.position.y = default_left_foot_pos.y + left_lift
	right_foot.position.y = default_right_foot_pos.y + right_lift
	
	left_foot.rotation.x = deg_to_rad(-90) + (left_foot_swing * 0.4)
	right_foot.rotation.x = deg_to_rad(-90) + (right_foot_swing * 0.4)

	# Check for nearby NPCs to start talking
	if talk_cooldown <= 0.0:
		for other in get_tree().get_nodes_in_group("npc"):
			if other != self and other.current_state == State.WANDERING and other.talk_cooldown <= 0.0:
				var dist = global_position.distance_to(other.global_position)
				if dist < 2.8:
					# Start talking!
					_start_talking_with(other)
					other._start_talking_with(self)
					break

func _process_talking(delta: float) -> void:
	# Stop movement
	velocity.x = move_toward(velocity.x, 0, SPEED)
	velocity.z = move_toward(velocity.z, 0, SPEED)

	# Return feet to idle positions
	left_foot.position = left_foot.position.lerp(default_left_foot_pos, delta * 8.0)
	right_foot.position = right_foot.position.lerp(default_right_foot_pos, delta * 8.0)
	left_foot.rotation = left_foot.rotation.lerp(Vector3(-PI/2, 0, 0), delta * 8.0)
	right_foot.rotation = right_foot.rotation.lerp(Vector3(-PI/2, 0, 0), delta * 8.0)

	# Face partner
	if is_instance_valid(talking_partner):
		var to_partner = talking_partner.global_position - global_position
		to_partner.y = 0.0
		if to_partner.length() > 0.1:
			var target_rot = atan2(-to_partner.x, -to_partner.z)
			rotation.y = rotate_toward(rotation.y, target_rot, delta * 5.0)

	# Mimic talking timer
	talking_timer -= delta
	if talking_timer <= 0.0:
		_stop_talking()
		return

	# --- Conversational Gesturing Hand Animations ---
	var t_talk = (Time.get_ticks_msec() / 1000.0) * 8.0
	
	# Left arm gestures up/down/inward
	var left_gesture_x = 0.8 + sin(t_talk) * 0.4
	var left_gesture_y = -0.3 + cos(t_talk * 0.8) * 0.2
	var left_gesture_z = -0.4 + sin(t_talk * 1.1) * 0.3
	
	left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, left_gesture_x, delta * 10.0)
	left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, left_gesture_y, delta * 10.0)
	left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, left_gesture_z, delta * 10.0)

	# Right arm gestures up/down/inward out-of-phase
	var right_gesture_x = 0.8 + cos(t_talk * 0.95) * 0.4
	var right_gesture_y = 0.3 + sin(t_talk * 0.75) * 0.2
	var right_gesture_z = 0.4 + cos(t_talk * 1.05) * 0.3

	right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, right_gesture_x, delta * 10.0)
	right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, right_gesture_y, delta * 10.0)
	right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, right_gesture_z, delta * 10.0)

	# Squint eyelids randomly to look like they are talking animatedly
	var squint_val = abs(sin(t_talk * 0.3)) * 0.5
	var left_mat = left_eye.get_surface_override_material(0)
	if left_mat:
		left_mat.set_shader_parameter("squint", squint_val)
	var right_mat = right_eye.get_surface_override_material(0)
	if right_mat:
		right_mat.set_shader_parameter("squint", squint_val)

func _choose_new_wander_target() -> void:
	wander_target = Vector3(
		randf_range(WANDER_MIN_X, WANDER_MAX_X),
		global_position.y,
		randf_range(WANDER_MIN_Z, WANDER_MAX_Z)
	)

func _start_talking_with(partner: CharacterBody3D) -> void:
	current_state = State.TALKING
	talking_partner = partner
	talking_timer = 10.0

func _stop_talking() -> void:
	current_state = State.WANDERING
	talking_partner = null
	talk_cooldown = 10.0 # Walk away for 10 seconds before talking again
	_choose_new_wander_target()
	
	# Reset squint/eyelids
	var left_mat = left_eye.get_surface_override_material(0)
	if left_mat:
		left_mat.set_shader_parameter("squint", 0.0)
	var right_mat = right_eye.get_surface_override_material(0)
	if right_mat:
		right_mat.set_shader_parameter("squint", 0.0)
