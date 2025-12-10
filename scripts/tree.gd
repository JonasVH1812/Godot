extends Node3D

@export var max_health: int = 3
@export var tree_log: PackedScene   # drag your tree_log.tscn here!

var health: int = 0

@onready var anim: AnimationPlayer = $AnimationPlayer
@export var hit_sound: AudioStream  # Drag your chopping sound here in the Inspector



func _ready():
	health = max_health


func damage(amount: int = 1):
	health -= amount
	print("Tree hit! HP:", health)

	# Play chopping sound
	if hit_sound:
		var sfx = AudioStreamPlayer3D.new()
		add_child(sfx)  # attach to tree so it has a position
		sfx.stream = hit_sound
		sfx.play()
		
		# Wait until the sound finishes, then free the player
		var timer = get_tree().create_timer(sfx.stream.get_length())
		await timer.timeout
		sfx.queue_free()

	if health <= 0:
		fall_and_spawn_logs()




func fall_and_spawn_logs() -> void:
	print("### FALL FUNCTION CALLED ###")

	# play the tree fall animation (1 second)
	if anim and anim.has_animation("tree_fall"):
		anim.play("tree_fall")
		print("Playing tree_fall animation...")
		await get_tree().create_timer(1.0).timeout
	else:
		print("NO animation named tree_fall found!")

	# spawn a log after animation
	if tree_log:
		print("Spawning tree_log scene...")
		var log = tree_log.instantiate()
		get_parent().add_child(log)
		log.global_transform = global_transform
	else:
		print("ERROR: tree_log is NOT assigned in Inspector!!!")

	# delete the tree
	queue_free()
