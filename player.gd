extends CharacterBody3D

const WALK_SPEED = 8.0
const SNEAK_SPEED = 4.0
const CROUCH_SPEED = 2.5
const SPRINT_SPEED = 13.0
const JUMP_VELOCITY = 11.0
const GRAVITY_MULTIPLIER = 4.0   # Snappy, non-moon physics!
const MOUSE_SENSITIVITY = 0.002
const BODY_TILT_AMOUNT = 0.35    # Exposes body lean percentage (0.35 = 35% of looking pitch)

# Head bobbing constants
const BOB_FREQ = 2.4
const BOB_AMP = 0.08
var t_bob = 0.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var head: Node3D = $Head
@onready var spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var camera: Camera3D = $Head/SpringArm3D/Camera3D
@onready var left_shoulder: Node3D = $BodyMesh/LeftShoulder
@onready var right_shoulder: Node3D = $BodyMesh/RightShoulder
@onready var left_foot: MeshInstance3D = $LeftFoot
@onready var right_foot: MeshInstance3D = $RightFoot
@onready var left_eye: MeshInstance3D = $BodyMesh/LeftEye
@onready var right_eye: MeshInstance3D = $BodyMesh/RightEye
@onready var default_head_pos: Vector3 = head.position
@onready var default_left_foot_pos: Vector3 = left_foot.position
@onready var default_right_foot_pos: Vector3 = right_foot.position
@onready var sprint_lines: ColorRect = $SprintLinesLayer/SprintLines
@onready var interaction_ray: RayCast3D = $Head/SpringArm3D/Camera3D/InteractionRay
@onready var carry_pivot: Node3D = $CarryPivot
@onready var prompt_label: Label = $InteractionPromptLayer/PromptLabel
@onready var dot_crosshair: ColorRect = $InteractionPromptLayer/DotCrosshair
@onready var task_progress_bar: ProgressBar = $InteractionPromptLayer/TaskProgressBar
@onready var checklist_label: Label = $InteractionPromptLayer/ChecklistLabel
@onready var wallet_label: Label = $InteractionPromptLayer/WalletLabel
@onready var mop_tool: Node3D = $BodyMesh/RightShoulder/RightHand/MopTool
@onready var hotbar_container: HBoxContainer = $InteractionPromptLayer/HotbarPanel/HBoxContainer

@onready var default_capsule_height: float = collision_shape.shape.height
@onready var default_body_mesh_height: float = 1.8 # Standard capsule mesh height

var was_on_floor = true
var squash_stretch_y = 1.0
var zoom_level = 0.0
var is_aiming = false
var trajectory_dots = []
var wallet_cash: int = 0
var active_slot_index: int = 0

var is_tasking = false
var task_progress = 0.0
var highlight_material: StandardMaterial3D
var hovered_mesh: MeshInstance3D = null

var carried_object: RigidBody3D = null
var original_parent: Node = null

# Camera FOV constants
const BASE_FOV = 75.0
const SPRINT_FOV = 85.0

@onready var accessories: Node3D = $BodyMesh/Accessories
@onready var bellboy_hat: MeshInstance3D = $BodyMesh/Accessories/BellboyHat
@onready var cs_headset: Node3D = $BodyMesh/Accessories/CSHeadset
@onready var security_cap: Node3D = $BodyMesh/Accessories/SecurityCap
@onready var engineer_hat: Node3D = $BodyMesh/Accessories/EngineerHat
@onready var flashlight_light: SpotLight3D = $BodyMesh/RightShoulder/RightHand/FlashlightLight

enum Role { JANITOR, CUSTOMER_SERVICE, SECURITY, ENGINEER }
var current_role: Role = Role.JANITOR

enum CameraMode { THIRD_PERSON, FIRST_PERSON, FRONT_VIEW }
var current_camera_mode = CameraMode.THIRD_PERSON
var vertical_look = 0.0

