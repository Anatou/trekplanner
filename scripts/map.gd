extends Node3D
var thread: Thread


var tiles_api = TilesApi.new(3000)
var layers = tiles_api.layers.keys()
var layer_i = 0
var layer = layers[layer_i]
var material = StandardMaterial3D.new() 
var map_move_step = 3

var level = 16
var coords = tiles_api.gps_to_grid(45.1140770, 6.5637753, level)

var loading_symbol: MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$MapPlane.material_override = material
	loading_symbol = $LoadingSymbol

func _process(_delta: float) -> void:
	if thread != null and thread.is_started() and not thread.is_alive():
		var img = thread.wait_to_finish()
		material.albedo_texture = ImageTexture.create_from_image(img)
		loading_symbol.hide()

	if Input.is_action_just_pressed(&"map"): 
		get_map()
	if Input.is_action_just_pressed(&"next_map"): 
		layer_i = (layer_i+1)%layers.size()
		layer = layers[layer_i]
		get_map()
	if Input.is_action_just_pressed(&"prev_map"): 
		layer_i = (layer_i-1)%layers.size()
		layer = layers[layer_i]
		get_map()
	if Input.is_action_just_pressed(&"map_left"): 
		coords += Vector2i(-map_move_step, 0)
		get_map()
	if Input.is_action_just_pressed(&"map_right"): 
		coords += Vector2i(map_move_step, 0)
		get_map()
	if Input.is_action_just_pressed(&"map_top"): 
		coords += Vector2i(0, -map_move_step)
		get_map()
	if Input.is_action_just_pressed(&"map_bottom"): 
		coords += Vector2i(0, map_move_step)
		get_map()

func update_texture(image: Image) -> void:
	material.albedo_texture = ImageTexture.create_from_image(image)

func get_map() -> void:
	if thread != null and thread.is_started() and thread.is_alive():
		return
	var f: Callable
	$LoadingSymbol.show()
	if not tiles_api.layers[layer].is_connected_to_host():
		#f = func(): tiles_api.layers[layer].connect_to_host(); return tiles_api.layers[layer].get_square_zone(Vector2i(coords.x-4, coords.y-4), Vector2i(8, 8), level, update_texture)
		f = func(): tiles_api.layers[layer].connect_to_host(); return tiles_api.layers[layer].get_circle_zone(Vector2i(coords.x, coords.y), 6, level, update_texture)
	else:
		#f = func(): return tiles_api.layers[layer].get_square_zone(Vector2i(coords.x-4, coords.y-4), Vector2i(8, 8), level, update_texture)
		f = func(): return tiles_api.layers[layer].get_circle_zone(Vector2i(coords.x, coords.y), 6, level, update_texture)
	thread = Thread.new()
	thread.start(f)

func _exit_tree():
	thread.wait_to_finish()
