class_name Player
extends CharacterBody2D

const NORMAL_ANIMATION_PREFIX := &"normal"
const ARMED_ANIMATION_PREFIX := &"armed"
const DEFAULT_MOVE_SPEED_MULTIPLER := 1.0
const DEFAULT_FIRE_RATE_MULTIPLER := 1.0
const SPIRAL_PHASE_STEP := PI / 12

@export var move_speed: float = 120.0
@export var bullet_scene: PackedScene
@export var bullet_spawn_distance: float = 18.0

var facing_suffix: StringName = &"right"
var last_move_direction: Vector2 = Vector2.RIGHT
var current_move_speed_multiplier: float = DEFAULT_MOVE_SPEED_MULTIPLER
var rapid_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLER
var form_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLER
var current_form_mode: int = PickupConfig.PlayerFormMode.NORMAL
var current_shot_pattern: int = PickupConfig.ShotPattern.NORMAL
var speed_buff_time_left: float = 0.0
var rapid_buff_time_left: float = 0.0
var form_buff_time_left: float = 0.0
var spiral_phase: float = 0.0
var fire_interval: float = 0.18
var _mouse_held: bool = false
var _mouse_direction: Vector2 = Vector2.RIGHT

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var armed_effect_sprite: AnimatedSprite2D = $ArmedEffectSprite
@onready var shooting_timer: Timer = $ShootingTimer


func _ready() -> void:
	shooting_timer.one_shot = true
	shooting_timer.wait_time = _get_effective_fire_interval()
	_update_animation()
	_update_armed_effect()


func _physics_process(delta: float) -> void:
	_update_pickup_effects(delta)

	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = move_input * _get_effective_move_speed()
	move_and_slide()

	if move_input != Vector2.ZERO:
		last_move_direction = move_input

	if _mouse_held:
		_mouse_direction = (get_global_mouse_position() - global_position).normalized()

	_update_facing(move_input)
	_update_animation()
	_update_armed_effect()

	# Spiral pattern fires automatically; normal pattern waits for input.
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		_try_auto_spiral_shoot()
	elif _mouse_held:
		_try_shoot(_mouse_direction)
	elif Input.is_action_pressed("shoot"):
		var dir := last_move_direction if last_move_direction != Vector2.ZERO else Vector2.RIGHT
		_try_shoot(dir.normalized())


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot") and event is InputEventMouseButton:
		_mouse_held = true
		_mouse_direction = (get_global_mouse_position() - global_position).normalized()
	elif event.is_action_released("shoot") and event is InputEventMouseButton:
		_mouse_held = false


func apply_pickup(config: PickupConfig) -> bool:
	if config == null:
		return false

	var applied := false
	var should_refresh_shooting_timer := false
	var buff_duration := maxf(config.duration, 0.0)
	var has_form_override := (
		config.player_form_mode != PickupConfig.PlayerFormMode.NORMAL
		or config.shot_pattern != PickupConfig.ShotPattern.NORMAL
	)
	var has_fire_rate_override := not is_equal_approx(
		config.fire_rate_multiplier,
		DEFAULT_FIRE_RATE_MULTIPLER,
	)

	if not is_equal_approx(config.move_speed_multiplier, DEFAULT_MOVE_SPEED_MULTIPLER):
		current_move_speed_multiplier = config.move_speed_multiplier
		speed_buff_time_left = buff_duration
		applied = true

	if has_fire_rate_override and not has_form_override:
		rapid_fire_rate_multiplier = config.fire_rate_multiplier
		rapid_buff_time_left = buff_duration
		should_refresh_shooting_timer = true
		applied = true

	if has_form_override:
		current_form_mode = config.player_form_mode
		current_shot_pattern = config.shot_pattern
		form_fire_rate_multiplier = (
			config.fire_rate_multiplier if has_fire_rate_override else DEFAULT_FIRE_RATE_MULTIPLER
		)
		form_buff_time_left = buff_duration
		spiral_phase = 0.0
		should_refresh_shooting_timer = true
		applied = true

	if should_refresh_shooting_timer:
		_refresh_shooting_timer_wait_time()
	return applied


func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [_get_animation_prefix(), facing_suffix])

	# Fall back to normal prefix if the current form's animation doesn't exist.
	if not body_sprite.sprite_frames.has_animation(animation_name):
		var fallback_animation_name := StringName(
			"%s_%s" % [NORMAL_ANIMATION_PREFIX, facing_suffix],
		)
		if not body_sprite.sprite_frames.has_animation(fallback_animation_name):
			push_warning("Missing player animation: %s" % animation_name)
			return
		animation_name = fallback_animation_name

	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)


