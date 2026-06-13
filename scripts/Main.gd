extends Node3D

const VERSION := "0.9.2"
const CONE_POINTS := 75

const MAP_SIZE := 1400.0
const GRID_N := 185               # terrain vertices per side
const ROAD_WIDTH := 14.0
const ROAD_CARVE := 28.0          # how far the roadbed blends into the hills
const PLAZA := Vector2(0.0, 190.0)
const PLAZA_R := 50.0
const PLAZA_H := 3.0

# Desert canyon (east of the mountains): the rim opens up past DESERT_X,
# terrain becomes a sandy plateau, and the canyon pass cuts down to a
# river running along the canyon floor.
const DESERT_X := 330.0
const PLATEAU_H := 26.0
const CANYON_FLOOR := -12.0
const CANYON_INNER := 26.0        # flat canyon floor half-width
const CANYON_OUTER := 100.0       # distance over which walls rise to plateau
const RIVER_OFFSET := 17.0        # river sits this far to one side of the road
const RIVER_HALF := 6.0           # river half-width
const RIVER_DEPTH := 1.4          # trench depth below the water surface

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

var air_time := 0.0
var air_launch_speed := 0.0
var _was_grounded := true

var _cones: Array[RigidBody3D] = []
var _cone_spawns: Array[Vector3] = []
var _cone_hit: Array[bool] = []

var _noise := FastNoiseLite.new()
var _road_samples: Array[Vector3] = []      # the tōge loop (scenery anchors)
var _road_tangents: Array[Vector3] = []
var _spur_samples: Array[Vector3] = []      # the canyon pass / desert route
var _spur_tangents: Array[Vector3] = []
var _carve_samples: Array[Vector3] = []     # loop + spur, for terrain carving
var _carve_next: PackedInt32Array = []      # next sample on same road (-1 = end)
var _carve_prev: PackedInt32Array = []      # prev sample on same road (-1 = end)
var _road_grid: Dictionary = {}             # cell -> indices into _carve_samples
var _spur_grid: Dictionary = {}             # cell -> indices into _spur_samples
var _river_pts: Array[Vector3] = []         # river centerline (y = water surface)
var _river_grid: Dictionary = {}            # cell -> indices into _river_pts
var _petals: GPUParticles3D
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_idx := 0

func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 4

	_build_environment()
	_build_road_path()
	_build_canyon_path()
	_build_terrain()
	_build_road_mesh()
	_build_river()
	_build_boundaries()
	_build_pagoda_plaza()
	_build_torii_gates()
	_build_trees()
	_build_mountains()
	_build_desert_scenery()
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

	var pause := PauseLayer.new()
	pause.live_car = car
	add_child(pause)

	# Audio: looping engine/skid tied to the car, plus a one-shot pool.
	var car_audio := preload("res://scripts/CarAudio.gd").new()
	car_audio.car = car
	add_child(car_audio)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)

func _play_sfx(stream: AudioStream, vol := 0.0, pitch := 1.0) -> void:
	var p := _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()

func _physics_process(delta: float) -> void:
	hud.set_speed(car.flat_speed * 3.6)
	_petals.global_position = car.global_position + Vector3(0, 16, 0)

	# Compass bearing: N = -Z, E = +X.
	var xform: Transform3D = car.global_transform
	var fwd := -xform.basis.z
	hud.set_heading(rad_to_deg(atan2(fwd.x, -fwd.z)))

	_update_airtime(delta)

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

func _update_airtime(delta: float) -> void:
	var grounded: bool = car.is_on_floor()
	if not grounded:
		if air_time == 0.0:
			air_launch_speed = car.flat_speed
		air_time += delta
		# Live readout once it's clearly a jump, not a bump.
		if air_time > 0.35:
			hud.set_air(true, _air_award())
	else:
		if not _was_grounded and air_time > 0.45:
			var pts := _air_award()
			if pts > 0:
				total_score += pts
				var label := "AIRTIME +%d" % pts
				if air_time > 1.6:
					label = "HUGE AIR +%d" % pts
				hud.flash(label, Color(0.55, 0.8, 1.0))
				_play_sfx(Sfx.whoosh(), -2.0, clampf(1.3 - air_time * 0.2, 0.7, 1.3))
		hud.set_air(false, 0)
		air_time = 0.0
	_was_grounded = grounded

