extends StaticBody3D

## Trash Bin that receives trash items tossed in or deposited via [E] interaction.

signal item_disposed()

@onready var deposit_area: Area3D = $DepositArea

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("trash_bin")
	if deposit_area:
		deposit_area.body_entered.connect(_on_body_entered)

func get_interaction_prompt() -> String:
	return "Press [E] to Dispose Trash into Bin"

func interact(player: Node = null) -> void:
	if player and player.get("carried_object") != null:
		var item = player.carried_object
		if is_instance_valid(item) and (item.is_in_group("trash") or item.is_in_group("pickable")):
			player.carried_object = null
			_dispose_trash_node(item, player)

func _on_body_entered(body: Node) -> void:
	if is_instance_valid(body) and (body.is_in_group("trash") or body.is_in_group("pickable")) and not body.get("is_disposed"):
		_dispose_trash_node(body, null)

func _dispose_trash_node(trash_node: Node, player: Node) -> void:
	if not is_instance_valid(trash_node):
		return

	if trash_node.has_method("dispose"):
		trash_node.dispose()
	else:
		var tween = create_tween()
		tween.tween_property(trash_node, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
		tween.tween_callback(trash_node.queue_free)

	item_disposed.emit()

	if player and player.has_method("show_alert"):
		player.show_alert("🗑️ Trash Disposed!", 1.8)