# Facing direction priority: spiral mode ignores aim, otherwise mouse aim > move direction.
func _update_facing(move_input: Vector2) -> void:
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		if move_input != Vector2.ZERO:
			facing_suffix = _vector_to_facing_suffix(move_input)
		return

	if _mouse_held:
		facing_suffix = _vector_to_facing_suffix(_mouse_direction)
	elif move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)


func _try_shoot(shoot_input: Vector2) -> void:
	if not shooting_timer.is_stopped():
		return

	var shoot_direction := shoot_input.normalized()
	var has_spawned_bullet := _fire_bullets(shoot_direction)
	if has_spawned_bullet:
		shooting_timer.start(_get_effective_fire_interval())


# Normal pattern fires one bullet; spiral fires forward + backward with rotating phase.
func _fire_bullets(base_direction: Vector2) -> bool:
	if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
		var has_spawned_forward_bullet := _spawn_bullet(base_direction)
		var has_spawned_backward_bullet := _spawn_bullet(base_direction.rotated(PI))
		spiral_phase = wrapf(spiral_phase + SPIRAL_PHASE_STEP, 0.0, TAU)
		return has_spawned_forward_bullet or has_spawned_backward_bullet
	return _spawn_bullet(base_direction)


func _spawn_bullet(shoot_direction: Vector2) -> bool:
	var bullet := bullet_scene.instantiate() as Bullet
	if bullet == null:
		return false

	# Detach bullet from player's transform so it continues flying even if player moves.
	bullet.top_level = true

	var spawn_parent := get_tree().current_scene
	if spawn_parent == null:
		return false

	spawn_parent.add_child(bullet)
	bullet.setup(
		shoot_direction,
		global_position + shoot_direction * bullet_spawn_distance,
		_get_playable_bounds(spawn_parent),
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


# Automatic firing for spiral pattern — no input required.
func _try_auto_spiral_shoot() -> void:
	if not shooting_timer.is_stopped():
		return

	var spiral_direction := Vector2.RIGHT.rotated(spiral_phase)
	var has_spawned_bullet := _fire_bullets(spiral_direction)
	if has_spawned_bullet:
		shooting_timer.start(_get_effective_fire_interval())


func _update_pickup_effects(delta: float) -> void:
	if speed_buff_time_left > 0.0:
		speed_buff_time_left = maxf(speed_buff_time_left - delta, 0.0)
		if speed_buff_time_left <= 0.0:
			current_move_speed_multiplier = DEFAULT_MOVE_SPEED_MULTIPLER

	if rapid_buff_time_left > 0.0:
		rapid_buff_time_left = maxf(rapid_buff_time_left - delta, 0.0)
		if rapid_buff_time_left <= 0.0:
			rapid_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLER
			_refresh_shooting_timer_wait_time()

	if form_buff_time_left > 0.0:
		form_buff_time_left = maxf(form_buff_time_left - delta, 0.0)
		if form_buff_time_left <= 0.0:
			current_form_mode = PickupConfig.PlayerFormMode.NORMAL
			current_shot_pattern = PickupConfig.ShotPattern.NORMAL
			form_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLER
			spiral_phase = 0.0
			_refresh_shooting_timer_wait_time()


func _get_effective_move_speed() -> float:
	return move_speed * current_move_speed_multiplier


func _get_effective_fire_interval() -> float:
	return maxf(fire_interval / _get_effective_fire_rate_multiplier(), 0.01)


# When a form/pattern override is active, use form_fire_rate_multiplier; otherwise use rapid_fire.
func _get_effective_fire_rate_multiplier() -> float:
	if _has_active_form_override():
		return maxf(form_fire_rate_multiplier, 0.01)
	return maxf(rapid_fire_rate_multiplier, 0.01)


func _has_active_form_override() -> bool:
	return (
		current_form_mode != PickupConfig.PlayerFormMode.NORMAL
		or current_shot_pattern != PickupConfig.ShotPattern.NORMAL
	)


func _refresh_shooting_timer_wait_time() -> void:
	var new_interval := _get_effective_fire_interval()
	shooting_timer.wait_time = new_interval

	if shooting_timer.is_stopped():
		return
	if shooting_timer.time_left <= new_interval:
		return

	shooting_timer.start(new_interval)


func _get_animation_prefix() -> StringName:
	if current_form_mode == PickupConfig.PlayerFormMode.ARMED:
		return ARMED_ANIMATION_PREFIX
	return NORMAL_ANIMATION_PREFIX


func _update_armed_effect() -> void:
	var is_armed := current_form_mode == PickupConfig.PlayerFormMode.ARMED

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


# Converts an 8-direction vector to a 4-direction suffix for animation lookup.
# Uses the dominant axis (abs larger) to pick right/left vs up/down.
func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
	return &"down" if direction.y > 0.0 else &"up"
