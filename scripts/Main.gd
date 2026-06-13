extends Node3D

const VERSION := "0.2.0"
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
	_build_pagoda()
	_build_torii_gates()
	_build_trees()
	_build_fuji()
	_build_petals()
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
	# Soft spring morning: pale blue sky fading into sakura-pink haze.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.62, 0.92)
	sky_mat.sky_horizon_color = Color(0.97, 0.8, 0.76)
	sky_mat.ground_bottom_color = Color(0.25, 0.28, 0.32)
	sky_mat.ground_horizon_color = Color(0.95, 0.78, 0.72)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.92, 0.78, 0.78)
	env.fog_density = 0.0012

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 50.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.25
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
	mat.albedo_color = Color(0.19, 0.19, 0.21)
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

	# Vermillion drift ring around the pagoda.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 27.0
	torus.outer_radius = 28.0
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.02, 1.0)
	ring.position = Vector3(0, 0.03, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.9, 0.22, 0.12)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.95, 0.2, 0.1)
	ring_mat.emission_energy_multiplier = 1.2
	ring.material_override = ring_mat
	add_child(ring)

	# White painted track-edge lines inset from the walls.
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_color = Color(0.95, 0.95, 0.92)
	strip_mat.emission_enabled = true
	strip_mat.emission = Color(0.9, 0.9, 0.88)
	strip_mat.emission_energy_multiplier = 0.25
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
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.27, 0.17, 0.12)
	wood_mat.roughness = 0.85
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.82, 0.16, 0.12)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.85, 0.15, 0.1)
	trim_mat.emission_energy_multiplier = 0.4
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
		mesh.material_override = wood_mat
		wall.add_child(mesh)
		var trim := MeshInstance3D.new()
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(size.x + 0.2, 0.35, size.z + 0.2)
		trim.mesh = trim_mesh
		trim.position = Vector3(0, 1.65, 0)
		trim.material_override = trim_mat
		wall.add_child(trim)
		add_child(wall)

func _build_pagoda() -> void:
	var pagoda := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12.0, 12.0, 12.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 6.0, 0)
	pagoda.add_child(col)

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.55, 0.55, 0.52)
	stone_mat.roughness = 0.9
	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.78, 0.16, 0.12)
	red_mat.roughness = 0.6
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.13, 0.15, 0.2)
	roof_mat.roughness = 0.4
	roof_mat.metallic = 0.3
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.9, 0.75, 0.3)
	gold_mat.metallic = 0.8
	gold_mat.roughness = 0.3

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(13.0, 1.2, 13.0)
	base.mesh = base_mesh
	base.position = Vector3(0, 0.6, 0)
	base.material_override = stone_mat
	pagoda.add_child(base)

	var y := 1.2
	var widths := [10.5, 8.0, 5.5]
	for w in widths:
		var tier := MeshInstance3D.new()
		var tier_mesh := BoxMesh.new()
		tier_mesh.size = Vector3(w, 2.4, w)
		tier.mesh = tier_mesh
		tier.position = Vector3(0, y + 1.2, 0)
		tier.material_override = red_mat
		pagoda.add_child(tier)
		y += 2.4

		var roof := MeshInstance3D.new()
		var roof_mesh := BoxMesh.new()
		roof_mesh.size = Vector3(w + 3.5, 0.5, w + 3.5)
		roof.mesh = roof_mesh
		roof.position = Vector3(0, y + 0.25, 0)
		roof.material_override = roof_mat
		pagoda.add_child(roof)
		y += 0.5

	var finial := MeshInstance3D.new()
	var finial_mesh := CylinderMesh.new()
	finial_mesh.top_radius = 0.12
	finial_mesh.bottom_radius = 0.25
	finial_mesh.height = 2.2
	finial.mesh = finial_mesh
	finial.position = Vector3(0, y + 1.1, 0)
	finial.material_override = gold_mat
	pagoda.add_child(finial)

	add_child(pagoda)

func _build_torii_gates() -> void:
	# Drive-through corridor on the east side, plus scattered gates.
	_add_torii(Vector3(60, 0, 0), PI / 2.0)
	_add_torii(Vector3(78, 0, 0), PI / 2.0)
	_add_torii(Vector3(96, 0, 0), PI / 2.0)
	_add_torii(Vector3(-65, 0, 65), -PI / 4.0)
	_add_torii(Vector3(-65, 0, -65), PI / 4.0)
	_add_torii(Vector3(0, 0, -90), 0.0)

