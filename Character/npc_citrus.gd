extends CharacterBody3D

enum State { WAITING_5s, WALKING_TO_RECEPTION, WAITING_FOR_PLAYER, SERVED, LEAVING }
var current_state: State = State.WAITING_5s

@export var speed: float = 2.5
const GRAVITY_MULTIPLIER = 4.0

# Target position in front of reception desk (guest side)
@export var reception_target_pos: Vector3 = Vector3(0.0, 0.25, 2.7)
# Exit target position after check-in
@export var exit_target_pos: Vector3 = Vector3(8.0, 0.25, 8.0)

# Timers
var initial_delay_timer: float = 5.0

# Animation constants
const ANIM_WALK = "Armature|preset_biped_walk"
const ANIM_IDLE = "Armature|preset_biped_wait"
var anim_player: AnimationPlayer = null
var anim_ready: bool = false

@onready var citrus_model = $Citruswalk if has_node("Citruswalk") else ($Player1 if has_node("Player1") else null)

func _ready():
	add_to_group("interactable")
	add_to_group("npc")
	_setup_animation()

func _setup_animation():
	if citrus_model:
		anim_player = citrus_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not anim_player:
		return

	if anim_player.has_animation("Armature|Armature"):
		var anim_lib = anim_player.get_animation_library("")
		if anim_lib and anim_lib.has_animation("Armature|Armature"):
			anim_lib.remove_animation("Armature|Armature")

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
	_play_anim(ANIM_IDLE)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += (get_gravity() * GRAVITY_MULTIPLIER) * delta

	match current_state:
		State.WAITING_5s:
			_process_waiting_5s(delta)
		State.WALKING_TO_RECEPTION:
			_process_walking(delta, reception_target_pos)
		State.WAITING_FOR_PLAYER:
			_process_waiting_for_player(delta)
		State.SERVED:
			_process_served(delta)
		State.LEAVING:
			_process_walking(delta, exit_target_pos)

	move_and_slide()

func _process_waiting_5s(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.z = move_toward(velocity.z, 0, speed)
	_play_anim(ANIM_IDLE)
	
	initial_delay_timer -= delta
	if initial_delay_timer <= 0.0:
		current_state = State.WALKING_TO_RECEPTION
		_show_feedback_message("Heading to Reception Desk...")
		get_tree().create_timer(2.0).timeout.connect(func():
			if current_state == State.WALKING_TO_RECEPTION and has_node("StatusLabel3D"):
				$StatusLabel3D.visible = false
		)

func _process_walking(delta: float, target: Vector3) -> void:
	var to_target = target - global_position
	to_target.y = 0.0

	if to_target.length() < 0.7:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		if current_state == State.WALKING_TO_RECEPTION:
			current_state = State.WAITING_FOR_PLAYER
			_show_feedback_message("🔔 Waiting at Reception [Press E]")
		elif current_state == State.LEAVING:
			queue_free()
		return

	var dir = to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	var target_rotation_y = atan2(dir.x, dir.z)
	rotation.y = rotate_toward(rotation.y, target_rotation_y, delta * 5.0)

	_play_anim(ANIM_WALK, 1.2)

func _process_waiting_for_player(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.z = move_toward(velocity.z, 0, speed)
	
	# Turn facing the reception counter (facing -Z towards desk)
	rotation.y = rotate_toward(rotation.y, PI, delta * 4.0)
	_play_anim(ANIM_IDLE)

func _process_served(_delta: float) -> void:
	_play_anim(ANIM_IDLE)

# Called when Player interacts with Npc_Citrus (presses E)
func interact(_player_node = null):
	if current_state == State.WAITING_FOR_PLAYER:
		print("Npc_Citrus interacted with!")
		current_state = State.SERVED
		
		# Show feedback message
		_show_feedback_message("Thank you! Checked in! 😊")
		
		# Wait 1.8 seconds then start walking away
		get_tree().create_timer(1.8).timeout.connect(func():
			_show_feedback_message("Goodbye!")
			current_state = State.LEAVING
		)

func get_interaction_prompt() -> String:
	if current_state == State.WAITING_FOR_PLAYER:
		return "Press [E] to Check-in Citrus"
	elif current_state == State.SERVED:
		return "Checking in Citrus..."
	return ""

func _show_feedback_message(msg: String):
	if has_node("StatusLabel3D"):
		$StatusLabel3D.text = msg
		$StatusLabel3D.visible = true


func _play_anim(anim_name: String, speed_scale: float = 1.0) -> void:
	if not anim_ready or not anim_player:
		return
	if not anim_player.has_animation(anim_name):
		return
	if anim_player.current_animation != anim_name:
		anim_player.play(anim_name, 0.25)
	anim_player.speed_scale = speed_scale