func _air_award() -> int:
	# Longer hangtime and faster launches are worth more.
	return int(air_time * air_time * 140.0 + air_time * air_launch_speed * 6.0)

func _bank_drift() -> void:
	if drift_points >= 50.0:
		total_score += int(drift_points)
		hud.flash("+%d BANKED" % int(drift_points), Color(0.4, 1.0, 0.6))
		_play_sfx(Sfx.chime(), -5.0)
	drift_points = 0.0
	multiplier = 1.0
	drift_chain_active = false

func _on_car_crashed(_impact_speed: float) -> void:
	_play_sfx(Sfx.thud(), 2.0, randf_range(0.8, 1.0))
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
			_play_sfx(Sfx.thud(), -8.0, randf_range(1.4, 1.9))
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
	_register_carve(_road_samples, true)

func _build_canyon_path() -> void:
	# Open spur off the loop's east straight: a smooth canyon pass that
	# descends through the mountains into a desert canyon, then sweeps
	# along the river. All flowing curves — no tight corners.
	var pts: Array[Vector3] = [
		Vector3(245, 22, 40),     # junction on the loop
		Vector3(335, 15, 78),     # climbing out east
		Vector3(430, 7, 55),      # the pass — gap in the mountains
		Vector3(515, -3, -5),     # dropping into the basin
		Vector3(560, -9, -110),   # entering the canyon, sweeping south
		Vector3(600, -11, -210),
		Vector3(565, -12, -310),  # long right-hand sweeper
		Vector3(470, -12, -370),
		Vector3(360, -11, -395),  # canyon floor straight
		Vector3(250, -10, -380),  # scenic turnaround end
	]
	var n := pts.size()
	var curve := Curve3D.new()
	for i in n:
		var prev := pts[maxi(i - 1, 0)]
		var nxt := pts[mini(i + 1, n - 1)]
		var tangent := (nxt - prev) * 0.3
		curve.add_point(pts[i], -tangent, tangent)

	var length := curve.get_baked_length()
	var count := int(length / 6.0)
	for i in count:
		_spur_samples.append(curve.sample_baked(length * i / float(count - 1)))
	for i in count:
		var a := _spur_samples[maxi(i - 1, 0)]
		var b := _spur_samples[mini(i + 1, count - 1)]
		_spur_tangents.append((b - a).normalized())

	# Spur gets its own grid (for canyon shaping) plus the shared carve grid.
	for i in count:
		var cell := Vector2i(floori(_spur_samples[i].x / 32.0), floori(_spur_samples[i].z / 32.0))
		if not _spur_grid.has(cell):
			_spur_grid[cell] = []
		_spur_grid[cell].append(i)
	_register_carve(_spur_samples, false)

	# River centerline: offset from the spur, desert portion only. Water
	# surface sits a touch below road level; the terrain carves a trench.
	for i in count:
		if _desert_weight(_spur_samples[i].x, _spur_samples[i].z) < 0.8:
			continue
		var side := _side_t(_spur_tangents, i)
		var rp := _spur_samples[i] + side * RIVER_OFFSET
		rp.y = _spur_samples[i].y - 0.6
		_river_pts.append(rp)
	for i in _river_pts.size():
		var cell := Vector2i(floori(_river_pts[i].x / 32.0), floori(_river_pts[i].z / 32.0))
		if not _river_grid.has(cell):
			_river_grid[cell] = []
		_river_grid[cell].append(i)

func _register_carve(samples: Array[Vector3], closed: bool) -> void:
	var base := _carve_samples.size()
	var n := samples.size()
	for s in samples:
		_carve_samples.append(s)
	for i in n:
		var idx := base + i
		# Neighbour links so the carve can interpolate height along segments
		# instead of snapping to the nearest sample (which steps on slopes).
		var nxt := base + (i + 1) if i + 1 < n else (base if closed else -1)
		var prv := base + (i - 1) if i - 1 >= 0 else (base + n - 1 if closed else -1)
		_carve_next.append(nxt)
		_carve_prev.append(prv)
		var cell := Vector2i(floori(samples[i].x / 32.0), floori(samples[i].z / 32.0))
		if not _road_grid.has(cell):
			_road_grid[cell] = []
		_road_grid[cell].append(idx)

