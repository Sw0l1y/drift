class_name PrerunnerTruck
extends RigidBody3D

# Physically simulated offroad truck — no kinematic tricks. Each wheel is
# a raycast suspension (spring + damper) applying real forces to the body;
# tire traction is computed per contact from slip velocity and clamped by
# a friction limit proportional to that wheel's instantaneous load, so
# weight transfer, wheelspin and body roll emerge from the simulation.

signal crashed(impact_speed: float)

const TRUCK_MASS := 1400.0
const ENGINE_FORCE := 24000.0
const TOP_SPEED := 44.0
const BRAKE_FORCE := 20000.0
const REVERSE_FORCE := 11000.0
const STEER_MAX := 0.55
const SPRING_K := 26000.0        # N/m per wheel
const SPRING_DAMP := 2400.0      # Ns/m per wheel
const REST_LEN := 0.85           # suspension travel
const WHEEL_RADIUS := 0.55
const MU_LAT := 1.15
const MU_LONG := 1.3
const QUARTER_MASS := TRUCK_MASS / 4.0

var flat_speed := 0.0
var drift_angle := 0.0
var is_drifting := false
var cone_reach := 2.9
var cam_distance := 10.0
var cam_height := 4.4
var spawn_transform: Transform3D

var _wheels: Array[Dictionary] = []
var _steer := 0.0
var _grounded := false
var _prev_speed := 0.0
var _flip_timer := 0.0
var _smoke_l: GPUParticles3D
var _smoke_r: GPUParticles3D

