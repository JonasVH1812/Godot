extends Node3D

@export var max_health: int = 3
var health: int

func _ready():
	health = max_health

func damage(amount: int = 1):
	health -= amount
	if health <= 0:
		print("TREE DESTROYED:", name)
		queue_free()
	else:
		print("Tree hit! Remaining health:", health)
