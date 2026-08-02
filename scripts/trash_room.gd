extends Node3D

## Utility Trash Room with industrial dumpster compactor.
## Empties loaded Trash Carts brought inside and awards a cash disposal bonus!

signal cart_emptied(bonus_amount: int)

@export var disposal_bonus_per_item: int = 25
@export var base_emptying_bonus: int = 50

@onready var dumpster_zone: Area3D = $Dumpster/DumpsterZone

func _ready() -> void:
	if dumpster_zone:
		dumpster_zone.body_entered.connect(_on_dumpster_zone_entered)

func _on_dumpster_zone_entered(body: Node) -> void:
	if body and body.is_in_group("trash_cart") and body.has_method("empty_cart"):
		empty_cart_in_dumpster(body, null)

func empty_cart_in_dumpster(cart: Node, player: Node = null) -> void:
	if not is_instance_valid(cart) or not cart.has_method("empty_cart"):
		return

	var item_count = cart.get("collected_trash_count")
	if item_count <= 0:
		if player and player.has_method("show_alert"):
			player.show_alert("ℹ️ Trash Cart is already empty!", 2.0)
		return

	# Calculate payout bonus
	var total_payout = base_emptying_bonus + (item_count * disposal_bonus_per_item)

	if multiplayer.has_multiplayer_peer():
		rpc("_sync_empty_cart", cart.get_path(), total_payout)
	else:
		_sync_empty_cart(cart.get_path(), total_payout)

	if player and player.has_method("show_alert"):
		player.show_alert("♻️ Trash Cart Emptied in Dumpster! +$%d Bonus" % total_payout, 3.5)

@rpc("any_peer", "call_local", "reliable")
func _sync_empty_cart(cart_path: NodePath, payout: int) -> void:
	var cart = get_node_or_null(cart_path)
	if is_instance_valid(cart) and cart.has_method("empty_cart"):
		cart.empty_cart()

	GameManager.add_cash(payout)
	cart_emptied.emit(payout)
	print("[TrashRoom] Cart emptied in dumpster! Awarded +$", payout)