func _side(i: int) -> Vector3:
	var t := _road_tangents[i]
	return Vector3(t.z, 0.0, -t.x).normalized()

func _side_t(tangents: Array[Vector3], i: int) -> Vector3:
	var t := tangents[i]
	return Vector3(t.z, 0.0, -t.x).normalized()

func _nearest_river(x: float, z: float) -> Vector2:
	# (xz distance to river centerline, water-surface height there).
	var c := Vector2i(floori(x / 32.0), floori(z / 32.0))
	var bd := 1e18
	var by := 0.0
	for cx in range(c.x - 1, c.x + 2):
		for cz in range(c.y - 1, c.y + 2):
			var cell := Vector2i(cx, cz)
			if not _river_grid.has(cell):
				continue
			for i: int in _river_grid[cell]:
				var dx := _river_pts[i].x - x
				var dz := _river_pts[i].z - z
				var d := dx * dx + dz * dz
				if d < bd:
					bd = d
					by = _river_pts[i].y
	return Vector2(sqrt(bd), by)

func _nearest_spur(x: float, z: float) -> Vector2:
	# (xz distance to spur centerline, road height there) via the spur grid.
	var c := Vector2i(floori(x / 32.0), floori(z / 32.0))
	var bd := 1e18
	var by := 0.0
	for cx in range(c.x - 2, c.x + 3):
		for cz in range(c.y - 2, c.y + 3):
			var cell := Vector2i(cx, cz)
			if not _spur_grid.has(cell):
				continue
			for i: int in _spur_grid[cell]:
				var dx := _spur_samples[i].x - x
				var dz := _spur_samples[i].z - z
				var d := dx * dx + dz * dz
				if d < bd:
					bd = d
					by = _spur_samples[i].y
	return Vector2(sqrt(bd), by)

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
	# Nearest sample via the hash grid, then project onto the two adjacent
	# segments and interpolate height — so the carve follows the smooth road
	# elevation instead of stepping between samples on slopes.
	var c := Vector2i(floori(x / 32.0), floori(z / 32.0))
	var bd := 1e18
	var best := -1
	for cx in range(c.x - 1, c.x + 2):
		for cz in range(c.y - 1, c.y + 2):
			var cell := Vector2i(cx, cz)
			if not _road_grid.has(cell):
				continue
			for i: int in _road_grid[cell]:
				var dx := _carve_samples[i].x - x
				var dz := _carve_samples[i].z - z
				var d := dx * dx + dz * dz
				if d < bd:
					bd = d
					best = i
	if best < 0:
		return Vector2(1e9, 0.0)
	var res := Vector2(sqrt(bd), _carve_samples[best].y)
	for nb: int in [_carve_next[best], _carve_prev[best]]:
		if nb >= 0:
			var seg := _project_segment(x, z, _carve_samples[best], _carve_samples[nb])
			if seg.x < res.x:
				res = seg
	return res

func _project_segment(x: float, z: float, a: Vector3, b: Vector3) -> Vector2:
	# Closest point on segment a-b (in xz), returns (distance, interpolated y).
	var abx := b.x - a.x
	var abz := b.z - a.z
	var denom := abx * abx + abz * abz
	var t := 0.0
	if denom > 0.0001:
		t = clampf(((x - a.x) * abx + (z - a.z) * abz) / denom, 0.0, 1.0)
	var cx := a.x + abx * t
	var cz := a.z + abz * t
	var cy := a.y + (b.y - a.y) * t
	var dx := x - cx
	var dz := z - cz
	return Vector2(sqrt(dx * dx + dz * dz), cy)

func _desert_weight(x: float, z: float) -> float:
	# 0 in the green valley, 1 deep in the desert (blends across the gap).
	return smoothstep(DESERT_X - 60.0, DESERT_X + 80.0, x)

