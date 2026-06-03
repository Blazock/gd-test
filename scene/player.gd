extends CharacterBody2D
class_name Player

const NORMAL_ANIMATION_PREFIX := &"normal"
const ARMED_ANIMATION_PREFIX := &"armed"
const PLAYER_FORM_MODE_NORMAL := 0
const PLAYER_FORM_MODE_ARMED := 1

@onready var body_sprite: AnimatedSprite2D = $BodySprite
@onready var armed_effect_sprite: AnimatedSprite2D = $ArmedEffectSprite

var facing_suffix: StringName = &"right"
var _mouse_held: bool = false
var _mouse_direction: Vector2 = Vector2.RIGHT
var current_form_mode: int = PLAYER_FORM_MODE_NORMAL

@export var move_speed: float = 120.0


func _ready() -> void:
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

	if _mouse_held:
		_mouse_direction = (get_global_mouse_position() - global_position).normalized()

	_update_facing(move_input)
	_update_animation()
	_update_armed_effect()


func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [_get_animation_prefix(), facing_suffix])

	if not body_sprite.sprite_frames.has_animation(animation_name):
		push_warning("Missing player animation: %s" % animation_name)
		return

	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)


func _update_facing(move_input: Vector2) -> void:
	if _mouse_held:
		facing_suffix = _vector_to_facing_suffix(_mouse_direction)
	elif move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)


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
