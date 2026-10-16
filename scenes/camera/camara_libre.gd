extends Camera3D
class_name CamaraLibre
## Camara libre para recorrer el ramal.
##   Boton derecho + mouse : mirar
##   W A S D / Q E         : mover solo en cámara libre
##   Shift                 : rapido
##   F                     : seguimiento desde atrás
##   C                     : seguimiento elevado del tren seleccionado
## En seguimiento, el botón derecho rota la mirada y la rueda ajusta el zoom.
## Godot 4.x / 4.7

const DISTANCIA_SEGUIMIENTO_MINIMA := 40.0
const DISTANCIA_SEGUIMIENTO_MAXIMA := 90.0
 
@export var velocidad: float = 30.0
@export var multiplicador_rapido: float = 5.0
@export var sensibilidad: float = 0.003
@export var formacion: Node3D          ## opcional, para el modo seguimiento
@export var seguir_al_inicio: bool = true   ## arranca enganchada atrás del tren
@export_group("Vista cenital")
@export_range(10.0, 500.0, 1.0) var altura_cenital: float = 85.0
@export_range(1.0, 30.0, 0.5) var suavizado_seguimiento: float = 18.0
@export_group("Seguimiento del tren")
@export_range(40.0, 90.0, 1.0) var distancia_seguimiento: float = 64.0
@export_range(1.0, 10.0, 1.0) var paso_zoom: float = 5.0

enum ModoSeguimiento { LIBRE, TRASERO, CENITAL }

var _mirando: bool = false
var _modo: ModoSeguimiento = ModoSeguimiento.LIBRE
var _giro: Vector2 = Vector2.ZERO
var _distancia_seguimiento_actual: float = 0.0


func _ready() -> void:
	_giro = Vector2(rotation.y, rotation.x)
	_modo = ModoSeguimiento.TRASERO if seguir_al_inicio else ModoSeguimiento.LIBRE
	_distancia_seguimiento_actual = distancia_seguimiento


## Activa la vista elevada para el tren indicado. Se invoca al seleccionar
## una formación y conserva el encuadre relativo anterior al cambiar de tren.
func seguir_tren_cenital(tren: Node3D) -> void:
	formacion = tren
	_modo = ModoSeguimiento.CENITAL
	_distancia_seguimiento_actual = distancia_seguimiento
	var coche := _obtener_coche_principal()
	var yaw := coche.global_rotation.y if coche != null else rotation.y
	# Inclinación inicial de 45°; el usuario puede ajustarla con el mouse.
	_giro = Vector2(yaw, -PI * 0.25)
	rotation = Vector3(_giro.y, _giro.x, 0.0)


## Reutiliza la cámara libre para visitar una estación y encuadrar sus andenes.
## El salto es inmediato incluso si la simulación está pausada.
func enfocar_estacion(estacion: Estacion) -> void:
	if not is_instance_valid(estacion):
		return
	formacion = null
	_modo = ModoSeguimiento.LIBRE
	_mirando = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var limites: AABB = estacion.obtener_limites_andenes_pasajeros()
	var centro: Vector3 = limites.get_center()
	# Misma altura que la vista del tren, conservando la mirada inclinada hacia los andenes.
	var lateral: Vector3 = estacion.global_transform.basis.z
	lateral.y = 0.0
	var posicion: Vector3 = centro + Vector3.UP * altura_cenital + lateral.normalized() * altura_cenital * 0.35
	look_at_from_position(posicion, centro, Vector3.UP)
	_giro = Vector2(rotation.y, rotation.x)


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventMouseButton and _modo == ModoSeguimiento.CENITAL and evento.pressed and evento.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var factor_zoom := -paso_zoom if evento.button_index == MOUSE_BUTTON_WHEEL_UP else paso_zoom
		_distancia_seguimiento_actual = clampf(_distancia_seguimiento_actual + factor_zoom, DISTANCIA_SEGUIMIENTO_MINIMA, DISTANCIA_SEGUIMIENTO_MAXIMA)
		get_viewport().set_input_as_handled()
	elif evento is InputEventMouseButton and evento.button_index == MOUSE_BUTTON_RIGHT:
		_mirando = evento.pressed
		Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if _mirando
				else Input.MOUSE_MODE_VISIBLE)
	elif evento is InputEventMouseMotion and _mirando:
		_giro.x -= evento.relative.x * sensibilidad
		if _modo == ModoSeguimiento.CENITAL:
			_giro.y = clampf(_giro.y - evento.relative.y * sensibilidad, -1.48, -0.15)
		else:
			_giro.y = clampf(_giro.y - evento.relative.y * sensibilidad, -1.54, 1.4)
		rotation = Vector3(_giro.y, _giro.x, 0.0)
	elif evento is InputEventKey and evento.pressed and not evento.echo:
		if evento.keycode == KEY_ESCAPE:
			_modo = ModoSeguimiento.LIBRE
			_mirando = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif evento.keycode == KEY_F:
			_modo = ModoSeguimiento.LIBRE if _modo == ModoSeguimiento.TRASERO else ModoSeguimiento.TRASERO
		elif evento.keycode == KEY_C:
			if _modo == ModoSeguimiento.CENITAL:
				_modo = ModoSeguimiento.LIBRE
			else:
				_modo = ModoSeguimiento.CENITAL
				_distancia_seguimiento_actual = distancia_seguimiento
				_giro.y = -PI * 0.25


func _process(delta: float) -> void:
	if _modo == ModoSeguimiento.CENITAL and is_instance_valid(formacion):
		_seguir_cenital(delta)
		return

	var coche: Node3D = _obtener_coche_principal()
	if _modo == ModoSeguimiento.TRASERO and coche != null:
		var atras: Vector3 = coche.global_transform.basis.z.normalized()
		global_position = global_position.lerp(
				coche.global_position + atras * 45.0 + Vector3.UP * 14.0,
				minf(1.0, suavizado_seguimiento * delta))
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


func _seguir_cenital(delta: float) -> void:
	var coche: Node3D = _obtener_coche_principal()
	if coche == null:
		return
	var adelante: Vector3 = -coche.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	var punto_mirada := coche.global_position + adelante * 18.0 + Vector3.UP * 2.0
	var inclinacion := absf(_giro.y)
	var distancia_horizontal := _distancia_seguimiento_actual * cos(inclinacion)
	var altura := _distancia_seguimiento_actual * sin(inclinacion)
	var direccion_camara := Vector3.FORWARD.rotated(Vector3.UP, _giro.x)
	var destino := punto_mirada - direccion_camara * distancia_horizontal + Vector3.UP * altura
	global_position = global_position.lerp(destino, minf(1.0, suavizado_seguimiento * delta))
	rotation = Vector3(_giro.y, _giro.x, 0.0)


## El nodo raíz de Tren es un contenedor fijo; el coche físico que se mueve es
## Coche_0. Se consulta cada frame para sobrevivir a una reconstrucción.
func _obtener_coche_principal() -> Node3D:
	if formacion == null or not is_instance_valid(formacion):
		return null
	if formacion.has_method("obtener_coche_principal"):
		return formacion.call("obtener_coche_principal") as Node3D
	return formacion.get_node_or_null("Coche_0") as Node3D
