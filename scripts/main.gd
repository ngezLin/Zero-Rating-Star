extends Node3D

@export var player_scene: PackedScene = preload("res://Character/player.tscn")
@onready var players_container: Node3D = $Players

func _ready() -> void:
	# Enable Shift state in GameManager
	GameManager.start_shift()
	
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Spawn all connected peers
		for peer_id in NetworkManager.players:
			_spawn_player(peer_id)
		multiplayer.peer_connected.connect(_spawn_player)
		multiplayer.peer_disconnected.connect(_despawn_player)
	elif not multiplayer.has_multiplayer_peer():
		# Standalone / Editor testing mode
		_spawn_player(1)

func _spawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		return
	
	var p_node = player_scene.instantiate()
	p_node.name = str(peer_id)
	
	# Position player spawn points cleanly in front of reception desk
	var spawn_index = players_container.get_child_count()
	var offset_x = (spawn_index % 4) * 1.8 - 2.7
	p_node.transform.origin = Vector3(offset_x, 1.18, 4.0)
	
	players_container.add_child(p_node, true)

func _despawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		players_container.get_node(str(peer_id)).queue_free()
