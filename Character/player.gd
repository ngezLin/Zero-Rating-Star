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
@onready var body_mesh: Node3D = $BodyMesh
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
@onready var checklist_label: Label = $InteractionPromptLayer/ChecklistLabel
@onready var wallet_label: Label = $InteractionPromptLayer/WalletLabel
@onready var mop_tool: Node3D = $BodyMesh/RightShoulder/RightHand/MopTool
@onready var hotbar_container: HBoxContainer = $InteractionPromptLayer/HotbarPanel/HBoxContainer
@onready var alert_banner: Control = get_node_or_null("InteractionPromptLayer/AlertBanner")
@onready var alert_label: Label = get_node_or_null("InteractionPromptLayer/AlertBanner/AlertLabel")
@onready var pause_menu: Control = get_node_or_null("InteractionPromptLayer/PauseMenu")

var alert_tween: Tween = null

@onready var default_capsule_height: float = collision_shape.shape.height
@onready var default_body_mesh_height: float = 1.8 # Standard capsule mesh height

var was_on_floor = true
var zoom_level = 0.0
var is_aiming = false
var trajectory_dots = []
var wallet_cash: int = 0
var active_slot_index: int = 0

var highlight_material: StandardMaterial3D
var hovered_mesh: MeshInstance3D = null
var current_hold_target: Node = null
var is_pushing_cart: bool = false
var pushed_cart: Node = null

var carried_object: RigidBody3D = null
var original_parent: Node = null

# Camera FOV constants
const BASE_FOV = 75.0
const SPRINT_FOV = 85.0

@onready var flashlight_light: SpotLight3D = get_node_or_null("BodyMesh/RightShoulder/RightHand/FlashlightLight")

enum CameraMode { THIRD_PERSON, FIRST_PERSON, FRONT_VIEW }
var current_camera_mode = CameraMode.THIRD_PERSON
var vertical_look = 0.0

func _enter_tree() -> void:
	# Node name is set to str(peer_id) by main.gd _spawn_player
	var n = str(name)
	if n.is_valid_int():
		set_multiplayer_authority(n.to_int())
		print("[Player] _enter_tree: name=", n, " authority set to ", n.to_int())

func _ready() -> void:
	var n = str(name)
	if n.is_valid_int():
		set_multiplayer_authority(n.to_int())

	print("[Player] _ready: name=", name, " authority=", get_multiplayer_authority(), " my_peer=", multiplayer.get_unique_id(), " is_authority=", is_multiplayer_authority())

	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# Use a short timer to guarantee the camera activates after the tree is stable
		var timer = get_tree().create_timer(0.1)
		timer.timeout.connect(_activate_my_camera)
	else:
		if camera:
			camera.current = false
		var ui = get_node_or_null("InteractionPromptLayer")
		if ui:
			ui.visible = false
		var sprint_ui = get_node_or_null("SprintLinesLayer")
		if sprint_ui:
			sprint_ui.visible = false

# --- RPC Position/Rotation Sync ---
@rpc("any_peer", "call_remote", "unreliable")
func _sync_state(pos: Vector3, rot: Vector3, head_rot: Vector3, anim_name: String, anim_speed: float) -> void:
	# Applied on non-authority peers to update this player's visual position
	global_position = pos
	rotation = rot
	if head:
		head.rotation = head_rot
	# Play the synced animation on the remote player's model
	var cm = body_mesh.get_node_or_null("CitrusModel") if body_mesh else null
	if cm:
		var ap = cm.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			if anim_name != "" and (ap.current_animation != anim_name or not ap.is_playing()):
				if ap.has_animation(anim_name):
					ap.play(anim_name, 0.25)
					ap.speed_scale = anim_speed
			elif anim_name == "" and ap.is_playing():
				ap.stop()

