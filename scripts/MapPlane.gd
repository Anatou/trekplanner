extends MeshInstance3D

var map_mesh = ArrayMesh.new()
var surface_array: Array

func _normalize(value: float, minimum: float, maximum: float) -> float:
	return (value-minimum)/(maximum-minimum)

func _distance_squared(v1: Vector3, v2: Vector3) -> float:
	return v1.distance_squared_to(v2)

func _draw_gizmo_point(pos: Vector3, radius = 0.01, color = null) -> void:
	var point_obj = MeshInstance3D.new()
	var point_mesh = SphereMesh.new()
	var material = StandardMaterial3D.new() 
	point_mesh.radius = radius
	point_mesh.height = radius*2
	point_obj.position = pos
	point_obj.mesh = point_mesh
	if color is Color:
		material.albedo_color = color
		point_obj.material_override = material
	self.add_child(point_obj)

func _push_pair_to_set(s: Set, v1: int, v2: int) -> void:
	if v1<v2: s.push([v1,v2])
	else: s.push([v2,v1])
func _is_pair_in_set(s: Set, v1: int, v2: int) -> bool:
	if v1<v2: return s.has([v1,v2])
	else: return s.has([v2,v1])

func _arrange_points_clockwise(verts: PackedVector3Array, points: Array[int]) -> Array[int]:
	var pt1: Vector3 = verts[points[0]]
	var pt2: Vector3 = verts[points[1]]
	var pt3: Vector3 = verts[points[2]]
	if (pt2-pt1).cross(pt3-pt1).y < 0:
		return [points[0], points[1], points[2]]
	return [points[0], points[2], points[1]]

func _add_neighbor_to_point(d: Dictionary, pt1: int, pt2: int) -> void:
	if not d.has(pt1): d.set(pt1, [])
	if not d.has(pt2): d.set(pt2, [])
	d[pt1].append(pt2)
	d[pt2].append(pt1)

func _get_angle_with_center(v: Vector3) -> float:
	var angle = v.angle_to(Vector3(1, 0, 0))
	var s = -1 if v.angle_to(Vector3(0, 0, 1)) > PI/2.0 else 1
	return angle*s

