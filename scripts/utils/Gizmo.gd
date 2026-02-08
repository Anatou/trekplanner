class_name Gizmo
extends MeshInstance3D

func _init(pos: Vector3, radius = 0.01, color = null) -> void:
	mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2
	position = pos
	if color is Color:
		var material = StandardMaterial3D.new() 
		material.albedo_color = color
		material_override = material
