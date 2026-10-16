extends VBoxContainer
class_name PanelEstaciones
## Listado de estaciones con pasajeros y estado de abordaje en tiempo real.

signal estacion_elegida(estacion: Estacion)
signal cierre_solicitado

const COLOR_TEXTO: Color = Color(0.82, 0.84, 0.90, 1.0)
const COLOR_TEXTO_SUAVE: Color = Color(0.60, 0.63, 0.70, 1.0)
const COLOR_ACENTO: Color = Color(1.0, 0.756863, 0.278431, 1.0)
const COLOR_SUSPENDIDO: Color = Color(1.0, 0.45, 0.35, 1.0)

var _lista: VBoxContainer
var _sin_estaciones: Label
var _filas: Dictionary = {}  ## Estacion -> controles de su fila.


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var encabezado: HBoxContainer = HBoxContainer.new()
	add_child(encabezado)
	var titulo: Label = Label.new()
	titulo.text = "ESTACIONES"
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.add_theme_font_size_override("font_size", 16)
	titulo.add_theme_color_override("font_color", COLOR_ACENTO)
	encabezado.add_child(titulo)
	var cerrar: Button = Button.new()
	cerrar.text = "✕"
	cerrar.tooltip_text = "Cerrar estaciones"
	cerrar.flat = true
	cerrar.add_theme_color_override("font_color", COLOR_TEXTO)
	cerrar.pressed.connect(func() -> void: cierre_solicitado.emit())
	encabezado.add_child(cerrar)
	var ayuda: Label = Label.new()
	ayuda.text = "Estaciones activas del recorrido."
	ayuda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ayuda.add_theme_font_size_override("font_size", 12)
	ayuda.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	add_child(ayuda)
	add_child(HSeparator.new())
	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 8)
	add_child(_lista)
	_sin_estaciones = Label.new()
	_sin_estaciones.text = "No hay estaciones en este nivel."
	_sin_estaciones.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	add_child(_sin_estaciones)
	for nodo: Node in get_tree().get_nodes_in_group("estaciones"):
		if nodo is Estacion:
			_agregar_estacion(nodo as Estacion)
	get_tree().node_added.connect(_on_nodo_agregado)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_nodo_agregado):
		get_tree().node_added.disconnect(_on_nodo_agregado)
	for estacion: Estacion in _filas.keys():
		_desconectar_estacion(estacion)


func _unhandled_key_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE:
		cierre_solicitado.emit()
		get_viewport().set_input_as_handled()


func _on_nodo_agregado(nodo: Node) -> void:
	if nodo is Estacion:
		call_deferred("_agregar_estacion_por_id", nodo.get_instance_id())


func _agregar_estacion_por_id(id: int) -> void:
	var estacion: Estacion = instance_from_id(id) as Estacion
	if is_inside_tree() and is_instance_valid(estacion) and estacion.is_in_group("estaciones"):
		_agregar_estacion(estacion)


func _agregar_estacion(estacion: Estacion) -> void:
	if _filas.has(estacion):
		return
	var boton: Button = Button.new()
	boton.custom_minimum_size = Vector2(0.0, 72.0)
	boton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boton.tooltip_text = "Ir a %s" % estacion.nombre_estacion
	boton.add_theme_stylebox_override("normal", _estilo_fila(false))
	boton.add_theme_stylebox_override("hover", _estilo_fila(true))
	boton.add_theme_stylebox_override("pressed", _estilo_fila(true))
	boton.add_theme_stylebox_override("focus", _estilo_fila(true))
	boton.pressed.connect(_seleccionar_estacion.bind(estacion))
	_lista.add_child(boton)
	var contenido: VBoxContainer = VBoxContainer.new()
	contenido.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contenido.offset_left = 12.0
	contenido.offset_right = -12.0
	contenido.offset_top = 8.0
	contenido.offset_bottom = -8.0
	contenido.add_theme_constant_override("separation", 5)
	contenido.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boton.add_child(contenido)
	var nombre: Label = Label.new()
	nombre.text = estacion.nombre_estacion
	nombre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombre.add_theme_font_size_override("font_size", 13)
	nombre.add_theme_color_override("font_color", COLOR_TEXTO)
	contenido.add_child(nombre)
	var datos: HBoxContainer = HBoxContainer.new()
	datos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contenido.add_child(datos)
	var pasajeros: Label = Label.new()
	pasajeros.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pasajeros.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pasajeros.add_theme_font_size_override("font_size", 12)
	pasajeros.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	datos.add_child(pasajeros)
	var estado: Label = Label.new()
	estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	estado.add_theme_font_size_override("font_size", 12)
	datos.add_child(estado)
	_filas[estacion] = {"boton": boton, "pasajeros": pasajeros, "estado": estado}
	estacion.pasajeros_actualizados.connect(_actualizar_fila)
	estacion.abordaje_cambiado.connect(_on_abordaje_cambiado.bind(estacion))
	estacion.ingreso_pasajeros_cambiado.connect(_on_ingreso_pasajeros_cambiado.bind(estacion))
	estacion.tree_exiting.connect(_quitar_estacion.bind(estacion))
	_sin_estaciones.hide()
	_actualizar_fila(estacion)


