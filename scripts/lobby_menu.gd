extends Control

@onready var player_list_container: VBoxContainer = %PlayerListContainer
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var status_label: Label = %StatusLabel

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	UIAnimator.setup_node_buttons(self)
	GameManager.change_state(GameManager.AppState.LOBBY)
	
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	
	NetworkManager.player_list_updated.connect(_update_lobby_ui)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	_update_lobby_ui()

func _update_lobby_ui() -> void:
	for child in player_list_container.get_children():
		child.queue_free()
		
	var is_server = multiplayer.is_server()
	start_button.visible = is_server
	
	var all_ready = true
	var current_player_count = NetworkManager.players.size()
	
	for p_id in NetworkManager.players:
		var p_data = NetworkManager.players[p_id]
		var item = HBoxContainer.new()
		
		var name_lbl = Label.new()
		name_lbl.text = p_data.get("name", "Unknown")
		if p_id == 1:
			name_lbl.text += " (Host)"
		if p_id == multiplayer.get_unique_id():
			name_lbl.text += " [YOU]"
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_child(name_lbl)
		
		var ready_lbl = Label.new()
		var is_p_ready = p_data.get("ready", false)
		ready_lbl.text = "READY" if is_p_ready else "NOT READY"
		ready_lbl.modulate = Color(0.2, 0.9, 0.3) if is_p_ready else Color(0.9, 0.3, 0.3)
		ready_lbl.custom_minimum_size.x = 100
		item.add_child(ready_lbl)
		
		player_list_container.add_child(item)
		
		if not is_p_ready:
			all_ready = false
			
	ready_button.text = "UNREADY" if NetworkManager.local_player_ready else "READY UP"
	
	if is_server:
		start_button.disabled = not (all_ready and current_player_count >= 1)
		if not all_ready:
			status_label.text = "Waiting for all staff members to Ready Up..."
		else:
			status_label.text = "All staff ready! Click 'Start Shift' to begin."
	else:
		status_label.text = "Waiting for Host to start the shift..."

func _on_ready_pressed() -> void:
	NetworkManager.toggle_ready()

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		NetworkManager.start_game()

func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_server_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