func _make_dense_disk_mesh(n: int, radius: float) -> Array:
	#region INITIALIZATION
	var surface = []
	surface.resize(Mesh.ARRAY_MAX)

	var max_x = radius
	var min_x = -radius
	var max_y = radius
	var min_y = -radius

	# PackedVector**Arrays for mesh construction.
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	var unindexed_points: Array[int] = []
	#endregion
	#region DRAW DISK POINTS
	# Draw points using Vogel's method: https://www.marmakoide.org/posts/2012-04-04-spreading-points/post.html
	var phi = PI * (3-sqrt(5)) ## golden angle
	for i in n:
		var theta = i * phi
		var r = sqrt(i) / sqrt(n)
		var x = r * cos(theta) * radius
		var y = r * sin(theta) * radius
		#_draw_gizmo_point(Vector3(x, 0, y), 0.01, Color.from_hsv((((i)% n)/(n as float)), 1, 1))
		verts.append(Vector3(x, 0, y))
		uvs.append(Vector2(_normalize(x, min_x, max_x), _normalize(y, min_y, max_y)))
		normals.append(Vector3.UP)
		unindexed_points.append(i)
	#endregion
	#region CONNECT DISK MESH
	var segments: Set = Set.new() ## All segments as pair of points, sorted in ascending order
	var border_pts: Dictionary = {} ## All the points at the border of the constructed mesh and their connected points

	# Initialize the mesh's first triangle
	for _i in 3: indices.append(unindexed_points.pop_front())
	border_pts[0] = [1,2]
	border_pts[1] = [0,2]
	border_pts[2] = [0,1]
	_push_pair_to_set(segments, 0,1)
	_push_pair_to_set(segments, 0,2)
	_push_pair_to_set(segments, 1,2)

	while not unindexed_points.is_empty():
		# Get next point
		var pt: int = unindexed_points.pop_front()
		# Find the 2 nearest point in the border
		var min_distance1: float = INF
		var min_distance2: float = INF
		var min_point1: int = -1
		var min_point2: int = -1
		for border_pt in border_pts.keys():
			assert(pt != border_pt, "pt == border_pt")
			var dist = _distance_squared(verts[border_pt], verts[pt])
			if dist < min_distance1:
				min_distance1 = dist
				min_point1 = border_pt
			elif dist < min_distance2:
				min_distance2 = dist
				min_point2 = border_pt
		assert(min_point1 != -1)
		assert(min_point2 != -1)
		# If the 2 border points are not connected, make a triangle first and update segments & border_pts
		if not _is_pair_in_set(segments, min_point1, min_point2):
			var pt1_neighbors = border_pts[min_point1]
			var pt2_neighbors = border_pts[min_point2]
			var pt_for_triangle = -1
			for pt1_n in pt1_neighbors:
				if pt1_n in pt2_neighbors:
					pt_for_triangle = pt1_n
					assert(pt1_n in border_pts.keys())
					break
			if pt_for_triangle == -1:
				push_error("pt_for_triangle == -1")
				break
			indices.append_array(_arrange_points_clockwise(verts, [min_point1, min_point2, pt_for_triangle]))
			_push_pair_to_set(segments, min_point1, min_point2)
			border_pts.erase(pt_for_triangle) # pt is now enclosed and not part of the border
		# Make triangle of the 3 points and update segments & border_pts
		indices.append_array(_arrange_points_clockwise(verts, [min_point1, min_point2, pt]))
		_push_pair_to_set(segments, min_point1, pt)
		_push_pair_to_set(segments, min_point2, pt)
		_add_neighbor_to_point(border_pts, pt, min_point1)
		_add_neighbor_to_point(border_pts, pt, min_point2)
	#endregion
	#region FIND OUTER POINTS
	var outer_points: PackedInt32Array = []
	var start_pti = verts.size()-1
	var pti = start_pti
	var prev_pti = start_pti
	var found_all_outer_points = false
	outer_points.append(pti) 
	# Find outer points using property index_a > index_b -> dist_to_center_a > dist_to_center_b
	# Get the farthest point from center in the counter-clockwise direction
	while not found_all_outer_points:
		var pt_neighbors = border_pts[pti]
		var max_index = -1
		for neigh in pt_neighbors:
			if neigh == start_pti and neigh != prev_pti:
				found_all_outer_points = true
				break
			if neigh > max_index and verts[pti].cross(verts[neigh]).y < 0:
				max_index = neigh
		if not found_all_outer_points:
			prev_pti = pti
			pti = max_index
			outer_points.append(pti) 
	var outer_pts_size = outer_points.size()
	#endregion
	#region DRAW CIRCLE POINTS
	# var point_count: int = max(3, outer_pts_size) # At least 3 points
	# var alpha = 2*PI / point_count
	# var last_disk_point = verts[-1]
	# var start_angle = last_disk_point.angle_to(Vector3(1, 0, 0)) #+ alpha/2.0
	# var start_sign = -1 if last_disk_point.angle_to(Vector3(0, 0, 1)) > PI/2.0 else 1
	# var circle_points: PackedInt32Array = []
	# var verts_size = verts.size()
	# for i in point_count:
	# 	var x = radius*cos(alpha*i+start_angle*start_sign)
	# 	var y = radius*sin(alpha*i+start_angle*start_sign)
	# 	_draw_gizmo_point(Vector3(x, 0, y), 0.01, Color.from_rgba8(i, i, i))
	# 	verts.append(Vector3(x, 0, y))
	# 	circle_points.append(verts_size)
	# 	verts_size += 1
	# 	uvs.append(Vector2(_normalize(x, min_x, max_x), _normalize(y, min_y, max_y)))
	# 	normals.append(Vector3.UP)
	# 	unindexed_points.append(i)
	# var circle_pts_size = circle_points.size()
	var circle_points: PackedInt32Array = []
	var verts_size = verts.size()
	for i in outer_pts_size:
		var pt: Vector3 = verts[outer_points[i]].normalized()
		var x = pt.x * radius
		var y = pt.z * radius
		verts.append(Vector3(x, 0, y))
		circle_points.append(verts_size)
		verts_size += 1
		uvs.append(Vector2(_normalize(x, min_x, max_x), _normalize(y, min_y, max_y)))
		normals.append(Vector3.UP)
	var circle_pts_size = circle_points.size()
	#endregion
	#region CONNECT CIRCLE TO MESH
	# outer_pts and circle_pts rotate around the disk in the same direction
	# let's step over those two with two pointers and limit comparisons
	var outer_pti: int = 0
	var circle_pti: int = 0
	while outer_pti<outer_pts_size-1 and circle_pti<circle_pts_size-1:
		indices.append_array(_arrange_points_clockwise(verts, [outer_points[outer_pti], outer_points[outer_pti+1], circle_points[circle_pti]]))
		indices.append_array(_arrange_points_clockwise(verts, [outer_points[outer_pti+1], circle_points[circle_pti], circle_points[circle_pti+1]]))
		outer_pti += 1
		circle_pti += 1
	indices.append_array(_arrange_points_clockwise(verts, [outer_points[outer_pti], circle_points[circle_pti], circle_points[0]]))
	#endregion
	# Assign arrays to surface array.
	surface[Mesh.ARRAY_VERTEX] = verts
	surface[Mesh.ARRAY_TEX_UV] = uvs
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_INDEX] = indices
	return surface

func _ready() -> void:
	self.mesh = map_mesh
	var material = StandardMaterial3D.new() 
	surface_array = _make_dense_disk_mesh(1024*6, 2)

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	material.albedo_texture = ResourceLoader.load("res://addons/kenney_prototype_textures/purple/texture_04.png")
	self.material_override = material

func _process(_delta: float) -> void:
	var n = surface_array[Mesh.ARRAY_VERTEX].size()
	var height = 0.2
	# var speed = 0.0
	var speed = 0.001
	var wavelength = 4
	for i in n:
		var d = surface_array[Mesh.ARRAY_VERTEX][i].distance_squared_to(Vector3(0,0,0))
		surface_array[Mesh.ARRAY_VERTEX][i].y = sin(Time.get_ticks_msec()*speed + d*wavelength)*(height/2)
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
