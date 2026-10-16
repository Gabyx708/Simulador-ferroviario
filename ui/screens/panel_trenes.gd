extends VBoxContainer
class_name PanelTrenes
## Listado de formaciones, selección, despacho y eliminación mediante la API pública.

signal cierre_solicitado

const COLOR_TEXTO: Color = Color(0.82, 0.84, 0.90, 1.0)
const COLOR_TEXTO_SUAVE: Color = Color(0.60, 0.63, 0.70, 1.0)
const COLOR_ACENTO: Color = Color(1.0, 0.756863, 0.278431, 1.0)
const COLOR_ELIMINAR: Color = Color(0.9, 0.35, 0.35, 1.0)
const INTERVALO_REFRESCO_MS: int = 500

var _controlador: SimulacionController
var _nivel: Node
var _titulo: Label
var _lista: VBoxContainer
var _sin_trenes: Label
var _agregar: Button
var _agregar_bosques: Button
var _mensaje: Label
var _filas: Dictionary = {}  ## ID operativo -> controles de la formación.
var _proximo_refresco_ms: int = 0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_nivel = _resolver_nivel()
	if _nivel != null:
		_controlador = _nivel.get_node_or_null("SimulacionController") as SimulacionController
	_construir_panel()
	if _controlador != null:
		_controlador.tren_agregado.connect(_on_tren_agregado)
		_controlador.tren_eliminado.connect(_on_tren_eliminado)
	_actualizar()


func _resolver_nivel() -> Node:
	var ancestro: Node = get_parent()
	while ancestro != null:
		if ancestro.get_node_or_null("SimulacionController") != null:
			return ancestro
		ancestro = ancestro.get_parent()
	return null


func _construir_panel() -> void:
	var encabezado: HBoxContainer = HBoxContainer.new()
	add_child(encabezado)
	_titulo = _crear_etiqueta(16, COLOR_ACENTO)
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encabezado.add_child(_titulo)
	var cerrar: Button = Button.new()
	cerrar.text = "✕"
	cerrar.tooltip_text = "Cerrar trenes"
	cerrar.flat = true
	cerrar.add_theme_font_size_override("font_size", 12)
	cerrar.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	cerrar.pressed.connect(func() -> void: cierre_solicitado.emit())
	encabezado.add_child(cerrar)
	add_child(HSeparator.new())
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 8)
	add_child(_lista)
	_sin_trenes = _crear_etiqueta(12, COLOR_TEXTO_SUAVE)
	_sin_trenes.text = "No hay trenes en este nivel."
	add_child(_sin_trenes)
	_agregar = Button.new()
	_agregar.custom_minimum_size = Vector2(0.0, 32.0)
	_agregar.add_theme_font_size_override("font_size", 12)
	_agregar.pressed.connect(_agregar_tren)
	add_child(_agregar)
	_agregar_bosques = Button.new()
	_agregar_bosques.custom_minimum_size = Vector2(0.0, 32.0)
	_agregar_bosques.add_theme_font_size_override("font_size", 12)
	_agregar_bosques.pressed.connect(_agregar_tren_bosques)
	add_child(_agregar_bosques)
	_mensaje = _crear_etiqueta(12, COLOR_TEXTO_SUAVE)
	_mensaje.hide()
	add_child(_mensaje)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= _proximo_refresco_ms:
		_actualizar()


func _actualizar() -> void:
	_proximo_refresco_ms = Time.get_ticks_msec() + INTERVALO_REFRESCO_MS
	if not is_instance_valid(_controlador):
		_titulo.text = "TRENES"
		_sin_trenes.text = "No hay un controlador de trenes en este nivel."
		_agregar.text = "+ Agregar tren en Constitución"
		_agregar.disabled = true
		_agregar_bosques.text = "+ Agregar tren en Bosques"
		_agregar_bosques.disabled = true
		return
	var resumen: Dictionary = _controlador.obtener_resumen_global()
	_titulo.text = "TRENES · %d simultáneos" % int(resumen.get("trenes_activos", 0))
	_titulo.tooltip_text = "Máximo simultáneo: %d trenes" % int(resumen.get("concurrencia_maxima", 0))
	var ids_actuales: Array[int] = []
	for datos: Dictionary in _controlador.obtener_trenes():
		var id: int = int(datos.get("id", 0))
		ids_actuales.append(id)
		if not _filas.has(id):
			_crear_fila(id)
		_actualizar_fila(id, datos)
	for id: int in _filas.keys():
		if id not in ids_actuales:
			_quitar_fila(id)
	_sin_trenes.visible = _filas.is_empty()
	var en_cola: int = int(_nivel.call("trenes_en_cola")) if is_instance_valid(_nivel) and _nivel.has_method("trenes_en_cola") else 0
	_agregar.text = "+ Agregar tren en Constitución" + (" · %d en cola" % en_cola if en_cola > 0 else "")
	var en_cola_bosques: int = int(_nivel.call("trenes_bosques_en_cola")) if is_instance_valid(_nivel) and _nivel.has_method("trenes_bosques_en_cola") else 0
	_agregar_bosques.text = "+ Agregar tren en Bosques" + (" · %d en cola" % en_cola_bosques if en_cola_bosques > 0 else "")


