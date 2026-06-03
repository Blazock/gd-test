extends CharacterBody2D
class_name Player

const NORMAL_ANIMATION_PREFIX := &"normal"
const ARMED_ANIMATION_PREFIX := &"armed"
const PLAYER_FORM_MODE_NORMAL := 0
const PLAYER_FORM_MODE_ARMED := 1
const SPIRAL_PHASE_STEP := PI / 12

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var armed_effect_sprite: AnimatedSprite2D = $ArmedEffectSprite
@onready var shooting_timer: Timer = $ShootingTimer

var facing_suffix: StringName = &"right"
var last_move_direction: Vector2 = Vector2.RIGHT
var _mouse_held: bool = false
var _mouse_direction: Vector2 = Vector2.RIGHT
var current_form_mode: int = PLAYER_FORM_MODE_NORMAL
var spiral_phase: float = 0.0
var fire_interval: float = 0.18

@export var move_speed: float = 120.0
@export var bullet_scene: PackedScene
@export var bullet_spawn_distance: float = 18.0


func _ready() -> void:
	shooting_timer.one_shot = true
	shooting_timer.wait_time = fire_interval
	_update_animation()
	_update_armed_effect()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot") and event is InputEventMouseButton:
		_mouse_held = true
		_mouse_direction = (get_global_mouse_position() - global_position).normalized()
	elif event.is_action_released("shoot") and event is InputEventMouseButton:
		_mouse_held = false


func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = move_input * move_speed
	move_and_slide()

	if move_input != Vector2.ZERO:
		last_move_direction = move_input

	if _mouse_held:
		_mouse_direction = (get_global_mouse_position() - global_position).normalized()

	_update_facing(move_input)
	_update_animation()
	_update_armed_effect()

	if _mouse_held:
		_try_shoot(_mouse_direction)
	elif Input.is_action_pressed("shoot"):
		var dir := last_move_direction if last_move_direction != Vector2.ZERO else Vector2.RIGHT
		_try_shoot(dir.normalized())


func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [_get_animation_prefix(), facing_suffix])

	if not body_sprite.sprite_frames.has_animation(animation_name):
		push_warning("Missing player animation: %s" % animation_name)
		return

	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)


func _update_facing(move_input: Vector2) -> void:
	if current_form_mode == PLAYER_FORM_MODE_ARMED:
		if move_input != Vector2.ZERO:
			facing_suffix = _vector_to_facing_suffix(move_input)
		return

	if _mouse_held:
		facing_suffix = _vector_to_facing_suffix(_mouse_direction)
	elif move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)


func _try_shoot(direction: Vector2) -> void:
	if not shooting_timer.is_stopped():
		return

	var shoot_direction := direction.normalized()
	var has_spawned_bullet := _spawn_bullet(shoot_direction)
	if has_spawned_bullet:
		shooting_timer.start(fire_interval)


func _spawn_bullet(shoot_direction: Vector2) -> bool:
	var bullet := bullet_scene.instantiate() as Bullet
	if bullet == null:
		return false

	bullet.top_level = true

	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		return false

	spawn_parent.add_child(bullet)
	bullet.setup(
		shoot_direction,
		global_position + shoot_direction * bullet_spawn_distance,
		_get_playable_bounds(spawn_parent)
	)
	return true


func _get_playable_bounds(root: Node) -> Rect2:
	var world_bounds := root.get_node_or_null("WorldBounds")
	if world_bounds == null:
		return Rect2(-INF, -INF, INF * 2, INF * 2)

	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF

	for child in world_bounds.get_children():
		var shape_node := child.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node == null or shape_node.shape is not SegmentShape2D:
			continue
		var segment := shape_node.shape as SegmentShape2D
		var a_global := shape_node.global_position + segment.a
		var b_global := shape_node.global_position + segment.b
		min_x = minf(min_x, minf(a_global.x, b_global.x))
		min_y = minf(min_y, minf(a_global.y, b_global.y))
		max_x = maxf(max_x, maxf(a_global.x, b_global.x))
		max_y = maxf(max_y, maxf(a_global.y, b_global.y))

	if min_x == INF:
		return Rect2(-INF, -INF, INF * 2, INF * 2)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _get_animation_prefix() -> StringName:
	if current_form_mode == PLAYER_FORM_MODE_ARMED:
		return ARMED_ANIMATION_PREFIX
	return NORMAL_ANIMATION_PREFIX


func _update_armed_effect() -> void:
	var is_armed := current_form_mode == PLAYER_FORM_MODE_ARMED

	if not is_armed:
		if armed_effect_sprite.visible:
			armed_effect_sprite.visible = false

		if armed_effect_sprite.is_playing():
			armed_effect_sprite.stop()
		return
	if not armed_effect_sprite.visible:
		armed_effect_sprite.visible = true
	if armed_effect_sprite.is_playing():
		return
	if armed_effect_sprite.sprite_frames == null:
		return
	if armed_effect_sprite.sprite_frames.has_animation(&"default"):
		armed_effect_sprite.play(&"default")


func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
	return &"down" if direction.y > 0.0 else &"up"
