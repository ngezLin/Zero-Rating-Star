extends StaticBody3D

## Mobile Trash Cart / Cleaning Trolley synced across multiplayer peers via RPC.

signal item_disposed()

@export var max_storage_capacity: int = 20

var stored_items: Array[Node] = []
var collected_trash_count: int = 0

@onready var trash_container: Node3D = $TrashContainer
@onready var deposit_area: Area3D = $DepositArea

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("trash_cart")
	if deposit_area:
		deposit_area.body_entered.connect(_on_body_entered)

func get_interaction_prompt() -> String:
	return "Press [E] to Store Trash in Cart (%d items)" % collected_trash_count

func interact(player: Node = null) -> void:
	if player and player.get("carried_object") != null:
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
	var rand_height = min(0.35, 0.1 + (collected_trash_count * 0.05))
	var target_pos = Vector3(rand_offset_x, rand_height, rand_offset_z)
	var target_rot = Vector3(randf_range(-0.4, 0.4), randf_range(-3.14, 3.14), randf_range(-0.4, 0.4))

	# Smoothly animate item landing inside the cart
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(trash_node, "position", target_pos, 0.35)
	tween.tween_property(trash_node, "rotation", target_rot, 0.35)
	tween.tween_property(trash_node, "scale", Vector3(0.85, 0.85, 0.85), 0.35)

	item_disposed.emit()