func _add_torii(pos: Vector3, rot_y: float) -> void:
	var gate := StaticBody3D.new()
	gate.position = pos
	gate.rotation.y = rot_y

	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.85, 0.14, 0.1)
	red_mat.roughness = 0.55
	var black_mat := StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.1, 0.1, 0.12)
	black_mat.roughness = 0.5

	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.32
	pillar_mesh.bottom_radius = 0.38
	pillar_mesh.height = 6.0
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		pillar.mesh = pillar_mesh
		pillar.position = Vector3(2.4 * side, 3.0, 0)
		pillar.material_override = red_mat
		gate.add_child(pillar)
		var col := CollisionShape3D.new()
		var col_shape := CylinderShape3D.new()
		col_shape.radius = 0.4
		col_shape.height = 6.0
		col.shape = col_shape
		col.position = Vector3(2.4 * side, 3.0, 0)
		gate.add_child(col)

	var nuki := MeshInstance3D.new()
	var nuki_mesh := BoxMesh.new()
	nuki_mesh.size = Vector3(5.8, 0.42, 0.5)
	nuki.mesh = nuki_mesh
	nuki.position = Vector3(0, 4.7, 0)
	nuki.material_override = red_mat
	gate.add_child(nuki)

	var kasagi := MeshInstance3D.new()
	var kasagi_mesh := BoxMesh.new()
	kasagi_mesh.size = Vector3(6.8, 0.5, 0.7)
	kasagi.mesh = kasagi_mesh
	kasagi.position = Vector3(0, 5.95, 0)
	kasagi.material_override = red_mat
	gate.add_child(kasagi)

	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(7.2, 0.25, 0.85)
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 6.3, 0)
	cap.material_override = black_mat
	gate.add_child(cap)

	add_child(gate)

func _build_trees() -> void:
	for pos in [
		Vector3(40, 0, 100), Vector3(-40, 0, 100),
		Vector3(40, 0, -100), Vector3(-40, 0, -100),
		Vector3(100, 0, 55), Vector3(100, 0, -55),
		Vector3(-100, 0, 55), Vector3(-100, 0, -55),
	]:
		_add_sakura(pos)

func _add_sakura(pos: Vector3) -> void:
	var tree := StaticBody3D.new()
	tree.position = pos

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.3, 0.2, 0.15)
	trunk_mat.roughness = 0.9
	var bloom_mat := StandardMaterial3D.new()
	bloom_mat.albedo_color = Color(0.98, 0.74, 0.8)
	bloom_mat.roughness = 0.8

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.28
	trunk_mesh.bottom_radius = 0.42
	trunk_mesh.height = 3.2
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0, 1.6, 0)
	trunk.material_override = trunk_mat
	tree.add_child(trunk)

	var col := CollisionShape3D.new()
	var col_shape := CylinderShape3D.new()
	col_shape.radius = 0.45
	col_shape.height = 3.2
	col.shape = col_shape
	col.position = Vector3(0, 1.6, 0)
	tree.add_child(col)

	for blob in [
		{"pos": Vector3(0, 4.2, 0), "r": 2.3},
		{"pos": Vector3(1.5, 3.6, 0.6), "r": 1.6},
		{"pos": Vector3(-1.3, 3.7, -0.5), "r": 1.5},
		{"pos": Vector3(0.3, 3.4, -1.3), "r": 1.3},
	]:
		var canopy := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = blob["r"]
		sphere.height = blob["r"] * 2.0
		canopy.mesh = sphere
		canopy.position = blob["pos"]
		canopy.material_override = bloom_mat
		tree.add_child(canopy)

	add_child(tree)

func _build_fuji() -> void:
	# Distant silhouette beyond the north wall.
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.45, 0.5, 0.62)
	base_mat.roughness = 1.0
	var mountain := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 28.0
	base_mesh.bottom_radius = 170.0
	base_mesh.height = 120.0
	base_mesh.radial_segments = 24
	mountain.mesh = base_mesh
	mountain.position = Vector3(40, 60, -400)
	mountain.material_override = base_mat
	add_child(mountain)

	var snow_mat := StandardMaterial3D.new()
	snow_mat.albedo_color = Color(0.96, 0.96, 0.98)
	snow_mat.roughness = 0.9
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 3.0
	cap_mesh.bottom_radius = 30.0
	cap_mesh.height = 30.0
	cap_mesh.radial_segments = 24
	cap.mesh = cap_mesh
	cap.position = Vector3(40, 133, -400)
	cap.material_override = snow_mat
	add_child(cap)

func _build_petals() -> void:
	var petals := GPUParticles3D.new()
	petals.amount = 400
	petals.lifetime = 14.0
	petals.preprocess = 14.0
	petals.local_coords = false
	petals.position = Vector3(0, 20, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(ARENA_SIZE / 2.0, 2.0, ARENA_SIZE / 2.0)
	mat.direction = Vector3(0.4, -1.0, 0.2)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.9
	mat.gravity = Vector3(0.35, -1.1, 0.15)
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	petals.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.16)
	var petal_mat := StandardMaterial3D.new()
	petal_mat.albedo_color = Color(1.0, 0.72, 0.8)
	petal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	petal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	petal_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = petal_mat
	petals.draw_pass_1 = quad

	add_child(petals)

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
	mat.albedo_color = Color(0.92, 0.2, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.18, 0.1)
	mat.emission_energy_multiplier = 0.3
	mesh.material_override = mat
	cone.add_child(mesh)

	add_child(cone)
	_cones.append(cone)
	_cone_spawns.append(pos)
	_cone_hit.append(false)
