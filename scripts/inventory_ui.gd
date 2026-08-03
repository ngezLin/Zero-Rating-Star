extends Control
class_name InventoryUI

## HUD Inventory Bar UI component (4 PEAK-style slots).
## Displays slot frames, number keybind badges [1] [2] [3] [4], and active selection highlight.

@onready var slot_container: HBoxContainer = $MarginContainer/HBoxContainer

var slot_nodes: Array[Control] = []
var inventory: Inventory = null

# Styling colors
const COLOR_ACTIVE_BORDER = Color(1.0, 0.85, 0.2, 0.95) # Glowing Amber/Gold
const COLOR_INACTIVE_BORDER = Color(1.0, 1.0, 1.0, 0.25) # Soft translucent
const COLOR_SLOT_BG = Color(0.08, 0.1, 0.14, 0.75) # Dark glassmorphic background

func setup(p_inventory: Inventory) -> void:
	inventory = p_inventory
	if inventory:
		inventory.active_slot_changed.connect(_on_active_slot_changed)
		inventory.inventory_updated.connect(_on_inventory_updated)
	_build_slot_ui()
	_update_slot_highlights()

func _build_slot_ui() -> void:
	# Clear existing children
	for child in slot_container.get_children():
		child.queue_free()
	slot_nodes.clear()

	var max_slots = inventory.max_slots if inventory else 4
	
	for i in range(max_slots):
		var slot_panel = PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(72, 72)
		
		# Custom StyleBoxFlat for glassmorphic slot panel
		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = COLOR_SLOT_BG
		stylebox.border_width_left = 2
		stylebox.border_width_top = 2
		stylebox.border_width_right = 2
		stylebox.border_width_bottom = 2
		stylebox.border_color = COLOR_INACTIVE_BORDER
		stylebox.corner_radius_top_left = 8
		stylebox.corner_radius_top_right = 8
		stylebox.corner_radius_bottom_left = 8
		stylebox.corner_radius_bottom_right = 8
		slot_panel.add_theme_stylebox_override("panel", stylebox)
		
		# Slot layout container
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 4)
		margin.add_theme_constant_override("margin_top", 4)
		margin.add_theme_constant_override("margin_right", 4)
		margin.add_theme_constant_override("margin_bottom", 4)
		slot_panel.add_child(margin)
		
		# Keybind badge label [1], [2], [3], [4] at top-left of slot
		var badge = Label.new()
		badge.text = str(i + 1)
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		margin.add_child(badge)
		
		# Item icon texture placeholder
		var icon_rect = TextureRect.new()
		icon_rect.name = "Icon"
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		margin.add_child(icon_rect)
		
		slot_container.add_child(slot_panel)
		slot_nodes.append(slot_panel)

func _on_active_slot_changed(active_idx: int) -> void:
	_update_slot_highlights()

func _on_inventory_updated() -> void:
	if not inventory:
		return
	for i in range(slot_nodes.size()):
		var slot_panel = slot_nodes[i]
		var icon_rect = slot_panel.find_child("Icon", true, false) as TextureRect
		var item_data = inventory.slots[i]
		
		if item_data != null and item_data.has("icon_texture"):
			icon_rect.texture = item_data["icon_texture"]
			icon_rect.visible = true
		else:
			icon_rect.texture = null
			icon_rect.visible = false

func _update_slot_highlights() -> void:
	var active_idx = inventory.active_slot_index if inventory else 0
	
	for i in range(slot_nodes.size()):
		var slot_panel = slot_nodes[i]
		var stylebox = slot_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		
		if i == active_idx:
			stylebox.border_color = COLOR_ACTIVE_BORDER
			stylebox.border_width_left = 3
			stylebox.border_width_top = 3
			stylebox.border_width_right = 3
			stylebox.border_width_bottom = 3
			stylebox.bg_color = Color(0.15, 0.18, 0.24, 0.85)
			
			# Scale animation pop for active slot
			var tween = create_tween()
			tween.tween_property(slot_panel, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(slot_panel, "scale", Vector2(1.05, 1.05), 0.05)
		else:
			stylebox.border_color = COLOR_INACTIVE_BORDER
			stylebox.border_width_left = 2
			stylebox.border_width_top = 2
			stylebox.border_width_right = 2
			stylebox.border_width_bottom = 2
			stylebox.bg_color = COLOR_SLOT_BG
			
			var tween = create_tween()
			tween.tween_property(slot_panel, "scale", Vector2(1.0, 1.0), 0.1)

		slot_panel.add_theme_stylebox_override("panel", stylebox)
