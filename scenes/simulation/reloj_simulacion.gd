extends Node
class_name RelojSimulacion
## Reloj de la simulación: tiempo transcurrido y fecha/hora derivada.
##
## Usa `_process(delta)`: Godot ya escala `delta` con `Engine.time_scale`, que
## es exactamente lo que `SimulacionController.establecer_velocidad_simulacion()`
## cambia (`Engine.time_scale = factor`). No lee nada del controlador: se
## congela solo en pausa (factor 0.0) y corre más rápido con factores > 1.0.

signal minuto_simulado_cambiado(dia: int, hora: int, minuto: int)

## El reloj y los trenes comparten los mismos segundos simulados. La velocidad
## global se controla con Engine.time_scale, no con otro multiplicador del reloj.
var minutos_simulados_por_segundo: float = 1.0 / 60.0
@export_range(0, 23, 1) var hora_inicial: int = 6

var _tiempo_simulado_s: float = 0.0
var _dia: int = 1
var _hora: int = 0
var _minuto: int = 0
var _resto_segundos: float = 0.0


func _ready() -> void:
	_hora = hora_inicial


func _process(delta: float) -> void:
	_tiempo_simulado_s += delta
	_avanzar_fecha_simulada(delta)


func _avanzar_fecha_simulada(delta_simulado: float) -> void:
	_resto_segundos += delta_simulado
	if _resto_segundos < 60.0:
		return
	var minutos_a_sumar: int = int(_resto_segundos / 60.0)
	_resto_segundos -= minutos_a_sumar * 60.0
	_minuto += minutos_a_sumar
	_hora += _minuto / 60
	_minuto = _minuto % 60
	_dia += _hora / 24
	_hora = _hora % 24
	minuto_simulado_cambiado.emit(_dia, _hora, _minuto)


## Segundos simulados transcurridos desde que el reloj entró en el árbol.
## Monótono, nunca retrocede; congelado mientras la simulación está pausada.
func tiempo_simulado_s() -> float:
	return _tiempo_simulado_s


func fecha_hora_simulada() -> Dictionary:
	return {"dia": _dia, "hora": _hora, "minuto": _minuto}
