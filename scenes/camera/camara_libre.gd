extends Camera3D
class_name CamaraLibre
## Camara libre para recorrer el ramal.
##   Boton derecho + mouse : mirar
##   W A S D               : mover
##   Q / E                 : bajar / subir
##   Shift                 : rapido
##   F                     : seguir a la formacion desde atras
## Godot 4.x / 4.7
 
@export var velocidad: float = 30.0
@export var multiplicador_rapido: float = 5.0
@export var sensibilidad: float = 0.003
@export var formacion: Node3D          ## opcional, para el modo seguimiento
@export var seguir_al_inicio: bool = true   ## arranca enganchada atrás del tren

var _mirando: bool = false
var _siguiendo: bool = false
var _giro: Vector2 = Vector2.ZERO


func _ready() -> void:
	_giro = Vector2(rotation.y, rotation.x)
	_siguiendo = seguir_al_inicio


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and evento.button_index == MOUSE_BUTTON_RIGHT:
		_mirando = evento.pressed
		Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if _mirando
				else Input.MOUSE_MODE_VISIBLE)
	elif evento is InputEventMouseMotion and _mirando:
		_giro.x -= evento.relative.x * sensibilidad
		_giro.y = clampf(_giro.y - evento.relative.y * sensibilidad, -1.4, 1.4)
		rotation = Vector3(_giro.y, _giro.x, 0.0)
	elif evento is InputEventKey and evento.pressed and not evento.echo:
		if evento.keycode == KEY_F:
			_siguiendo = not _siguiendo


func _process(delta: float) -> void:
	if _siguiendo and formacion != null and formacion.get_child_count() > 0:
		var coche: Node3D = formacion.get_child(0)
		var atras: Vector3 = coche.global_transform.basis.z.normalized()
		global_position = global_position.lerp(
				coche.global_position + atras * 45.0 + Vector3.UP * 14.0, 4.0 * delta)
		look_at(coche.global_position + Vector3.UP * 2.0, Vector3.UP)
		_giro = Vector2(rotation.y, rotation.x)
		return

	var dir: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= basis.z
	if Input.is_key_pressed(KEY_S): dir += basis.z
	if Input.is_key_pressed(KEY_A): dir -= basis.x
	if Input.is_key_pressed(KEY_D): dir += basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP

	if dir != Vector3.ZERO:
		var v: float = velocidad
		if Input.is_key_pressed(KEY_SHIFT):
			v *= multiplicador_rapido
		global_position += dir.normalized() * v * delta
