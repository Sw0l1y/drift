extends Node3D

const VERSION := "0.5.0"
const CONE_POINTS := 75

const MAP_SIZE := 800.0
const GRID_N := 121               # terrain vertices per side
const ROAD_WIDTH := 14.0
const ROAD_CARVE := 28.0          # how far the roadbed blends into the hills
const PLAZA := Vector2(0.0, 190.0)
const PLAZA_R := 50.0
const PLAZA_H := 3.0

# Untyped on purpose: cars are duck-typed against the Garage contract
# (DriftCar is a CharacterBody3D, PrerunnerTruck is a RigidBody3D).
var car
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

var _noise := FastNoiseLite.new()
var _road_samples: Array[Vector3] = []
var _road_tangents: Array[Vector3] = []
var _road_grid: Dictionary = {}
var _petals: GPUParticles3D

func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 4

	_build_environment()
	_build_road_path()
	_build_terrain()
	_build_road_mesh()
	_build_boundaries()
	_build_pagoda_plaza()
	_build_torii_gates()
	_build_trees()
	_build_mountains()
	_build_petals()
	_spawn_cones()

	var start := _road_samples[2]
	var dir := _road_tangents[2]
	car = Garage.create_selected()
	car.transform = Transform3D(Basis.looking_at(dir), start + Vector3.UP * 1.5)
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
	_petals.global_position = car.global_position + Vector3(0, 16, 0)

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
	# Cones don't collide with the car (no ramp launches at speed) — the car
	# passes through and we fling them with a scripted impulse instead.
	if car.flat_speed < 3.0:
		return
	var car_pos: Vector3 = car.global_position
	for i in _cones.size():
		if _cone_hit[i]:
			continue
		var cp := _cones[i].global_position
		if cp.distance_to(car_pos) < float(car.cone_reach):
			_cone_hit[i] = true
			var away: Vector3 = (cp - car_pos).normalized()
			var cv: Vector3 = car.vel3()
			var fling: Vector3 = Vector3(cv.x, 0.0, cv.z) * 0.08 + away * 1.5 + Vector3(0, 3.0, 0)
			_cones[i].apply_central_impulse(fling)
			_cones[i].apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 4.0)
			if drift_chain_active:
				drift_points += CONE_POINTS * multiplier
			else:
				total_score += CONE_POINTS

# ---------- terrain & road ----------

func _build_road_path() -> void:
	# Hand-designed closed toge loop: start straight south, climbing east
	# sweepers, esses to a northern summit, a west hairpin, then home.
	var pts: Array[Vector3] = [
		Vector3(0, 2, 240),
		Vector3(130, 6, 215),
		Vector3(215, 14, 150),
		Vector3(245, 22, 40),
		Vector3(200, 30, -60),
		Vector3(255, 36, -150),
		Vector3(170, 44, -225),
		Vector3(60, 50, -255),
		Vector3(-50, 46, -235),
		Vector3(-150, 38, -265),
		Vector3(-235, 30, -205),
		Vector3(-260, 26, -130),
		Vector3(-175, 22, -95),
		Vector3(-235, 14, 20),
		Vector3(-175, 6, 150),
		Vector3(-60, 2, 235),
	]
	var n := pts.size()
	var curve := Curve3D.new()
	for i in n + 1:
		var p := pts[i % n]
		var tangent := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]) * 0.22
		curve.add_point(p, -tangent, tangent)

	var length := curve.get_baked_length()
	var count := int(length / 6.0)
	for i in count:
		_road_samples.append(curve.sample_baked(length * i / count))
	for i in count:
		var t := _road_samples[(i + 1) % count] - _road_samples[(i - 1 + count) % count]
		_road_tangents.append(t.normalized())

	# Spatial hash of samples for fast nearest-road lookups during carving.
	for i in count:
		var cell := Vector2i(floori(_road_samples[i].x / 32.0), floori(_road_samples[i].z / 32.0))
		if not _road_grid.has(cell):
			_road_grid[cell] = []
		_road_grid[cell].append(i)

func _side(i: int) -> Vector3:
	var t := _road_tangents[i]
	return Vector3(t.z, 0.0, -t.x).normalized()

