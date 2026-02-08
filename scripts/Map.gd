extends Node3D
class_name Map

var thread: Thread
var loading_symbol: MeshInstance3D
var map_plane: CustomPlane
var tiles_api = TilesApi.new(3000)
var material: ShaderMaterial = ShaderMaterial.new()

var layers_count = tiles_api.layers.size()
var current_layer = 0

var level = 16
var coords: Vector2 = Vector2(0,0)
var map_radius: float = 6.0
var last_texture_coords: Vector2 = coords
var last_texture_radius: float = map_radius

var map_plane_radius: float = 2.0
var map_plane_resolution: int = 2048

#region PRIVATE METHODS
func _ready() -> void:
	map_plane = $MapPlane
	loading_symbol = $LoadingSymbol
	map_plane.generate_disk_mesh(map_plane_resolution, map_plane_radius)
	material.shader = ResourceLoader.load("res://scripts/map_shader.gdshader")
	map_plane.material_override = material
	add_child(Gizmo.new(Vector3(0,0,0)))
func _exit_tree():
	if thread != null:
		thread.wait_to_finish()
func _process(_delta: float) -> void:
	# Manage loading symbol display and collect thread
	if thread != null and thread.is_started() and not thread.is_alive():
		var img = thread.wait_to_finish()
		_update_texture(img)
		loading_symbol.hide()

func _update_texture_zoom() -> void:
	var map_zoom = 1.0-(last_texture_radius-map_radius+0.5)/(last_texture_radius+0.5)
	material.set_shader_parameter("ZOOM", Vector2(map_zoom, map_zoom))
func _update_texture_offset() -> void:
	var coords_offset = coords - (floor(last_texture_coords) + Vector2(0.5,0.5))
	var grid_offset: Vector2 = coords_offset/float(ceil(map_radius)*2+1)
	material.set_shader_parameter("OFFSET", grid_offset)
func _update_texture(image: Image) -> void:
	last_texture_coords = coords
	last_texture_radius = ceilf(map_radius)
	material.set_shader_parameter("TEXTURE", ImageTexture.create_from_image(image))
	_update_texture_offset()
	_update_texture_zoom()
func _get_map() -> Image:
	return tiles_api.layers[current_layer].get_circle_zone(Vector2i(floorf(coords.x), floorf(coords.y)), ceilf(map_radius), level, _update_texture)
#endregion
#region PUBLIC METHODS
func update_map_texture() -> void:
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
	coords = tiles_api.gps_to_grid(lat, long, level)
	_update_texture_offset()
func move_to_coords(x: float, y: float) -> void:
	coords = Vector2(x, y)
	_update_texture_offset()
func move_relative(x: float, y: float) -> void:
	coords += Vector2(x, y)
	_update_texture_offset()
# func move_meters_relative_to_gps(x: float, y: float) -> void:
# 	assert(false, "todo")
func zoom_map(zoom: float) -> void:
	map_radius *= 1.0-zoom
	_update_texture_zoom()
func set_map_level(l: int) -> void:
	level = l
	update_map_texture()
func scale_plane(plane_scale: float) -> void:
	map_plane.scale *= 1.0-plane_scale
## Clears the cached tiles for this layer
func clear_layer_cache(layer: int = -1) -> void:
	if layer == -1: layer = current_layer
	assert(layer >= 0 and layer < layers_count)
	tiles_api.layers[layer]._cache.empty_cache()
## Returns the cache size in byte for this layer
func get_layer_cache_size(layer: int = -1) -> float:
	if layer == -1: layer = current_layer
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer]._cache.get_cache_size()
func get_current_layer() -> int:
	return current_layer
func next_layer() -> void:
	current_layer = (current_layer+1)% layers_count
func prev_layer() -> void:
	current_layer = (current_layer-1)% layers_count
func set_layer(layer: int) -> void:
	assert(layer >= 0 and layer < layers_count)
	current_layer = layer
func get_layer_count() -> int:
	return layers_count
func get_layer_id(layer: int = -1) -> String:
	if layer == -1: layer = current_layer
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer].id()
func get_layer_name(layer: int = -1) -> String:
	if layer == -1: layer = current_layer
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer].name()
func get_layer_description(layer: int = -1) -> String:
	if layer == -1: layer = current_layer
	assert(layer >= 0 and layer < layers_count)
	return tiles_api.layers[layer].description()
#endregion
