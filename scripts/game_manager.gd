extends Node

enum AppState { MAIN_MENU, LOBBY, IN_SHIFT, SHIFT_SUMMARY }

signal state_changed(new_state: AppState)
signal shift_timer_updated(time_left: float)
signal wallet_changed(new_amount: int)
signal rating_changed(new_rating: int)

var current_state: AppState = AppState.MAIN_MENU
var is_fullscreen: bool = true
var total_hotel_cash: int = 500
var day_count: int = 1
var current_hotel_rating: int = 0

var shift_duration: float = 300.0 # 5 minutes shift
var shift_time_remaining: float = 300.0
var shift_active: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_setup_input_actions()
	set_fullscreen(true)
	change_state(AppState.MAIN_MENU)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		toggle_fullscreen()
		
	if event.is_action_pressed("ui_cancel"):
		if current_state == AppState.IN_SHIFT:
			# Toggle mouse mode during shift to allow menu interaction
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_9:
			set_rating(0)
		elif event.physical_keycode == KEY_0:
			set_rating(5)
		elif event.physical_keycode == KEY_8:
			set_rating(4)

func _process(delta: float) -> void:
	if shift_active and current_state == AppState.IN_SHIFT:
		shift_time_remaining = max(0.0, shift_time_remaining - delta)
		shift_timer_updated.emit(shift_time_remaining)
		if shift_time_remaining <= 0.0:
			end_shift()

func change_state(new_state: AppState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	
	match current_state:
		AppState.MAIN_MENU, AppState.LOBBY, AppState.SHIFT_SUMMARY:
			shift_active = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
		AppState.IN_SHIFT:
			shift_time_remaining = shift_duration
			shift_active = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func toggle_fullscreen() -> void:
	set_fullscreen(!is_fullscreen)

func set_fullscreen(enable: bool) -> void:
	is_fullscreen = enable
	if enable:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func start_shift() -> void:
	change_state(AppState.IN_SHIFT)

func end_shift() -> void:
	shift_active = false
	change_state(AppState.SHIFT_SUMMARY)

func add_cash(amount: int) -> void:
	total_hotel_cash += amount
	wallet_changed.emit(total_hotel_cash)

func deduct_cash(amount: int) -> bool:
	if total_hotel_cash >= amount:
		total_hotel_cash -= amount
		wallet_changed.emit(total_hotel_cash)
		return true
	return false

@rpc("any_peer", "call_local")
func _sync_rating(stars: int) -> void:
	current_hotel_rating = stars
	rating_changed.emit(stars)

func set_rating(stars: int) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc("_sync_rating", stars)
	else:
		_sync_rating(stars)

func _setup_input_actions() -> void:
	if not InputMap.has_action("toggle_fullscreen"):
		InputMap.add_action("toggle_fullscreen")
		var ev_f11 = InputEventKey.new()
		ev_f11.physical_keycode = KEY_F11
		InputMap.action_add_event("toggle_fullscreen", ev_f11)
		
		var ev_alt_enter = InputEventKey.new()
		ev_alt_enter.physical_keycode = KEY_ENTER
		ev_alt_enter.alt_pressed = true
		InputMap.action_add_event("toggle_fullscreen", ev_alt_enter)