func _nearest_sample(x: float, z: float) -> int:
	var best := 0
	var bd := 1e18
	for i in _road_samples.size():
		var dx := _road_samples[i].x - x
		var dz := _road_samples[i].z - z
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d
			best = i
	return best

func _nearest_road(x: float, z: float) -> Vector2:
	# Returns (xz distance to road, road height there), using the hash grid.
	var c := Vector2i(floori(x / 32.0), floori(z / 32.0))
	var bd := 1e18
	var by := 0.0
	for cx in range(c.x - 1, c.x + 2):
		for cz in range(c.y - 1, c.y + 2):
			var cell := Vector2i(cx, cz)
			if not _road_grid.has(cell):
				continue
			for i: int in _road_grid[cell]:
				var dx := _road_samples[i].x - x
				var dz := _road_samples[i].z - z
				var d := dx * dx + dz * dz
				if d < bd:
					bd = d
					by = _road_samples[i].y
	return Vector2(sqrt(bd), by)

func _terrain_height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * 14.0 + 8.0
	# Mountain rim toward the map edges.
	var r := maxf(absf(x), absf(z)) / (MAP_SIZE / 2.0)
	var edge := smoothstep(0.6, 1.05, r)
	h += edge * edge * 110.0 + edge * absf(_noise.get_noise_2d(x * 3.0 + 900.0, z * 3.0)) * 50.0
	# Flat plaza pad.
	var dp := Vector2(x, z).distance_to(PLAZA)
	if dp < PLAZA_R + 25.0:
		h = lerpf(PLAZA_H, h, smoothstep(PLAZA_R, PLAZA_R + 25.0, dp))
	# Carve the roadbed into the hills.
	var road := _nearest_road(x, z)
	if road.x < ROAD_CARVE:
		h = lerpf(road.y - 0.2, h, smoothstep(ROAD_WIDTH / 2.0 + 2.0, ROAD_CARVE, road.x))
	return h

func _build_terrain() -> void:
	var n := GRID_N
	var cell := MAP_SIZE / float(n - 1)
	var half := MAP_SIZE / 2.0

	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for zi in n:
		for xi in n:
			heights[zi * n + xi] = _terrain_height(xi * cell - half, zi * cell - half)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass_a := Color(0.2, 0.36, 0.16)
	var grass_b := Color(0.29, 0.43, 0.19)
	var rock := Color(0.36, 0.33, 0.31)
	var snow := Color(0.93, 0.94, 0.96)

	var colors := []
	colors.resize(n * n)
	for zi in n:
		for xi in n:
			var h := heights[zi * n + xi]
			var hx0 := heights[zi * n + maxi(xi - 1, 0)]
			var hx1 := heights[zi * n + mini(xi + 1, n - 1)]
			var hz0 := heights[maxi(zi - 1, 0) * n + xi]
			var hz1 := heights[mini(zi + 1, n - 1) * n + xi]
			var steep := Vector2((hx1 - hx0) / (2.0 * cell), (hz1 - hz0) / (2.0 * cell)).length()
			var c := grass_a.lerp(grass_b, (_noise.get_noise_2d(xi * 31.0, zi * 31.0) + 1.0) * 0.5)
			c = c.lerp(rock, clampf((steep - 0.45) * 2.5, 0.0, 1.0))
			c = c.lerp(rock, smoothstep(50.0, 80.0, h))
			c = c.lerp(snow, smoothstep(85.0, 110.0, h))
			colors[zi * n + xi] = c

	for zi in n - 1:
		for xi in n - 1:
			var i00 := zi * n + xi
			var i10 := zi * n + xi + 1
			var i01 := (zi + 1) * n + xi
			var i11 := (zi + 1) * n + xi + 1
			for idx: int in [i00, i10, i01, i01, i10, i11]:
				var vx := (idx % n) * cell - half
				@warning_ignore("integer_division")
				var vz := (idx / n) * cell - half
				st.set_color(colors[idx])
				st.add_vertex(Vector3(vx, heights[idx], vz))
	st.generate_normals()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh_inst.material_override = mat

	var body := StaticBody3D.new()
	body.add_child(mesh_inst)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(cell, 1.0, cell)
	body.add_child(col)
	add_child(body)

