class_name Cache

const CACHE_PATH = "user://_cache/"
const TMP_CACHE_PATH = "user://_cache/tmp/"

var _path: StringName
var _is_temporary: bool
var _max_size: int
## How many percent of _max_size is removed in garbage collection
var _reduction_percent: float

var _dirAccess: DirAccess

var _files: PackedStringArray
var _cache_size: int

#region PRIVATE METHODS
func _init(path: String, is_temporary = true, max_size: int = 80_000_000, reduction_percent: float = 0.2) -> void:
	_is_temporary = is_temporary
	_max_size = max_size
	_reduction_percent = reduction_percent
	_path = "%s%s" % [TMP_CACHE_PATH, path] if is_temporary else "%s%s" % [CACHE_PATH, path]
	if not DirAccess.dir_exists_absolute(_path):
		_make_dir_absolute_recursive(_path)
	_dirAccess = DirAccess.open(_path)
	assert(_dirAccess != null, "_dirAccess is null (err %d)" % DirAccess.get_open_error())
	_cache_size = 0

	match is_temporary:
		true:
			_files = PackedStringArray()
		false:
			_files = _dirAccess.get_files()
			for file_name in _files:
				_cache_size += FileAccess.get_size(_mpath(file_name))

func _make_dir_absolute_recursive(path: String) -> Error:
	var path_splitted = path.replace("user://", "").split("/")
	var path_built = "user://"
	var err = OK
	for step in path_splitted:
		path_built +=  "/" + step
		err = DirAccess.make_dir_absolute(path_built)
		if not err in [OK, ERR_ALREADY_EXISTS]: return err
	return err

## Make the absolute file path for the file_name specified in params
func _make_file_path(name: String) -> String:
	return "%s/%s" % [_path, name]
## Simple name alias for [code]_make_file_path()[/code]
func _mpath(name: String) -> String:
	return _make_file_path(name)
#endregion

#region PUBLIC METHODS
func cache_file(bytes: PackedByteArray, name: StringName) -> Error:
	var result_code = OK
	var already_in_cache = false
	if FileAccess.file_exists(_mpath(name)):
		_cache_size -= FileAccess.get_size(_mpath(name))
		already_in_cache = true
	var file = FileAccess.open(_mpath(name), FileAccess.WRITE)
	if file==null:
		result_code = FileAccess.get_open_error()
	else:
		file.store_buffer(bytes)
		_cache_size += bytes.size()
		if not already_in_cache:
			_files.append(name)
		file.close()
	return result_code

func get_file(name: StringName) -> PackedByteArray:
	var bytes = PackedByteArray()

	if FileAccess.file_exists(_mpath(name)):
		var length = FileAccess.get_size(_mpath(name))
		var file = FileAccess.open(_mpath(name), FileAccess.READ)
		bytes = file.get_buffer(length)
		file.close()
	return bytes

func is_file_cached(name: StringName) -> bool:
	return name in _files

func get_cache_size() -> int:
	return _cache_size

func empty_cache() -> void:
	for file in _dirAccess.get_files():
		_dirAccess.remove(file)
	_cache_size = 0
	_files = PackedStringArray()
	_dirAccess = DirAccess.open(_path)

func garbage_collect() -> int:
	## x->time [br]y->index in [code]_files[/code]
	var files_time: Array[Vector2i] = []
	var space_freed = 0
	if _cache_size > _max_size:
		# Get all files and timestamp
		for i in _files.size():
			files_time.append(Vector2i(
				FileAccess.get_modified_time(_mpath(_files[i])), i
			))
		# Sort array on date
		files_time.sort_custom(func(v1:Vector2i, v2:Vector2i): return v1.x<v2.x)
		# Delete files until space_freed is satisfied
		var free_objective = round((_max_size as float) * _reduction_percent)
		while space_freed < free_objective:
			var tuple = files_time.pop_front()
			space_freed += FileAccess.get_size(_mpath(_files[tuple.y]))
			_dirAccess.remove(_files[tuple.y])
		_files = _dirAccess.get_files()
		_cache_size = 0
		for file in _files:
			_cache_size += FileAccess.get_size(_mpath(file))

	return 0
#endregion
