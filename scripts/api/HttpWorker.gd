class_name HttpWorker
## HttpWorker
##
## Simple class used to output a worker and it's id 

var id: int
var w: HTTPClient

func _init(id_in: int, w_in: HTTPClient) -> void:
	id = id_in
	w = w_in
