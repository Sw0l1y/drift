class_name ChaseCamera
extends Camera3D

const DISTANCE := 8.0
const HEIGHT := 3.4

var target: DriftCar

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var fwd := -target.global_transform.basis.z
	var vel := Vector3(target.velocity.x, 0.0, target.velocity.z)
	# Blend toward the velocity direction so the camera swings wide during drifts.
	var look_dir := fwd
	if vel.length() > 4.0:
		look_dir = fwd.lerp(vel.normalized(), 0.45).normalized()
	var desired := target.global_position - look_dir * DISTANCE + Vector3.UP * HEIGHT
	# Keep the camera above the terrain on crests and hillsides.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(desired + Vector3.UP * 30.0, desired - Vector3.UP * 10.0)
	query.exclude = [target.get_rid()]
	var hit := space.intersect_ray(query)
	if hit and desired.y < hit.position.y + 1.6:
		desired.y = hit.position.y + 1.6
	global_position = global_position.lerp(desired, 1.0 - exp(-6.0 * delta))
	var focus := target.global_position + Vector3.UP * 1.0
	if global_position.distance_to(focus) > 0.5:
		look_at(focus)
	fov = lerpf(fov, 70.0 + vel.length() * 0.5, 1.0 - exp(-3.0 * delta))

func snap_to_target() -> void:
	if target == null:
		return
	var fwd := -target.global_transform.basis.z
	global_position = target.global_position - fwd * DISTANCE + Vector3.UP * HEIGHT
	look_at(target.global_position + Vector3.UP * 1.0)
