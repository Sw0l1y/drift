class_name ChaseCamera
extends Camera3D

# Untyped: any Garage car (duck-typed contract — vel3, cam_distance, …).
var target

func _physics_process(delta: float) -> void:
	if target == null:
		return
	# Flatten the car's forward — the chassis pitches with terrain,
	# and the camera should stay level rather than dive on slopes.
	var xform: Transform3D = target.global_transform
	var fwd := -xform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var vel: Vector3 = target.vel3()
	vel.y = 0.0
	# Blend toward the velocity direction so the camera swings wide during drifts.
	var look_dir := fwd
	if vel.length() > 4.0:
		look_dir = fwd.lerp(vel.normalized(), 0.45).normalized()
	var tpos: Vector3 = target.global_position
	var desired: Vector3 = tpos - look_dir * float(target.cam_distance) + Vector3.UP * float(target.cam_height)
	# Keep the camera above the terrain on crests and hillsides.
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(desired + Vector3.UP * 30.0, desired - Vector3.UP * 10.0)
	query.exclude = [target.get_rid()]
	var hit := space.intersect_ray(query)
	if hit and desired.y < hit.position.y + 1.6:
		desired.y = hit.position.y + 1.6
	global_position = global_position.lerp(desired, 1.0 - exp(-6.0 * delta))
	var focus: Vector3 = target.global_position + Vector3.UP * 1.0
	if global_position.distance_to(focus) > 0.5:
		look_at(focus)
	fov = lerpf(fov, 70.0 + vel.length() * 0.5, 1.0 - exp(-3.0 * delta))

func snap_to_target() -> void:
	if target == null:
		return
	var xform: Transform3D = target.global_transform
	var fwd := -xform.basis.z
	var tpos: Vector3 = target.global_position
	global_position = tpos - fwd * float(target.cam_distance) + Vector3.UP * float(target.cam_height)
	look_at(tpos + Vector3.UP * 1.0)
