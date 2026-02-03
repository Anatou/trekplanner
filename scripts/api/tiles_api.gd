class_name TilesApi

var _timeout: int ## Time before request timeout (in ms)
var layers: Dictionary[String,TileApi]

func _init(timeout: int = 5000) -> void:
	_timeout = timeout
	layers = {
		"cyclosm": CyclosmTileApi.new(_timeout),
		"osm": OsmTileApi.new(_timeout),
		"topo": TopoTileApi.new(_timeout),
	}

## Convert XYZ Web Mercator coordinates to GPS
func grid_to_gps(x: int, y: int, level: int) -> Vector2:
	#https://gis.stackexchange.com/questions/461842/generating-my-own-xyz-tiles-how-do-x-y-z-map-to-gps-bounds
	# Based on the OSM wiki page for "slippy map" tilenames, XYZ tiles use the Web Mercator projection (WGS84/EPSG:3857)
	var n = 2**level
	var a = PI*(1-2*y/(n as float))
	var lat = 180/PI * atan(sinh(a))
	var long = 360*x/((n - 180) as float)
	return Vector2(snapped(lat, .001), snapped(long, .001))
## Convert GPS coordinates to XYZ Web Mercator
func gps_to_grid(lat: float, long: float, level: int) -> Vector2i:
	#https://gis.stackexchange.com/questions/461842/generating-my-own-xyz-tiles-how-do-x-y-z-map-to-gps-bounds
	# Based on the OSM wiki page for "slippy map" tilenames, XYZ tiles use the Web Mercator projection (WGS84/EPSG:3857)
	var n = 2**level
	var r = PI/180.0 * lat
	var lts = log(tan(r) + 1/cos(r))
	var x = n*(0.5+long/360)
	var y = n*(1-lts/PI) /2
	return Vector2i(round(x), round(y))

@abstract class TileApi extends Node:
	var _timeout: int ## Time before request timeout (in ms)
	var _max_workers: int ## Maximum parallel Http worker count
	var _is_connected_to_host: bool = false ## Object starts disconnected to ease startup time, use [code]connect_to_host()[/code] to connect
	var http_workers: HttpWorkerPool ## HTTP workers manager

	#region ABSTRACT MEHTODS	
	@abstract func name() -> String ## Returns API name for display
	@abstract func description() -> String ## Returns API description for display

	## Returns prepared request (without host) as a string [br]
	## ex: "/7/1/1.png"
	@abstract func _get_request(x: int, y: int, level: int) -> String

	## Returns an [code]Array[String][/code] of all possible hosts
	## Hosts are used following a round robin 
	@abstract func _get_host() -> Array[String]

	## Returns the tile size (which is both height and width as tiles are squares)
	@abstract func _get_size() -> int

	## Transforms the response body in the correct image format, returns the error code
	@abstract func _body_to_img(image: Image, body: PackedByteArray) -> int
	#endregion
	#region PRIVATE MEHTODS
	func _init(timeout: int = 5000, max_workers: int = 16) -> void:
		_timeout = timeout
		_max_workers = max_workers
	func _make_headers(w:int) -> Array[String]:
		return [
			"Host: %s" % http_workers.get_worker_host(w),
			"User-Agent: trekplanner/0.1.0 (Godot)",
			"Accept-Language: en-US,en;q=0.5",
			"Accept-Encoding: gzip",
			"Connection: keep-alive",
		]
	func _get_error_tile() -> Image:
		var image = Image.create_empty(self._get_size(), self._get_size(), false, Image.FORMAT_RGB8)
		image.fill(Color.ORANGE)
		return image
	func _get_tile_batch(coords_queue: Array[Vector2i], pos: Vector2i, out_image: Image, level: int, callback: Callable, update_count: int = 15) -> Image:
		var start_time = Time.get_ticks_msec()
		var worker_coords: Dictionary[int, Vector2i] = {}
		var finished_workers: Array[int] = []
		var count = 0
		var img_count = coords_queue.size()
		# Get the tiles
		while count < img_count:
			if Time.get_ticks_msec()-start_time > _timeout:
				push_warning("get_square_zone: TIMEOUT")
				break
			# Start requests
			if not coords_queue.is_empty():
				var available_worker_count = http_workers.get_available_worker_count()
				for _w in min(available_worker_count, coords_queue.size()):
					var worker = http_workers.get_available_worker()
					worker_coords[worker.id] = coords_queue.pop_front()
					var request = self._get_request(worker_coords[worker.id].x+pos.x, worker_coords[worker.id].y+pos.y, level)
					var headers = self._make_headers(worker.id)
					worker.w.request(worker.w.METHOD_GET, request, headers)
			# Poll requests
			while http_workers.get_busy_worker_count() > 0 and finished_workers.size() == 0:
				finished_workers = http_workers.poll()
				if Time.get_ticks_msec()-start_time > _timeout:
					push_warning("get_square_zone: TIMEOUT (from polling loop)")
					break
			# Treat finished workers
			for w in finished_workers:
				var body = http_workers.get_response_body(w)
				var res: Image
				var err = -1
				if not body.is_empty(): 
					res = Image.new()
					err = self._body_to_img(res, body)
				if err != OK: 
					# Request failed and is started again
					# Place a red temporary tile to notify user
					res = self._get_error_tile()
					var request = self._get_request(worker_coords[w].x+pos.x, worker_coords[w].y+pos.y, level)
					var worker = http_workers.get_worker(w)
					var headers = self._make_headers(worker.id)
					worker.w.request(worker.w.METHOD_GET, request, headers)
				var rect = Rect2i(0, 0, self._get_size(), self._get_size())
				var coords = worker_coords[w]
				out_image.blit_rect(res, rect, coords*self._get_size())
				count += 1
				if count % update_count == 0:
					callback.call_deferred(out_image)
			finished_workers = []
		http_workers.reset_busy_workers()
		return out_image
	#endregion
	#region PUBLIC METHODS
	func connect_to_host() -> void:
		if not _is_connected_to_host:
			http_workers = HttpWorkerPool.new(self._get_host(), _timeout, _max_workers)
			_is_connected_to_host = true
	func is_connected_to_host() -> bool: 
		return _is_connected_to_host
	func get_tile(x: int, y: int, level: int) -> Image:
		var start_time = Time.get_ticks_msec()
		var worker: HttpWorker = http_workers.get_available_worker()
		var headers = self._make_headers(worker.id)
		var request = self._get_request(x, y, level)
		worker.w.request(worker.w.METHOD_GET, request, headers)
		while http_workers.poll_one(worker.id):
			if Time.get_ticks_msec()-start_time > _timeout:
				return self._get_error_tile()
		var body = http_workers.get_response_body(worker.id)
		var image = Image.new()
		var err = self._body_to_img(image, body)
		if err != OK:
			image = self._get_error_tile()
		return image
	func get_square_zone(pos: Vector2i, size: Vector2i, level: int, callback: Callable = func(_img: Image): pass, update_count: int = 15) -> Image:
		assert(http_workers.get_busy_worker_count() == 0, "No worker should be busy when starting get_square_zone")
		var out_image = Image.create_empty(size.x*self._get_size(), size.y*self._get_size(), false, Image.FORMAT_RGB8)
		var coords_queue: Array[Vector2i] = []

		# Make the coordinate queue and sort it by distance to center
		var center = Vector2i(0,0)
		for x in size.x: 
			for y in size.y: 
				coords_queue.append(Vector2i(x, y))
				center += coords_queue[-1]
		center /= coords_queue.size()
		coords_queue.sort_custom(func(v1:Vector2i, v2:Vector2i): return v1.distance_to(center)<v2.distance_to(center))
		
		return _get_tile_batch(coords_queue, pos, out_image, level, callback, update_count)
	func get_circle_zone(center: Vector2i, radius: int, level: int, callback: Callable = func(_img: Image): pass, update_count: int = 15) -> Image:
		assert(http_workers.get_busy_worker_count() == 0, "No worker should be busy when starting get_square_zone")
		var out_image = Image.create_empty(radius*2*self._get_size(), radius*2*self._get_size(), false, Image.FORMAT_RGB8)
		var coords_queue: Array[Vector2i] = []

		# Make the coordinate queue and sort it by distance to center
		var sort_center = Vector2i(radius, radius)
		for x in radius*2: 
			for y in radius*2: 
				if ((x-radius)**2+(y-radius)**2 < radius**2):
					coords_queue.append(Vector2i(x, y))
		coords_queue.sort_custom(func(v1:Vector2i, v2:Vector2i): return v1.distance_to(sort_center)<v2.distance_to(sort_center))
		
		return _get_tile_batch(coords_queue, center-sort_center, out_image, level, callback, update_count)
	#endregion