func _activate_my_camera() -> void:
	if camera:
		camera.current = true
		camera.make_current()
		print("[Player] Camera ACTIVATED for peer: ", multiplayer.get_unique_id())

	# Exclude the player's own collision body from the interaction raycast query
	interaction_ray.add_exception(self)
	
	# Set interaction raycast range to 4.5 meters for easy cleaning/interacting
	interaction_ray.target_position = Vector3(0, 0, -4.5)
	interaction_ray.collision_mask = 0xFFFFFFFF
	
	_add_key_to_action("jump", KEY_SPACE)
	_add_key_to_action("ui_accept", KEY_SPACE)
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
	
	_add_key_to_action("slot_1", KEY_1)
	_add_key_to_action("slot_2", KEY_2)
	_add_key_to_action("slot_3", KEY_3)
	_add_key_to_action("slot_4", KEY_4)
	_add_key_to_action("slot_5", KEY_5)
	_add_key_to_action("slot_6", KEY_6)
	
	_add_mouse_to_action("zoom_in", MOUSE_BUTTON_WHEEL_UP)
	_add_mouse_to_action("zoom_out", MOUSE_BUTTON_WHEEL_DOWN)
	_add_mouse_to_action("throw", MOUSE_BUTTON_LEFT)
	
	# PlayStation Controller Joypad Mappings
	_add_joy_button_to_action("jump", JOY_BUTTON_A) # Cross (X)
	_add_joy_button_to_action("ui_accept", JOY_BUTTON_A) # Cross (X)
	_add_joy_button_to_action("interact", JOY_BUTTON_X) # Square (□) for doors/interactions!
	_add_joy_button_to_action("toggle_perspective", JOY_BUTTON_LEFT_SHOULDER) # L1 for FPS/TPS toggle!
	_add_joy_axis_to_action("crouch", JOY_AXIS_TRIGGER_LEFT, 0.5) # L2 Trigger for crouching!
	_add_joy_button_to_action("crouch", JOY_BUTTON_B) # Circle (O)
	_add_joy_button_to_action("ui_cancel", JOY_BUTTON_START) # Options Button
	_add_joy_button_to_action("toggle_flashlight", JOY_BUTTON_Y) # Triangle (Δ)
	_add_joy_button_to_action("sprint", JOY_BUTTON_LEFT_STICK) # L3 Click
	_add_joy_button_to_action("throw", JOY_BUTTON_RIGHT_SHOULDER) # R1
	
	# Initialize highlight material
	highlight_material = StandardMaterial3D.new()
	highlight_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.albedo_color = Color(1.0, 1.0, 1.0, 0.25)
	highlight_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	
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
		
	# Hide checklist and inventory hotbar panel by default
	if checklist_label:
		checklist_label.visible = false
	var hotbar_panel = get_node_or_null("InteractionPromptLayer/HotbarPanel")
	if hotbar_panel:
		hotbar_panel.visible = false
		
	_setup_pause_menu()

func show_alert(message: String, duration: float = 3.5) -> void:
	if alert_banner and alert_label:
		alert_label.text = message
		alert_banner.visible = true
		alert_banner.modulate.a = 1.0
		
		if alert_tween and alert_tween.is_running():
			alert_tween.kill()
			
		alert_tween = create_tween()
		alert_tween.tween_interval(duration)
		alert_tween.tween_property(alert_banner, "modulate:a", 0.0, 0.5)
		alert_tween.tween_callback(func(): alert_banner.visible = false)

func _add_key_to_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return
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