func _actualizar_fila(estacion: Estacion) -> void:
	if not is_instance_valid(estacion) or not _filas.has(estacion):
		return
	var fila: Dictionary = _filas[estacion]
	var pasajeros: Label = fila["pasajeros"] as Label
	var estado: Label = fila["estado"] as Label
	var cantidad: int = estacion.pasajeros_esperando + estacion.pasajeros_saliendo
	pasajeros.text = "%d pasajeros" % cantidad
	var abordando: bool = estacion.hay_tren_abordando()
	if not estacion.ingreso_pasajeros_habilitado:
		estado.text = "Suspendido"
		estado.add_theme_color_override("font_color", COLOR_SUSPENDIDO)
	else:
		estado.text = "Abordando" if abordando else "En espera"
		estado.add_theme_color_override("font_color", COLOR_ACENTO if abordando else COLOR_TEXTO_SUAVE)


func _on_abordaje_cambiado(_activo: bool, estacion: Estacion) -> void:
	_actualizar_fila(estacion)


func _on_ingreso_pasajeros_cambiado(_habilitado: bool, estacion: Estacion) -> void:
	_actualizar_fila(estacion)


func _quitar_estacion(estacion: Estacion) -> void:
	if not _filas.has(estacion):
		return
	_desconectar_estacion(estacion)
	var boton: Button = _filas[estacion]["boton"] as Button
	boton.queue_free()
	_filas.erase(estacion)
	_sin_estaciones.visible = _filas.is_empty()


func _desconectar_estacion(estacion: Estacion) -> void:
	if not is_instance_valid(estacion):
		return
	if estacion.pasajeros_actualizados.is_connected(_actualizar_fila):
		estacion.pasajeros_actualizados.disconnect(_actualizar_fila)
	var abordaje: Callable = _on_abordaje_cambiado.bind(estacion)
	if estacion.abordaje_cambiado.is_connected(abordaje):
		estacion.abordaje_cambiado.disconnect(abordaje)
	var ingreso: Callable = _on_ingreso_pasajeros_cambiado.bind(estacion)
	if estacion.ingreso_pasajeros_cambiado.is_connected(ingreso):
		estacion.ingreso_pasajeros_cambiado.disconnect(ingreso)
	var salida: Callable = _quitar_estacion.bind(estacion)
	if estacion.tree_exiting.is_connected(salida):
		estacion.tree_exiting.disconnect(salida)


func _seleccionar_estacion(estacion: Estacion) -> void:
	if is_instance_valid(estacion) and not estacion.is_queued_for_deletion():
		estacion_elegida.emit(estacion)


func _estilo_fila(hover: bool) -> StyleBoxFlat:
	var estilo: StyleBoxFlat = StyleBoxFlat.new()
	estilo.bg_color = Color(0.17, 0.165, 0.12, 0.98) if hover else Color(0.14, 0.145, 0.18, 0.85)
	estilo.set_border_width_all(1)
	estilo.border_color = Color(COLOR_ACENTO, 0.7 if hover else 0.25)
	estilo.set_corner_radius_all(6)
	return estilo
