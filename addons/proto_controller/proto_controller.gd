extends CharacterBody3D

@export var can_move: bool = true
@export var has_gravity: bool = true
@export var can_jump: bool = true
@export var can_sprint: bool = false
@export var can_freefly: bool = false

# Pickup system
@export var pickup_distance: float = 5.0
@export var base_throw_strength: float = 5.0

# Smooth scrollable hold distance (MAX NOW CLOSER: 5m)
@export var min_hold_distance: float = 0.5
@export var max_hold_distance: float = 5.0   # ← REDUCED from 8.0 (a bit dichter!)
@export var scroll_sensitivity: float = 0.3
@export var hold_lerp_speed: float = 12.0
var target_hold_distance: float = 2.0
var current_hold_distance: float = 2.0

var picked_object: RigidBody3D = null

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider as CollisionShape3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var pickup_raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var pickup_hand: Node3D = $Head/Camera3D/Hand

var mouse_captured: bool = false
var look_rotation: Vector2 = Vector2.ZERO
var move_speed: float = 0.0
var freeflying: bool = false
var mouse_was_pressed: bool = false
var logs = 0

# Speeds
@export var look_speed: float = 0.002
@export var base_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var sprint_speed: float = 10.0
@export var freefly_speed: float = 25.0

# Input actions
@export var input_left: String = "left"
@export var input_right: String = "right"
@export var input_forward: String = "forward"
@export var input_back: String = "backwards"
@export var input_jump: String = "ui_accept"
@export var input_sprint: String = "sprint"
@export var input_freefly: String = "freefly"
@export var input_pickup: String = "pickup"

# Tree chopping
@export var chop_distance: float = 3.0
var chop_cooldown: float = 3.0
var can_chop: bool = true
@export var tree_log_scene: PackedScene
@export var log_pickup_sound: AudioStream

# ----------------------
# PICKUP FUNCTIONS
# ----------------------
func _find_rigid_body_from_node(node: Node) -> RigidBody3D:
	var n = node
	while n:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null

func pick_up_object_from_collider(collider_node: Node) -> void:
	if collider_node == null:
		return
	var body := _find_rigid_body_from_node(collider_node)
	if body == null or body == picked_object:
		return
	if global_transform.origin.distance_to(body.global_transform.origin) > pickup_distance:
		return
	pick_up_object(body)

func pick_up_object(body: RigidBody3D) -> void:
	if not body or not body.is_inside_tree():
		return

	body.set_meta("orig_layer", body.collision_layer)
	body.set_meta("orig_mask", body.collision_mask)
	body.set_deferred("collision_layer", 0)
	body.set_deferred("collision_mask", 0)
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

	var old_transform := body.global_transform
	var parent := body.get_parent()
	if parent:
		parent.remove_child(body)
	pickup_hand.add_child(body)
	body.global_transform = old_transform

	target_hold_distance = 2.0
	current_hold_distance = 2.0
	picked_object = body

func update_held_object_position() -> void:
	if picked_object and is_instance_valid(picked_object):
		var target_pos = camera.global_position + (-camera.global_transform.basis.z) * current_hold_distance
		picked_object.global_position = target_pos

# FIXED DROP — drops exactly where it was
func drop_object() -> void:
	if picked_object == null:
		return

	var world = get_tree().current_scene
	var saved_transform := picked_object.global_transform

	pickup_hand.remove_child(picked_object)
	world.add_child(picked_object)
	picked_object.global_transform = saved_transform

	picked_object.freeze = false
	if picked_object.has_meta("orig_layer"):
		var orig_layer := picked_object.get_meta("orig_layer")
		var orig_mask := picked_object.get_meta("orig_mask")
		picked_object.set_deferred("collision_layer", orig_layer)
		picked_object.set_deferred("collision_mask", orig_mask)
		picked_object.remove_meta("orig_layer")
		picked_object.remove_meta("orig_mask")

	# Drops EXACTLY where it was floating (no nudge)
	picked_object = null

func throw_object() -> void:
	if picked_object == null:
		return

	var world = get_tree().current_scene
	var saved_transform := picked_object.global_transform

	pickup_hand.remove_child(picked_object)
	world.add_child(picked_object)
	picked_object.global_transform = saved_transform

	picked_object.freeze = false
	if picked_object.has_meta("orig_layer"):
		var orig_layer := picked_object.get_meta("orig_layer")
		var orig_mask := picked_object.get_meta("orig_mask")
		picked_object.set_deferred("collision_layer", orig_layer)
		picked_object.set_deferred("collision_mask", orig_mask)
		picked_object.remove_meta("orig_layer")
		picked_object.remove_meta("orig_mask")

	var dir := -camera.global_transform.basis.z.normalized()
	var force := base_throw_strength
	if picked_object.mass > 0:
		force = base_throw_strength / picked_object.mass
	picked_object.linear_velocity = dir * force
	picked_object = null

# ----------------------
# INPUT
# ----------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and picked_object and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_hold_distance = clamp(target_hold_distance + scroll_sensitivity, min_hold_distance, max_hold_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_hold_distance = clamp(target_hold_distance - scroll_sensitivity, min_hold_distance, max_hold_distance)
			get_viewport().set_input_as_handled()

	if event.is_action_pressed("Interact"):
		if picked_object:
			drop_object()
		else:
			var collider_node := pickup_raycast.get_collider()
			if collider_node:
				pick_up_object_from_collider(collider_node)

	if event.is_action_pressed("Throw") and picked_object:
		throw_object()

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

# ----------------------
# PROCESS & PHYSICS
# ----------------------
func _process(delta: float) -> void:
	if picked_object:
		current_hold_distance = lerp(current_hold_distance, target_hold_distance, hold_lerp_speed * delta)
		update_held_object_position()

	var mouse_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if mouse_pressed and not mouse_was_pressed:
		if can_chop:
			if anim_player and not anim_player.is_playing():
				anim_player.play("hakken")
			raycast_chop_tree()
			can_chop = false
			start_chop_cooldown()
	mouse_was_pressed = mouse_pressed

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

# ----------------------
# OTHER FUNCTIONS
# ----------------------
func add_log():
	logs += 1
	print("Logs:", logs)

func _ready() -> void:
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	capture_mouse()

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

func start_chop_cooldown() -> void:
	var timer = get_tree().create_timer(chop_cooldown)
	await timer.timeout
	can_chop = true

func raycast_chop_tree() -> void:
	var from := camera.global_position
	var to := from + -camera.global_transform.basis.z * chop_distance
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	if collider:
		query.exclude.append(collider)
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