func _terrain_height(x: float, z: float) -> float:
	var dw := _desert_weight(x, z)

	# Green-valley base + sandy-plateau base, blended by desert weight.
	var valley := _noise.get_noise_2d(x, z) * 14.0 + 8.0
	var dunes := _noise.get_noise_2d(x * 0.6 + 500.0, z * 0.6) * 7.0
	var plateau := PLATEAU_H + dunes
	var h := lerpf(valley, plateau, dw)

	# Mountain rim — but the east side opens up so the pass leads to desert.
	var rx := absf(x) / (MAP_SIZE / 2.0)
	var rz := absf(z) / (MAP_SIZE / 2.0)
	var rim := maxf(rz, rx if x < 0.0 else rx * (1.0 - dw))
	var east_edge := smoothstep(0.86, 1.04, x / (MAP_SIZE / 2.0)) * dw
	var edge := maxf(smoothstep(0.6, 1.05, rim), east_edge * 0.35)
	h += edge * edge * 110.0 + edge * absf(_noise.get_noise_2d(x * 3.0 + 900.0, z * 3.0)) * 50.0

	# Desert canyon: cut a steep-walled channel down to the river/road.
	if dw > 0.01:
		var spur := _nearest_spur(x, z)
		if spur.x < CANYON_OUTER:
			var floor_h := spur.y - 1.0
			var wall := lerpf(floor_h, h, smoothstep(CANYON_INNER, CANYON_OUTER, spur.x))
			h = lerpf(h, wall, dw)
		# River trench: a sunken channel the water sits in, with banks.
		if not _river_pts.is_empty():
			var river := _nearest_river(x, z)
			if river.x < RIVER_HALF + 6.0:
				var bed := river.y - RIVER_DEPTH
				h = lerpf(bed, h, smoothstep(RIVER_HALF, RIVER_HALF + 6.0, river.x))

	# Flat plaza pad (green side only).
	var dp := Vector2(x, z).distance_to(PLAZA)
	if dp < PLAZA_R + 25.0:
		h = lerpf(PLAZA_H, h, smoothstep(PLAZA_R, PLAZA_R + 25.0, dp))

	# Carve the actual roadbed into whatever's underneath (loop + spur).
	# Flat band a touch below the road across the full width + a margin, so
	# the surface always sits just above the terrain (no clip-through), then
	# a graded shoulder blends out to the natural slope (no abrupt gap).
	var road := _nearest_road(x, z)
	if road.x < ROAD_CARVE:
		var bed := road.y - 0.25
		h = lerpf(bed, h, smoothstep(ROAD_WIDTH / 2.0 + 2.5, ROAD_CARVE, road.x))
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
	var sand := Color(0.78, 0.62, 0.36)
	var sand_b := Color(0.7, 0.53, 0.3)
	var red_rock := Color(0.62, 0.32, 0.2)
	var red_dark := Color(0.45, 0.22, 0.14)

	var colors := []
	colors.resize(n * n)
	for zi in n:
		for xi in n:
			var wx := xi * cell - half
			var wz := zi * cell - half
			var h := heights[zi * n + xi]
			var hx0 := heights[zi * n + maxi(xi - 1, 0)]
			var hx1 := heights[zi * n + mini(xi + 1, n - 1)]
			var hz0 := heights[maxi(zi - 1, 0) * n + xi]
			var hz1 := heights[mini(zi + 1, n - 1) * n + xi]
			var steep := Vector2((hx1 - hx0) / (2.0 * cell), (hz1 - hz0) / (2.0 * cell)).length()
			# Green-valley palette.
			var green := grass_a.lerp(grass_b, (_noise.get_noise_2d(xi * 31.0, zi * 31.0) + 1.0) * 0.5)
			green = green.lerp(rock, clampf((steep - 0.45) * 2.5, 0.0, 1.0))
			green = green.lerp(rock, smoothstep(50.0, 80.0, h))
			green = green.lerp(snow, smoothstep(85.0, 110.0, h))
			# Desert palette: sand floor, banded red rock on the canyon walls.
			var band := (sin(h * 0.35) + 1.0) * 0.5
			var desert := sand.lerp(sand_b, (_noise.get_noise_2d(xi * 23.0 + 7.0, zi * 23.0) + 1.0) * 0.5)
			var wall := red_rock.lerp(red_dark, band)
			desert = desert.lerp(wall, clampf((steep - 0.4) * 2.2, 0.0, 1.0))
			colors[zi * n + xi] = green.lerp(desert, _desert_weight(wx, wz))

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
	_build_ribbon(_road_samples, _road_tangents, true)
	_build_ribbon(_spur_samples, _spur_tangents, false)