#region TILE API IMPLEMENTATIONS
class CyclosmTileApi extends TileApi:
	var hosts: Array[String] = [
		"a.tile-cyclosm.openstreetmap.fr",
		"b.tile-cyclosm.openstreetmap.fr",
		"c.tile-cyclosm.openstreetmap.fr"
	]
	func name() -> String:             return "Cyclosm OpenStreeMap"
	func description() -> String:      return "Free API: Maps mainly for cyclism, but is quite useful for trekking."
	func _get_host() -> Array[String]: return hosts
	func _get_size() -> int:           return 256
	func _get_request(x: int, y: int, level: int) -> String: return "/cyclosm/%d/%d/%d.png" % [level, x, y]
	func _body_to_img(image: Image, body: PackedByteArray) -> int: 
		return image.load_png_from_buffer(body)
class TopoTileApi extends TileApi:
	var domain_rr = 0
	var hosts: Array[String] = [
		"a.tile.opentopomap.org",
		"b.tile.opentopomap.org",
		"c.tile.opentopomap.org"
	]
	func name() -> String:             return "OpenTopoMap"
	func description() -> String:      return "Free API: Topographic maps inspired by German Vermessungsämter."
	func _get_host() -> Array[String]: return hosts
	func _get_size() -> int:           return 256
	func _get_request(x: int, y: int, level: int) -> String: return "/%d/%d/%d.png" % [level, x, y]
	func _body_to_img(image: Image, body: PackedByteArray) -> int: 
		return image.load_png_from_buffer(body)
class OsmTileApi extends TileApi:
	func name() -> String:             return "OpenStreetMap"
	func description() -> String:      return "Free API: Standard OpenStreetMap Tiles, mainly useful in cities."
	func _get_host() -> Array[String]: return ["tile.openstreetmap.org"]
	func _get_size() -> int:           return 256
	func _get_request(x: int, y: int, level: int) -> String: return "/%d/%d/%d.png" % [level, x, y]
	func _body_to_img(image: Image, body: PackedByteArray) -> int: 
		return image.load_png_from_buffer(body)
#endregion