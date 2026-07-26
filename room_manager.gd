extends Node

signal tasks_updated(remaining: int)
signal room_ready

@export var room_name: String = "Room 101"
@export var total_tasks: int = 5
var remaining_tasks: int = 5

func _ready() -> void:
	remaining_tasks = total_tasks
	emit_signal("tasks_updated", remaining_tasks)
	
	# Connect trash bin signals
	var bins = get_tree().get_nodes_in_group("trash_bin")
	for bin_node in bins:
		var logic = bin_node.get_node_or_null("TrashBinLogic")
		if logic and logic.has_signal("item_disposed"):
			logic.item_disposed.connect(_on_task_completed)
			
	# Connect bed task signals
	var beds = get_tree().get_nodes_in_group("bed_task")
	for bed in beds:
		if bed.has_signal("bed_tidied"):
			bed.bed_tidied.connect(_on_task_completed)
			
	# Connect stain patch signals
	var stains = get_tree().get_nodes_in_group("stain")
	for stain in stains:
		if stain.has_signal("cleaned"):
			stain.cleaned.connect(_on_task_completed)

func _on_task_completed() -> void:
	if remaining_tasks > 0:
		remaining_tasks -= 1
		emit_signal("tasks_updated", remaining_tasks)
		if remaining_tasks == 0:
			emit_signal("room_ready")
