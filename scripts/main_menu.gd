extends Control

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var ip_input: LineEdit = %IPInput
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var fullscreen_checkbox: CheckBox = %FullscreenCheckBox
@onready var quit_button: Button = %QuitButton
@onready var status_label: Label = %StatusLabel
@onready var my_ip_label: Label = get_node_or_null("%MyIPLabel")

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.public_ip_fetched.connect(_on_public_ip_fetched)
	
	fullscreen_checkbox.button_pressed = GameManager.is_fullscreen
	status_label.text = ""
	
	if NetworkManager.public_ip_address != "":
		_update_ip_display(NetworkManager.public_ip_address)
	else:
		if my_ip_label:
			my_ip_label.text = "Generating your 6-Digit Lobby Code..."

func _on_public_ip_fetched(ip: String) -> void:
	_update_ip_display(ip)

func _update_ip_display(_ip: String) -> void:
	if my_ip_label:
		var code = NetworkManager.get_lobby_code()
		my_ip_label.text = "Your Host 6-Digit Lobby Code: " + code

func _on_host_pressed() -> void:
	var name_text = player_name_input.text.strip_edges()
	var err = NetworkManager.host_game(7777, name_text)
	if err == OK:
		get_tree().change_scene_to_file("res://scenes/lobby_menu.tscn")
	else:
		status_label.text = "Failed to create server on port 7777!"

func _on_join_pressed() -> void:
	var name_text = player_name_input.text.strip_edges()
	var input_text = ip_input.text.strip_edges()
	if input_text == "":
		input_text = "127.0.0.1"
	
	status_label.text = "Connecting to %s..." % input_text
	host_button.disabled = true
	join_button.disabled = true
	
	var err = NetworkManager.join_game(input_text, 7777, name_text)
	if err != OK:
		status_label.text = "Error connecting to host."
		host_button.disabled = false
		join_button.disabled = false

func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby_menu.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Connection failed! For internet play, ensure Host has UPnP / Port 7777 open, or use ZeroTier/Tailscale."
	host_button.disabled = false
	join_button.disabled = false

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	GameManager.set_fullscreen(toggled_on)

func _on_quit_pressed() -> void:
	get_tree().quit()
