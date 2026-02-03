class_name HttpWorkerPool
## HttpWorkerPool
##
## Makes and manages an array of [i]n[/i] HTTPClient connected to a same host.
## Allows to make parallel asyncronous calls to a web API.
##
## @tutorial: Creation -> loop (poll, process responses, launch request) 

var _max_workers: int
var _worker_count: int
var _available_workers: Array
var _busy_workers: Array
var _workers: Array[HTTPClient]
var _worker_hosts: Array[String]
var _host: Array[String]
var _host_rr: int
var _timeout: int

func _init(host: Array[String], timeout:int, max_workers: int = 8, worker_init_count: int = 4) -> void:
	_timeout = timeout
	_worker_count = worker_init_count
	_max_workers = max_workers
	_host = host
	_host_rr = 0
	_available_workers = range(worker_init_count)
	_busy_workers = []
	var res = self._make_connected_client_array(worker_init_count)
	_workers = res.clients
	_worker_hosts = res.hosts

## Returns the status name as a String for a given status code
static func _status_string(status: HTTPClient.Status) -> String:
	match status:
		HTTPClient.STATUS_DISCONNECTED: return "STATUS_DISCONNECTED";
		HTTPClient.STATUS_RESOLVING: return "STATUS_RESOLVING";
		HTTPClient.STATUS_CANT_RESOLVE: return "STATUS_CANT_RESOLVE";
		HTTPClient.STATUS_CONNECTING: return "STATUS_CONNECTING";
		HTTPClient.STATUS_CANT_CONNECT: return "STATUS_CANT_CONNECT";
		HTTPClient.STATUS_CONNECTED: return "STATUS_CONNECTED";
		HTTPClient.STATUS_REQUESTING: return "STATUS_REQUESTING";
		HTTPClient.STATUS_BODY: return "STATUS_BODY";
		HTTPClient.STATUS_CONNECTION_ERROR: return "STATUS_CONNECTION_ERROR";
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: return "STATUS_TLS_HANDSHAKE_ERROR";
		_: return "UnknownStatus(%d)" % status;

## Returns a host_string to use
func _get_host() -> String:
	_host_rr = (_host_rr+1)%_host.size()
	return _host[_host_rr]

## Makes an array of [param size] connected HTTPClient (blocking call)
func _make_connected_client_array(size: int) -> ConnectedClientArrayResult:
	var start_time = Time.get_ticks_msec()
	var clients: Array[HTTPClient] = []
	var hosts: Array[String] = []
	var pending_clients: Array[int] = []
	# Start connecting for all clients
	for i in size:
		pending_clients.append(i)
		var host = _get_host()
		clients.append(HTTPClient.new())
		hosts.append(host)
		clients[i].connect_to_host("https://%s" % host)
	# Wait for connection
	while pending_clients.size() != 0:
		if Time.get_ticks_msec()-start_time > _timeout:
			push_warning("_make_connected_client_array: Client connection is unusually long >%f" % (_timeout/(1000 as float)))
			start_time = Time.get_ticks_msec()
		for i in range(pending_clients.size()-1,-1,-1):
			match clients[pending_clients[i]].get_status():
				HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
					clients[pending_clients[i]].poll()
				HTTPClient.STATUS_CONNECTED:
					pending_clients.remove_at(i)
				_: 
					assert(false, "_make_connected_client_array: Error while connecting client to host (%s)" % self._status_string(clients[pending_clients[i]].get_status()))
	return ConnectedClientArrayResult.new(clients, hosts)

func _make_connected_client() -> ConnectedClientResult:
	var start_time = Time.get_ticks_msec()
	var client = HTTPClient.new()
	var host = _get_host()
	client.connect_to_host("https://%s" % host)
	var is_client_connected = false
	while not is_client_connected:
		if Time.get_ticks_msec()-start_time > _timeout:
			push_warning("_make_connected_client: Client connection is unusually long >%f" % (_timeout/(1000 as float)))
			start_time = Time.get_ticks_msec()
		match client.get_status():
			HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
				client.poll()
			HTTPClient.STATUS_CONNECTED:
				is_client_connected = true
			_: 
				assert(false, "_make_connected_client: Error while connecting client to host %s (%s)" % [_host, self._status_string(client.get_status())])
	return ConnectedClientResult.new(client, host)

## Polls the busy workers and frees the finished ones [br]
## **return** : an array with the id of freed workers
func poll() -> Array[int]:
	var freed: Array[int] = []
	for i in range(_busy_workers.size()-1, -1, -1):
		var w = _busy_workers[i] ## worker_id	
		match _workers[w].get_status():
			HTTPClient.STATUS_REQUESTING:
				_workers[w].poll()
			HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED:
				_busy_workers.remove_at(i)
				_available_workers.append(w)
				freed.append(w)
			HTTPClient.STATUS_CONNECTION_ERROR:
				_workers[w].close()
				var res = _make_connected_client()
				_workers[w] = res.client
				_worker_hosts[w] = res.host
				_busy_workers.remove_at(i)
				_available_workers.append(w)
				freed.append(w)
			_: 
				assert(false, "poll: Unexpected status for finished worker %d (%s)" % [w, self._status_string(_workers[w].get_status())])
	return freed