func _add_joy_button_to_action(action: String, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return
	var new_event = InputEventJoypadButton.new()
	new_event.button_index = button
	InputMap.action_add_event(action, new_event)

func _add_joy_axis_to_action(action: String, axis: JoyAxis, axis_value: float = 1.0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis:
			return
	var new_event = InputEventJoypadMotion.new()
	new_event.axis = axis
	new_event.axis_value = axis_value
	InputMap.action_add_event(action, new_event)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	# Handle mouse look movement (disabled while pushing cart — cart A/D steer drives camera)
	if event is InputEventMouseMotion and not is_pushing_cart:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		vertical_look -= event.relative.y * MOUSE_SENSITIVITY
		vertical_look = clamp(vertical_look, deg_to_rad(-89), deg_to_rad(89))
		
	# Press Escape to open Pause & Settings Menu
	if event.is_action_pressed("ui_cancel"):
		toggle_pause_menu()
			
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

func set_pushing_cart(pushing: bool, cart: Node = null) -> void:
	is_pushing_cart = pushing
	pushed_cart = cart

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if camera and not camera.current:
		camera.make_current()

	# While pushing cart, player body doesn't move independently (cart drives them)
	if is_pushing_cart:
		# Still need to run the rest of _physics_process for E key interaction!
		# Show the release prompt and handle E to stop pushing
		if Input.is_action_just_pressed("interact") and is_instance_valid(pushed_cart):
			pushed_cart.stop_pushing()
			return
		return

	# Handle Right Stick camera look for controllers (PlayStation DualShock/DualSense)
	var rs_x = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var rs_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	const JOY_DEADZONE = 0.15
	const JOY_LOOK_SPEED = 2.8
	if abs(rs_x) > JOY_DEADZONE or abs(rs_y) > JOY_DEADZONE:
		var look_x = rs_x if abs(rs_x) > JOY_DEADZONE else 0.0
		var look_y = rs_y if abs(rs_y) > JOY_DEADZONE else 0.0
		rotate_y(-look_x * JOY_LOOK_SPEED * delta)
		vertical_look -= look_y * JOY_LOOK_SPEED * delta
		vertical_look = clamp(vertical_look, deg_to_rad(-89), deg_to_rad(89))

	# Add the snappy gravity.
	if not is_on_floor():
		velocity += (get_gravity() * GRAVITY_MULTIPLIER) * delta

	was_on_floor = is_on_floor()

	# Handle jump (SPACE key).
	if (Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("ui_accept")) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Determine crouching and sneaking states (supports L2 trigger axis, Circle button, and C key)
	var is_crouching = (Input.is_action_pressed("crouch") or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.3) and is_on_floor()
	var is_sneaking = Input.is_action_pressed("sneak") and is_on_floor() and not is_crouching

	# Keep body mesh scale natural when full skeletal crouch animations are active
	var target_crouch_scale = 1.0
	body_mesh.scale = Vector3(1.0, target_crouch_scale, 1.0)

	# Lower head position when crouching for camera perspective
	var target_head_y = default_head_pos.y * 0.65 if is_crouching else default_head_pos.y
	head.position.y = lerp(head.position.y, target_head_y, delta * 10.0)

	# Adjust collision shape height
	collision_shape.shape.height = lerp(collision_shape.shape.height, 1.2 if is_crouching else 1.8, delta * 10.0)

	# Get the input direction relative to the player's current look angle
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Determine speed based on sneak, crouch, or carrying states
	var current_speed = WALK_SPEED
	if carried_object != null:
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
	
	if direction:
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

	# --- Hand & Foot Sway Animations (Only for procedural primitive block model) ---
	var citrus_model = body_mesh.get_node_or_null("CitrusModel")
	if citrus_model == null:
		if carried_object != null:
			if is_aiming:
				# --- AIMING TO THROW POSE ---
				left_shoulder.rotation.x = lerp_angle(left_shoulder.rotation.x, 1.4 + vertical_look, delta * 12.0)
				left_shoulder.rotation.y = lerp_angle(left_shoulder.rotation.y, -0.2, delta * 12.0)
				left_shoulder.rotation.z = lerp_angle(left_shoulder.rotation.z, -0.1, delta * 12.0)
				
				right_shoulder.rotation.x = lerp_angle(right_shoulder.rotation.x, 1.4 + vertical_look, delta * 12.0)
				right_shoulder.rotation.y = lerp_angle(right_shoulder.rotation.y, 0.2, delta * 12.0)
				right_shoulder.rotation.z = lerp_angle(right_shoulder.rotation.z, 0.1, delta * 12.0)
			else:
				# --- HOLDING BOX POSE ---
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
		# Reset procedural limbs so 3D Citrus skeleton handles all body poses cleanly
		if is_instance_valid(left_foot):
			left_foot.position = default_left_foot_pos
			left_foot.rotation = Vector3(deg_to_rad(-90), 0, 0)
		if is_instance_valid(right_foot):
			right_foot.position = default_right_foot_pos
			right_foot.rotation = Vector3(deg_to_rad(-90), 0, 0)
		if is_instance_valid(left_shoulder):
			left_shoulder.rotation = Vector3.ZERO
		if is_instance_valid(right_shoulder) and not flashlight_light.visible:
			right_shoulder.rotation = Vector3.ZERO

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
			
	spring_arm.spring_length = lerp(spring_arm.spring_length, target_spring_length, delta * 15.0)
	spring_arm.rotation.y = target_spring_yaw
	head.rotation.x = target_head_pitch
	
	# --- 3D Character Head Tilt (Look Up / Down with Camera) ---
	if citrus_model and current_camera_mode != CameraMode.FIRST_PERSON:
		var skel = citrus_model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel:
			var head_b = skel.find_bone("Head")
			if head_b != -1:
				var head_tilt = clamp(-vertical_look * 0.5, deg_to_rad(-45), deg_to_rad(45))
				var tilt_quat = Quaternion(Vector3(1, 0, 0), head_tilt)
				var rest_rot = skel.get_bone_rest(head_b).basis.get_rotation_quaternion()
				skel.set_bone_pose_rotation(head_b, rest_rot * tilt_quat)

	# Dynamically show/hide 3D Citrus model in first-person mode
	if current_camera_mode == CameraMode.FIRST_PERSON:
		camera.cull_mask = 1048573 # Hide layer 2 (eyes) to prevent clipping
		if citrus_model:
			citrus_model.visible = false
	else:
		camera.cull_mask = 1048575 # Show all layers (including eyes)
		if citrus_model:
			citrus_model.visible = true

	# --- Eye tracking (look at camera in Front View) ---
	if current_camera_mode == CameraMode.FRONT_VIEW and is_instance_valid(left_eye) and is_instance_valid(right_eye):
		var target_pos = camera.global_position
		left_eye.look_at(target_pos, Vector3.UP)
		right_eye.look_at(target_pos, Vector3.UP)
	elif is_instance_valid(left_eye) and is_instance_valid(right_eye):
		left_eye.rotation = Vector3.ZERO
		right_eye.rotation = Vector3.ZERO

	# --- Interaction & Crosshair Hover Highlight System ---
	var can_interact = false
	var current_hovered_mesh: MeshInstance3D = null
	var ray_target = null
	
	if carried_object == null and interaction_ray.is_colliding():
		var collider = interaction_ray.get_collider()
		if collider:
			if collider.is_in_group("pickable") or collider.is_in_group("loot") or collider.is_in_group("interactable") or collider.has_method("interact"):
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

	# Reset hold timer on previous target if user looks away
	if ray_target != current_hold_target:
		if is_instance_valid(current_hold_target) and current_hold_target.has_method("reset_hold"):
			current_hold_target.reset_hold()
		current_hold_target = ray_target

	# --- Pickup & Loot Interaction System ---
	if carried_object == null:
		prompt_label.visible = false
		if can_interact and ray_target:
			if ray_target.is_in_group("loot"):
				prompt_label.text = "Press [E] or [Square] to Steal Valuables ($150)"
				prompt_label.visible = true
				if Input.is_action_just_pressed("interact"):
					var amount = ray_target.collect_loot()
					if amount > 0:
						wallet_cash += amount
						wallet_label.text = "💰 Cash: $%d" % wallet_cash
						prompt_label.text = "Stolen Loot! +$%d" % amount
						prompt_label.visible = true
			elif ray_target.has_method("interact"):
				if ray_target.has_method("process_hold_interaction"):
					if Input.is_action_pressed("interact"):
						var finished = ray_target.process_hold_interaction(delta, self)
						if finished:
							prompt_label.visible = false
					else:
						if ray_target.has_method("reset_hold"):
							ray_target.reset_hold()
					
					if is_instance_valid(ray_target) and ray_target.has_method("get_interaction_prompt"):
						var prompt = ray_target.get_interaction_prompt()
						if prompt != "":
							prompt_label.text = prompt
							prompt_label.visible = true
				else:
					if ray_target.has_method("get_interaction_prompt"):
						var prompt = ray_target.get_interaction_prompt()
						if prompt != "":
							prompt_label.text = prompt
							prompt_label.visible = true
					else:
						prompt_label.text = "Press [E] to Interact"
						prompt_label.visible = true
					if Input.is_action_just_pressed("interact"):
						ray_target.interact(self)
					elif Input.is_action_just_pressed("crouch") and ray_target.has_method("deny_current_guest"):
						ray_target.deny_current_guest(self)
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
		# Allow interacting with targets (e.g. TrashBin) while carrying an object
		if can_interact and is_instance_valid(ray_target) and ray_target.has_method("interact"):
			if ray_target.has_method("get_interaction_prompt"):
				var prompt = ray_target.get_interaction_prompt()
				if prompt != "":
					prompt_label.text = prompt
					prompt_label.visible = true
			else:
				prompt_label.text = "Press [E] to Interact"
				prompt_label.visible = true
			
			if Input.is_action_just_pressed("interact"):
				ray_target.interact(self)
		# Otherwise drop carried object on floor if interact button (E) is pressed
		elif Input.is_action_just_pressed("interact"):
			is_aiming = false
			for dot in trajectory_dots:
				dot.visible = false
			
			var obj = carried_object
			carried_object = null
			
			if is_instance_valid(obj):
				obj.set_collision_layer_value(1, true)
				obj.set_collision_mask_value(1, true)
				if is_instance_valid(original_parent):
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

	# --- Update 3D Citrus Model Animations ---
	citrus_model = body_mesh.get_node_or_null("CitrusModel")
	if citrus_model:
		var anim_player = citrus_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim_player:
			if anim_player.has_animation("Armature|Armature"):
				var anim_lib = anim_player.get_animation_library("")
				if anim_lib and anim_lib.has_animation("Armature|Armature"):
					anim_lib.remove_animation("Armature|Armature")
			
			# Automatically import jump animations from res://Citrus.fbx if available
			if not anim_player.has_meta("fbx_imported"):
				anim_player.set_meta("fbx_imported", true)
				var fbx_path = "res://models/characters/Citrus.fbx"
				if ResourceLoader.exists(fbx_path):
					var fbx_scene = load(fbx_path).instantiate()
					if fbx_scene:
						var fbx_ap = fbx_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
						if fbx_ap:
							var default_lib = anim_player.get_animation_library("")
							if not default_lib:
								default_lib = AnimationLibrary.new()
								anim_player.add_animation_library("", default_lib)
							for anim_name in fbx_ap.get_animation_list():
								if anim_name == "RESET":
									continue
								var fbx_anim = fbx_ap.get_animation(anim_name)
								if fbx_anim:
									default_lib.add_animation("fbx_jump", fbx_anim.duplicate())
									default_lib.add_animation(anim_name, fbx_anim.duplicate())
						fbx_scene.queue_free()
			
			# Automatically import crouch animations from Crouching Idle.fbx and Crouched Walking.fbx
			if not anim_player.has_meta("crouch_imported"):
				anim_player.set_meta("crouch_imported", true)
				
				# Get exact Skeleton3D node path prefix from CitrusModel walk animation (e.g. "Armature/Skeleton3D:")
				var target_prefix = "Armature/Skeleton3D:"
				if anim_player.has_animation("Armature|preset_biped_walk"):
					var sample_anim = anim_player.get_animation("Armature|preset_biped_walk")
					if sample_anim and sample_anim.get_track_count() > 0:
						var sample_p = str(sample_anim.track_get_path(0))
						if ":" in sample_p:
							target_prefix = sample_p.split(":")[0] + ":"

				var crouch_files = {
					"crouch_idle": "res://Crouching Idle.fbx",
					"crouch_walk": "res://Crouched Walking.fbx"
				}
				var default_lib = anim_player.get_animation_library("")
				if not default_lib:
					default_lib = AnimationLibrary.new()
					anim_player.add_animation_library("", default_lib)

				for key in crouch_files.keys():
					var file_path = crouch_files[key]
					if ResourceLoader.exists(file_path):
						var scene_inst = load(file_path).instantiate()
						if scene_inst:
							var fbx_ap = scene_inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
							if fbx_ap:
								for anim_name in fbx_ap.get_animation_list():
									if anim_name == "RESET":
										continue
									var anim_obj = fbx_ap.get_animation(anim_name)
									if anim_obj:
										var anim_dup = anim_obj.duplicate()
										
										# Strip ParentNode container tracks and map bone tracks to target_prefix
										for track_idx in range(anim_dup.get_track_count() - 1, -1, -1):
											var track_path_str = str(anim_dup.track_get_path(track_idx))
											if ":" in track_path_str:
												var bone_name = track_path_str.split(":")[1]
												var new_path = NodePath(target_prefix + bone_name)
												anim_dup.track_set_path(track_idx, new_path)
											else:
												# Remove non-bone scene parent tracks
												anim_dup.remove_track(track_idx)

										default_lib.add_animation(key, anim_dup)
										print("[Player] Successfully imported & mapped ", key, " with target prefix: ", target_prefix)
										break
							scene_inst.queue_free()

			var walk_anim = ""
			var idle_anim = ""
			var jump_anim = ""
			
			for anim_name in anim_player.get_animation_list():
				var lower = anim_name.to_lower()
				if "jump" in lower or anim_name == "fbx_jump":
					jump_anim = anim_name
				elif lower == "walk" or "walk" in lower:
					walk_anim = anim_name
				elif lower == "idle" or "wait" in lower or "idle" in lower:
					idle_anim = anim_name
			
			if walk_anim == "":
				walk_anim = "Walk" if anim_player.has_animation("Walk") else "Armature|preset_biped_walk"
			if idle_anim == "":
				idle_anim = "Idle" if anim_player.has_animation("Idle") else "Armature|preset_biped_wait"
			
			var horizontal_speed = Vector2(velocity.x, velocity.z).length()
			var anim_to_play = ""
			
			if not is_on_floor():
				if jump_anim != "":
					anim_to_play = jump_anim
				elif anim_player.has_animation(walk_anim):
					anim_to_play = walk_anim
			elif is_crouching:
				if horizontal_speed > 0.3 and anim_player.has_animation("crouch_walk"):
					anim_to_play = "crouch_walk"
				elif anim_player.has_animation("crouch_idle"):
					anim_to_play = "crouch_idle"
				elif horizontal_speed > 0.3 and anim_player.has_animation(walk_anim):
					anim_to_play = walk_anim
				elif anim_player.has_animation(idle_anim):
					anim_to_play = idle_anim
			elif horizontal_speed > 0.3:
				if anim_player.has_animation(walk_anim):
					anim_to_play = walk_anim
			else:
				if anim_player.has_animation(idle_anim):
					anim_to_play = idle_anim
			
			if anim_to_play != "":
				var anim = anim_player.get_animation(anim_to_play)
				if anim and anim_to_play != jump_anim and anim.loop_mode != Animation.LOOP_LINEAR:
					var anim_lib = anim_player.get_animation_library("")
					if anim_lib:
						anim = anim.duplicate()
						anim.loop_mode = Animation.LOOP_LINEAR
						anim_lib.add_animation(anim_to_play, anim)

				if anim_player.current_animation != anim_to_play or not anim_player.is_playing():
					anim_player.play(anim_to_play, 0.15 if anim_to_play == jump_anim else 0.2)
				
				if anim_to_play == walk_anim:
					anim_player.speed_scale = clamp(horizontal_speed / 6.0, 0.6, 1.8)
				elif anim_to_play == "crouch_walk":
					anim_player.speed_scale = clamp(horizontal_speed / 2.2, 0.6, 1.5)
				else:
					anim_player.speed_scale = 1.0

				# Keep model orientation clean
				citrus_model.rotation_degrees.x = lerp(citrus_model.rotation_degrees.x, 0.0, delta * 15.0)
			else:
				if anim_player.is_playing():
					anim_player.stop()
				citrus_model.rotation_degrees.x = lerp(citrus_model.rotation_degrees.x, 0.0, delta * 15.0)

	move_and_slide()
	
	# Broadcast our position/rotation + animation to all other peers
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		var cur_anim = ""
		var cur_speed = 1.0
		var cm = body_mesh.get_node_or_null("CitrusModel") if body_mesh else null
		if cm:
			var ap = cm.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap and ap.is_playing():
				cur_anim = ap.current_animation
				cur_speed = ap.speed_scale
		rpc("_sync_state", global_position, rotation, head.rotation, cur_anim, cur_speed)

func _fix_citrus_model_mesh_gaps(node: Node) -> void:
	if not node:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			for surface_idx in range(child.get_surface_override_material_count()):
				var mat = child.get_surface_override_material(surface_idx)
				if not mat and child.mesh:
					mat = child.mesh.surface_get_material(surface_idx)
				if mat and mat is StandardMaterial3D:
					var dup_mat = mat.duplicate() as StandardMaterial3D
					dup_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					child.set_surface_override_material(surface_idx, dup_mat)
			if child.mesh:
				for i in range(child.mesh.get_surface_count()):
					if not child.get_surface_override_material(i):
						var orig_mat = child.mesh.surface_get_material(i)
						if orig_mat and orig_mat is StandardMaterial3D:
							var dup_mat = orig_mat.duplicate() as StandardMaterial3D
							dup_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
							child.set_surface_override_material(i, dup_mat)
		_fix_citrus_model_mesh_gaps(child)

func _setup_pause_menu() -> void:
	if not pause_menu:
		return
	pause_menu.visible = false
	var resume_btn = pause_menu.get_node_or_null("%ResumeButton")
	var fullscreen_btn = pause_menu.get_node_or_null("%FullscreenButton")
	var invite_btn = pause_menu.get_node_or_null("%InviteButton")
	var menu_btn = pause_menu.get_node_or_null("%MainMenuButton")
	var quit_btn = pause_menu.get_node_or_null("%QuitButton")
	
	if resume_btn:
		resume_btn.pressed.connect(toggle_pause_menu)
	if fullscreen_btn:
		fullscreen_btn.pressed.connect(func(): GameManager.toggle_fullscreen())
	if invite_btn:
		invite_btn.pressed.connect(_on_invite_friends_pressed)
	if menu_btn:
		menu_btn.pressed.connect(_on_exit_to_main_menu_pressed)
	if quit_btn:
		quit_btn.pressed.connect(func(): get_tree().quit())

func toggle_pause_menu() -> void:
	if not pause_menu:
		return
	pause_menu.visible = not pause_menu.visible
	if pause_menu.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
		var status_lbl = pause_menu.get_node_or_null("%PauseStatusLabel")
		if status_lbl:
			var code = NetworkManager.get_lobby_code()
			status_lbl.text = "Lobby Code: " + code
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_invite_friends_pressed() -> void:
	var code = NetworkManager.get_lobby_code()
	var invite_info = "Join my Zero-Star Rating shift! Lobby Code: " + code
	DisplayServer.clipboard_set(code)
	var status_lbl = pause_menu.get_node_or_null("%PauseStatusLabel")
	if status_lbl:
		status_lbl.text = "Copied 6-Digit Lobby Code to clipboard:\n" + code

func _on_exit_to_main_menu_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
