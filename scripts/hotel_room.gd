extends Node3D

## Hotel room manager. Tracks dirty spots, randomizes their positions on room load,
## and awards cash when all are cleaned.

signal room_cleaned()

@export var room_number: int = 101
@export var reward_cash: int = 50

var dirty_spots: Array[Node] = []
var total_spots: int = 0
var cleaned_count: int = 0

# Candidate floor positions across open room areas (X, Z)
const CANDIDATE_POSITIONS: Array[Vector2] = [
	Vector2(-0.8, 0.6),   # Near bed foot
	Vector2(-0.4, -1.8),  # Near nightstand
	Vector2(0.8, -0.6),   # Room center
	Vector2(1.6, -1.2),   # Under/near desk
	Vector2(1.2, 1.2),    # Near wardrobe
	Vector2(-0.4, 1.8),   # Near doorway left
	Vector2(0.8, 1.8),    # Near doorway right
	Vector2(-2.1, 1.5)    # Bed side corner
]

# Random stain names
const STAIN_NAMES: Array[String] = [
	"Floor Stain",
	"Spilled Coffee",
	"Muddy Footprints",
	"Dust Cluster",
	"Mystery Blob"
]

func _ready() -> void:
	# Collect all dirty spots in this room
	_find_dirty_spots(self)
	total_spots = dirty_spots.size()
	
	# Randomize positions of the dirty spots across open room areas
	_randomize_spot_positions()
	
	print("[HotelRoom] Room ", room_number, " loaded with ", total_spots, " randomized dirty spots")

func _randomize_spot_positions() -> void:
	var available_pos = CANDIDATE_POSITIONS.duplicate()
	available_pos.shuffle()
	
	var names_pool = STAIN_NAMES.duplicate()
	names_pool.shuffle()

	var pos_index = 0
	for spot in dirty_spots:
		# Exclude bed blanket or stationary items from floor randomization
		if spot.name.begins_with("DirtySpot"):
			if pos_index < available_pos.size():
				var p2d = available_pos[pos_index]
				spot.global_position = global_transform * Vector3(p2d.x, 0.10, p2d.y)
				pos_index += 1
			if pos_index <= names_pool.size() and "spot_name" in spot:
				spot.spot_name = names_pool[pos_index - 1]

func _find_dirty_spots(node: Node) -> void:
	for child in node.get_children():
		# Skip TrashCart node itself so it doesn't duplicate signal counts
		if child.is_in_group("trash_cart"):
			_find_dirty_spots(child)
			continue

		if child.has_signal("cleaned"):
			dirty_spots.append(child)
			child.cleaned.connect(_on_spot_cleaned)
		elif child.has_signal("disposed"):
			dirty_spots.append(child)
			child.disposed.connect(_on_spot_cleaned)
		elif child.has_signal("tidied"):
			dirty_spots.append(child)
			child.tidied.connect(_on_spot_cleaned)
		_find_dirty_spots(child)

func _on_spot_cleaned() -> void:
	cleaned_count += 1
	print("[HotelRoom] Room ", room_number, ": ", cleaned_count, "/", total_spots, " spots cleaned")

	if cleaned_count >= total_spots:
		_on_all_clean()

func _on_all_clean() -> void:
	room_cleaned.emit()
	GameManager.add_cash(reward_cash)
	print("[HotelRoom] Room ", room_number, " FULLY CLEAN! +$", reward_cash)

	# Show alert on all local players
	var players_node = get_tree().get_first_node_in_group("players_container")
	if players_node:
		for p in players_node.get_children():
			if p.has_method("show_alert") and p.is_multiplayer_authority():
				p.show_alert("🏨 Room %d Clean! +$%d" % [room_number, reward_cash], 4.0)
	else:
		# Fallback: try to find any player
		for p in get_tree().get_nodes_in_group("player"):
			if p.has_method("show_alert"):
				p.show_alert("🏨 Room %d Clean! +$%d" % [room_number, reward_cash], 4.0)
				break

func get_clean_progress() -> float:
	if total_spots == 0:
		return 1.0
	return float(cleaned_count) / float(total_spots)
