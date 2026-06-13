class_name Tuning
# Persistent, profile-based tuning store. Holds editable physics params
# for each car, saved to user://tuning.cfg so edits survive restarts.
# Multiple named profiles (e.g. Balanced, Insane) can be swapped live.
#
# Schema per param: [default, min, max, step, label]. Cars read values
# via get_val(); the dev panel edits them; save() persists everything.

const PATH := "user://tuning.cfg"

const SCHEMA := {
	"coupe": {
		"engine_power": [42.0, 10.0, 200.0, 2.0, "Engine Power"],
		"max_speed":    [46.0, 15.0, 150.0, 2.0, "Top Speed"],
		"steer_rate":   [2.5, 0.5, 8.0, 0.1, "Steering"],
		"base_grip":    [10.0, 2.0, 30.0, 0.5, "Grip"],
		"drift_grip":   [2.2, 0.5, 12.0, 0.1, "Drift Slip"],
		"gravity":      [30.0, 8.0, 80.0, 1.0, "Gravity"],
	},
	"truck": {
		"engine_force": [30000.0, 8000.0, 120000.0, 1000.0, "Engine Power"],
		"top_speed":    [54.0, 20.0, 160.0, 2.0, "Top Speed"],
		"mass":         [1250.0, 600.0, 3000.0, 50.0, "Mass"],
		"spring_k":     [30000.0, 12000.0, 80000.0, 1000.0, "Spring Rate"],
		"spring_damp":  [2600.0, 800.0, 8000.0, 100.0, "Damping"],
		"mu_lat":       [1.25, 0.4, 3.0, 0.05, "Lateral Grip"],
		"mu_long":      [1.45, 0.4, 3.0, 0.05, "Drive Grip"],
		"steer_max":    [0.6, 0.2, 1.2, 0.02, "Steer Lock"],
	},
}

# Built-in profiles seeded on first run. Values here override SCHEMA
# defaults; anything omitted falls back to the default.
const SEED_PROFILES := {
	"Balanced": {},
	"Insane": {
		"coupe": {"engine_power": 110.0, "max_speed": 95.0, "steer_rate": 3.6, "drift_grip": 1.4},
		"truck": {"engine_force": 85000.0, "top_speed": 120.0, "mass": 850.0, "mu_long": 2.2},
	},
}

static var profiles: Dictionary = {}
static var current: String = "Balanced"
static var _loaded := false

static func _ensure() -> void:
	if not _loaded:
		load_cfg()

static func get_val(car: String, key: String) -> float:
	_ensure()
	var prof: Dictionary = profiles.get(current, {})
	var cardict: Dictionary = prof.get(car, {})
	if cardict.has(key):
		return float(cardict[key])
	return float(SCHEMA[car][key][0])

static func set_val(car: String, key: String, value: float) -> void:
	_ensure()
	if not profiles.has(current):
		profiles[current] = {}
	if not profiles[current].has(car):
		profiles[current][car] = {}
	profiles[current][car][key] = value

static func profile_names() -> Array:
	_ensure()
	return profiles.keys()

static func add_profile(pname: String) -> void:
	_ensure()
	if pname.strip_edges() == "" or profiles.has(pname):
		return
	# Clone the current profile's overrides as a starting point.
	var src: Dictionary = profiles.get(current, {})
	var copy := {}
	for car: String in src:
		copy[car] = (src[car] as Dictionary).duplicate()
	profiles[pname] = copy
	current = pname

static func delete_profile(pname: String) -> void:
	_ensure()
	if profiles.size() <= 1 or not profiles.has(pname):
		return
	profiles.erase(pname)
	if current == pname:
		current = profiles.keys()[0]

static func reset_current() -> void:
	_ensure()
	profiles[current] = {}

static func load_cfg() -> void:
	_loaded = true
	profiles = {}
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		current = cfg.get_value("_meta", "current", "Balanced")
		for section in cfg.get_sections():
			if section == "_meta":
				continue
			# Section format: "<profile>/<car>"
			var parts := section.split("/")
			if parts.size() != 2:
				continue
			var pname := parts[0]
			var car := parts[1]
			if not profiles.has(pname):
				profiles[pname] = {}
			var cardict := {}
			for key in cfg.get_section_keys(section):
				cardict[key] = float(cfg.get_value(section, key))
			profiles[pname][car] = cardict
	# Ensure seed profiles exist (first run, or new built-ins added later).
	for pname: String in SEED_PROFILES:
		if not profiles.has(pname):
			var seed: Dictionary = SEED_PROFILES[pname]
			var copy := {}
			for car: String in seed:
				copy[car] = (seed[car] as Dictionary).duplicate()
			profiles[pname] = copy
	if not profiles.has(current):
		current = "Balanced"

static func save_cfg() -> void:
	_ensure()
	var cfg := ConfigFile.new()
	cfg.set_value("_meta", "current", current)
	for pname: String in profiles:
		var prof: Dictionary = profiles[pname]
		# Always write at least an empty marker so the profile persists.
		cfg.set_value("_meta", "profile_" + pname, true)
		for car: String in prof:
			var cardict: Dictionary = prof[car]
			for key: String in cardict:
				cfg.set_value(pname + "/" + car, key, cardict[key])
	cfg.save(PATH)
