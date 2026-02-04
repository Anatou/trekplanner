class_name Set
## A neat wrapper around a Dictionary to uniquely store values and quickly test for inclusion

var _d = {}

func has(val) -> bool:
	return _d.has(val)

func push(val) -> bool:
	return _d.set(val, null)

func remove(val) -> bool:
	return _d.erase(val)

func size() -> int:
	return _d.keys().size()

func values() -> Array:
	return _d.keys()