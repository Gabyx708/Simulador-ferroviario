extends Control
class_name PopupEventos

const ANCHO_POPUP: float = 520.0
const FRASES_FALLA_ELECTRICA_ZONA: Array[String] = [
	"Se detectó una falla eléctrica en este tramo.",
	"Una pérdida de tensión interrumpió la circulación por el tramo.",
	"La catenaria del tramo quedó fuera de servicio por una falla eléctrica."
]
const FRASES: Dictionary = {
	GestorEventos.TipoEvento.FALLA_ELECTRICA: [
		"Una descarga en la catenaria obligó a detener la formación.",
		"El pantógrafo detectó una pérdida de tensión en la línea.",
		"Una falla eléctrica interrumpió la marcha del tren."
	],
	GestorEventos.TipoEvento.DESPERFECTO_MECANICO: [
		"Una falla en el sistema de tracción dejó el tren fuera de servicio.",
		"El tren se detuvo tras detectarse una avería en el rodamiento.",
		"Un desperfecto en los frenos obligó a retirar la formación."
	]
}

var _nivel: Node
var _gestor: GestorEventos
var _reloj: RelojSimulacion
var _controlador: SimulacionController
var _lista: VBoxContainer
var _fallas_mostradas: Dictionary = {}  ## id_evento -> true, evita repetir el aviso al detenerse un tren.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# El fondo transparente no debe consumir la entrada destinada al mundo.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ancestro: Node = get_parent()
	while ancestro != null:
		if ancestro.get_node_or_null("GestorEventos") != null:
			_nivel = ancestro
			break
		ancestro = ancestro.get_parent()
	if _nivel == null:
		visible = false
		return
	_gestor = _nivel.get_node_or_null("GestorEventos") as GestorEventos
	_reloj = _nivel.get_node_or_null("RelojSimulacion") as RelojSimulacion
	_controlador = _nivel.get_node_or_null("SimulacionController") as SimulacionController
	_lista = VBoxContainer.new()
	_lista.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_lista.offset_left = -ANCHO_POPUP - 24.0
	_lista.offset_right = -24.0
	_lista.offset_top = 24.0
	_lista.offset_bottom = -24.0
	_lista.add_theme_constant_override("separation", 10)
	_lista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lista)
	if _gestor != null:
		_gestor.evento_disparado.connect(_mostrar_evento_zona)
		_gestor.evento_individual_disparado.connect(_mostrar_evento)
		_gestor.evento_finalizado.connect(_limpiar_falla_mostrada)


func _crear_popup(evento: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = ANCHO_POPUP
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.075, 0.082, 0.105, 0.97)
	estilo.border_color = Color(0.84, 0.16, 0.19, 1.0)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(8)
	estilo.content_margin_left = 14
	estilo.content_margin_right = 14
	estilo.content_margin_top = 12
	estilo.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", estilo)
	_lista.add_child(panel)
	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 7)
	panel.add_child(columna)
	var cabecera := HBoxContainer.new()
	columna.add_child(cabecera)
	var icono := Label.new()
	icono.add_theme_font_size_override("font_size", 28)
	icono.add_theme_color_override("font_color", Color(0.96, 0.20, 0.23))
	cabecera.add_child(icono)
	var titulo := Label.new()
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titulo.add_theme_font_size_override("font_size", 18)
	titulo.add_theme_color_override("font_color", Color(0.96, 0.94, 0.92))
	cabecera.add_child(titulo)
	var hora := Label.new()
	hora.add_theme_font_size_override("font_size", 12)
	hora.add_theme_color_override("font_color", Color(0.75, 0.77, 0.82))
	cabecera.add_child(hora)
	var cerrar := Button.new()
	cerrar.text = "×"
	cerrar.flat = true
	cerrar.tooltip_text = "Cerrar aviso"
	cerrar.add_theme_font_size_override("font_size", 20)
	cerrar.add_theme_color_override("font_color", Color(0.96, 0.35, 0.37))
	cabecera.add_child(cerrar)
	cerrar.pressed.connect(_cerrar_popup.bind(panel))
	var afectado := Label.new()
	afectado.add_theme_font_size_override("font_size", 13)
	afectado.add_theme_color_override("font_color", Color(0.93, 0.93, 0.95))
	columna.add_child(afectado)
	var mensaje := Label.new()
	mensaje.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mensaje.add_theme_font_size_override("font_size", 13)
	mensaje.add_theme_color_override("font_color", Color(0.77, 0.79, 0.84))
	columna.add_child(mensaje)
	var tipo: int = int(evento.get("tipo", -1))
	titulo.text = str(evento.get("tipo_evento", GestorEventos.nombre_tipo(tipo)))
	match tipo:
		GestorEventos.TipoEvento.FALLA_ELECTRICA:
			icono.text = "⚡"
		GestorEventos.TipoEvento.PIQUETE:
			icono.text = "⚠"
		_:
			icono.text = "⚙"
	hora.text = str(evento.get("hora", "--:--"))
	var tipo_afectado: String = "Tren afectado"
	match tipo:
		GestorEventos.TipoEvento.FALLA_ELECTRICA:
			tipo_afectado = "Tramo afectado desde"
		GestorEventos.TipoEvento.PIQUETE:
			tipo_afectado = "Estación afectada"
	afectado.text = "%s: %s" % [tipo_afectado, str(evento.get("perjudicado", "Sin identificar"))]
	mensaje.text = str(evento.get("mensaje", ""))


