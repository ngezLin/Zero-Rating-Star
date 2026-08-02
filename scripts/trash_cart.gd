extends CharacterBody3D

## Mobile Driveable/Pushable Trash Cart synced across multiplayer peers via RPC.

signal item_disposed()

@export var drive_speed: float = 5.0
@export var turn_speed: float = 2.5
@export var max_storage_capacity: int = 20

var stored_items: Array[Node] = []
var collected_trash_count: int = 0

var pushing_player: Node = null
var is_being_pushed: bool = false

@onready var trash_container: Node3D = $TrashContainer
@onready var deposit_area: Area3D = $DepositArea

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("trash_cart")
	collision_layer = 1
	collision_mask = 1
	if deposit_area:
		deposit_area.body_entered.connect(_on_body_entered)

func get_interaction_prompt() -> String:
	if is_being_pushed:
		return "Press [E] to Release Trash Cart | WASD to Drive"
	
	return "Press [E] to Push & Drive Trash Cart (%d items)" % collected_trash_count

func interact(player: Node = null) -> void:
	if not player:
		return

	# If player is holding a trash item, deposit it
	if player.get("carried_object") != null:
		var item = player.carried_object
		if is_instance_valid(item) and (item.is_in_group("trash") or item.is_in_group("pickable")):
			player.carried_object = null
			var item_path = item.get_path()
			if multiplayer.has_multiplayer_peer():
				rpc("_sync_store_trash", item_path)
			else:
				_sync_store_trash(item_path)

			if player.has_method("show_alert"):
				player.show_alert("🛒 Trash Stored in Cart! (%d items)" % collected_trash_count, 1.8)
	else:
		# Toggle push/drive mode
		if is_being_pushed:
			stop_pushing()
		else:
			start_pushing(player)

func start_pushing(player: Node) -> void:
	if not is_instance_valid(player):
		return

	if multiplayer.has_multiplayer_peer():
		rpc("_sync_set_pushing_player", player.get_path())
	else:
		_sync_set_pushing_player(player.get_path())

	if player.has_method("show_alert"):
		player.show_alert("🛒 Driving Trash Cart! WASD to Push/Steer, [E] to Release", 3.0)

func stop_pushing() -> void:
	if multiplayer.has_multiplayer_peer():
		rpc("_sync_stop_pushing")
	else:
		_sync_stop_pushing()

@rpc("any_peer", "call_local", "reliable")
func _sync_set_pushing_player(player_path: NodePath) -> void:
	var p = get_node_or_null(player_path)
	if is_instance_valid(p):
		pushing_player = p
		is_being_pushed = true
		add_collision_exception_with(p)
		if p is PhysicsBody3D:
			p.add_collision_exception_with(self)
		if p.has_method("set_pushing_cart"):
			p.set_pushing_cart(true, self)

@rpc("any_peer", "call_local", "reliable")
func _sync_stop_pushing() -> void:
	if is_instance_valid(pushing_player):
		remove_collision_exception_with(pushing_player)
		if pushing_player is PhysicsBody3D:
			pushing_player.remove_collision_exception_with(self)
		if pushing_player.has_method("set_pushing_cart"):
			pushing_player.set_pushing_cart(false, null)
	pushing_player = null
	is_being_pushed = false
	velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	# Add gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	if is_being_pushed and is_instance_valid(pushing_player) and pushing_player.is_multiplayer_authority():
		# Drive controls using standard movement actions
		var input_dir = Vector2.ZERO
		if Input.is_action_pressed("move_forward"):
			input_dir.y -= 1.0
		if Input.is_action_pressed("move_back"):
			input_dir.y += 1.0
		if Input.is_action_pressed("move_left"):
			input_dir.x -= 1.0
		if Input.is_action_pressed("move_right"):
			input_dir.x += 1.0

		# Steering (left/right input rotates cart)
		if input_dir.x != 0.0:
			rotate_y(-input_dir.x * turn_speed * delta)

		# Forward/backward drive velocity along cart forward heading
		var drive_dir = -transform.basis.z * input_dir.y
		velocity.x = drive_dir.x * drive_speed
		velocity.z = drive_dir.z * drive_speed

		move_and_slide()

		# Position player right behind cart push handle facing forward
		var handle_pos = global_transform * Vector3(0, 0, -0.9)
		pushing_player.global_position = Vector3(handle_pos.x, pushing_player.global_position.y, handle_pos.z)
		pushing_player.rotation.y = rotation.y

		# Sync cart position across peers
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			rpc_id(0, "_sync_cart_transform", global_position, rotation)
	else:
		move_and_slide()

@rpc("unreliable")
func _sync_cart_transform(pos: Vector3, rot: Vector3) -> void:
	if not is_being_pushed or not pushing_player or not pushing_player.is_multiplayer_authority():
		global_position = pos
		rotation = rot

func empty_cart() -> void:
	collected_trash_count = 0
	for item in stored_items:
		if is_instance_valid(item):
			var tween = create_tween()
			tween.tween_property(item, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
			tween.tween_callback(item.queue_free)
	stored_items.clear()

func _on_body_entered(body: Node) -> void:
	if is_instance_valid(body) and (body.is_in_group("trash") or body.is_in_group("pickable")) and not body.get("is_disposed"):
		var item_path = body.get_path()
		if multiplayer.has_multiplayer_peer():
			rpc("_sync_store_trash", item_path)
		else:
			_sync_store_trash(item_path)

@rpc("any_peer", "call_local", "reliable")
func _sync_store_trash(item_path: NodePath) -> void:
	var trash_node = get_node_or_null(item_path)
	if not is_instance_valid(trash_node):
		return

	if trash_node.get("is_disposed") == true:
		return

	if trash_node.has_method("dispose"):
		trash_node.dispose()
	else:
		trash_node.set("is_disposed", true)

	collected_trash_count += 1
	stored_items.append(trash_node)

	# Disable physics/collision on the trash item so it sits inside cart cleanly
	if trash_node is RigidBody3D:
		trash_node.freeze = true
		trash_node.set_collision_layer_value(1, false)
		trash_node.set_collision_mask_value(1, false)

	# Reparent to cart's interior storage container
	if trash_container:
		trash_node.reparent(trash_container)
	else:
		trash_node.reparent(self)

	# Calculate position inside the cart bin for visual piling effect
	var rand_offset_x = randf_range(-0.25, 0.25)
	var rand_offset_z = randf_range(-0.15, 0.15)
	var rand_height = 0.05 + (collected_trash_count * 0.06)
	var target_pos = Vector3(rand_offset_x, rand_height, rand_offset_z)
	var target_rot = Vector3(randf_range(-0.4, 0.4), randf_range(-3.14, 3.14), randf_range(-0.4, 0.4))

	# Smoothly animate item landing inside the cart
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(trash_node, "position", target_pos, 0.35)
	tween.tween_property(trash_node, "rotation", target_rot, 0.35)
	tween.tween_property(trash_node, "scale", Vector3(1.1, 1.1, 1.1), 0.35)

	item_disposed.emit()
