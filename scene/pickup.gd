extends Area2D
class_name Pickup

const BLINK_ENABLED_SHADER_PARAMETER := &"blink_enabled"

@export var config: PickupConfig
# Seconds before lifetime ends to start the blink warning.
@export_range(0.0, 10.0, 0.1, "or_greater") var blink_before_expire: float = 1.2

@onready var sprite: Sprite2D = $Sprite2D
@onready var lifetime_timer: Timer = $LifetimeTimer

var is_expiring: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	lifetime_timer.timeout.connect(_on_lifetime_timer_timeout)
	lifetime_timer.one_shot = true
	if lifetime_timer.wait_time > 0.0:
		lifetime_timer.start()
	_set_blink_enabled(false)
	_apply_config_to_visual()


# Start blinking when remaining lifetime drops below the threshold.
func _process(delta: float) -> void:
	if is_expiring:
		return
	if lifetime_timer.is_stopped():
		return
	if lifetime_timer.time_left > blink_before_expire:
		return

	is_expiring = true
	_set_blink_enabled(true)


func _apply_config_to_visual() -> void:
	if config == null:
		push_warning("Pickup config is missing.")
		return
	sprite.texture = config.icon_texture


func _on_body_entered(body: Node2D) -> void:
	if config == null:
		return

	# Only the player can pick up items.
	var player := body as Player
	if player == null:
		return

	if player.apply_pickup(config):
		queue_free()


func _on_lifetime_timer_timeout() -> void:
	queue_free()


# Toggle the blink shader parameter to show/hide the visual warning.
func _set_blink_enabled(enabled: bool) -> void:
	var sprite_material := sprite.material as ShaderMaterial
	if sprite_material != null:
		sprite_material.set_shader_parameter(BLINK_ENABLED_SHADER_PARAMETER, enabled)