func _ready() -> void:
	# Captures the mouse cursor inside the game window for looking around
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Exclude the player's own collision body from the interaction raycast query
	interaction_ray.add_exception(self)
	
	# Set interaction raycast range to 4.5 meters for easy cleaning/interacting
	interaction_ray.target_position = Vector3(0, 0, -4.5)
	
	# Dynamically map WASD, Shift, Ctrl, C, V, and 1-6 keys to actions
	_add_key_to_action("ui_left", KEY_A)
	_add_key_to_action("ui_right", KEY_D)
	_add_key_to_action("ui_up", KEY_W)
	_add_key_to_action("ui_down", KEY_S)
	_add_key_to_action("sprint", KEY_SHIFT)
	_add_key_to_action("sneak", KEY_CTRL)
	_add_key_to_action("crouch", KEY_C)
	_add_key_to_action("toggle_perspective", KEY_V)
	_add_key_to_action("interact", KEY_E)
	_add_key_to_action("toggle_flashlight", KEY_F)
	_add_key_to_action("task", KEY_R)
	
	_add_key_to_action("slot_1", KEY_1)
	_add_key_to_action("slot_2", KEY_2)
	_add_key_to_action("slot_3", KEY_3)
	_add_key_to_action("slot_4", KEY_4)
	_add_key_to_action("slot_5", KEY_5)
	_add_key_to_action("slot_6", KEY_6)
	
	_add_mouse_to_action("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_to_action("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse_to_action("throw", MOUSE_BUTTON_LEFT)
	
	# Initialize highlight material
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1.0, 1.0, 1.0, 0.25)
	highlight_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
	# Lock to Janitor role
	current_role = Role.JANITOR
	set_role(current_role)
	
	# Initialize hotbar selection
	_select_slot(0)
	
	# Create trajectory dots programmatically
	for i in range(15):
		var dot = MeshInstance3D.new()
		var s_mesh = SphereMesh.new()
		s_mesh.radius = 0.04
		s_mesh.height = 0.08
		dot.mesh = s_mesh
		var mat = StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
		dot.material_override = mat
		dot.visible = false
		get_parent().call_deferred("add_child", dot)
		trajectory_dots.append(dot)
		
	call_deferred("_connect_room_manager")

func _connect_room_manager() -> void:
	var rm = get_parent().find_child("RoomManager*", true, false)
	if rm:
		if rm.has_signal("tasks_updated"):
			rm.tasks_updated.connect(_on_room_tasks_updated)
		if rm.has_signal("room_ready"):
			rm.room_ready.connect(_on_room_ready)

func _on_room_tasks_updated(remaining: int) -> void:
	checklist_label.text = "🏨 Room 101: %d Tasks Remaining" % remaining

func _on_room_ready() -> void:
	checklist_label.text = "🏨 Room 101: READY FOR CHECK-IN ✅"

func _add_key_to_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)
	var new_event = InputEventKey.new()
	new_event.physical_keycode = keycode
	InputMap.action_add_event(action, new_event)

