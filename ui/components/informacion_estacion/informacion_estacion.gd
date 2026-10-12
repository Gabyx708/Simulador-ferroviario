extends PanelContainer
class_name InformacionEstacion
## Información de la estación seleccionada, actualizada mediante sus señales.

@onready var _titulo: Label = %Titulo
@onready var _esperando: Label = %Esperando
@onready var _barra_ocupacion: ProgressBar = %BarraOcupacion
@onready var _andenes: Label = %PasajerosPorAnden
@onready var _historico: Label = %Historico
@onready var _subieron: Label = %Subieron
@onready var _bajaron: Label = %Bajaron
@onready var _boton_cerrar: Button = %BotonCerrar

var _estacion: Estacion


func _ready() -> void:
	_boton_cerrar.pressed.connect(cerrar)


func mostrar_estacion(estacion: Estacion) -> void:
	cerrar()
	if not is_instance_valid(estacion):
		return
	_estacion = estacion
	_estacion.pasajeros_actualizados.connect(_on_pasajeros_actualizados)
	_estacion.tree_exiting.connect(cerrar)
	_actualizar_informacion()
	visible = true


func cerrar() -> void:
	if is_instance_valid(_estacion):
		if _estacion.pasajeros_actualizados.is_connected(_on_pasajeros_actualizados):
			_estacion.pasajeros_actualizados.disconnect(_on_pasajeros_actualizados)
		if _estacion.tree_exiting.is_connected(cerrar):
			_estacion.tree_exiting.disconnect(cerrar)
	_estacion = null
	hide()


func _unhandled_key_input(evento: InputEvent) -> void:
	if visible and evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE:
		cerrar()
		get_viewport().set_input_as_handled()


func _on_pasajeros_actualizados(_origen: Estacion) -> void:
	_actualizar_informacion()


func _actualizar_informacion() -> void:
	if not is_instance_valid(_estacion):
		cerrar()
		return
	_titulo.text = _estacion.nombre_estacion
	var pasajeros_en_estacion: int = _estacion.pasajeros_esperando + _estacion.pasajeros_saliendo
	_esperando.text = "En espera: %d / %d" % [pasajeros_en_estacion, _estacion.capacidad_maxima_espera]
	_barra_ocupacion.max_value = maxi(1, _estacion.capacidad_maxima_espera)
	_barra_ocupacion.value = pasajeros_en_estacion
	_historico.text = "Histórico: %d pasajeros" % _estacion.pasajeros_totales_historicos
	_subieron.text = "Subieron al tren: %d" % _estacion.pasajeros_subidos_total
	_bajaron.text = "Bajaron del tren: %d" % _estacion.pasajeros_bajados_total
	var cantidades: Array[int] = _estacion.obtener_pasajeros_por_anden()
	var lineas: PackedStringArray = PackedStringArray()
	for indice: int in range(cantidades.size()):
		lineas.append("Andén %d: %d pasajeros" % [indice + 1, cantidades[indice]])
	_andenes.text = "\n".join(lineas)
	call_deferred("_ajustar_altura")


func _ajustar_altura() -> void:
	var altura: float = get_combined_minimum_size().y
	custom_minimum_size.y = altura
	size.y = altura
