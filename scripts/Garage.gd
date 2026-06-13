class_name Garage
# Car registry + selection. Add future cars here — each entry's script
# must implement the shared car contract used by Main/ChaseCamera/HUD:
#   flat_speed, drift_angle, is_drifting, cone_reach, cam_distance,
#   cam_height, signal crashed(impact_speed), respawn(), vel3()

static var selected := 0

static func cars() -> Array[Dictionary]:
	return [
		{
			"name": "KAZE",
			"desc": "drift coupe · nimble & slidey",
			"script": preload("res://scripts/Car.gd"),
		},
		{
			"name": "TANUKI",
			"desc": "prerunner truck · low, wide & zippy",
			"script": preload("res://scripts/Truck.gd"),
		},
	]

static func create_selected() -> Node3D:
	var def := cars()[clampi(selected, 0, cars().size() - 1)]
	return (def["script"] as GDScript).new()