func _add_mouse_to_action(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button:
			return
	var new_event = InputEventMouseButton.new()
	new_event.button_index = button
	InputMap.action_add_event(action, new_event)

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse look movement
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		vertical_look -= event.relative.y * MOUSE_SENSITIVITY
		vertical_look = clamp(vertical_look, deg_to_rad(-89), deg_to_rad(89))
		
	# Press Escape to release/recapture the mouse cursor easily while testing
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			
	# Toggle perspective (TPS, FPS, Front View) when pressing V
	if event.is_action_pressed("toggle_perspective"):
		current_camera_mode = ((current_camera_mode + 1) % 3) as CameraMode

	# Handle scroll wheel zooming
	if event.is_action_pressed("zoom_in"):
		zoom_level = clamp(zoom_level + 0.15, 0.0, 1.0)
	if event.is_action_pressed("zoom_out"):
		zoom_level = clamp(zoom_level - 0.15, 0.0, 1.0)

	# Toggle Flashlight
	if event.is_action_pressed("toggle_flashlight"):
		flashlight_light.visible = not flashlight_light.visible

	# Hotbar Slot Switching (Keys 1-6)
	if event.is_action_pressed("slot_1"):
		_select_slot(0)
	elif event.is_action_pressed("slot_2"):
		_select_slot(1)
	elif event.is_action_pressed("slot_3"):
		_select_slot(2)
	elif event.is_action_pressed("slot_4"):
		_select_slot(3)
	elif event.is_action_pressed("slot_5"):
		_select_slot(4)
	elif event.is_action_pressed("slot_6"):
		_select_slot(5)

func _select_slot(index: int) -> void:
	active_slot_index = index
	
	# Update visual highlights on Hotbar UI labels
	if hotbar_container:
		var slot_nodes = hotbar_container.get_children()
		for i in range(slot_nodes.size()):
			if slot_nodes[i] is Label:
				if i == active_slot_index:
					slot_nodes[i].modulate = Color(0.3, 1.0, 0.4, 1.0) # Bright green active
				else:
					slot_nodes[i].modulate = Color(0.7, 0.7, 0.7, 0.8) # Dim inactive
					
	# Toggle Mop Tool visibility when Slot 2 (Mop) is selected!
	if mop_tool:
		mop_tool.visible = (active_slot_index == 1)

func _physics_process(delta: float) -> void:
	# Add the snappy gravity.
	if not is_on_floor():
		velocity += (get_gravity() * GRAVITY_MULTIPLIER) * delta

	# Landing squash detection
	if is_on_floor() and not was_on_floor:
		squash_stretch_y = 0.65  # Squash down
	was_on_floor = is_on_floor()

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		squash_stretch_y = 1.35  # Stretch up

	# Determine crouching and sneaking states
	var is_crouching = Input.is_action_pressed("crouch") and is_on_floor()
	var is_sneaking = Input.is_action_pressed("sneak") and is_on_floor() and not is_crouching

	# Smoothly return body mesh to its default scale (squash & stretch + crouch scaling)
	squash_stretch_y = lerp(squash_stretch_y, 1.0, delta * 8.0)
	var target_crouch_scale = 0.65 if is_crouching else 1.0
	body_mesh.scale.y = squash_stretch_y * target_crouch_scale
	body_mesh.scale.x = (1.0 / sqrt(squash_stretch_y)) * (1.0 / sqrt(target_crouch_scale))
	body_mesh.scale.z = (1.0 / sqrt(squash_stretch_y)) * (1.0 / sqrt(target_crouch_scale))

	# Lower head position when crouching
	var target_head_y = default_head_pos.y * 0.55 if is_crouching else default_head_pos.y
	head.position.y = lerp(head.position.y, target_head_y, delta * 10.0)

	# Adjust collision shape height
	collision_shape.shape.height = lerp(collision_shape.shape.height, 1.2 if is_crouching else 1.8, delta * 10.0)

	# Get the input direction relative to the player's current look angle
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Determine speed based on sneak, crouch, carrying, or tasking states
	var current_speed = WALK_SPEED
	if is_tasking:
		current_speed = 0.0
	elif carried_object != null:
		current_speed = 5.0 # Slow down due to item weight
		if is_crouching:
			current_speed = 2.0
		elif is_sneaking:
			current_speed = 3.2
	else:
		if is_crouching:
			current_speed = CROUCH_SPEED
		elif is_sneaking:
			current_speed = SNEAK_SPEED
	
	if direction and not is_tasking:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)

	# --- Body Leaning (Velocity & Pitch) & Head Tilt ---
	var local_vel = global_transform.basis.inverse() * velocity
	var lean_factor = 0.015 # Normal lean
	if is_crouching:
		lean_factor = 0.008 # Dampen lean when crouching
	var body_target_pitch = (vertical_look * BODY_TILT_AMOUNT) + (local_vel.z * lean_factor)
	if carried_object != null:
		body_target_pitch -= 0.12 # Lean backward to simulate weight strain
	var body_target_roll = -local_vel.x * 0.025
	
	body_mesh.rotation.x = lerp_angle(body_mesh.rotation.x, body_target_pitch, delta * 10.0)
	body_mesh.rotation.z = lerp_angle(body_mesh.rotation.z, body_target_roll, delta * 10.0)

	# Update CarryPivot to follow body mesh rotation/position without inheriting its squash & stretch scale
	var unscaled_basis = body_mesh.global_transform.basis.orthonormalized()
	carry_pivot.global_position = body_mesh.global_position + (unscaled_basis * Vector3(0, 0, -0.95))
	carry_pivot.global_rotation = unscaled_basis.get_euler()

	# --- Head Bobbing logic ---
	var horizontal_velocity = Vector3(velocity.x, 0, velocity.z)
	var is_running = Input.is_action_pressed("sprint") and is_on_floor() and direction.length() > 0.1 and not is_crouching and not is_sneaking and carried_object == null
	
	# Neck pivot calculation: offset the head slightly forward/down when looking down
	var neck_pivot = default_head_pos - Vector3(0, 0.15, -0.08)
	var neck_offset = Vector3(0, 0.15, -0.08)
	var rotated_neck_offset = neck_offset.rotated(Vector3.RIGHT, head.rotation.x)
	var base_head_pos = neck_pivot + rotated_neck_offset
	
	if is_on_floor() and horizontal_velocity.length() > 0.1:
		t_bob += delta * horizontal_velocity.length()
		var new_head_pos = base_head_pos
		new_head_pos.y += sin(t_bob * BOB_FREQ) * BOB_AMP
		new_head_pos.x += cos(t_bob * BOB_FREQ / 2.0) * BOB_AMP * 0.5
		head.position = head.position.lerp(new_head_pos, delta * 10.0)
	else:
		head.position = head.position.lerp(base_head_pos, delta * 10.0)

	# --- Hand & Foot Sway Animations ---
	# 1. Arm/Shoulder Pose/Swing Animation
	if is_tasking:
		# --- SWEEPING/FIXING TASK GESTURE ---
		var t_task = (Time.get_ticks_msec() / 1000.0) * 8.0
		var sway_x = sin(t_task) * 0.3
		var sway_y = cos(t_task) * 0.4
		
		left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, 1.0 + sway_x, delta * 12.0)
		left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, -0.3 + sway_y, delta * 12.0)
		left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.2, delta * 12.0)
		
		right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, 1.0 - sway_x, delta * 12.0)
		right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, 0.3 - sway_y, delta * 12.0)
		right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.2, delta * 12.0)
	elif carried_object != null:
		if is_aiming:
			# --- AIMING TO THROW POSE ---
			# Point both arms straight forward to aim the throw
			left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, 1.4 + vertical_look, delta * 12.0)
			left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, -0.2, delta * 12.0)
			left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.1, delta * 12.0)
			
			right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, 1.4 + vertical_look, delta * 12.0)
			right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, 0.2, delta * 12.0)
			right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.1, delta * 12.0)
		else:
			# --- HOLDING BOX POSE ---
			# Rotate shoulders forward and inward to hug/hold the box in front of the chest
			var t_carry = (Time.get_ticks_msec() / 1000.0) * 3.0
			var carry_bob = sin(t_carry) * 0.05
			
			left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, 1.2 + carry_bob, delta * 12.0)
			left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, -0.5, delta * 12.0)
			left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.6, delta * 12.0)
			
			right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, 1.2 + carry_bob, delta * 12.0)
			right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, 0.5, delta * 12.0)
			right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.6, delta * 12.0)
	else:
		# --- NORMAL HAND ANIMATIONS (Walk / Sprint / Idle) ---
		if is_on_floor() and horizontal_velocity.length() > 0.1:
			if is_running:
				# --- NARUTO RUN ARMS ---
				var t_run = (Time.get_ticks_msec() / 1000.0) * 15.0
				var flutter = sin(t_run) * 0.04
				left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, -1.85 + flutter, delta * 12.0)
				left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, 0.1, delta * 12.0)
				left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.15, delta * 12.0)
				
				if not flashlight_light.visible:
					right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, -1.85 - flutter, delta * 12.0)
					right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, -0.1, delta * 12.0)
					right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.15, delta * 12.0)
			else:
				# --- WALK ARMS ---
				var sway_amp = 0.2 if is_crouching else (0.3 if is_sneaking else 0.4)
				var left_sway = sin(t_bob * BOB_FREQ * 0.5) * sway_amp
				var right_sway = -left_sway
				left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, left_sway, delta * 8.0)
				left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.15 - abs(left_sway * 0.2), delta * 8.0)
				left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, left_sway * 0.3, delta * 8.0)
				
				if not flashlight_light.visible:
					right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, right_sway, delta * 8.0)
					right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.15 + abs(right_sway * 0.2), delta * 8.0)
					right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, right_sway * 0.3, delta * 8.0)
		else:
			# --- IDLE ARMS ---
			left_shoulder.rotation = left_shoulder.rotation.lerp(Vector3.ZERO, delta * 8.0)
			if not flashlight_light.visible:
				right_shoulder.rotation = right_shoulder.rotation.lerp(Vector3.ZERO, delta * 8.0)
				
		# --- FLASHLIGHT HOLDING POSE (Overrides right arm if active) ---
		if flashlight_light.visible and not is_aiming:
			right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, 1.5 + vertical_look, delta * 12.0)
			right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, 0.0, delta * 12.0)
			right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.0, delta * 12.0)

	# 2. Foot/Shoe Animation
	if is_on_floor() and horizontal_velocity.length() > 0.1:
		var step_amp_y = 0.04 if is_crouching else (0.06 if is_sneaking else 0.08)
		var step_amp_z = 0.08 if is_crouching else (0.12 if is_sneaking else 0.15)
		var angle_mult = 0.2 if is_crouching else (0.3 if is_sneaking else 0.4)
		
		var left_foot_swing = sin(t_bob * BOB_FREQ * 0.5) * step_amp_z
		var right_foot_swing = -left_foot_swing
		
		left_foot.position.z = default_left_foot_pos.z + left_foot_swing
		right_foot.position.z = default_right_foot_pos.z + right_foot_swing
		
		var left_lift = max(0.0, cos(t_bob * BOB_FREQ * 0.5)) * step_amp_y
		var right_lift = max(0.0, -cos(t_bob * BOB_FREQ * 0.5)) * step_amp_y
		
		left_foot.position.y = default_left_foot_pos.y + left_lift
		right_foot.position.y = default_right_foot_pos.y + right_lift
		
		left_foot.rotation.x = deg_to_rad(-90) + (left_foot_swing * angle_mult)
		right_foot.rotation.x = deg_to_rad(-90) + (right_foot_swing * angle_mult)
	else:
		left_foot.position = left_foot.position.lerp(default_left_foot_pos, delta * 8.0)
		right_foot.position = right_foot.position.lerp(default_right_foot_pos, delta * 8.0)
		left_foot.rotation = left_foot.rotation.lerp(Vector3(-PI/2, 0, 0), delta * 8.0)
		right_foot.rotation = right_foot.rotation.lerp(Vector3(-PI/2, 0, 0), delta * 8.0)

	# --- Sprint Camera & Screen Effect logic ---
	var target_intensity = 1.0 if is_running else 0.0
	var current_intensity = sprint_lines.material.get_shader_parameter("sprint_intensity")
	sprint_lines.material.set_shader_parameter("sprint_intensity", lerp(current_intensity, target_intensity, delta * 10.0))
	
	# Apply camera zoom (decreasing FOV) when zoom_level > 0
	var base_target_fov = lerp(BASE_FOV, 35.0, zoom_level)
	var target_fov = SPRINT_FOV if is_running else base_target_fov
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)

	# --- Eye Squinting (Shader parameter uniform) ---
	var left_mat = left_eye.get_surface_override_material(0)
	if left_mat:
		var current_squint = left_mat.get_shader_parameter("squint")
		left_mat.set_shader_parameter("squint", lerp(current_squint, zoom_level, delta * 10.0))
	var right_mat = right_eye.get_surface_override_material(0)
	if right_mat:
		var current_squint = right_mat.get_shader_parameter("squint")
		right_mat.set_shader_parameter("squint", lerp(current_squint, zoom_level, delta * 10.0))

	# --- Perspective (Isometric/First/Third/Front View) logic ---
	var target_spring_length = 0.0
	var target_spring_yaw = 0.0
	var target_head_pitch = vertical_look
	
	match current_camera_mode:
		CameraMode.FIRST_PERSON:
			target_spring_length = 0.0
			target_spring_yaw = 0.0
		CameraMode.THIRD_PERSON:
			target_spring_length = 2.5
			target_spring_yaw = 0.0
		CameraMode.FRONT_VIEW:
			target_spring_length = 2.5
			target_spring_yaw = PI
			
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_spring_length, delta * 10.0)
	spring_arm.rotation.y = lerp_angle(spring_arm.rotation.y, target_spring_yaw, delta * 8.0)
	head.rotation.x = lerp(head.rotation.x, target_head_pitch, delta * 15.0)
	
	# Dynamically show/hide the player's eyes and uniform accessories depending on perspective
	if current_camera_mode == CameraMode.FIRST_PERSON:
		camera.cull_mask = 1048573 # Hide layer 2 (eyes) to prevent clipping
		accessories.visible = false
	else:
		camera.cull_mask = 1048575 # Show all layers (including eyes)
		accessories.visible = true

	# --- Eye tracking (look at camera in Front View) ---
	if current_camera_mode == CameraMode.FRONT_VIEW:
		var target_pos = camera.global_position
		left_eye.look_at(target_pos, Vector3.UP)
		right_eye.look_at(target_pos, Vector3.UP)
	else:
		left_eye.rotation = Vector3.ZERO
		right_eye.rotation = Vector3.ZERO

	# --- Interaction & Crosshair Hover Highlight System ---
	var can_interact = false
	var current_hovered_mesh: MeshInstance3D = null
	var ray_target = null
	
	if carried_object == null and interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()
		if collider:
			if collider.is_in_group("pickable") or collider.is_in_group("bed_task") or collider.is_in_group("stain") or collider.is_in_group("loot"):
				can_interact = true
				ray_target = collider
				current_hovered_mesh = collider.get_node_or_null("MeshInstance3D")

	# Manage object highlight white glow overlay
	if current_hovered_mesh != hovered_mesh:
		if is_instance_valid(hovered_mesh):
			hovered_mesh.material_overlay = null
		hovered_mesh = current_hovered_mesh
		if is_instance_valid(hovered_mesh):
			hovered_mesh.material_overlay = highlight_material

	# Crosshair Feedback: scale and change color when hovering over interactables
	if can_interact:
		dot_crosshair.color = Color(0.2, 0.9, 0.3, 0.95) # Vibrant feedback green
		dot_crosshair.scale = Vector2(1.5, 1.5)
		dot_crosshair.pivot_offset = Vector2(3, 3)
	else:
		dot_crosshair.color = Color(1.0, 1.0, 1.0, 0.5) # Soft translucent white
		dot_crosshair.scale = Vector2(1.0, 1.0)
		dot_crosshair.pivot_offset = Vector2(3, 3)

	# --- Pickup, Task & Loot Interaction System ---
	if carried_object == null:
		prompt_label.visible = false
		if can_interact and ray_target:
			if ray_target.is_in_group("bed_task") and not ray_target.is_tidied:
				prompt_label.text = "Press [E] or Hold [R] to Tidy Bed"
				prompt_label.visible = true
				if Input.is_action_pressed("task") or Input.is_action_pressed("interact"):
					is_tasking = true
					ray_target.tidy(delta * 0.75)
					task_progress_bar.value = ray_target.tidy_progress * 100.0
					task_progress_bar.visible = true
			elif ray_target.is_in_group("stain"):
				prompt_label.text = "Press [E] or Hold [R] to Wipe Stain"
				prompt_label.visible = true
				if Input.is_action_pressed("task") or Input.is_action_pressed("interact"):
					is_tasking = true
					ray_target.clean(delta * 0.75)
					task_progress_bar.value = ray_target.clean_progress * 100.0
					task_progress_bar.visible = true
			elif ray_target.is_in_group("loot"):
				prompt_label.text = "Press [E] to Steal Valuables ($150)"
				prompt_label.visible = true
				if Input.is_action_just_pressed("interact"):
					var amount = ray_target.collect_loot()
					if amount > 0:
						wallet_cash += amount
						wallet_label.text = "💰 Cash: $%d" % wallet_cash
						prompt_label.text = "Stolen Loot! +$%d" % amount
						prompt_label.visible = true
			elif ray_target.is_in_group("pickable"):
				prompt_label.text = "Press [E] to Pick Up Trash"
				prompt_label.visible = true
				
				if Input.is_action_just_pressed("interact"):
					carried_object = ray_target
					original_parent = carried_object.get_parent()
					
					# Remove targeted hover glow upon pickup
					if is_instance_valid(hovered_mesh):
						hovered_mesh.material_overlay = null
					hovered_mesh = null
					
					# Reparent to carry pivot
					carried_object.reparent(carry_pivot)
					carried_object.position = Vector3.ZERO
					carried_object.rotation = Vector3.ZERO
					carried_object.scale = Vector3.ONE
					carried_object.freeze = true
					
					# Disable collision with player
					carried_object.set_collision_layer_value(1, false)
					carried_object.set_collision_mask_value(1, false)
	else:
		# Cancel Aiming/Drop if interact button (E) is pressed
		if Input.is_action_just_pressed("interact"):
			is_aiming = false
			for dot in trajectory_dots:
				dot.visible = false
			
			var obj = carried_object
			carried_object = null
			
			obj.set_collision_layer_value(1, true)
			obj.set_collision_mask_value(1, true)
			obj.reparent(original_parent)
			obj.scale = Vector3.ONE
			obj.freeze = false
		
		# Aiming Mode (Hold Left Click)
		elif Input.is_action_pressed("throw"):
			is_aiming = true
			
			# Predict and draw projectile trajectory arc
			var p0 = carry_pivot.global_position
			var throw_dir = -camera.global_transform.basis.z
			var v0 = throw_dir * 18.0
			var g_accel = Vector3(0, -9.8, 0)
			
			for i in range(15):
				var t = i * 0.07 # Time steps
				var pos = p0 + v0 * t + 0.5 * g_accel * t * t
				trajectory_dots[i].global_position = pos
				trajectory_dots[i].visible = true
				
		# Release to Throw
		elif is_aiming and Input.is_action_just_released("throw"):
			is_aiming = false
			for dot in trajectory_dots:
				dot.visible = false
				
			var obj = carried_object
			carried_object = null
			
			obj.set_collision_layer_value(1, true)
			obj.set_collision_mask_value(1, true)
			obj.reparent(original_parent)
			obj.scale = Vector3.ONE
			obj.freeze = false
			
			# Apply impulse
			var throw_dir = -camera.global_transform.basis.z
			obj.apply_central_impulse(throw_dir * 18.0)
			
		else:
			# Hide dots if not aiming
			for dot in trajectory_dots:
				dot.visible = false
	
	# Fallback safety: hide dots if not carrying
	if carried_object == null:
		is_aiming = false
		for dot in trajectory_dots:
			dot.visible = false

	# --- Interactive Tasking System (Hold R) ---
	if Input.is_action_pressed("task") and carried_object == null:
		is_tasking = true
		task_progress = min(task_progress + delta * 33.3, 100.0) # 3 seconds to complete
		task_progress_bar.value = task_progress
		task_progress_bar.visible = true
		
		prompt_label.text = "Task in Progress... %d%%" % int(task_progress)
		prompt_label.visible = true
		
		if task_progress >= 100.0:
			prompt_label.text = "Task Completed!"
			prompt_label.visible = true
	else:
		if is_tasking:
			task_progress_bar.visible = false
			prompt_label.visible = false
			is_tasking = false
			task_progress = 0.0

	move_and_slide()

func set_role(role: Role) -> void:
	current_role = role
	bellboy_hat.visible = (role == Role.JANITOR)
	cs_headset.visible = (role == Role.CUSTOMER_SERVICE)
	security_cap.visible = (role == Role.SECURITY)
	engineer_hat.visible = (role == Role.ENGINEER)
