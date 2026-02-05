extends Node3D
class_name Map

var thread: Thread
var loading_symbol: MeshInstance3D
var map_plane: CustomPlane
var tiles_api = TilesApi.new(3000)

var layers_count = tiles_api.layers.size()
var current_layer = 0
var material: ShaderMaterial = ShaderMaterial.new()

var level = 16
var gps: Vector2 = Vector2(0,0)
var gps_move_step: float = 0.001

var map_plane_radius: float = 2.0
var map_plane_resolution: int = 2048
var map_tiles_radius: int = 6

#region PRIVATE METHODS
func _ready() -> void:
	map_plane = $MapPlane
	loading_symbol = $LoadingSymbol
	map_plane.generate_disk_mesh(map_plane_resolution, map_plane_radius)
	material.shader = ResourceLoader.load("res://scripts/map_shader.gdshader")
	map_plane.material_override = material
func _exit_tree():
	if thread != null:
		thread.wait_to_finish()
func _process(_delta: float) -> void:
	# Manage loading symbol display and collect thread
	if thread != null and thread.is_started() and not thread.is_alive():
		var img = thread.wait_to_finish()
		_update_texture(img)
		loading_symbol.hide()
	# Process inputs
	
func _update_texture(image: Image) -> void:
	var coords = tiles_api.gps_to_grid(gps.x, gps.y, level)
	var gps_snapped_to_tiles: Vector2 = tiles_api.grid_to_gps(coords.x, coords.y, level)
	var tile_size_in_gps: Vector2 = tiles_api.grid_to_gps(coords.x+1, coords.y+1, level) - gps_snapped_to_tiles
	var gps_snapped_tile_center = gps_snapped_to_tiles + tile_size_in_gps/2.0
	var gps_diff: Vector2 = gps-gps_snapped_tile_center
	var tile_offset: Vector2 = Vector2(gps_diff.y/tile_size_in_gps.y, gps_diff.x/tile_size_in_gps.x)
	# This currently only applies to a circle map
	var grid_offset: Vector2 = tile_offset/float(map_tiles_radius*2+1)
	var texture_scale = float(map_tiles_radius*2-1)/float(map_tiles_radius*2+1)
	material.set_shader_parameter("OFFSET", grid_offset)
	material.set_shader_parameter("SCALE", Vector2(texture_scale, texture_scale))
	material.set_shader_parameter("TEXTURE", ImageTexture.create_from_image(image))
func _get_map() -> Image:
	var coords = tiles_api.gps_to_grid(gps.x, gps.y, level)
	return tiles_api.layers[current_layer].get_circle_zone(Vector2i(coords.x, coords.y), map_tiles_radius, level, _update_texture)
#endregion
#region PUBLIC METHODS
func update_map() -> void:
	# If map is still getting updated
	if thread != null and thread.is_started() and thread.is_alive():
		return
	# Plan actions needed
	var f: Callable
	loading_symbol.show()
	if not tiles_api.layers[current_layer].is_connected_to_host():
		f = func(): tiles_api.layers[current_layer].connect_to_host(); return _get_map()
	else:
		f = func(): return _get_map()
	# Start thread
	thread = Thread.new()
	thread.start(f)
func move_to_gps(lat: float, long: float) -> void:
	gps = Vector2(lat, long)
	update_map()
func move_relative_to_gps(lat: float, long: float) -> void:
	gps += Vector2(lat, long)
	update_map()
func move_meters_relative_to_gps(x: float, y: float) -> void:
	assert(false, "todo")
func zoom_map(zoom: float) -> void:
	assert(false, "todo")
func scale_plane(plane_scale: float) -> void:
	map_plane_radius *= plane_scale
	map_plane.generate_disk_mesh(map_plane_resolution, map_plane_radius)
## Clears the cached tiles for this layer
func clear_layer_cache(layer: int) -> void:
	assert(layer >= 0 and layer < layers_count)
	tiles_api.layers[layer]._cache.empty_cache()
## Returns the cache size in byte for this layer
func get_layer_cache_size(layer: int) -> float:
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer]._cache.get_cache_size()
func get_current_layer() -> int:
	return current_layer
func next_layer() -> void:
	current_layer = (current_layer+1)% layers_count
	update_map()
func prev_layer() -> void:
	current_layer = (current_layer-1)% layers_count
	update_map()
func get_layer_count() -> int:
	return layers_count
func get_layer_id(layer: int) -> String:
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer].id()
func get_layer_name(layer: int) -> String:
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer].name()
func get_layer_description(layer: int) -> String:
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer].description()
#endregion
