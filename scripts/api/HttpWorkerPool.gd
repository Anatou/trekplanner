class_name HttpWorkerPool
## HttpWorkerPool
##
## Tests

var _max_workers: int
var _worker_count: int
var _available_workers: Array
var _busy_workers: Array
var _workers: Array[HTTPClient]
var _host: String

func _init(host: String, max_workers: int = 8, worker_init_count: int = 4) -> void:
	_worker_count = worker_init_count
	_max_workers = max_workers
	_host = host
	_available_workers = range(worker_init_count)
	_busy_workers = []
	_workers = self._make_connected_client_array(worker_init_count)

## Makes an array of <size> connected HTTPClient (blocking call)
func _make_connected_client_array(size: int) -> Array[HTTPClient]:
	var connected_clients: Array[HTTPClient] = []
	var pending_clients: Array[int] = []
	for i in size:
		pending_clients.append(i)
		connected_clients.append(HTTPClient.new())
		connected_clients[i].connect_to_host(_host)
	while pending_clients.size() != 0:
		for i in range(pending_clients.size()-1,-1,-1):
			if connected_clients[pending_clients[i]].get_status() == HTTPClient.STATUS_CONNECTING or connected_clients[pending_clients[i]].get_status() == HTTPClient.STATUS_RESOLVING:
				connected_clients[pending_clients[i]].poll()
			else:
				pending_clients.remove_at(i)
	return connected_clients

## Polls the busy workers and frees the finished ones
## returns and array with the id of freed workers
func poll() -> Array[int]:
	var freed: Array[int] = []
	for i in range(_busy_workers.size()-1, -1, -1):
		var w = _busy_workers[i]
		if _workers[w].get_status() == HTTPClient.STATUS_REQUESTING:
			_workers[w].poll()
		else:
			assert(_workers[w].get_status() == HTTPClient.STATUS_BODY or _workers[w].get_status() == HTTPClient.STATUS_CONNECTED, "poll: Request finished requesting but is not connected status=%d" % _workers[w].get_status())
			_busy_workers.remove_at(i)
			_available_workers.append(w)
			freed.append(w)
	return freed

func poll_one(w: int) -> bool:
	if _workers[w].get_status() == HTTPClient.STATUS_REQUESTING:
		_workers[w].poll()
		return false
	else:
		assert(_workers[w].get_status() == HTTPClient.STATUS_BODY or _workers[w].get_status() == HTTPClient.STATUS_CONNECTED, "poll_one: Request finished requesting but is not connected")
		var i = _busy_workers.find(w)
		if i>=0:
			_busy_workers.remove_at(i)
			_available_workers.append(w)
		return true

func get_available_worker_count() -> int:
	return _max_workers - _busy_workers.size()

func get_busy_worker_count() -> int:
	return _busy_workers.size()

## Returns a connected HTTPClient if available and marks it as busy, else returns none
func get_available_worker() -> HttpWorker:
	if _busy_workers.size() >= _max_workers:
		return null
	else:
		if _busy_workers.size() >= _worker_count:
			var new_worker_count = min(_worker_count, _max_workers-_worker_count)
			_available_workers.append_array(range(_worker_count, _worker_count+new_worker_count))
			_worker_count += new_worker_count
			_workers.append_array(self._make_connected_client_array(new_worker_count))
		var w = _available_workers.pop_back()
		_busy_workers.append(w)
		return HttpWorker.new(w, _workers[w])

## Returns the body of the HTTPResponse got by worker <worker_id>
## worker <worker_id> must have a HTTPResponse or it will fail 
func get_response_body(worker_id: int) -> PackedByteArray:
	assert(_workers[worker_id].get_status() == HTTPClient.STATUS_BODY, "Request does not have a body")
	var rb = PackedByteArray()
	while _workers[worker_id].get_status() == HTTPClient.STATUS_BODY:
		_workers[worker_id].poll()
		var chunk = _workers[worker_id].read_response_body_chunk()
		if chunk.size() == 0:
			continue
		else:
			rb = rb + chunk # Append to read buffer.
	return rb

class HttpWorker:
	var id: int
	var w: HTTPClient
	func _init(id_in: int, w_in: HTTPClient) -> void:
		id = id_in
		w = w_in