func _build_ribbon(samples: Array[Vector3], tangents: Array[Vector3], closed: bool) -> void:
	var count := samples.size()
	var half := ROAD_WIDTH / 2.0
	var segs := count if closed else count - 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var skirt_out := 2.2
	var skirt_down := Vector3.DOWN * 0.9
	for i in segs:
		var j := (i + 1) % count
		var si := _side_t(tangents, i)
		var sj := _side_t(tangents, j)
		var li := samples[i] + si * half
		var ri := samples[i] - si * half
		var lj := samples[j] + sj * half
		var rj := samples[j] - sj * half
		for v in [li, lj, ri, ri, lj, rj]:
			st.add_vertex(v)
			faces.append(v)
		# Shoulder skirts drape from each road edge outward and down, hiding
		# any lip/gap where the coarse terrain doesn't meet the road edge.
		var lo_i := li + si * skirt_out + skirt_down
		var lo_j := lj + sj * skirt_out + skirt_down
		var ro_i := ri - si * skirt_out + skirt_down
		var ro_j := rj - sj * skirt_out + skirt_down
		for v in [li, lo_i, lj, lj, lo_i, lo_j]:
			st.add_vertex(v)
		for v in [ri, rj, ro_i, ro_i, rj, ro_j]:
			st.add_vertex(v)
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
	_add_road_lines(samples, tangents, closed, [half - 0.7, -(half - 0.7)], 0.35, false, Color(0.92, 0.92, 0.9))
	_add_road_lines(samples, tangents, closed, [0.0], 0.3, true, Color(0.95, 0.8, 0.25))

func _add_road_lines(samples: Array[Vector3], tangents: Array[Vector3], closed: bool, offsets: Array, width: float, dashed: bool, color: Color) -> void:
	var count := samples.size()
	var segs := count if closed else count - 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.06
	for offset: float in offsets:
		for i in segs:
			if dashed and i % 4 >= 2:
				continue
			var j := (i + 1) % count
			var li := samples[i] + _side_t(tangents, i) * (offset + width / 2.0) + lift
			var ri := samples[i] + _side_t(tangents, i) * (offset - width / 2.0) + lift
			var lj := samples[j] + _side_t(tangents, j) * (offset + width / 2.0) + lift
			var rj := samples[j] + _side_t(tangents, j) * (offset - width / 2.0) + lift
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

func _build_river() -> void:
	# Water ribbon sitting in the carved river trench (built from the same
	# centerline the terrain trench was carved from, so it always fits).
	if _river_pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	for i in _river_pts.size():
		var a := _river_pts[maxi(i - 1, 0)]
		var b := _river_pts[mini(i + 1, _river_pts.size() - 1)]
		var dir := (b - a)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(dir.z, 0.0, -dir.x)
		verts.append(_river_pts[i] + side * RIVER_HALF)
		verts.append(_river_pts[i] - side * RIVER_HALF)
	for i in range(0, verts.size() - 2, 2):
		var a := verts[i]
		var b := verts[i + 1]
		var c := verts[i + 2]
		var d := verts[i + 3]
		for v in [a, c, b, b, c, d]:
			st.add_vertex(v)
	st.generate_normals()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.5, 0.62, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = 0.5
	mat.roughness = 0.1
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.4, 0.55)
	mat.emission_energy_multiplier = 0.4
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
	# Fuji to the north plus a skyline ring beyond the playable map. The
	# east side is left open so the canyon pass leads out to the desert.
	_add_mountain(Vector3(40, 0, -780), 320.0, 250.0, true)
	_add_mountain(Vector3(-760, 0, 120), 220.0, 190.0, true)
	_add_mountain(Vector3(-640, 0, -460), 190.0, 160.0, false)
	_add_mountain(Vector3(-420, 0, 740), 200.0, 170.0, false)
	_add_mountain(Vector3(360, 0, 760), 180.0, 140.0, false)
	# Distant desert buttes far to the east, low on the horizon.
	_add_mountain(Vector3(880, 0, -250), 150.0, 110.0, false, Color(0.58, 0.3, 0.19))
	_add_mountain(Vector3(840, 0, -520), 130.0, 90.0, false, Color(0.52, 0.27, 0.18))
	_add_mountain(Vector3(840, 0, 60), 140.0, 95.0, false, Color(0.6, 0.32, 0.2))

