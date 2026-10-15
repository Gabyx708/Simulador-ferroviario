class_name ShowcaseCamera
extends Camera3D
## Controlador de cámara para el laboratorio de switches.
## Ofrece vistas predefinidas con interpolación cinemática suave (Tween)
## y modo de vuelo libre (WASD + botón derecho del ratón).

enum ModoCamara { CINEMATICA, LIBRE }

@export var velocidad_libre: float = 18.0
@export var sensibilidad_mouse: float = 0.003

var modo: ModoCamara = ModoCamara.CINEMATICA
var _rotacion_libre: Vector2 = Vector2.ZERO
var _tween_camara: Tween = null

# Vistas predeterminadas: [posicion, rotacion_grados]
const VISTAS: Dictionary = {
	"tipo_a": [Vector3(-17.5, 11.0, -26.0), Vector3(-24.0, 180.0, 0.0)],
	"tipo_b": [Vector3(0.0, 11.0, -26.0), Vector3(-24.0, 180.0, 0.0)],
	"tipo_c": [Vector3(14.0, 11.0, -26.0), Vector3(-24.0, 180.0, 0.0)],
	"tipo_d": [Vector3(30.0, 11.0, -30.0), Vector3(-24.0, 180.0, 0.0)],
	"tipo_e": [Vector3(48.0, 12.0, -30.0), Vector3(-24.0, 180.0, 0.0)],
	"general": [Vector3(16.0, 32.0, -56.0), Vector3(-34.0, 180.0, 0.0)]
}


func _ready() -> void:
	current = true
	_rotacion_libre.y = rotation.y
	_rotacion_libre.x = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				modo = ModoCamara.LIBRE
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	elif event is InputEventMouseMotion and modo == ModoCamara.LIBRE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_rotacion_libre.y -= mm.relative.x * sensibilidad_mouse
		_rotacion_libre.x -= mm.relative.y * sensibilidad_mouse
		_rotacion_libre.x = clampf(_rotacion_libre.x, deg_to_rad(-85.0), deg_to_rad(85.0))
		rotation.y = _rotacion_libre.y
		rotation.x = _rotacion_libre.x


func _process(delta: float) -> void:
	if modo != ModoCamara.LIBRE or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var mov: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mov -= transform.basis.z
	if Input.is_key_pressed(KEY_S): mov += transform.basis.z
	if Input.is_key_pressed(KEY_A): mov -= transform.basis.x
	if Input.is_key_pressed(KEY_D): mov += transform.basis.x
	if Input.is_key_pressed(KEY_E): mov += Vector3.UP
	if Input.is_key_pressed(KEY_Q): mov -= Vector3.UP

	if mov.length_squared() > 0.001:
		var vel: float = velocidad_libre * (2.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		position += mov.normalized() * (vel * delta)


## Transiciona suavemente la cámara hacia una de las vistas predeterminadas.
func enfocar_vista(clave: String, duracion: float = 1.0) -> void:
	if not VISTAS.has(clave):
		return

	modo = ModoCamara.CINEMATICA
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _tween_camara != null and _tween_camara.is_valid():
		_tween_camara.kill()

	var datos: Array = VISTAS[clave] as Array
	var target_pos: Vector3 = datos[0] as Vector3
	var target_rot_deg: Vector3 = datos[1] as Vector3
	var target_rot_rad: Vector3 = Vector3(
		deg_to_rad(target_rot_deg.x),
		deg_to_rad(target_rot_deg.y),
		deg_to_rad(target_rot_deg.z)
	)

	if duracion <= 0.001:
		position = target_pos
		rotation = target_rot_rad
		_rotacion_libre.x = target_rot_rad.x
		_rotacion_libre.y = target_rot_rad.y
		return

	_tween_camara = create_tween().set_parallel(true)
	_tween_camara.tween_property(self, "position", target_pos, duracion).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween_camara.tween_property(self, "rotation", target_rot_rad, duracion).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_rotacion_libre.x = target_rot_rad.x
	_rotacion_libre.y = target_rot_rad.y
