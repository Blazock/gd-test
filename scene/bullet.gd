class_name Bullet
extends Area2D

# World collision layer mask: used to detect walls/obstacles via raycast.
const WORLD_COLLISION_MASK := 1

@export var speed: float = 320.0
@export var max_lifetime: float = 2.0

var direction: Vector2 = Vector2.RIGHT
var remaining_lifetime: float = 0.0
var _playable_bounds: Rect2


func _ready() -> void:
	remaining_lifetime = max_lifetime
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	var current_position := global_position
	var next_position := current_position + direction * speed * delta

	# Pre-hit check: destroy bullet before it passes through a wall this frame.
	if _will_hit_world(current_position, next_position):
		queue_free()
		return

	global_position = next_position

	# Last resort: destroy if bullet somehow escapes the playable area.
	if not _playable_bounds.has_point(global_position):
		queue_free()
		return

	remaining_lifetime -= delta
	if remaining_lifetime <= 0.0:
		queue_free()


func setup(direction: Vector2, spawn_position: Vector2, bounds: Rect2) -> void:
	self.direction = direction.normalized()
	rotation = self.direction.angle()
	_playable_bounds = bounds
	global_position = _clamp_to_bounds(spawn_position, bounds)


# Raycasts ahead to see if the bullet would collide with a world obstacle.
# Prevents bullet from clipping through walls at high speed.
func _will_hit_world(from_position: Vector2, to_position: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(
		from_position,
		to_position,
		WORLD_COLLISION_MASK,
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hit_result: Dictionary = space_state.intersect_ray(query)
	return not hit_result.is_empty()


func _clamp_to_bounds(pos: Vector2, bounds: Rect2) -> Vector2:
	var top_left := bounds.position
	var bottom_right := bounds.position + bounds.size
	return Vector2(
		clampf(pos.x, top_left.x, bottom_right.x),
		clampf(pos.y, top_left.y, bottom_right.y),
	)


func _on_area_entered(area: Area2D) -> void:
	# Ignore collision with other bullets to avoid mutual destruction.
	if area is Bullet:
		return

	queue_free()
