extends Node3D

@export var guest_scene: PackedScene = preload("res://Character/wanderer.tscn")
@export var max_queued_guests: int = 4
@export var spawn_interval: float = 6.0

@onready var xray_scanner: StaticBody3D = $XRayScanner
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var scanner_point: Marker3D = $ScannerPoint
@onready var gangway_point: Marker3D = $GangwayPoint
@onready var ship_entry_point: Marker3D = $ShipEntryPoint
@onready var exit_point: Marker3D = $ExitPoint

var guest_queue: Array[Node3D] = []
var active_scanning_guest: Node3D = null
var spawn_timer: float = 0.0

const GUEST_NAMES = ["Captain Banana", "Mr. Pineapple", "Ms. Coconut", "Sir Mango", "Lady Citrus", "Dr. Avocado"]
const LUGGAGE_SAFE = ["Sunscreen & Clothes", "Snorkel & Camera", "Beach Towels", "Books & Sunglasses", "Souvenirs"]
const LUGGAGE_CONTRABAND = ["Illegal Fireworks 💥", "Extinct Bio-Plant ☣️", "Smuggled Gold 💰", "Unlicensed Parakeet 🦜"]

func _ready() -> void:
	if xray_scanner:
		if xray_scanner.has_signal("guest_approved"):
			xray_scanner.guest_approved.connect(_on_guest_approved)
		if xray_scanner.has_signal("guest_denied"):
			xray_scanner.guest_denied.connect(_on_guest_denied)
			
	# Spawn initial guest
	_spawn_npc_guest()

func _process(delta: float) -> void:
	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		if guest_queue.size() < max_queued_guests and active_scanning_guest == null:
			_spawn_npc_guest()
			
	_update_queue_positions()

func _spawn_npc_guest() -> void:
	if guest_scene == null or spawn_point == null:
		return
		
	var guest = guest_scene.instantiate()
	guest.global_position = spawn_point.global_position
	
	# Generate random luggage data
	var is_contraband = randf() < 0.25 # 25% chance of contraband
	var name_txt = GUEST_NAMES[randi() % GUEST_NAMES.size()]
	var luggage_txt = LUGGAGE_CONTRABAND[randi() % LUGGAGE_CONTRABAND.size()] if is_contraband else LUGGAGE_SAFE[randi() % LUGGAGE_SAFE.size()]
	
	var guest_info = {
		"name": name_txt,
		"luggage": luggage_txt,
		"has_contraband": is_contraband
	}
	guest.set_meta("guest_info", guest_info)
	guest.set_meta("harbor_state", "WALKING_TO_SCANNER")
	
	add_child(guest)
	guest_queue.append(guest)
	
	if active_scanning_guest == null:
		_send_next_to_scanner()

func _send_next_to_scanner() -> void:
	if guest_queue.size() == 0 or active_scanning_guest != null:
		return
		
	active_scanning_guest = guest_queue.pop_front()
	active_scanning_guest.set_meta("harbor_state", "WALKING_TO_SCANNER")

func _update_queue_positions() -> void:
	# Update active scanning guest movement
	if is_instance_valid(active_scanning_guest):
		var state = active_scanning_guest.get_meta("harbor_state", "")
		if state == "WALKING_TO_SCANNER":
			var target_pos = scanner_point.global_position
			var dir = (target_pos - active_scanning_guest.global_position)
			dir.y = 0
			if dir.length() > 0.6:
				active_scanning_guest.global_position += dir.normalized() * 2.0 * get_process_delta_time()
				active_scanning_guest.look_at(target_pos, Vector3.UP)
			else:
				active_scanning_guest.set_meta("harbor_state", "WAITING_FOR_INSPECTION")
				var info = active_scanning_guest.get_meta("guest_info", {})
				xray_scanner.set_guest_to_scan(active_scanning_guest, info)
				
		elif state == "BOARDING_SHIP":
			var target_pos = ship_entry_point.global_position
			var dir = (target_pos - active_scanning_guest.global_position)
			dir.y = 0
			if dir.length() > 0.8:
				active_scanning_guest.global_position += dir.normalized() * 2.5 * get_process_delta_time()
				active_scanning_guest.look_at(target_pos, Vector3.UP)
			else:
				# Entered ship lobby!
				active_scanning_guest.queue_free()
				active_scanning_guest = null
				_send_next_to_scanner()
				
		elif state == "LEAVING_HARBOR":
			var target_pos = exit_point.global_position
			var dir = (target_pos - active_scanning_guest.global_position)
			dir.y = 0
			if dir.length() > 0.8:
				active_scanning_guest.global_position += dir.normalized() * 2.8 * get_process_delta_time()
				active_scanning_guest.look_at(target_pos, Vector3.UP)
			else:
				active_scanning_guest.queue_free()
				active_scanning_guest = null
				_send_next_to_scanner()

func _on_guest_approved(guest: Node3D) -> void:
	if guest == active_scanning_guest:
		active_scanning_guest.set_meta("harbor_state", "BOARDING_SHIP")

func _on_guest_denied(guest: Node3D) -> void:
	if guest == active_scanning_guest:
		active_scanning_guest.set_meta("harbor_state", "LEAVING_HARBOR")