func _ready() -> void:
	spawn_transform = global_transform
	mass = TRUCK_MASS
	gravity_scale = 1.8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.5, 0.05)
	angular_damp = 0.8
	linear_damp = 0.0
	continuous_cd = true
	can_sleep = false

	var phys := PhysicsMaterial.new()
	phys.friction = 0.4
	phys.bounce = 0.0
	physics_material_override = phys

	for hp in [
		{"pos": Vector3(-0.98, 0.1, -1.55), "steer": true},
		{"pos": Vector3(0.98, 0.1, -1.55), "steer": true},
		{"pos": Vector3(-0.98, 0.1, 1.55), "steer": false},
		{"pos": Vector3(0.98, 0.1, 1.55), "steer": false},
	]:
		_wheels.append({
			"pos": hp["pos"], "steer": hp["steer"],
			"prev_comp": 0.0, "grounded": false, "load": 0.0,
			"pivot": null, "spinner": null,
		})

	_build_collision()
	_build_visuals()
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

	var up := global_transform.basis.y
	var fwd_flat := -global_transform.basis.z
	fwd_flat = Vector3(fwd_flat.x, 0.0, fwd_flat.z).normalized()
	var vel_flat := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	flat_speed = vel_flat.length()

	# Steering: smoothed input, max angle tightens with speed.
	var steer_limit := lerpf(STEER_MAX, 0.16, clampf(flat_speed / 32.0, 0.0, 1.0))
	var attack := 4.0 if absf(steer_input) > 0.05 else 7.0
	_steer = move_toward(_steer, steer_input * steer_limit, attack * delta)

	var space := get_world_3d().direct_space_state
	var grounded_count := 0
	for w in _wheels:
		w["grounded"] = false

	# Suspension pass first so we know how many wheels carry load.
	var ray_results: Array[Dictionary] = []
	for w: Dictionary in _wheels:
		var hardpoint: Vector3 = to_global(w["pos"])
		var query := PhysicsRayQueryParameters3D.create(
			hardpoint, hardpoint - up * (REST_LEN + WHEEL_RADIUS))
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		ray_results.append(hit)
		if hit:
			grounded_count += 1

	for i in _wheels.size():
		var w: Dictionary = _wheels[i]
		var hit: Dictionary = ray_results[i]
		var hardpoint: Vector3 = to_global(w["pos"])
		if hit.is_empty():
			w["prev_comp"] = 0.0
			w["load"] = 0.0
			continue
		w["grounded"] = true

		# --- suspension: spring + damper along chassis up ---
		var dist: float = hardpoint.distance_to(hit["position"])
		var comp: float = clampf(REST_LEN + WHEEL_RADIUS - dist, 0.0, REST_LEN)
		var comp_vel: float = (comp - w["prev_comp"]) / delta
		w["prev_comp"] = comp
		var load: float = clampf(SPRING_K * comp + SPRING_DAMP * comp_vel, 0.0, 45000.0)
		w["load"] = load
		apply_force(up * load, hardpoint - global_position)

		# --- tire forces at the contact patch ---
		var n: Vector3 = hit["normal"]
		var contact: Vector3 = hit["position"]
		var v: Vector3 = linear_velocity + angular_velocity.cross(contact - global_position)
		var wheel_fwd := -global_transform.basis.z
		if w["steer"]:
			wheel_fwd = wheel_fwd.rotated(up, _steer)
		wheel_fwd = (wheel_fwd - n * wheel_fwd.dot(n)).normalized()
		var side := wheel_fwd.cross(n).normalized()
		var v_lat := v.dot(side)
		var v_fwd := v.dot(wheel_fwd)

		# Lateral: try to cancel slip, limited by load (friction circle) —
		# unloaded inside wheels grip less, so slides develop naturally.
		var mu_l := MU_LAT
		if handbrake and not w["steer"]:
			mu_l *= 0.4
		var f_lat := clampf(-v_lat * QUARTER_MASS / 0.18, -mu_l * load, mu_l * load)
		# Applied slightly above the contact to soften rollover leverage.
		apply_force(side * f_lat, contact + up * 0.8 - global_position)

		# Longitudinal: AWD drive, brakes, handbrake-locked rears.
		var f_long := -v_fwd * 35.0  # rolling resistance
		if throttle and grounded_count > 0:
			f_long += (ENGINE_FORCE / grounded_count) * maxf(0.0, 1.0 - flat_speed / TOP_SPEED)
		if brake:
			if v_fwd > 1.0:
				f_long -= BRAKE_FORCE / 4.0
			else:
				f_long -= (REVERSE_FORCE / grounded_count) * maxf(0.0, 1.0 - flat_speed / (TOP_SPEED * 0.4))
		if handbrake and not w["steer"]:
			f_long = clampf(-v_fwd * QUARTER_MASS / 0.15, -mu_l * load, mu_l * load)
		f_long = clampf(f_long, -MU_LONG * load, MU_LONG * load)
		apply_force(wheel_fwd * f_long, contact - global_position)

	# Aero drag.
	apply_central_force(-linear_velocity * linear_velocity.length() * 1.6)

	# Drift state for scoring (same contract as the drift coupe).
	drift_angle = 0.0
	var grounded := grounded_count >= 2
	_grounded = grounded
	if grounded and flat_speed > 4.0 and vel_flat.dot(fwd_flat) > 0.0:
		drift_angle = fwd_flat.angle_to(vel_flat / flat_speed)
	is_drifting = grounded and drift_angle > 0.26 and flat_speed > 7.0

	# Crash detection: sudden speed loss while grounded = hit something.
	if grounded and _prev_speed - flat_speed > 8.0:
		crashed.emit(_prev_speed - flat_speed)
	_prev_speed = flat_speed

	# Stuck upside down → flip upright after a moment.
	if global_transform.basis.y.y < 0.05 and flat_speed < 2.0:
		_flip_timer += delta
		if _flip_timer > 1.2:
			var yaw := global_rotation.y
			global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * 1.5)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			_flip_timer = 0.0
	else:
		_flip_timer = 0.0

	_smoke_l.emitting = is_drifting
	_smoke_r.emitting = is_drifting
	_update_wheel_visuals(delta)

func vel3() -> Vector3:
	return linear_velocity

func is_on_floor() -> bool:
	return _grounded

func respawn() -> void:
	global_transform = spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	flat_speed = 0.0
	drift_angle = 0.0
	is_drifting = false
	_steer = 0.0
	_prev_speed = 0.0
	_flip_timer = 0.0
	for w in _wheels:
		w["prev_comp"] = 0.0

func _update_wheel_visuals(delta: float) -> void:
	for w: Dictionary in _wheels:
		var pivot: Node3D = w["pivot"]
		var spinner: Node3D = w["spinner"]
		var pos: Vector3 = w["pos"]
		var droop: float = REST_LEN - w["prev_comp"] if w["grounded"] else REST_LEN
		pivot.position = Vector3(pos.x, pos.y - droop, pos.z)
		if w["steer"]:
			pivot.rotation.y = _steer
		var v := linear_velocity.dot(-global_transform.basis.z)
		spinner.rotation.x -= v * delta / WHEEL_RADIUS

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.2, 4.4)
	col.shape = shape
	col.position = Vector3(0, 1.0, 0)
	add_child(col)

