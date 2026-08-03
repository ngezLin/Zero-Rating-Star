extends Node
class_name Inventory

## 4-Slot PEAK-Style Player Inventory System.
## Handles slot selection, active item state, and inventory signals.

signal active_slot_changed(slot_index: int)
signal inventory_updated()

@export var max_slots: int = 4
@export var active_slot_index: int = 0

# Array of 4 slots. Each slot stores a Dictionary with item data or null if empty.
# Example item data: { "id": "trash_can", "name": "Soda Can", "icon_path": "...", "node": NodeRef }
var slots: Array = [null, null, null, null]

func _ready() -> void:
	# Ensure slots array size matches max_slots
	slots.resize(max_slots)
	for i in range(max_slots):
		if slots[i] == null:
			slots[i] = null

func select_slot(index: int) -> void:
	if index < -1 or index >= max_slots:
		return
	if active_slot_index == index and index != -1:
		# Toggle off to pure hands mode (-1) if pressing the active slot key again
		active_slot_index = -1
		active_slot_changed.emit(active_slot_index)
	elif active_slot_index != index:
		active_slot_index = index
		active_slot_changed.emit(active_slot_index)

func next_slot() -> void:
	var next_idx = (active_slot_index + 1) % max_slots
	select_slot(next_idx)

func previous_slot() -> void:
	var prev_idx = (active_slot_index - 1 + max_slots) % max_slots
	select_slot(prev_idx)

func get_active_item():
	if active_slot_index >= 0 and active_slot_index < max_slots:
		return slots[active_slot_index]
	return null

func add_item(item_info: Dictionary) -> bool:
	# 1. Try to place in active slot if valid and empty
	if active_slot_index >= 0 and active_slot_index < max_slots and slots[active_slot_index] == null:
		slots[active_slot_index] = item_info
		inventory_updated.emit()
		return true
	
	# 2. Otherwise place in first available empty slot
	for i in range(max_slots):
		if slots[i] == null:
			slots[i] = item_info
			inventory_updated.emit()
			return true
			
	return false # Inventory full

func remove_item(index: int):
	if index >= 0 and index < max_slots:
		var removed = slots[index]
		slots[index] = null
		inventory_updated.emit()
		return removed
	return null
