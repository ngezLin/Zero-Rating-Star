extends Node3D

@export var player_scene: PackedScene = preload("res://Character/player.tscn")
@onready var players_container: Node3D = $Players

func _ready() -> void:
	# Enable Shift state in GameManager
	GameManager.start_shift()
	
	if multiplayer.has_multiplayer_peer():
		# Both server AND client spawn all players
		for peer_id in NetworkManager.players:
			_spawn_player(peer_id)
		
		# Both server and client handle disconnections
		multiplayer.peer_disconnected.connect(_despawn_player)
		
		if multiplayer.is_server():
			multiplayer.peer_connected.connect(_spawn_player)
		else:
			# If the server goes away, return to main menu
			multiplayer.server_disconnected.connect(_on_server_disconnected)
	else:
		# Standalone / Editor testing mode
		_spawn_player(1)

func _spawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		return
	
	var p_node = player_scene.instantiate()
	p_node.name = str(peer_id)
	p_node.set_multiplayer_authority(peer_id)
	
	# Position player spawn points cleanly in front of reception desk
	var spawn_index = players_container.get_child_count()
	var offset_x = (spawn_index % 4) * 1.8 - 2.7
	p_node.transform.origin = Vector3(offset_x, 1.18, 4.0)
	
	players_container.add_child(p_node, true)

func _despawn_player(peer_id: int) -> void:
	if players_container.has_node(str(peer_id)):
		players_container.get_node(str(peer_id)).queue_free()

func _on_server_disconnected() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