func _cerrar_popup(panel: PanelContainer) -> void:
	if is_instance_valid(panel):
		panel.queue_free()


func _mostrar_evento(evento: Dictionary) -> void:
	var tipo: int = int(evento.get("tipo", -1))
	if not FRASES.has(tipo):
		return
	if tipo == GestorEventos.TipoEvento.FALLA_ELECTRICA and _fallas_mostradas.has(int(evento.get("id", -1))):
		return
	var id_tren: int = int(evento.get("id_tren", -1))
	var tipo_evento: String = GestorEventos.nombre_tipo(tipo)
	var perjudicado: String = _nombre_tren(id_tren)
	var mensaje: String = FRASES[tipo][randi() % FRASES[tipo].size()]
	var datos_popup: Dictionary = {
		"tipo_evento": tipo_evento,
		"perjudicado": perjudicado,
		"mensaje": mensaje,
		"tipo": tipo,
		"hora": _hora_actual()
	}
	_crear_popup(datos_popup)


func _mostrar_evento_zona(evento: Dictionary) -> void:
	var tipo: int = int(evento.get("tipo", -1))
	if tipo == GestorEventos.TipoEvento.FALLA_ELECTRICA:
		var id_evento: int = int(evento.get("id", -1))
		_fallas_mostradas[id_evento] = true
		_crear_popup({
			"tipo_evento": GestorEventos.nombre_tipo(tipo),
			"perjudicado": str(evento.get("clave", "Tramo sin identificar")),
			"mensaje": FRASES_FALLA_ELECTRICA_ZONA.pick_random(),
			"tipo": tipo,
			"hora": _hora_actual()
		})
		return
	if tipo != GestorEventos.TipoEvento.PIQUETE:
		return
	var datos_popup: Dictionary = evento.duplicate()
	datos_popup["hora"] = _hora_actual()
	_crear_popup(datos_popup)


func _limpiar_falla_mostrada(evento: Dictionary) -> void:
	if int(evento.get("tipo", -1)) == GestorEventos.TipoEvento.FALLA_ELECTRICA:
		_fallas_mostradas.erase(int(evento.get("id", -1)))


func _nombre_tren(id_tren: int) -> String:
	if id_tren <= 0:
		return "Tren sin identificar"
	if _controlador != null:
		var datos: Dictionary = _controlador.obtener_tren(id_tren)
		var nombre: String = str(datos.get("nombre", ""))
		if not nombre.is_empty():
			return nombre
	return "Tren %d" % id_tren


func _hora_actual() -> String:
	if _reloj == null:
		return "--:--"
	var fecha: Dictionary = _reloj.fecha_hora_simulada()
	return "%02d:%02d" % [int(fecha.get("hora", 0)), int(fecha.get("minuto", 0))]
