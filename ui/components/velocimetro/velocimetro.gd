extends Control
class_name Velocimetro
## Widget de HUD que muestra velocidad, sentido de circulación y estado
## (detenido / en marcha) de una formación, además de identificarla.
##
## Reactivo: se suscribe a las señales del [Tren] asignado en lugar de
## sondear (polling) su estado cada frame. Puede vincularse desde el
## Inspector o en tiempo de ejecución (ej. `BaseLevel` conecta la formación
## principal automáticamente al arrancar el nivel, y la selección por clic
## la reasigna a cualquier tren de la escena).

## Duración de la animación con la que el número se desliza hacia el nuevo
## valor, en vez de saltar de golpe.
const DURACION_TRANSICION: float = 0.35

const COLOR_EN_MARCHA: Color = Color(0.35, 0.85, 0.55)
const COLOR_EN_ESTACION: Color = Color(1.0, 0.756863, 0.278431)
const COLOR_SIN_TREN: Color = Color(0.5, 0.52, 0.58)

## Formación cuyo estado se muestra. Reasignable en tiempo de ejecución.
@export var tren: Tren:
	set(v):
		_desconectar_tren()
		tren = v
		_conectar_tren()

@onready var _etiqueta_identificador: Label = %Identificador
@onready var _etiqueta_sentido: Label = %Sentido
@onready var _etiqueta_valor: Label = %ValorVelocidad
@onready var _etiqueta_estado: Label = %Estado

var _valor_mostrado: float = 0.0
var _tween: Tween


func _ready() -> void:
	_conectar_tren()


## Desvincula la formación actual (si la hay). Pensado para cuando un tren
## se elimina en runtime y hay que soltar la referencia sin dejar al HUD
## mostrando datos de un tren que ya no existe.
func soltar_tren() -> void:
	tren = null


func _desconectar_tren() -> void:
	if tren == null or not is_instance_valid(tren):
		return
	if tren.velocidad_cambiada.is_connected(_on_velocidad_cambiada):
		tren.velocidad_cambiada.disconnect(_on_velocidad_cambiada)
	if tren.parada_alcanzada.is_connected(_on_parada_alcanzada):
		tren.parada_alcanzada.disconnect(_on_parada_alcanzada)
	if tren.marcha_reanudada.is_connected(_on_marcha_reanudada):
		tren.marcha_reanudada.disconnect(_on_marcha_reanudada)


func _conectar_tren() -> void:
	if tren == null or not is_instance_valid(tren):
		_etiqueta_identificador.text = "—"
		_etiqueta_sentido.text = ""
		_marcar_estado("SIN TREN", COLOR_SIN_TREN)
		_actualizar_velocidad(0.0, true)
		return

	if not tren.velocidad_cambiada.is_connected(_on_velocidad_cambiada):
		tren.velocidad_cambiada.connect(_on_velocidad_cambiada)
	if not tren.parada_alcanzada.is_connected(_on_parada_alcanzada):
		tren.parada_alcanzada.connect(_on_parada_alcanzada)
	if not tren.marcha_reanudada.is_connected(_on_marcha_reanudada):
		tren.marcha_reanudada.connect(_on_marcha_reanudada)

	_etiqueta_identificador.text = tren.name
	_etiqueta_sentido.text = "◀" if tren.invertir_sentido else "▶"
	if tren.esta_detenido():
		_marcar_estado("EN ESTACIÓN", COLOR_EN_ESTACION)
	else:
		_marcar_estado("EN MARCHA", COLOR_EN_MARCHA)
	_actualizar_velocidad(tren.velocidad_actual(), true)


func _on_velocidad_cambiada(kmh: float) -> void:
	_actualizar_velocidad(kmh, false)
	_etiqueta_sentido.text = "◀" if tren.invertir_sentido else "▶"


func _on_parada_alcanzada(_indice_parada: int) -> void:
	_marcar_estado("EN ESTACIÓN", COLOR_EN_ESTACION)


func _on_marcha_reanudada() -> void:
	_marcar_estado("EN MARCHA", COLOR_EN_MARCHA)


func _marcar_estado(texto: String, color: Color) -> void:
	_etiqueta_estado.text = texto
	_etiqueta_estado.add_theme_color_override("font_color", color)


## Anima el número hacia el nuevo valor en vez de saltar de golpe.
## `inmediato` salta directo, para la primera lectura al conectar un tren.
func _actualizar_velocidad(kmh: float, inmediato: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	if inmediato:
		_set_valor_mostrado(kmh)
		return

	_tween = create_tween()
	_tween.tween_method(_set_valor_mostrado, _valor_mostrado, kmh, DURACION_TRANSICION)


func _set_valor_mostrado(kmh: float) -> void:
	_valor_mostrado = kmh
	_etiqueta_valor.text = str(roundi(_valor_mostrado))
