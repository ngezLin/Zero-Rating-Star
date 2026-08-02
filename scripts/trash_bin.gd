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
	return "Press [E] to Dispose Carried Trash"

func interact(player: Node = null) -> void:
	if player and player.get("carried_object") != null:
		var item = player.carried_object
		if item.is_in_group("trash"):
			# Clear player carry
			player.carried_object = null
			if is_instance_valid(item.get_parent()):
				item.reparent(self)
			
			_dispose_trash_node(item, player)

func _on_body_entered(body: Node) -> void:
	if body and body.is_in_group("trash") and not body.get("is_disposed"):
		_dispose_trash_node(body, null)

func _dispose_trash_node(trash_node: Node, player: Node) -> void:
	if trash_node.has_method("dispose"):
		trash_node.dispose()
	else:
		trash_node.queue_free()

	item_disposed.emit()

	if player and player.has_method("show_alert"):
		player.show_alert("🗑️ Trash Disposed!", 1.8)