## Polls the worker [param w] and frees it if finished [br]
## **return** : a bool wether worker w is free
func poll_one(w: int) -> bool:
	var finished = false
	match _workers[w].get_status():
		HTTPClient.STATUS_REQUESTING:
			_workers[w].poll()
		HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED:
			var i = _busy_workers.find(w)
			if i>=0:
				_busy_workers.remove_at(i)
				_available_workers.append(w)
			else:
				push_warning("poll_one: Polled worker_%d which was already finished, nothing happened" % w)
			finished = true
		_:
			assert(false, "poll_one: Unexpected status for finished worker %d (%s)" % [w,self._status_string(_workers[w].get_status())])
	return finished

## Returns the maximum possible count of worker available [br]
## (even if those workers don't exist yet and would need to be created)
func get_available_worker_count() -> int:
	return _max_workers - _busy_workers.size()

## Returns true if there is any available worker
func is_any_worker_available() -> bool:
	return not _available_workers.is_empty()

## Returns the count of busy workers
func get_busy_worker_count() -> int:
	return _busy_workers.size()

## Resets the worker currently working (drop request and reconnect to host) [br]
## **return** : the count of worker reset
func reset_busy_workers() -> int:
	var reset_count = 0
	while not _busy_workers.is_empty():
		var w = _busy_workers.pop_front()
		_workers[w].close()
		var res = _make_connected_client()
		_workers[w] = res.client
		_worker_hosts[w] = res.host
		_available_workers.append(w)
		reset_count += 1
	return reset_count

## Returns the host used by the worker worker_id
func get_worker_host(worker_id: int) -> String:
	var res = ""
	if worker_id < _worker_count:
		res = _worker_hosts[worker_id]
	return res

## Returns the worker specified by [param worker_id] if it exists and is available and marks it as busy[br]
## **case 1**: Worker exists and is available -> returns the worker and it's id [br]
## **case 2**: Worker exists and is *not* available -> returns null and the id asked for [br]
## **case 3**: Worker *does not* exist -> returns null and id=-1
func get_worker(worker_id: int) -> HttpWorker:
	var worker: HttpWorker = HttpWorker.new(-1, null)
	if worker_id < _max_workers:
		if worker_id in _busy_workers:
			worker = HttpWorker.new(worker_id, null)
		else:
			if worker_id >= _worker_count:
				var new_worker_count = min(_worker_count, _max_workers-_worker_count)
				_available_workers.append_array(range(_worker_count, _worker_count+new_worker_count))
				_worker_count += new_worker_count
				var res = self._make_connected_client_array(new_worker_count)
				_workers.append_array(res.clients)
				_worker_hosts.append_array(res.hosts)
			assert(worker_id in _available_workers, "get_worker: worker_id should be in _available_workers and is not")
			var i = _available_workers.find(worker_id)
			_available_workers.remove_at(i)
			_busy_workers.append(worker_id)
			worker = HttpWorker.new(worker_id, _workers[worker_id])
	return worker

## Returns a connected HTTPClient along with it's id if available and marks it as busy, else returns null
func get_available_worker() -> HttpWorker:
	var worker: HttpWorker = null
	if _busy_workers.size() < _max_workers:
		if _busy_workers.size() >= _worker_count:
			var new_worker_count = min(_worker_count, _max_workers-_worker_count)
			_available_workers.append_array(range(_worker_count, _worker_count+new_worker_count))
			_worker_count += new_worker_count
			var res = self._make_connected_client_array(new_worker_count)
			_workers.append_array(res.clients)
			_worker_hosts.append_array(res.hosts)
		var w = _available_workers.pop_back()
		_busy_workers.append(w)
		return HttpWorker.new(w, _workers[w])
	return worker

## Returns the body of the HTTPResponse got by worker *worker_id*. [br]
## if there is no body, an empty [Class PackedByteArray] is returned
func get_response_body(worker_id: int) -> PackedByteArray:
	var rb: PackedByteArray = PackedByteArray()
	while _workers[worker_id].get_status() == HTTPClient.STATUS_BODY:
		_workers[worker_id].poll()
		var chunk = _workers[worker_id].read_response_body_chunk()
		if chunk.size() == 0:
			continue
		else:
			rb = rb + chunk
	return rb


class ConnectedClientArrayResult:
	var clients: Array[HTTPClient]
	var hosts: Array[String]
	func _init(c_in, h_in) -> void:
		clients = c_in
		hosts = h_in

class ConnectedClientResult:
	var client: HTTPClient
	var host: String
	func _init(c_in, h_in) -> void:
		client = c_in
		host = h_in
