extends Node3D
class_name PasajeroVisual

@export_range(0.5, 2.5, 0.05) var altura_metros: float = 1.65


func configurar_modelo(malla: Mesh, transformacion_modelo: Transform3D, bounds: AABB) -> void:
	if malla == null or bounds.size.y <= 0.0:
		return
	var instancia: MeshInstance3D = get_node_or_null("Modelo") as MeshInstance3D
	if instancia == null:
		return

	var centro: Vector3 = bounds.get_center()
	var transformacion: Transform3D = transformacion_modelo
	transformacion.origin -= Vector3(centro.x, bounds.position.y, centro.z)
	instancia.mesh = malla
	instancia.transform = transformacion
	var escala: float = altura_metros / bounds.size.y
	scale = Vector3.ONE * escala
