extends Control
class_name Velocimetro
## Widget de HUD que muestra la velocidad actual de una formación en km/h.
##
## Reactivo: se suscribe a la señal `velocidad_cambiada` del [Tren] asignado
## en lugar de sondear (polling) su valor cada frame. Puede vincularse desde
## el Inspector o en tiempo de ejecución (ej. `BaseLevel` conecta la
## formación principal automáticamente al arrancar el nivel).

## Formación cuya velocidad se muestra. Reasignable en tiempo de ejecución.
@export var tren: Tren:
	set(v):
		if tren != null and is_instance_valid(tren) and tren.velocidad_cambiada.is_connected(_on_velocidad_cambiada):
			tren.velocidad_cambiada.disconnect(_on_velocidad_cambiada)
		tren = v
		if tren != null and is_instance_valid(tren):
			if not tren.velocidad_cambiada.is_connected(_on_velocidad_cambiada):
				tren.velocidad_cambiada.connect(_on_velocidad_cambiada)
			_actualizar(tren.velocidad_actual())
		else:
			_actualizar(0.0)

@onready var _etiqueta_valor: Label = %ValorVelocidad


func _ready() -> void:
	if tren != null and is_instance_valid(tren):
		if not tren.velocidad_cambiada.is_connected(_on_velocidad_cambiada):
			tren.velocidad_cambiada.connect(_on_velocidad_cambiada)
		_actualizar(tren.velocidad_actual())
	else:
		_actualizar(0.0)


func _on_velocidad_cambiada(kmh: float) -> void:
	_actualizar(kmh)


func _actualizar(kmh: float) -> void:
	_etiqueta_valor.text = str(roundi(kmh))
