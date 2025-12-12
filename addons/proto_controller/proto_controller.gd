extends CharacterBody3D

@export var can_move: bool = true
@export var has_gravity: bool = true
@export var can_jump: bool = true
@export var can_sprint: bool = true
@export var can_freefly: bool = false

@export var pickup_distance: float = 5.0
@export var base_throw_strength: float = 12.0

@export var min_hold_distance: float = 0.8
@export var max_hold_distance: float = 5.0
@export var scroll_sensitivity: float = 0.4
@export var hold_lerp_speed: float = 12.0

@export var look_speed: float = 0.002
@export var base_speed: float = 7.0
@export var sprint_speed: float = 11.0
@export var jump_velocity: float = 8.0
@export var freefly_speed: float = 25.0

@export var input_left: String = "left"
@export var input_right: String = "right"
@export var input_forward: String = "forward"
@export var input_back: String = "backwards"
@export var input_jump: String = "ui_accept"
@export var input_sprint: String = "sprint"
@export var input_freefly: String = "freefly"
@export var input_pickup: String = "Interact"
@export var input_throw: String = "Throw"

@export var chop_distance: float = 3.5
var chop_cooldown: float = 2.8
var can_chop: bool = true

@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var collider: CollisionShape3D = $Collider
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var pickup_raycast: RayCast3D = $Head/Camera3D/RayCast3D
@onready var pickup_hand: Node3D = $Head/Camera3D/Hand

var mouse_captured: bool = false
var look_rotation: Vector2 = Vector2.ZERO
var freeflying: bool = false
var mouse_was_pressed: bool = false

var picked_object: RigidBody3D = null
var target_hold_distance: float = 2.5
var current_hold_distance: float = 2.5
var logs: int = 0

const LAYER_PLAYER: int = 1 << (2 - 1)
const LAYER_HELD:   int = 1 << (4 - 1)

