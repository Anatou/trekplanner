class_name TilesApi

var layers: Dictionary[String,TileApi] = {
	"osm": OsmTileApi.new(),
	"topo": TopoTileApi.new(),
	"cyclosm": CyclosmTileApi.new(),
	"test": TestTileApi.new(4)
} 

func grid_to_gps(x, y, level) -> Vector2:
	#https://gis.stackexchange.com/questions/461842/generating-my-own-xyz-tiles-how-do-x-y-z-map-to-gps-bounds
	# Based on the OSM wiki page for "slippy map" tilenames, XYZ tiles use the Web Mercator projection (WGS84/EPSG:3857)
	var n = 2**level
	var a = PI*(1-2*y/n)
	var lat = 180/PI * atan(sinh(a))
	var long = 360*x/n - 180
	return Vector2(snapped(lat, .001), snapped(long, .001))
func gps_to_grid(lat, long, level) -> Vector2i:
	#https://gis.stackexchange.com/questions/461842/generating-my-own-xyz-tiles-how-do-x-y-z-map-to-gps-bounds
	# Based on the OSM wiki page for "slippy map" tilenames, XYZ tiles use the Web Mercator projection (WGS84/EPSG:3857)
	var n = 2**level
	var r = PI/180.0 * lat
	var lts = log(tan(r) + 1/cos(r))
	var x = n*(0.5+long/360)
	var y = n*(1-lts/PI) /2
	return Vector2i(round(x), round(y))

@abstract class TileApi extends Node:
	var http_workers: HttpWorkerPool
	func _init(max_workers: int = 16) -> void:
		http_workers = HttpWorkerPool.new("https://%s" % [self._get_host()], max_workers)
	@abstract func name() -> String
	@abstract func description() -> String
	@abstract func _get_request(x: int, y: int, level: int) -> String
	@abstract func _get_host() -> String
	@abstract func _get_size() -> int
	@abstract func _body_to_img(body: PackedByteArray) -> Image
	func _make_headers() -> Array[String]:
		return [
			"Host: %s" % self._get_host(),
			"User-Agent: trekplanner/0.1.0 (Godot)",
			"Accept-Language: en-US,en;q=0.5",
			"Accept-Encoding: gzip",
			"Connection: keep-alive",
		]
	func get_tile(x: int, y: int, level: int) -> Image:
		var headers = self._make_headers()
		var worker = http_workers.get_available_worker()
		var request = self._get_request(x, y, level)
		worker.w.request(worker.w.METHOD_GET, request, headers)
		while http_workers.poll_one(worker.id): pass
		var body = http_workers.get_response_body(worker.id)
		return self._body_to_img(body)
	func get_zone(start_x: int, start_y: int, width: int, height: int, level: int, callback: Callable = func(_img: Image): pass) -> Image:
		var image = Image.create_empty(width*self._get_size(), height*self._get_size(), false, Image.FORMAT_RGB8)
		var img_count = 0
		var worker_coords: Dictionary[int, Vector2i] = {}
		var finished_workers: Array[int] = []
		var headers = self._make_headers()
		var coords_to_get: Array[Vector2i] = []
		for x in width: 
			for y in height: 
				coords_to_get.append(Vector2i(x, y))
		
		while img_count < width*height:
			while http_workers.get_busy_worker_count() > 0 and finished_workers.size() == 0:
				finished_workers = http_workers.poll()
			for w in finished_workers:
				var res = self._body_to_img(http_workers.get_response_body(w))
				var rect = Rect2i(0, 0, self._get_size(), self._get_size())
				var coords = worker_coords[w]
				image.blit_rect(res, rect, coords*self._get_size())
				callback.call_deferred(image)
				img_count += 1
			finished_workers = []
			if not coords_to_get.is_empty():
				var available_worker_count = http_workers.get_available_worker_count()
				for _w in min(available_worker_count, coords_to_get.size()):
					var worker = http_workers.get_available_worker()
					worker_coords[worker.id] = coords_to_get.pop_front()
					var request = self._get_request(worker_coords[worker.id].x+start_x, worker_coords[worker.id].y+start_y, level)
					worker.w.request(worker.w.METHOD_GET, request, headers)
		return image

class CyclosmTileApi extends TileApi:
	var domain_rr = 0
	var hosts = [
		"a.tile-cyclosm.openstreetmap.fr",
		"b.tile-cyclosm.openstreetmap.fr",
		"c.tile-cyclosm.openstreetmap.fr"
	]
	func name() -> String:        return "Cyclosm OpenStreeMap"
	func description() -> String: return "Free API: Maps mainly for cyclism, but is quite useful for trekking."
	func _get_host() -> String:   domain_rr = (domain_rr+1)%3; return hosts[domain_rr]
	func _get_size() -> int:      return 256
	func _get_request(x: int, y: int, level: int) -> String: return "/cyclosm/%d/%d/%d.png" % [level, x, y]
	func _body_to_img(body: PackedByteArray) -> Image: 
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		assert(err==OK, "OsmTileApi: Image convertion failed")
		return image
class TopoTileApi extends TileApi:
	var domain_rr = 0
	var hosts = [
		"a.tile.opentopomap.org",
		"b.tile.opentopomap.org",
		"c.tile.opentopomap.org"
	]
	func name() -> String:        return "OpenTopoMap"
	func description() -> String: return "Free API: Topographic maps inspired by German Vermessungsämter."
	func _get_host() -> String:   domain_rr = (domain_rr+1)%3; return hosts[domain_rr]
	func _get_size() -> int:      return 256
	func _get_request(x: int, y: int, level: int) -> String: return "/%d/%d/%d.png" % [level, x, y]
	func _body_to_img(body: PackedByteArray) -> Image: 
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		assert(err==OK, "TopoTileApi: Image convertion failed")
		return image
class OsmTileApi extends TileApi:
	func name() -> String:        return "OpenStreetMap"
	func description() -> String: return "Free API: Standard OpenStreetMap Tiles, mainly useful in cities."
	func _get_host() -> String:   return "tile.openstreetmap.org"
	func _get_size() -> int:      return 256
	func _get_request(x: int, y: int, level: int) -> String: return "/%d/%d/%d.png" % [level, x, y]
	func _body_to_img(body: PackedByteArray) -> Image: 
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		assert(err==OK, "OsmTileApi: Image convertion failed")
		return image
class TestTileApi extends TileApi:
	func name() -> String:        return "TestTiles"
	func description() -> String: return "Test placeholder API"
	func _get_host() -> String:   return "placehold.co"
	func _get_size() -> int:      return 512
	func _get_request(_x: int, _y: int, _level: int) -> String: return "/512.png"
	func _body_to_img(body: PackedByteArray) -> Image:
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		assert(err==OK, "TestTileApi: Image convertion failed")
		return image
