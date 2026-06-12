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

func _ready() -> void:
	spawn_transform = global_transform
	_build_visuals()
	_build_collision()
	_build_smoke()

func _physics_process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_R):
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

	var forward := -global_transform.basis.z
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	var fwd_speed := flat_vel.dot(forward)

	# Steering authority ramps up with speed so the car can't pivot in place,
	# and gets a bonus while drifting so slides stay controllable.
	var steer_strength := clampf(absf(fwd_speed) / 9.0, 0.0, 1.0)
	if is_drifting:
		steer_strength *= 1.3
	var steer_dir := 1.0 if fwd_speed >= -0.5 else -1.0
	rotate_y(steer_input * STEER_RATE * steer_strength * steer_dir * delta)
	forward = -global_transform.basis.z

	if throttle:
		flat_vel += forward * ENGINE_POWER * delta
	if brake:
		if fwd_speed > 1.0:
			flat_vel -= forward * BRAKE_POWER * delta
		else:
			flat_vel -= forward * REVERSE_POWER * delta

	fwd_speed = flat_vel.dot(forward)
	var lateral := flat_vel - forward * fwd_speed
	flat_speed = flat_vel.length()

	drift_angle = 0.0
	if flat_speed > 4.0 and fwd_speed > 0.0:
		drift_angle = forward.angle_to(flat_vel / flat_speed)

	var grip := BASE_GRIP
	if handbrake:
		grip = DRIFT_GRIP
	elif drift_angle > 0.18:
		# Once sliding, grip eases off so drifts sustain instead of snapping straight.
		grip = lerpf(BASE_GRIP, DRIFT_GRIP, clampf(drift_angle / 0.9, 0.0, 0.85))
	flat_vel -= lateral * clampf(grip * delta, 0.0, 1.0)

	flat_vel = flat_vel.move_toward(Vector3.ZERO, ROLL_FRICTION * delta)
	flat_vel -= flat_vel * clampf(DRAG * flat_speed * delta, 0.0, 1.0)
	if handbrake:
		flat_vel = flat_vel.move_toward(Vector3.ZERO, 4.0 * delta)
	flat_vel = flat_vel.limit_length(MAX_SPEED)

	velocity.x = flat_vel.x
	velocity.z = flat_vel.z
	velocity.y -= GRAVITY * delta

	var pre_speed := flat_vel.length()
	move_and_slide()

	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var normal := col.get_normal()
		if normal.y < 0.5:
			var collider := col.get_collider()
			if collider is RigidBody3D:
				collider.apply_central_impulse(-normal * maxf(pre_speed, 4.0) * 0.9)
				collider.apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * pre_speed * 0.4)
			else:
				var lost := pre_speed - Vector3(velocity.x, 0.0, velocity.z).length()
				if lost > 8.0:
					crashed.emit(lost)

	flat_speed = Vector3(velocity.x, 0.0, velocity.z).length()
	is_drifting = drift_angle > 0.26 and flat_speed > 7.0 and is_on_floor()

	_smoke_l.emitting = is_drifting
	_smoke_r.emitting = is_drifting
	_update_visuals(steer_input, lateral, delta)

func respawn() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	is_drifting = false
	drift_angle = 0.0
	flat_speed = 0.0

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
