extends Node
# Headless test harness: boots Main and injects scripted driving input.
# Never registered as an autoload — run it directly so project.godot is
# untouched (external edits there force a reload prompt in the editor):
#   godot --headless res://scenes/TestDrive.tscn -- drift
# Modes: straight (throttle only) · drift (throttle, then full-lock
# handbrake drift at t=4-8s, release after).

var t := 0.0
var mode := "drift"
var main: Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	# Second arg selects the car by Garage index (0=coupe, 1=truck).
	if args.size() > 1:
		Garage.selected = int(args[1])
	main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(main)

func _process(delta: float) -> void:
	t += delta
	_key(KEY_W, true)
	if mode == "drift":
		if t > 4.0 and t < 8.0:
			_key(KEY_A, true)
			_key(KEY_SPACE, true)
		elif t >= 8.0:
			_key(KEY_A, false)
			_key(KEY_SPACE, false)
	if Engine.get_process_frames() % 5 == 0:
		var car = main.car
		if car != null:
			var p: Vector3 = car.global_position
			var xform: Transform3D = car.global_transform
			var pitch := (-xform.basis.z).y
			print("t=%.1f pos=(%.0f,%.1f,%.0f) speed=%.1f angle=%.2f pitch=%.2f floor=%s" % [
				t, p.x, p.y, p.z, car.flat_speed, car.drift_angle, pitch, car.is_on_floor()])

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