func _crear_fila(id: int) -> void:
	var tarjeta: PanelContainer = PanelContainer.new()
	tarjeta.add_theme_stylebox_override("panel", _estilo_tarjeta())
	_lista.add_child(tarjeta)
	var contenido: VBoxContainer = VBoxContainer.new()
	contenido.add_theme_constant_override("separation", 4)
	tarjeta.add_child(contenido)
	var acciones: HBoxContainer = HBoxContainer.new()
	acciones.add_theme_constant_override("separation", 8)
	contenido.add_child(acciones)
	var seleccionar: Button = Button.new()
	seleccionar.text = "▶ Tren %d" % id
	seleccionar.alignment = HORIZONTAL_ALIGNMENT_LEFT
	seleccionar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seleccionar.flat = true
	seleccionar.tooltip_text = "Ver Tren %d" % id
	seleccionar.add_theme_font_size_override("font_size", 13)
	seleccionar.add_theme_color_override("font_color", COLOR_TEXTO)
	seleccionar.pressed.connect(_seleccionar_tren.bind(id))
	acciones.add_child(seleccionar)
	var eliminar: Button = Button.new()
	eliminar.text = "Eliminar"
	eliminar.tooltip_text = "Eliminar Tren %d de la simulación" % id
	eliminar.add_theme_font_size_override("font_size", 12)
	eliminar.add_theme_color_override("font_color", COLOR_ELIMINAR)
	eliminar.add_theme_color_override("font_hover_color", COLOR_ELIMINAR)
	eliminar.add_theme_color_override("font_pressed_color", COLOR_ELIMINAR)
	eliminar.pressed.connect(_eliminar_tren.bind(id))
	acciones.add_child(eliminar)
	var proxima: Label = _crear_etiqueta(12, COLOR_TEXTO_SUAVE)
	contenido.add_child(proxima)
	var pasajeros: Label = _crear_etiqueta(12, COLOR_TEXTO)
	contenido.add_child(pasajeros)
	var estado: Label = _crear_etiqueta(12, COLOR_TEXTO_SUAVE)
	contenido.add_child(estado)
	_filas[id] = {"tarjeta": tarjeta, "proxima": proxima, "pasajeros": pasajeros, "estado": estado}


func _actualizar_fila(id: int, datos: Dictionary) -> void:
	var fila: Dictionary = _filas[id]
	var proxima: String = str(datos.get("estacion_proxima", ""))
	var estado: int = int(datos.get("estado", -1))
	var finalizado: bool = estado in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA]
	(fila["proxima"] as Label).text = "Recorrido finalizado" if finalizado else "Próxima estación: %s" % (proxima if not proxima.is_empty() else "Sin parada asignada")
	(fila["pasajeros"] as Label).text = "Pasajeros: %d / %d" % [int(datos.get("pasajeros", 0)), int(datos.get("capacidad", 0))]
	var destino: String = "A Bosques" if str(datos.get("sentido", "ida")) == "ida" else "A Constitución"
	var estado_nombre: String = str(datos.get("estado_nombre", ""))
	var puntualidad: String = str(datos.get("puntualidad_nombre", "Sin horario"))
	(fila["estado"] as Label).text = "%s · %s%s" % [destino, estado_nombre, " · " + puntualidad if not finalizado and estado != Tren.EstadoOperacion.INCOMPLETO else ""]


func _quitar_fila(id: int) -> void:
	var tarjeta: PanelContainer = _filas[id]["tarjeta"] as PanelContainer
	_lista.remove_child(tarjeta)
	tarjeta.queue_free()
	_filas.erase(id)


func _seleccionar_tren(id: int) -> void:
	if is_instance_valid(_controlador) and _controlador.seleccionar_tren(id):
		cierre_solicitado.emit()


func _eliminar_tren(id: int) -> void:
	if is_instance_valid(_controlador):
		_controlador.eliminar_tren(id)
		_actualizar()


func _agregar_tren() -> void:
	if not is_instance_valid(_controlador):
		return
	var resultado: Dictionary = _controlador.agregar_tren()
	_mensaje.text = str(resultado.get("motivo", ""))
	_mensaje.visible = not _mensaje.text.is_empty()
	_actualizar()


func _agregar_tren_bosques() -> void:
	if not is_instance_valid(_controlador):
		return
	var resultado: Dictionary = _controlador.agregar_tren_en_bosques()
	_mensaje.text = str(resultado.get("motivo", ""))
	_mensaje.visible = not _mensaje.text.is_empty()
	_actualizar()


func _on_tren_agregado(_datos: Dictionary) -> void:
	_actualizar()


func _on_tren_eliminado(_id: int) -> void:
	_actualizar()


func _unhandled_key_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE:
		cierre_solicitado.emit()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if not is_instance_valid(_controlador):
		return
	if _controlador.tren_agregado.is_connected(_on_tren_agregado):
		_controlador.tren_agregado.disconnect(_on_tren_agregado)
	if _controlador.tren_eliminado.is_connected(_on_tren_eliminado):
		_controlador.tren_eliminado.disconnect(_on_tren_eliminado)


func _crear_etiqueta(tamano: int, color: Color) -> Label:
	var etiqueta: Label = Label.new()
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etiqueta.add_theme_font_size_override("font_size", tamano)
	etiqueta.add_theme_color_override("font_color", color)
	return etiqueta


func _estilo_tarjeta() -> StyleBoxFlat:
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.14, 0.145, 0.18, 0.85)
	estilo.set_border_width_all(1)
	estilo.border_color = Color(COLOR_ACENTO, 0.25)
	estilo.set_corner_radius_all(6)
	estilo.content_margin_left = 12.0
	estilo.content_margin_right = 12.0
	estilo.content_margin_top = 8.0
	estilo.content_margin_bottom = 8.0
	return estilo