func _build_road_mesh() -> void:
	var count := _road_samples.size()
	var half := ROAD_WIDTH / 2.0

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in count:
		var j := (i + 1) % count
		var li := _road_samples[i] + _side(i) * half
		var ri := _road_samples[i] - _side(i) * half
		var lj := _road_samples[j] + _side(j) * half
		var rj := _road_samples[j] - _side(j) * half
		for v in [li, lj, ri, ri, lj, rj]:
			st.add_vertex(v)
			faces.append(v)
	st.generate_normals()

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)
	mat.roughness = 0.95
	mesh_inst.material_override = mat

	var body := StaticBody3D.new()
	body.add_child(mesh_inst)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)

	# Painted lines: white edges, dashed yellow center.
	_add_road_lines([half - 0.7, -(half - 0.7)], 0.35, false, Color(0.92, 0.92, 0.9))
	_add_road_lines([0.0], 0.3, true, Color(0.95, 0.8, 0.25))

func _add_road_lines(offsets: Array, width: float, dashed: bool, color: Color) -> void:
	var count := _road_samples.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.06
	for offset: float in offsets:
		for i in count:
			if dashed and i % 4 >= 2:
				continue
			var j := (i + 1) % count
			var li := _road_samples[i] + _side(i) * (offset + width / 2.0) + lift
			var ri := _road_samples[i] + _side(i) * (offset - width / 2.0) + lift
			var lj := _road_samples[j] + _side(j) * (offset + width / 2.0) + lift
			var rj := _road_samples[j] + _side(j) * (offset - width / 2.0) + lift
			for v in [li, lj, ri, ri, lj, rj]:
				st.add_vertex(v)
	st.generate_normals()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.2
	mesh_inst.material_override = mat
	add_child(mesh_inst)

func _build_boundaries() -> void:
	var half := MAP_SIZE / 2.0
	for i in 4:
		var wall := StaticBody3D.new()
		var shape := BoxShape3D.new()
		if i < 2:
			shape.size = Vector3(MAP_SIZE + 20.0, 160.0, 4.0)
			wall.position = Vector3(0, 80, half * (1 if i == 0 else -1))
		else:
			shape.size = Vector3(4.0, 160.0, MAP_SIZE + 20.0)
			wall.position = Vector3(half * (1 if i == 2 else -1), 80, 0)
		var col := CollisionShape3D.new()
		col.shape = shape
		wall.add_child(col)
		add_child(wall)

# ---------- scenery ----------

func _build_environment() -> void:
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
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.92, 0.78, 0.78)
	env.fog_density = 0.0007

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 50.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)

func _build_pagoda_plaza() -> void:
	var base_pos := Vector3(PLAZA.x, PLAZA_H, PLAZA.y)

	var pagoda := StaticBody3D.new()
	pagoda.position = base_pos
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
	for w: float in [10.5, 8.0, 5.5]:
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

	# Vermillion drift ring on the plaza.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 27.0
	torus.outer_radius = 28.0
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.02, 1.0)
	ring.position = base_pos + Vector3(0, 0.05, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.9, 0.22, 0.12)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.95, 0.2, 0.1)
	ring_mat.emission_energy_multiplier = 1.2
	ring.material_override = ring_mat
	add_child(ring)

func _build_torii_gates() -> void:
	# Gates spanning the road at scenic spots (climb, summit, descent, home).
	for target: Vector2 in [Vector2(245, 40), Vector2(60, -255), Vector2(-235, 20), Vector2(-175, 150)]:
		var i := _nearest_sample(target.x, target.y)
		var t := _road_tangents[i]
		_add_torii(_road_samples[i], atan2(t.x, t.z))

func _add_torii(pos: Vector3, rot_y: float) -> void:
	var gate := StaticBody3D.new()
	gate.position = pos
	gate.rotation.y = rot_y
	gate.scale = Vector3(2.6, 1.7, 2.6)

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
	var count := _road_samples.size()
	for i in count:
		if i % 14 != 7:
			continue
		var side := 1.0 if int(i / 14.0) % 2 == 0 else -1.0
		var pos := _road_samples[i] + _side(i) * 15.0 * side
		pos.y = _terrain_height(pos.x, pos.z) - 0.2
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

