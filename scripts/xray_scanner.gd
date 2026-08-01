extends StaticBody3D

signal guest_approved(guest: Node3D)
signal guest_denied(guest: Node3D)

@export var scanner_name: String = "Harbor X-Ray Checkpoint 1"

var current_guest: Node3D = null
var current_guest_info: Dictionary = {}
var is_scanning: bool = false

@onready var monitor_label: Label3D = get_node_or_null("MonitorMesh/ScreenLabel")
@onready var status_light: OmniLight3D = get_node_or_null("StatusLight")

func _ready() -> void:
	add_to_group("interactable")
	_update_monitor_display()

func set_guest_to_scan(guest: Node3D, guest_data: Dictionary) -> void:
	current_guest = guest
	current_guest_info = guest_data
	is_scanning = true
	if status_light:
		status_light.color = Color(1.0, 0.8, 0.2) # Orange scanning light
	_update_monitor_display()

func clear_scanner() -> void:
	current_guest = null
	current_guest_info = {}
	is_scanning = false
	if status_light:
		status_light.color = Color(0.3, 0.8, 0.3) # Green ready light
	_update_monitor_display()

func _update_monitor_display() -> void:
	if not monitor_label:
		return
		
	if current_guest == null:
		monitor_label.text = "🔍 HARBOR X-RAY SCANNER\n[ Status: READY ]\nWaiting for next guest..."
	else:
		var name_str = current_guest_info.get("name", "NPC Guest")
		var items_str = current_guest_info.get("luggage", "Standard Luggage")
		var is_contraband = current_guest_info.get("has_contraband", false)
		
		var status_header = "⚠️ CONTRABAND DETECTED!" if is_contraband else "✅ CLEAR FOR BOARDING"
		monitor_label.text = "🔍 HARBOR X-RAY MONITOR\nPassenger: %s\nLuggage: %s\nStatus: %s\n\n[E / Square] APPROVE | [C / Circle] DENY" % [name_str, items_str, status_header]

func get_interaction_prompt() -> String:
	if current_guest == null:
		return "X-Ray Scanner: Waiting for Guest..."
	else:
		var is_contraband = current_guest_info.get("has_contraband", false)
		if is_contraband:
			return "⚠️ CONTRABAND! [E / Square] Approve | [C / Circle] Deny"
		else:
			return "Press [E / Square] to APPROVE Guest Boarding"

func interact(player: Node3D) -> void:
	if current_guest == null:
		if player.has_method("show_alert"):
			player.show_alert("X-Ray Scanner is clear. No guest in scanner booth.")
		return
		
	# Approve current guest
	approve_current_guest(player)

func approve_current_guest(player: Node3D) -> void:
	if current_guest == null:
		return
		
	var guest_to_process = current_guest
	var is_contraband = current_guest_info.get("has_contraband", false)
	
	clear_scanner()
	emit_signal("guest_approved", guest_to_process)
	
	if player and player.has_method("show_alert"):
		if is_contraband:
			player.show_alert("⚠️ Approved guest with contraband! Hotel warning issued.", 3.5)
		else:
			player.show_alert("✅ Guest Approved! Boarding cruise ship...", 2.5)

func deny_current_guest(player: Node3D) -> void:
	if current_guest == null:
		return
		
	var guest_to_process = current_guest
	var is_contraband = current_guest_info.get("has_contraband", false)
	
	clear_scanner()
	emit_signal("guest_denied", guest_to_process)
	
	if player and player.has_method("show_alert"):
		if is_contraband:
			player.show_alert("🛑 Contraband Denied! Guest turned away from harbor.", 3.0)
		else:
			player.show_alert("❌ Innocent Guest Denied Entry.", 2.5)