func _ready() -> void:
	look_rotation.y = rotation.y
	look_rotation.x = head.rotation.x
	capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and picked_object and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_hold_distance = clamp(target_hold_distance - scroll_sensitivity, min_hold_distance, max_hold_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_hold_distance = clamp(target_hold_distance + scroll_sensitivity, min_hold_distance, max_hold_distance)
			get_viewport().set_input_as_handled()

	if event.is_action_pressed(input_pickup):
		if picked_object:
			drop_object()
		else:
			var col = pickup_raycast.get_collider()
			if col:
				pick_up_object_from_collider(col)

	if event.is_action_pressed(input_throw) and picked_object:
		throw_object()

	if can_freefly and event.is_action_just_pressed(input_freefly):
		freeflying = !freeflying
		if freeflying: enable_freefly()
		else: disable_freefly()

	if event.is_action_pressed("ui_cancel"):
		release_mouse()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not mouse_captured and not picked_object:
		capture_mouse()

	if mouse_captured and event is InputEventMouseMotion:
		rotate_look(event.relative)

func _process(delta: float) -> void:
	if picked_object and is_instance_valid(picked_object):
		current_hold_distance = lerp(current_hold_distance, target_hold_distance, hold_lerp_speed * delta)
		update_held_object_position()

	var mouse_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if mouse_pressed and not mouse_was_pressed and can_chop and not picked_object:
		if anim_player and not anim_player.is_playing():
			anim_player.play("hakken")
		raycast_chop_tree()
		can_chop = false
		start_chop_cooldown()
	mouse_was_pressed = mouse_pressed

func _physics_process(delta: float) -> void:
	if can_freefly and freeflying:
		var input_dir = Input.get_vector(input_left, input_right, input_forward, input_back)
		var dir = (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		move_and_collide(dir * freefly_speed * delta)
		return

	if has_gravity and not is_on_floor():
		velocity += get_gravity() * delta

	if can_jump and Input.is_action_just_pressed(input_jump) and is_on_floor():
		velocity.y = jump_velocity

	var speed = sprint_speed if (can_sprint and Input.is_action_pressed(input_sprint)) else base_speed

	if can_move:
		var input_dir = Input.get_vector(input_left, input_right, input_forward, input_back)
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
	else:
		velocity.x = 0
		velocity.z = 0

	move_and_slide()


# —————————————————————————————
# PICKUP SYSTEM
# —————————————————————————————

func _find_rigid_body_from_node(node: Node) -> RigidBody3D:
	var n = node
	while n != null:
		if n is RigidBody3D:
			return n
		n = n.get_parent()
	return null

func pick_up_object_from_collider(collider_node: Node) -> void:
	if not collider_node: return
	var body = _find_rigid_body_from_node(collider_node)
	if not body or body == picked_object: return
	if global_position.distance_to(body.global_position) > pickup_distance: return
	pick_up_object(body)

func pick_up_object(body: RigidBody3D) -> void:
	if not body or not body.is_inside_tree(): return

	body.set_meta("orig_layer", body.collision_layer)
	body.set_meta("orig_mask",  body.collision_mask)

	body.set_deferred("collision_layer", LAYER_HELD)
	body.set_deferred("collision_mask", body.collision_mask & ~LAYER_PLAYER)

	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

	var old_transform = body.global_transform
	if body.get_parent():
		body.get_parent().remove_child(body)
	pickup_hand.add_child(body)
	body.global_transform = old_transform

	target_hold_distance = 2.5
	current_hold_distance = 2.5
	picked_object = body


# —————————————————————————————
# FIXED: NO WALL-CLIPPING WHILE HELD
# —————————————————————————————

func update_held_object_position() -> void:
	if not picked_object or not is_instance_valid(picked_object):
		return

	var cam = camera.global_transform
	var from = cam.origin
	var to = from + (-cam.basis.z * current_hold_distance)

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self, picked_object]

	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		# place object slightly in front of the wall
		to = hit.position + hit.normal * 0.15

	picked_object.global_position = to


# —————————————————————————————

func drop_object() -> void:
	if not picked_object: return
	var t = picked_object.global_transform
	pickup_hand.remove_child(picked_object)
	get_tree().current_scene.add_child(picked_object)
	picked_object.global_transform = t
	_restore_original_collision(picked_object)
	picked_object.freeze = false
	picked_object = null

func throw_object() -> void:
	if not picked_object: return
	var t = picked_object.global_transform
	pickup_hand.remove_child(picked_object)
	get_tree().current_scene.add_child(picked_object)
	picked_object.global_transform = t
	_restore_original_collision(picked_object)
	picked_object.freeze = false

	var dir = -camera.global_transform.basis.z.normalized()
	var force = base_throw_strength
	if picked_object.mass > 1.0:
		force /= picked_object.mass
	picked_object.apply_central_impulse(dir * force)
	picked_object = null

func _restore_original_collision(body: RigidBody3D) -> void:
	if body.has_meta("orig_layer"):
		body.set_deferred("collision_layer", body.get_meta("orig_layer"))
		body.set_deferred("collision_mask",  body.get_meta("orig_mask"))
		body.remove_meta("orig_layer")
		body.remove_meta("orig_mask")


# —————————————————————————————
# UTILS
# —————————————————————————————

func rotate_look(input: Vector2) -> void:
	look_rotation.x -= input.y * look_speed
	look_rotation.x = clamp(look_rotation.x, deg_to_rad(-85), deg_to_rad(85))
	look_rotation.y -= input.x * look_speed
	rotation.y = look_rotation.y
	head.rotation.x = look_rotation.x

func enable_freefly() -> void:
	collider.disabled = true
	freeflying = true
	velocity = Vector3.ZERO

func disable_freefly() -> void:
	collider.disabled = false
	freeflying = false

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false

func start_chop_cooldown() -> void:
	await get_tree().create_timer(chop_cooldown).timeout
	can_chop = true

func raycast_chop_tree() -> void:
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * chop_distance)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]
	if collider: query.exclude.append(collider)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty(): return
	var node = result.collider
	while node:
		if node.is_in_group("trees") and node.has_method("damage"):
			node.damage(1)
			return
		node = node.get_parent()

func add_log() -> void:
	logs += 1
	print("Logs:", logs)