func _build_visuals() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.92, 0.89, 0.82)
	body_mat.roughness = 0.5
	body_mat.metallic = 0.2
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.09, 0.09, 0.1)
	dark_mat.roughness = 0.8
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color(0.85, 0.2, 0.12)
	accent_mat.roughness = 0.6
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.1, 0.12, 0.18)
	glass_mat.metallic = 0.8
	glass_mat.roughness = 0.1

	_box(Vector3(1.9, 0.3, 4.3), Vector3(0, 0.55, 0), dark_mat)        # frame
	_box(Vector3(2.05, 0.55, 4.4), Vector3(0, 0.95, 0), body_mat)      # tub
	_box(Vector3(1.9, 0.28, 1.3), Vector3(0, 1.32, -1.45), body_mat)   # hood
	_box(Vector3(1.6, 0.1, 1.0), Vector3(0, 1.48, -1.45), accent_mat)  # hood stripe
	_box(Vector3(1.85, 0.72, 1.5), Vector3(0, 1.72, -0.25), body_mat)  # cab
	_box(Vector3(1.7, 0.5, 1.3), Vector3(0, 1.78, -0.25), glass_mat)   # glass
	_box(Vector3(1.9, 0.12, 1.7), Vector3(0, 1.28, 1.35), dark_mat)    # bed floor
	_box(Vector3(0.12, 0.4, 1.7), Vector3(-0.92, 1.5, 1.35), body_mat) # bed rail L
	_box(Vector3(0.12, 0.4, 1.7), Vector3(0.92, 1.5, 1.35), body_mat)  # bed rail R
	_box(Vector3(1.6, 0.14, 0.22), Vector3(0, 2.22, -0.7), dark_mat)   # light bar

	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.8, 0.4)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.75, 0.35)
	lamp_mat.emission_energy_multiplier = 2.2
	for i in 4:
		_box(Vector3(0.2, 0.16, 0.1), Vector3(-0.57 + i * 0.38, 2.24, -0.78), lamp_mat)

	var spare := MeshInstance3D.new()
	var spare_mesh := CylinderMesh.new()
	spare_mesh.top_radius = 0.5
	spare_mesh.bottom_radius = 0.5
	spare_mesh.height = 0.35
	spare.mesh = spare_mesh
	spare.material_override = dark_mat
	spare.position = Vector3(0, 1.5, 1.35)
	add_child(spare)

	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.07, 0.07, 0.08)
	tire_mat.roughness = 0.95
	var hub_mat := StandardMaterial3D.new()
	hub_mat.albedo_color = Color(0.7, 0.68, 0.62)
	hub_mat.metallic = 0.7
	hub_mat.roughness = 0.4

	for w: Dictionary in _wheels:
		var pivot := Node3D.new()
		pivot.position = w["pos"]
		add_child(pivot)
		var spinner := Node3D.new()
		pivot.add_child(spinner)
		var tire := MeshInstance3D.new()
		var tire_mesh := CylinderMesh.new()
		tire_mesh.top_radius = WHEEL_RADIUS
		tire_mesh.bottom_radius = WHEEL_RADIUS
		tire_mesh.height = 0.45
		tire.mesh = tire_mesh
		tire.material_override = tire_mat
		tire.rotation.z = PI / 2.0
		spinner.add_child(tire)
		var hub := MeshInstance3D.new()
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = WHEEL_RADIUS * 0.45
		hub_mesh.bottom_radius = WHEEL_RADIUS * 0.45
		hub_mesh.height = 0.47
		hub.mesh = hub_mesh
		hub.material_override = hub_mat
		hub.rotation.z = PI / 2.0
		spinner.add_child(hub)
		w["pivot"] = pivot
		w["spinner"] = spinner

func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	add_child(m)

func _build_smoke() -> void:
	for side in [-1.0, 1.0]:
		var p := GPUParticles3D.new()
		p.amount = 48
		p.lifetime = 1.1
		p.local_coords = false
		p.emitting = false
		p.position = Vector3(0.95 * side, 0.1, 1.6)

		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 35.0
		mat.initial_velocity_min = 1.2
		mat.initial_velocity_max = 3.0
		mat.gravity = Vector3(0, 1.4, 0)
		mat.scale_min = 0.9
		mat.scale_max = 2.0
		var grad := Gradient.new()
		grad.set_color(0, Color(0.78, 0.72, 0.6, 0.5))
		grad.set_color(1, Color(0.8, 0.75, 0.65, 0.0))
		var grad_tex := GradientTexture1D.new()
		grad_tex.gradient = grad
		mat.color_ramp = grad_tex
		p.process_material = mat

		var puff := SphereMesh.new()
		puff.radius = 0.2
		puff.height = 0.4
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
