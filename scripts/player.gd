class_name Player extends Node3D

@export_range(0.01, 1, 0.01) var speed: float = .05 # m/s
@export_range(1, 100, 1) var acceleration: float = 10 # m/s^2
@export_range(0.1, 3.0, 0.1, "or_greater") var camera_sens: float = 2
@export_range(0.1, 3.0, 0.1, "or_greater") var hand_sens: float = 1
@export_range(0.01, 1, 0.01) var hand_dist_sens: float = .1
@export_range(0.1, 3.0, 0.1) var max_reach: float = 3
@export_range(0.1, 3.0, 0.1) var min_reach: float = .1

var mouse_captured: bool = false
var do_move_camera: bool = false

var move_dir: Vector2 # Input direction for movement
var look_dir: Vector2 # Input direction for look/aim
var hand_pos: Vector2 # Hand position on viewport
var hand_dist: float = 1.0 # Hand position on viewport
var walk_vel: Vector3 # Walking velocity 

@onready var camera: Camera3D = $PlayerCamera
@onready var hand: Node3D = $PlayerHand
@onready var map: Map = $"../Map"

func _ready() -> void:
	capture_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if mouse_captured and do_move_camera:
			look_dir = event.relative * 0.001
			_rotate_camera()
			_move_hand()
		elif mouse_captured:
			hand_pos += event.relative * hand_sens
			hand_pos = hand_pos.clamp(Vector2(0,0), get_viewport().size)
			_move_hand()
	if event is InputEventMouseButton:
		if not mouse_captured and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: 
			capture_mouse()
		if mouse_captured and event.button_index == MOUSE_BUTTON_RIGHT:
			if not do_move_camera and event.pressed: do_move_camera = true
			if do_move_camera and not event.pressed: do_move_camera = false
		if mouse_captured and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			hand_dist += hand_dist_sens
			hand_dist = clamp(hand_dist, min_reach, max_reach)
			_move_hand()
		if mouse_captured and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			hand_dist -= hand_dist_sens
			hand_dist = clamp(hand_dist, min_reach, max_reach)
			_move_hand()
		
	if Input.is_action_just_pressed(&"exit"): 
		if mouse_captured: release_mouse()
		else: get_tree().quit()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed(&"map"):        map.move_to_gps(45.1140770, 6.5637753); map.update_map_texture()
	if Input.is_action_just_pressed(&"next_map"):   map.next_layer(); map.update_map_texture()
	if Input.is_action_just_pressed(&"prev_map"):   map.prev_layer(); map.update_map_texture()
	if Input.is_action_just_pressed(&"clear_cache"): map.clear_layer_cache(map.get_current_layer())
	if Input.is_action_just_pressed(&"cache_info"):  print("Cache size for layer %s: %dMo" % [map.get_layer_id(), map.get_layer_cache_size()/1_000_000])
	if Input.is_action_pressed(&"map_left"):   map.move_relative(-delta*1.0,0)
	if Input.is_action_pressed(&"map_right"):  map.move_relative(delta*1.0,0)
	if Input.is_action_pressed(&"map_top"):    map.move_relative(0, -delta*1.0)
	if Input.is_action_pressed(&"map_bottom"): map.move_relative(0, delta*1.0)
	if Input.is_action_pressed(&"zoom_map_tiles"):   map.zoom_map(+delta*0.5)
	if Input.is_action_pressed(&"dezoom_map_tiles"): map.zoom_map(-delta*0.5)
	if Input.is_action_pressed(&"zoom_map_plane"):   map.scale_plane(+delta*0.5)
	if Input.is_action_pressed(&"dezoom_map_plane"): map.scale_plane(-delta*0.5)
	if Input.is_action_just_released(&"map_left"):         map.update_map_texture()
	if Input.is_action_just_released(&"map_right"):        map.update_map_texture()
	if Input.is_action_just_released(&"map_top"):          map.update_map_texture()
	if Input.is_action_just_released(&"map_bottom"):       map.update_map_texture()
	if Input.is_action_just_released(&"zoom_map_tiles"):   map.update_map_texture()
	if Input.is_action_just_released(&"dezoom_map_tiles"): map.update_map_texture()

func _physics_process(delta: float) -> void:
	var velocity = _walk(delta)
	if Input.is_action_pressed(&"move_up"): velocity += Vector3(0,speed,0)
	if Input.is_action_pressed(&"move_down"): velocity += Vector3(0,-speed,0)
	self.position += velocity

func capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mouse_captured = false

func _move_hand() -> void:
	var pos = camera.project_position(hand_pos, hand_dist)
	hand.position = pos-self.position

func _rotate_camera(sens_mod: float = 1.0) -> void:
	camera.rotation.y -= look_dir.x * camera_sens * sens_mod
	camera.rotation.x = clamp(camera.rotation.x - look_dir.y * camera_sens * sens_mod, -1.5, 1.5)

func _walk(delta: float) -> Vector3:
	move_dir = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backward")
	var _forward: Vector3 = camera.global_transform.basis * Vector3(move_dir.x, 0, move_dir.y)
	var walk_dir: Vector3 = Vector3(_forward.x, 0, _forward.z).normalized()
	walk_vel = walk_vel.move_toward(walk_dir * speed * move_dir.length(), acceleration * delta)
	return walk_vel
