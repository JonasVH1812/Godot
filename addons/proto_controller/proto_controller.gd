extends CharacterBody3D

@export var can_move : bool = true
@export var has_gravity : bool = true
@export var can_jump : bool = true
@export var can_sprint : bool = false
@export var can_freefly : bool = false

# Pickup system
@export var pickup_distance: float = 5.0
var held_log: RigidBody3D = null
var hold_distance := 2.5
@export var input_pickup: String = "pickup"  # assign "E" in Input Map

@export_group("Speeds")
@export var look_speed : float = 0.002
@export var base_speed : float = 7.0
@export var jump_velocity : float = 4.5
@export var sprint_speed : float = 10.0
@export var freefly_speed : float = 25.0

@export_group("Input Actions")
@export var input_left : String = "left"
@export var input_right : String = "right"
@export var input_forward : String = "forward"
@export var input_back : String = "backwards"
@export var input_jump : String = "ui_accept"
@export var input_sprint : String = "sprint"
@export var input_freefly : String = "freefly"
@export var chop_distance : float = 3.0

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $collider
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var chop_cooldown: float = 3.0
var can_chop: bool = true
@export var tree_log_scene: PackedScene
@export var log_pickup_sound: AudioStream
var mouse_captured : bool = false
var look_rotation : Vector2 = Vector2.ZERO
var move_speed : float = 0.0
var freeflying : bool = false
var mouse_was_pressed : bool = false
var logs = 0

func add_log():
	logs += 1
	print("Logs:", logs)

func _ready() -> void:
	check_input_mappings()
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	capture_mouse()

func _process(delta: float) -> void:
	var mouse_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# Chopping
	if mouse_pressed and not mouse_was_pressed:
		if can_chop:
			if anim_player and not anim_player.is_playing():
				anim_player.play("hakken")
			raycast_chop_tree()
			can_chop = false
			start_chop_cooldown()
	mouse_was_pressed = mouse_pressed

	# Pickup / Drop with E
	if Input.is_action_just_pressed(input_pickup):
		if held_log:
			drop_log()
		else:
			try_pickup_log()

	# Move held log each frame
	if held_log:
		move_held_log(delta)

# ====================
# PICKUP SYSTEM
# ====================
func try_pickup_log():
	var from = camera.global_position
	var to = from + camera.global_transform.basis.z * -pickup_distance

	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.exclude = [self]

	var result = space_state.intersect_ray(query)
	# Debug print
	print("Raycast", from, "→", to, " hit:", result)

	if result == {}:
		return

	var obj = result.get("collider")
	if obj == null:
		return

	# Must be log
	if obj.is_in_group("logs") and obj is RigidBody3D:
		held_log = obj

		# Reparent under camera
		if held_log.get_parent() != null:
			held_log.get_parent().remove_child(held_log)
		camera.add_child(held_log)

		# Position relative to camera
		var t = Transform3D.IDENTITY
		t.origin = Vector3(0, 0.5, -hold_distance)
		held_log.transform = t

		# Freeze physics
		held_log.freeze = true
		held_log.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		held_log.gravity_scale = 0

		# Disable collision
		var col := held_log.get_node_or_null("CollisionShape3D")
		if col:
			col.disabled = true

		print("Picked up log:", held_log.name)

func move_held_log(delta):
	if held_log == null:
		return

	# Smooth move in front of camera
	var desired = camera.global_transform.origin \
		+ camera.global_transform.basis.z * -hold_distance \
		+ Vector3.UP * 0.5
	var current = held_log.global_transform.origin
	var newpos = current.lerp(desired, 0.2)
	var gt = held_log.global_transform
	gt.origin = newpos
	held_log.global_transform = gt

func drop_log():
	if held_log == null:
		return

	# Re-enable collision
	var col := held_log.get_node_or_null("CollisionShape3D")
	if col:
		col.disabled = false

	# Unfreeze physics
	held_log.freeze = false
	held_log.gravity_scale = 1

	# Reparent back to world
	var root = get_tree().current_scene
	if held_log.get_parent() != null:
		held_log.get_parent().remove_child(held_log)
	root.add_child(held_log)
	held_log.global_transform = held_log.global_transform

	# Give a small throw
	held_log.linear_velocity = -camera.global_transform.basis.z * 2.0

	held_log = null

# Cooldown timer
func start_chop_cooldown() -> void:
	var timer = get_tree().create_timer(chop_cooldown)
	await timer.timeout
	can_chop = true

# Tree chopping
func raycast_chop_tree() -> void:
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * chop_distance

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self, collider]
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result := space_state.intersect_ray(query)
	if result == {}:
		return

	var hit: Node = result.get("collider") as Node
	if hit == null:
		return

	var n: Node = hit
	while n.get_parent() != null:
		if n.is_in_group("trees"):
			break
		n = n.get_parent()

	if n and n.is_in_group("trees") and n.has_method("damage"):
		n.damage(1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or Input.is_key_pressed(KEY_ESCAPE):
		release_mouse()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not mouse_captured:
		capture_mouse()
	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)
	if can_freefly and Input.is_action_just_pressed(input_freefly):
		freeflying = !freeflying
		if freeflying:
			enable_freefly()
		else:
			disable_freefly()

func _physics_process(delta: float) -> void:
	if can_freefly and freeflying:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var motion := (head.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		move_and_collide(motion * freefly_speed * delta)
		return

	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

	if can_sprint and Input.is_action_pressed(input_sprint):
		move_speed = sprint_speed
	else:
		move_speed = base_speed

	if can_move:
		var input_dir := Input.get_vector(input_left, input_right, input_forward, input_back)
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if direction != Vector3.ZERO:
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()

func rotate_look(rot_input: Vector2) -> void:
	look_rotation.x -= rot_input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= rot_input.x * look_speed

	transform.basis = Basis()
	rotate_y(look_rotation.y)
	head.transform.basis = Basis()
	head.rotate_x(look_rotation.x)

func enable_freefly() -> void:
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO

func disable_freefly() -> void:
	collider.disabled = false
	freeflying = false

func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

func check_input_mappings() -> void:
	if can_move and not InputMap.has_action(input_left): can_move = false
	if can_move and not InputMap.has_action(input_right): can_move = false
	if can_move and not InputMap.has_action(input_forward): can_move = false
	if can_move and not InputMap.has_action(input_back): can_move = false
	if can_jump and not InputMap.has_action(input_jump): can_jump = false
	if can_sprint and not InputMap.has_action(input_sprint): can_sprint = false
	if can_freefly and not InputMap.has_action(input_freefly): can_freefly = false
	if not InputMap.has_action(input_pickup): print("Warning: 'pickup' input not defined!")
