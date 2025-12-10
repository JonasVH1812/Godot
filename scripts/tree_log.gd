extends Node3D

@onready var pickup_sound: AudioStreamPlayer3D = $PickupSound
@onready var area = $Area3D
var player_in_range: bool = false

func _ready():
	$Area3D.body_entered.connect(_on_body_entered)
	$Area3D.body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_range = true
		print("Press E to pick up log")

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_range = false

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("interact"):
		pickup()

func pickup():
	print("Picked up log!")
	if pickup_sound:
		pickup_sound.play()
		await get_tree().create_timer(pickup_sound.stream.get_length()).timeout
	queue_free()
