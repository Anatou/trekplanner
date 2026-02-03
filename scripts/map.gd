extends Node3D
var thread: Thread


var tiles_api = TilesApi.new(3000)
var layers_count = tiles_api.layers.size()
var layer = 0
var material = StandardMaterial3D.new() 
var map_move_step = 3

var level = 16
var coords = tiles_api.gps_to_grid(45.1140770, 6.5637753, level)

var loading_symbol: MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$MapPlane.material_override = material
	loading_symbol = $LoadingSymbol

	var _temp_cache = Cache.new("tempo", false)


func _process(_delta: float) -> void:
	if thread != null and thread.is_started() and not thread.is_alive():
		var img = thread.wait_to_finish()
		material.albedo_texture = ImageTexture.create_from_image(img)
		loading_symbol.hide()

	if Input.is_action_just_pressed(&"map"): 
		get_map()
	if Input.is_action_just_pressed(&"next_map"): 
		layer = (layer+1)% layers_count
		get_map()
	if Input.is_action_just_pressed(&"prev_map"): 
		layer = (layer-1)% layers_count
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
	if Input.is_action_just_pressed(&"clear_cache"): 
		tiles_api.layers[layer]._cache.empty_cache()
	if Input.is_action_just_pressed(&"cache_info"): 
		var cache_size = tiles_api.layers[layer]._cache.get_cache_size()
		print("Cache size for layer <%s>: %dMo" % [tiles_api.layers[layer].name(), cache_size/1000000])


func update_texture(image: Image) -> void:
	material.albedo_texture = ImageTexture.create_from_image(image)

func get_map() -> void:
	if thread != null and thread.is_started() and thread.is_alive():
		return
	var f: Callable
	$LoadingSymbol.show()
	if not tiles_api.layers[layer].is_connected_to_host():
		f = func(): tiles_api.layers[layer].connect_to_host(); return tiles_api.layers[layer].get_square_zone(Vector2i(coords.x-6, coords.y-6), Vector2i(12, 12), level, update_texture)
		#f = func(): tiles_api.layers[layer].connect_to_host(); return tiles_api.layers[layer].get_circle_zone(Vector2i(coords.x, coords.y), 5, level, update_texture)
	else:
		f = func(): return tiles_api.layers[layer].get_square_zone(Vector2i(coords.x-6, coords.y-6), Vector2i(12, 12), level, update_texture)
		#f = func(): return tiles_api.layers[layer].get_circle_zone(Vector2i(coords.x, coords.y), 5, level, update_texture)
	thread = Thread.new()
	thread.start(f)

func _exit_tree():
	if thread != null:
		thread.wait_to_finish()
