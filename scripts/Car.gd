class_name DriftCar
extends CharacterBody3D

signal crashed(impact_speed: float)

const ENGINE_POWER := 42.0
const REVERSE_POWER := 16.0
const BRAKE_POWER := 55.0
const MAX_SPEED := 46.0
const STEER_RATE := 2.5
const BASE_GRIP := 10.0
const DRIFT_GRIP := 2.2
const DRAG := 0.018
const ROLL_FRICTION := 1.4
const GRAVITY := 30.0

var spawn_transform: Transform3D
var is_drifting := false
var drift_angle := 0.0
var flat_speed := 0.0

var _body_root: Node3D
var _wheel_fl: Node3D
var _wheel_fr: Node3D
var _smoke_l: GPUParticles3D
var _smoke_r: GPUParticles3D
var _steer_visual := 0.0
var _steer := 0.0
var _ground_n := Vector3.UP
var _air_time := 0.0

func _ready() -> void:
	spawn_transform = global_transform
	floor_snap_length = 2.5
	floor_constant_speed = true
	_build_visuals()
	_build_collision()
	_build_smoke()

func _physics_process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_R) or global_position.y < -20.0:
		respawn()
		return

	var throttle := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var brake := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var handbrake := Input.is_physical_key_pressed(KEY_SPACE)
	var steer_input := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		steer_input += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		steer_input -= 1.0

	# Pitch/roll the chassis to follow the terrain so thrust runs along
	# the slope instead of digging into it. Brief airtime (bumps, crests)
	# keeps the last ground normal and full grip — "coyote time" — so the
	# car doesn't flicker between grounded and airborne handling.
	var near_ground := false
	if is_on_floor():
		_ground_n = get_floor_normal()
		_air_time = 0.0
	else:
		_air_time += delta
		# Skimming over heightmap facet ridges at speed counts as driving:
		# probe a short ray down to keep terrain alignment and grip.
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP, global_position + Vector3.DOWN * 2.5)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit:
			near_ground = true
			_ground_n = hit.normal
	var grounded := is_on_floor() or near_ground or _air_time < 0.25
	var ground_n := _ground_n if (grounded or _air_time < 0.6) else Vector3.UP
	_align_to_ground(ground_n, grounded, delta)

	var up := global_transform.basis.y
	var forward := -global_transform.basis.z
	var plane_vel := velocity - ground_n * velocity.dot(ground_n)
	var fwd_speed := plane_vel.dot(forward)

	# Keyboard steering is smoothed (~0.2s to full lock, faster release)
	# so taps allow fine corrections instead of instant full lock.
	var attack := 5.0 if absf(steer_input) > 0.05 else 9.0
	_steer = move_toward(_steer, steer_input, attack * delta)

	# Steering authority ramps up with speed so the car can't pivot in place.
	var steer_strength := clampf(absf(fwd_speed) / 9.0, 0.0, 1.0)
	if is_drifting:
		# Bonus authority to hold a slide, tapering off at big slip angles
		# so the car can't wind itself into a flat spin.
		steer_strength *= 1.25 * clampf(1.0 - (drift_angle - 0.55) / 0.9, 0.4, 1.0)
	var steer_dir := 1.0 if fwd_speed >= -0.5 else -1.0
	global_transform.basis = global_transform.basis.rotated(
		up, _steer * STEER_RATE * steer_strength * steer_dir * delta).orthonormalized()

	# Alignment assist: the nose pulls back toward the velocity direction,
	# strongly when steering is released, so slides straighten out instead
	# of tightening into a spin.
	if drift_angle > 0.2 and plane_vel.length() > 4.0:
		var align_rate := 1.0 if absf(_steer) < 0.1 else 0.35
		var cy := (-global_transform.basis.z).cross(plane_vel.normalized()).dot(up)
		global_transform.basis = global_transform.basis.rotated(
			up, signf(cy) * minf(drift_angle, 1.0) * align_rate * delta).orthonormalized()
	forward = -global_transform.basis.z

	if throttle:
		velocity += forward * ENGINE_POWER * delta
	if brake:
		if fwd_speed > 1.0:
			velocity -= forward * BRAKE_POWER * delta
		else:
			velocity -= forward * REVERSE_POWER * delta

	velocity += Vector3.DOWN * GRAVITY * delta
	if is_on_floor():
		# The ground supports the car: cancel velocity into the floor,
		# then press lightly along the normal so snapping holds.
		var into := velocity.dot(ground_n)
		if into < 0.0:
			velocity -= ground_n * into
		velocity -= ground_n * 2.0 * delta

	plane_vel = velocity - ground_n * velocity.dot(ground_n)
	fwd_speed = plane_vel.dot(forward)
	var lateral := plane_vel - forward * fwd_speed
	flat_speed = plane_vel.length()

	drift_angle = 0.0
	if flat_speed > 4.0 and fwd_speed > 0.0:
		drift_angle = forward.angle_to(plane_vel / flat_speed)

	var grip := BASE_GRIP
	if handbrake:
		grip = DRIFT_GRIP
	elif drift_angle > 0.18:
		# Once sliding, grip eases off so drifts sustain instead of snapping straight.
		grip = lerpf(BASE_GRIP, DRIFT_GRIP, clampf(drift_angle / 0.9, 0.0, 0.85))
	if not grounded:
		grip = 0.0
	velocity -= lateral * clampf(grip * delta, 0.0, 1.0)

	if grounded:
		velocity -= plane_vel.limit_length(ROLL_FRICTION * delta)
		if handbrake:
			velocity -= plane_vel.limit_length(4.0 * delta)
	velocity -= plane_vel * clampf(DRAG * flat_speed * delta, 0.0, 1.0)

	plane_vel = velocity - ground_n * velocity.dot(ground_n)
	if plane_vel.length() > MAX_SPEED:
		velocity -= plane_vel - plane_vel.limit_length(MAX_SPEED)

	var pre_speed := plane_vel.length()
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().y < 0.5:
			var post := velocity - ground_n * velocity.dot(ground_n)
			var lost := pre_speed - post.length()
			if lost > 8.0:
				crashed.emit(lost)

	flat_speed = (velocity - ground_n * velocity.dot(ground_n)).length()
	is_drifting = drift_angle > 0.26 and flat_speed > 7.0 and grounded

	_smoke_l.emitting = is_drifting
	_smoke_r.emitting = is_drifting
	_update_visuals(_steer, lateral, delta)

func respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	is_drifting = false
	drift_angle = 0.0
	flat_speed = 0.0
	_steer = 0.0

func _align_to_ground(n: Vector3, grounded: bool, delta: float) -> void:
	var rate := 12.0 if grounded else 2.5
	var w := 1.0 - exp(-rate * delta)
	var new_up := global_transform.basis.y.slerp(n, w).normalized()
	var x_axis := new_up.cross(global_transform.basis.z)
	if x_axis.length_squared() < 0.25:
		return
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(new_up).normalized()
	global_transform.basis = Basis(x_axis, new_up, z_axis)

func _update_visuals(steer_input: float, lateral: Vector3, delta: float) -> void:
	_steer_visual = lerpf(_steer_visual, steer_input * 0.45, 1.0 - exp(-10.0 * delta))
	_wheel_fl.rotation.y = _steer_visual
	_wheel_fr.rotation.y = _steer_visual
	var right := global_transform.basis.x
	var lat_amount := clampf(lateral.dot(right) * 0.012, -0.12, 0.12)
	_body_root.rotation.z = lerpf(_body_root.rotation.z, lat_amount, 1.0 - exp(-8.0 * delta))

func _build_visuals() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.95, 0.32, 0.12)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.35

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.08, 0.08, 0.1)
	dark_mat.roughness = 0.6

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.1, 0.12, 0.18)
	glass_mat.metallic = 0.8
	glass_mat.roughness = 0.1

	var chassis := MeshInstance3D.new()
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(1.8, 0.5, 3.8)
	chassis.mesh = chassis_mesh
	chassis.material_override = body_mat
	chassis.position = Vector3(0, 0.55, 0)
	_body_root.add_child(chassis)

	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.5, 0.45, 1.8)
	cabin.mesh = cabin_mesh
	cabin.material_override = glass_mat
	cabin.position = Vector3(0, 1.0, 0.25)
	_body_root.add_child(cabin)

	var spoiler := MeshInstance3D.new()
	var spoiler_mesh := BoxMesh.new()
	spoiler_mesh.size = Vector3(1.7, 0.08, 0.4)
	spoiler.mesh = spoiler_mesh
	spoiler.material_override = dark_mat
	spoiler.position = Vector3(0, 1.05, 1.75)
	_body_root.add_child(spoiler)

	var light_mat := StandardMaterial3D.new()
	light_mat.albedo_color = Color(1.0, 0.95, 0.7)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1.0, 0.9, 0.6)
	light_mat.emission_energy_multiplier = 2.0

	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(1.0, 0.1, 0.15)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.1)
	tail_mat.emission_energy_multiplier = 2.5

	for side in [-1.0, 1.0]:
		var head := MeshInstance3D.new()
		var head_mesh := BoxMesh.new()
		head_mesh.size = Vector3(0.35, 0.15, 0.05)
		head.mesh = head_mesh
		head.material_override = light_mat
		head.position = Vector3(0.6 * side, 0.6, -1.9)
		_body_root.add_child(head)

		var tail := MeshInstance3D.new()
		var tail_mesh := BoxMesh.new()
		tail_mesh.size = Vector3(0.45, 0.15, 0.05)
		tail.mesh = tail_mesh
		tail.material_override = tail_mat
		tail.position = Vector3(0.55 * side, 0.62, 1.92)
		_body_root.add_child(tail)

	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.36
	wheel_mesh.bottom_radius = 0.36
	wheel_mesh.height = 0.3
	for w in [
		{"pos": Vector3(-0.85, 0.36, -1.25), "front": true, "left": true},
		{"pos": Vector3(0.85, 0.36, -1.25), "front": true, "left": false},
		{"pos": Vector3(-0.85, 0.36, 1.25), "front": false, "left": true},
		{"pos": Vector3(0.85, 0.36, 1.25), "front": false, "left": false},
	]:
		var pivot := Node3D.new()
		pivot.position = w["pos"]
		_body_root.add_child(pivot)
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.material_override = dark_mat
		wheel.rotation.z = PI / 2.0
		pivot.add_child(wheel)
		if w["front"]:
			if w["left"]:
				_wheel_fl = pivot
			else:
				_wheel_fr = pivot

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 1.0, 3.8)
	col.shape = shape
	col.position = Vector3(0, 0.62, 0)
	add_child(col)

func _build_smoke() -> void:
	for side in [-1.0, 1.0]:
		var p := GPUParticles3D.new()
		p.amount = 40
		p.lifetime = 1.0
		p.local_coords = false
		p.emitting = false
		p.position = Vector3(0.8 * side, 0.2, 1.5)

		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 30.0
		mat.initial_velocity_min = 1.0
		mat.initial_velocity_max = 2.5
		mat.gravity = Vector3(0, 1.5, 0)
		mat.scale_min = 0.7
		mat.scale_max = 1.6
		var grad := Gradient.new()
		grad.set_color(0, Color(0.9, 0.9, 0.95, 0.45))
		grad.set_color(1, Color(0.9, 0.9, 0.95, 0.0))
		var grad_tex := GradientTexture1D.new()
		grad_tex.gradient = grad
		mat.color_ramp = grad_tex
		p.process_material = mat

		var puff := SphereMesh.new()
		puff.radius = 0.18
		puff.height = 0.36
		var puff_mat := StandardMaterial3D.new()
		puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_mat.vertex_color_use_as_albedo = true
		puff.material = puff_mat
		p.draw_pass_1 = puff

		add_child(p)
		if side < 0.0:
			_smoke_l = p
		else:
			_smoke_r = p