func _build_mountains() -> void:
	# Fuji to the north plus a skyline ring beyond the playable map.
	_add_mountain(Vector3(40, 0, -620), 300.0, 240.0, true)
	_add_mountain(Vector3(520, 0, -260), 180.0, 150.0, false)
	_add_mountain(Vector3(560, 0, 120), 200.0, 170.0, true)
	_add_mountain(Vector3(340, 0, 540), 170.0, 130.0, false)
	_add_mountain(Vector3(-300, 0, 560), 190.0, 160.0, false)
	_add_mountain(Vector3(-560, 0, 220), 210.0, 180.0, true)
	_add_mountain(Vector3(-520, 0, -330), 170.0, 140.0, false)

func _add_mountain(pos: Vector3, base_radius: float, height: float, snow_cap: bool) -> void:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.45, 0.5, 0.62)
	base_mat.roughness = 1.0
	var mountain := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = base_radius * 0.09
	mesh.bottom_radius = base_radius
	mesh.height = height
	mesh.radial_segments = 24
	mountain.mesh = mesh
	mountain.position = pos + Vector3(0, height / 2.0, 0)
	mountain.material_override = base_mat
	add_child(mountain)

	if snow_cap:
		var snow_mat := StandardMaterial3D.new()
		snow_mat.albedo_color = Color(0.96, 0.96, 0.98)
		snow_mat.roughness = 0.9
		var cap := MeshInstance3D.new()
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = base_radius * 0.01
		cap_mesh.bottom_radius = base_radius * 0.11
		cap_mesh.height = height * 0.13
		cap_mesh.radial_segments = 24
		cap.mesh = cap_mesh
		cap.position = pos + Vector3(0, height * 1.06, 0)
		cap.material_override = snow_mat
		add_child(cap)

func _build_petals() -> void:
	_petals = GPUParticles3D.new()
	_petals.amount = 260
	_petals.lifetime = 12.0
	_petals.preprocess = 12.0
	_petals.local_coords = false
	_petals.position = Vector3(0, 18, 0)

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(45.0, 3.0, 45.0)
	mat.direction = Vector3(0.4, -1.0, 0.2)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.9
	mat.gravity = Vector3(0.35, -1.1, 0.15)
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	_petals.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.16)
	var petal_mat := StandardMaterial3D.new()
	petal_mat.albedo_color = Color(1.0, 0.72, 0.8)
	petal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	petal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	petal_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = petal_mat
	_petals.draw_pass_1 = quad

	add_child(_petals)

# ---------- cones ----------

func _spawn_cones() -> void:
	# Slalom down the start straight.
	for idx in [6, 10, 14, 18, 22]:
		_add_cone(_road_samples[idx] + Vector3.UP * 0.45)
	# Circle on the pagoda plaza.
	for i in 12:
		var a := TAU * i / 12.0
		var pos := Vector3(PLAZA.x + cos(a) * 33.0, PLAZA_H + 0.45, PLAZA.y + sin(a) * 33.0)
		_add_cone(pos)
	# Roadside clusters at the ess and the hairpin.
	_add_cluster(Vector2(255, -150), 1.0)
	_add_cluster(Vector2(-260, -130), -1.0)

func _add_cluster(near: Vector2, side_sign: float) -> void:
	var i := _nearest_sample(near.x, near.y)
	var center := _road_samples[i] + _side(i) * 12.0 * side_sign
	for x in 3:
		for z in 3:
			var pos := center + Vector3((x - 1) * 2.2, 0.0, (z - 1) * 2.2)
			pos.y = _terrain_height(pos.x, pos.z) + 0.45
			_add_cone(pos)

func _add_cone(pos: Vector3) -> void:
	var cone := RigidBody3D.new()
	cone.mass = 0.8
	cone.position = pos
	cone.collision_layer = 2
	cone.collision_mask = 1

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
