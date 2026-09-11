@tool
extends Node3D
class_name PosteParada
## Poste de parada ferroviario visible en el editor 3D.
## Permite al usuario arrastrarlo en el visor 3D a lo largo de la vía
## para definir exactamente el punto donde debe detenerse la cabina del tren.

signal posicion_cambiada(poste: PosteParada)

@export var texto_cartel: String = "PARADA":
	set(v):
		texto_cartel = v
		_actualizar_cartel()

@export var color_cartel: Color = Color(0.9, 0.2, 0.2, 1.0):
	set(v):
		color_cartel = v
		_actualizar_cartel()

var _ignorar_notificacion: bool = false


func _ready() -> void:
	set_notify_transform(true)
	_actualizar_cartel()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_POST_ENTER_TREE:
			set_notify_transform(true)
			_actualizar_cartel()
		NOTIFICATION_TRANSFORM_CHANGED:
			if _ignorar_notificacion:
				return
			posicion_cambiada.emit(self)


func fijar_posicion_x(nuevo_x: float) -> void:
	if is_equal_approx(position.x, nuevo_x):
		return
	_ignorar_notificacion = true
	position.x = nuevo_x
	_ignorar_notificacion = false


func _actualizar_cartel() -> void:
	var cartel: MeshInstance3D = get_node_or_null("CartelVisual") as MeshInstance3D
	if cartel != null and cartel.mesh != null and cartel.mesh.material != null:
		var mat: StandardMaterial3D = cartel.mesh.material as StandardMaterial3D
		if mat != null:
			mat.albedo_color = color_cartel
