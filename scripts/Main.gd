extends Node3D

const VERSION := "0.1.0"
const ARENA_SIZE := 240.0
const CONE_POINTS := 75

var car: DriftCar
var cam: ChaseCamera
var hud: HUD

var total_score := 0
var drift_points := 0.0
var multiplier := 1.0
var drift_grace := 0.0
var drift_chain_active := false

var _cones: Array[RigidBody3D] = []
var _cone_spawns: Array[Vector3] = []
var _cone_hit: Array[bool] = []

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_walls()
	_build_center_pillar()
	_spawn_cones()

	car = DriftCar.new()
	car.position = Vector3(0, 1.0, 85)
	add_child(car)
	car.crashed.connect(_on_car_crashed)

	cam = ChaseCamera.new()
	add_child(cam)
	cam.target = car
	cam.current = true
	cam.snap_to_target()

	hud = HUD.new()
	add_child(hud)

func _physics_process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		return

	hud.set_speed(car.flat_speed * 3.6)

	if car.is_drifting:
		drift_chain_active = true
		drift_grace = 0.5
		multiplier = minf(multiplier + delta * 0.5, 5.0)
		drift_points += car.flat_speed * car.drift_angle * 10.0 * multiplier * delta
	elif drift_chain_active:
		drift_grace -= delta
		if drift_grace <= 0.0:
			_bank_drift()

	hud.set_drift(drift_chain_active, drift_points, multiplier)
	hud.set_total(total_score)
	_check_cones()

func _bank_drift() -> void:
	if drift_points >= 50.0:
		total_score += int(drift_points)
		hud.flash("+%d BANKED" % int(drift_points), Color(0.4, 1.0, 0.6))
	drift_points = 0.0
	multiplier = 1.0
	drift_chain_active = false

func _on_car_crashed(_impact_speed: float) -> void:
	if drift_chain_active and drift_points > 0.0:
		hud.flash("DRIFT LOST", Color(1.0, 0.3, 0.3))
	drift_points = 0.0
	multiplier = 1.0
	drift_chain_active = false

func _check_cones() -> void:
	for i in _cones.size():
		if _cone_hit[i]:
			continue
		if _cones[i].global_position.distance_to(_cone_spawns[i]) > 1.2:
			_cone_hit[i] = true
			if drift_chain_active:
				drift_points += CONE_POINTS * multiplier
			else:
				total_score += CONE_POINTS

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.13, 0.07, 0.25)
	sky_mat.sky_horizon_color = Color(0.95, 0.42, 0.28)
	sky_mat.ground_bottom_color = Color(0.07, 0.04, 0.1)
	sky_mat.ground_horizon_color = Color(0.85, 0.38, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.2, 0.35)
	env.fog_density = 0.0015

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-16.0, 40.0, 0.0)
	sun.light_color = Color(1.0, 0.75, 0.55)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

func _build_ground() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ARENA_SIZE + 40.0, 1.0, ARENA_SIZE + 40.0)
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(ARENA_SIZE + 40.0, 1.0, ARENA_SIZE + 40.0)
	mesh.mesh = box
	mesh.position = Vector3(0, -0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.16)
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

	# Glowing drift ring around the center pillar.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 27.0
	torus.outer_radius = 28.0
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.02, 1.0)
	ring.position = Vector3(0, 0.03, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.2, 0.9, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 0.95, 0.95)
	ring_mat.emission_energy_multiplier = 1.8
	ring.material_override = ring_mat
	add_child(ring)

	# Neon trim strips inset from the walls.
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(1.0, 0.2, 0.6)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(1.0, 0.18, 0.55)
	strip_mat.emission_energy_multiplier = 1.6
	var inset := ARENA_SIZE / 2.0 - 4.0
	for i in 4:
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		if i < 2:
			strip_mesh.size = Vector3(ARENA_SIZE - 8.0, 0.06, 0.35)
			strip.position = Vector3(0, 0.03, inset * (1 if i == 0 else -1))
		else:
			strip_mesh.size = Vector3(0.35, 0.06, ARENA_SIZE - 8.0)
			strip.position = Vector3(inset * (1 if i == 2 else -1), 0.03, 0)
		strip.mesh = strip_mesh
		strip.material_override = strip_mat
		add_child(strip)

func _build_walls() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.09, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.15, 0.6)
	mat.emission_energy_multiplier = 0.5
	var half := ARENA_SIZE / 2.0 + 1.0
	for i in 4:
		var wall := StaticBody3D.new()
		var shape := BoxShape3D.new()
		var size: Vector3
		if i < 2:
			size = Vector3(ARENA_SIZE + 6.0, 3.0, 2.0)
			wall.position = Vector3(0, 1.5, half * (1 if i == 0 else -1))
		else:
			size = Vector3(2.0, 3.0, ARENA_SIZE + 6.0)
			wall.position = Vector3(half * (1 if i == 2 else -1), 1.5, 0)
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		wall.add_child(col)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = mat
		wall.add_child(mesh)
		add_child(wall)

func _build_center_pillar() -> void:
	var pillar := StaticBody3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 10.0
	shape.height = 5.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 2.5, 0)
	pillar.add_child(col)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 10.0
	cyl.bottom_radius = 10.0
	cyl.height = 5.0
	mesh.mesh = cyl
	mesh.position = Vector3(0, 2.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.14)
	mat.roughness = 0.7
	mesh.material_override = mat
	pillar.add_child(mesh)

	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 10.05
	band_mesh.bottom_radius = 10.05
	band_mesh.height = 0.5
	band.mesh = band_mesh
	band.position = Vector3(0, 3.8, 0)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.2, 0.9, 0.9)
	band_mat.emission_enabled = true
	band_mat.emission = Color(0.2, 0.95, 0.95)
	band_mat.emission_energy_multiplier = 2.0
	band.material_override = band_mat
	pillar.add_child(band)
	add_child(pillar)

func _spawn_cones() -> void:
	# Slalom line in the south half.
	for i in 8:
		_add_cone(Vector3(-42.0 + i * 12.0, 0.45, -70.0))
	# Circle of cones around the drift ring.
	for i in 12:
		var a := TAU * i / 12.0
		_add_cone(Vector3(cos(a) * 38.0, 0.45, sin(a) * 38.0))
	# 3x3 clusters in each corner.
	for corner in [Vector3(75, 0, 75), Vector3(-75, 0, 75), Vector3(-75, 0, -75), Vector3(75, 0, -75)]:
		for x in 3:
			for z in 3:
				_add_cone(corner + Vector3((x - 1) * 2.2, 0.45, (z - 1) * 2.2))

func _add_cone(pos: Vector3) -> void:
	var cone := RigidBody3D.new()
	cone.mass = 0.8
	cone.position = pos

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3
	shape.height = 0.9
	col.shape = shape
	cone.add_child(col)

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.32
	cyl.height = 0.9
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 0.4
	mesh.material_override = mat
	cone.add_child(mesh)

	add_child(cone)
	_cones.append(cone)
	_cone_spawns.append(pos)
	_cone_hit.append(false)
