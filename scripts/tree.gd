extends Node3D

@export var max_health: int = 3
@export var tree_log: PackedScene
@export var hit_sound: AudioStream

var health: int = 0
@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready():
	health = max_health
	add_to_group("trees")

func damage(amount: int = 1):
	health -= amount
	print("Tree hit! HP:", health)

	if hit_sound:
		var s = AudioStreamPlayer3D.new()
		add_child(s)
		s.stream = hit_sound
		s.play()
		var timer = get_tree().create_timer(s.stream.get_length())
		await timer.timeout
		s.queue_free()

	if health <= 0:
		fall_and_spawn_logs()

func fall_and_spawn_logs():
	if anim and anim.has_animation("tree_fall"):
		anim.play("tree_fall")
		await get_tree().create_timer(1.0).timeout

	if tree_log:
		var new_log = tree_log.instantiate()
		get_parent().add_child(new_log)
		new_log.global_transform = global_transform

	queue_free()