func _build_desert_scenery() -> void:
	# Red-rock mesas and saguaro cacti scattered through the desert, with
	# a cluster of buttes flanking the canyon route.
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 42
	var mesa_spots := [
		Vector2(470, 140), Vector2(620, -40), Vector2(700, -180),
		Vector2(430, -250), Vector2(620, -430), Vector2(330, -300),
		Vector2(540, 60),
	]
	for spot: Vector2 in mesa_spots:
		var base_y := _terrain_height(spot.x, spot.y)
		_add_mesa(Vector3(spot.x, base_y, spot.y), seed_rng.randf_range(16.0, 30.0), seed_rng.randf_range(18.0, 40.0))

	# Saguaro cacti dotted along the desert floor.
	for i in 40:
		var x := seed_rng.randf_range(DESERT_X + 40.0, 660.0)
		var z := seed_rng.randf_range(-440.0, 200.0)
		var spur := _nearest_spur(x, z)
		# Keep them off the road but in the canyon area or floor.
		if spur.x < 20.0 or spur.x > 120.0:
			continue
		var y := _terrain_height(x, z)
		_add_cactus(Vector3(x, y - 0.3, z), seed_rng)

func _add_mesa(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var layers := 3
	var r := radius
	var y := 0.0
	var rock_a := Color(0.6, 0.31, 0.19)
	var rock_b := Color(0.5, 0.26, 0.17)
	for l in layers:
		var h := height / layers
		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r * 0.92
		cyl.bottom_radius = r
		cyl.height = h
		cyl.radial_segments = 7
		mesh.mesh = cyl
		mesh.position = Vector3(0, y + h / 2.0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = rock_a if l % 2 == 0 else rock_b
		mat.roughness = 1.0
		mesh.material_override = mat
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		var cshape := CylinderShape3D.new()
		cshape.radius = r * 0.92
		cshape.height = h
		col.shape = cshape
		col.position = Vector3(0, y + h / 2.0, 0)
		body.add_child(col)
		y += h
		r *= 0.78
	add_child(body)

func _add_cactus(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var cactus := StaticBody3D.new()
	cactus.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.42, 0.26)
	mat.roughness = 0.9
	var trunk_h := rng.randf_range(3.0, 5.5)
	var trunk := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.4
	tm.height = trunk_h
	trunk.mesh = tm
	trunk.position = Vector3(0, trunk_h / 2.0, 0)
	trunk.material_override = mat
	cactus.add_child(trunk)
	var col := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.4
	cs.height = trunk_h
	col.shape = cs
	col.position = Vector3(0, trunk_h / 2.0, 0)
	cactus.add_child(col)
	# A couple of arms.
	for s in [-1.0, 1.0]:
		if rng.randf() < 0.4:
			continue
		var arm := MeshInstance3D.new()
		var am := CapsuleMesh.new()
		am.radius = 0.3
		am.height = 1.8
		arm.mesh = am
		arm.material_override = mat
		var ah := rng.randf_range(1.2, trunk_h - 1.0)
		arm.position = Vector3(s * 0.7, ah, 0)
		arm.rotation.z = -s * 0.9
		cactus.add_child(arm)
		var arm2 := MeshInstance3D.new()
		arm2.mesh = am
		arm2.material_override = mat
		arm2.position = Vector3(s * 1.0, ah + 1.0, 0)
		cactus.add_child(arm2)
	add_child(cactus)

func _add_mountain(pos: Vector3, base_radius: float, height: float, snow_cap: bool, tint := Color(0.45, 0.5, 0.62)) -> void:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = tint
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
