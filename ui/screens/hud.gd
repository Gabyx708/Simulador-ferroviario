extends CanvasLayer
## Paneles de pruebas de marcha y switches de la formación seleccionada.
## El listado de trenes pertenece a la navegación inferior.

@onready var _panel_pruebas: PanelContainer = %PanelPruebas
@onready var _contenido_pruebas: VBoxContainer = $Paneles/PanelPruebas/Margen/Contenido
@onready var _titulo_pruebas: Button = $Paneles/PanelPruebas/Margen/Contenido/Titulo
@onready var _tren_pruebas: Label = %TrenPruebas
@onready var _velocidad_prueba: HSlider = %VelocidadPrueba
@onready var _aceleracion_prueba: HSlider = %AceleracionPrueba
@onready var _frenado_prueba: HSlider = %FrenadoPrueba
@onready var _valor_velocidad: Label = %ValorVelocidadPrueba
@onready var _valor_aceleracion: Label = %ValorAceleracionPrueba
@onready var _valor_frenado: Label = %ValorFrenadoPrueba
@onready var _restablecer: Button = %RestablecerPruebas
@onready var _lista_switches: VBoxContainer = %ListaSwitches
@onready var _estado_switches: Label = %EstadoSwitches
@onready var _mostrar_mas_switches: Button = %MostrarMasSwitches
@onready var _panel_switches: PanelContainer = $Paneles/PanelSwitches
@onready var _contenido_switches: VBoxContainer = $Paneles/PanelSwitches/Margen/Contenido
@onready var _titulo_switches: Button = $Paneles/PanelSwitches/Margen/Contenido/Titulo
@onready var _demora_salida: SpinBox = %DemoraSalida
@onready var _espera_estaciones: SpinBox = %EsperaEstaciones
var _tren_seleccionado: Tren
var _botones_switch: Dictionary = {}
var _titulos_switch: Dictionary = {}
var _firma_switches: String = ""
var _switch_seleccionado: int = 0
var _paneles_abiertos: Dictionary = {"pruebas": false, "switches": false}
const ALTURA_PANEL_CERRADO := 28.0
const ALTURAS_PANELES := {"pruebas": 230.0, "switches": 230.0}


func _ready() -> void:
	_aplicar_estilo_minimalista(self)
	_velocidad_prueba.value_changed.connect(_cambiar_parametros_prueba)
	_aceleracion_prueba.value_changed.connect(_cambiar_parametros_prueba)
	_frenado_prueba.value_changed.connect(_cambiar_parametros_prueba)
	_restablecer.pressed.connect(_restablecer_parametros_prueba)
	_demora_salida.value_changed.connect(_cambiar_tiempos_servicio)
	_espera_estaciones.value_changed.connect(_cambiar_tiempos_servicio)
	_titulo_pruebas.pressed.connect(_alternar_panel.bind("pruebas"))
	_titulo_switches.pressed.connect(_alternar_panel.bind("switches"))
	_mostrar_mas_switches.pressed.connect(_mostrar_siguiente_bloque_switches)
	var nivel: Node = get_parent()
	if nivel != null and nivel.has_signal("tren_agregado"):
		nivel.connect("tren_agregado", _on_tren_agregado)
	_actualizar_panel_pruebas()
	_aplicar_estado_paneles()
	call_deferred("_conectar_trenes")


func _aplicar_estilo_minimalista(nodo: Node) -> void:
	for hijo: Node in nodo.get_children():
		if hijo is InformacionEstacion or hijo is NavegacionPaneles:
			continue
		if hijo is Label:
			var etiqueta := hijo as Label
			etiqueta.add_theme_font_size_override("font_size", 10)
			etiqueta.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75, 1.0))
		elif hijo is Button:
			var boton := hijo as Button
			boton.add_theme_font_size_override("font_size", 10)
			if not boton.flat:
				boton.add_theme_stylebox_override("normal", _estilo_boton_minimalista(false))
				boton.add_theme_stylebox_override("hover", _estilo_boton_minimalista(true))
				boton.add_theme_stylebox_override("pressed", _estilo_boton_minimalista(true, true))
				boton.add_theme_stylebox_override("disabled", _estilo_boton_minimalista(false, false, true))
		_aplicar_estilo_minimalista(hijo)


func _estilo_boton_minimalista(hover: bool, presionado: bool = false, deshabilitado: bool = false) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.07, 0.075, 0.1, 0.62) if deshabilitado else (Color(0.16, 0.165, 0.21, 0.98) if hover else Color(0.102, 0.11, 0.149, 0.95))
	if presionado:
		estilo.bg_color = Color(0.18, 0.16, 0.12, 1.0)
	estilo.border_width_left = 1
	estilo.border_width_top = 1
	estilo.border_width_right = 1
	estilo.border_width_bottom = 1
	estilo.border_color = Color(0.36, 0.35, 0.36, 0.42 if deshabilitado else 0.9)
	estilo.corner_radius_top_left = 2
	estilo.corner_radius_top_right = 2
	estilo.corner_radius_bottom_left = 2
	estilo.corner_radius_bottom_right = 2
	estilo.content_margin_left = 4
	estilo.content_margin_right = 4
	return estilo


## Mismo identificador en toda la UI (paneles viejos, panel de control y
## métricas): "Tren %d" por id operativo, que es lo único realmente único
## entre trenes -- el nombre del nodo (p.ej. "TrenCSR_02") no lo es tanto
## y varía según cómo se haya instanciado cada formación.
func _identificador_tren(tren: Tren) -> String:
	var id: int = tren.obtener_id_operativo()
	return "Tren %d" % id if id > 0 else tren.name


func _conectar_trenes() -> void:
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			_conectar_seleccion_tren(nodo as Tren)


func _conectar_seleccion_tren(tren: Tren) -> void:
	if not is_instance_valid(tren) or tren.esta_eliminado():
		return
	var al_seleccionar: Callable = _marcar_seleccion.bind(tren)
	if not tren.seleccionado.is_connected(al_seleccionar):
		tren.seleccionado.connect(al_seleccionar)
	var al_eliminar: Callable = _on_tren_eliminado.bind(tren)
	if not tren.eliminado.is_connected(al_eliminar):
		tren.eliminado.connect(al_eliminar)


func _marcar_seleccion(tren: Tren) -> void:
	if _tren_seleccionado != null and is_instance_valid(_tren_seleccionado) and _tren_seleccionado != tren:
		_tren_seleccionado.activar_opciones_switch(false)
		_ocultar_indicador_switch()
		_switch_seleccionado = 0
	_tren_seleccionado = tren
	if tren != null and is_instance_valid(tren):
		tren.activar_opciones_switch(bool(_paneles_abiertos.get("switches", false)))
	if bool(_paneles_abiertos.get("pruebas", false)):
		_actualizar_panel_pruebas()
	if tren != null and is_instance_valid(tren):
		if not tren.opciones_switch_cambiadas.is_connected(_actualizar_panel_switches):
			tren.opciones_switch_cambiadas.connect(_actualizar_panel_switches)
		if not tren.ruta_actualizada.is_connected(_on_ruta_actualizada):
			tren.ruta_actualizada.connect(_on_ruta_actualizada)


func _actualizar_panel_pruebas() -> void:
	var disponible: bool = _tren_seleccionado != null and is_instance_valid(_tren_seleccionado)
	_panel_pruebas.modulate.a = 1.0
	_velocidad_prueba.editable = disponible
	_aceleracion_prueba.editable = disponible
	_frenado_prueba.editable = disponible
	_restablecer.disabled = not disponible
	if not disponible:
		_tren_pruebas.text = "Sin tren seleccionado"
		_demora_salida.editable = false
		_espera_estaciones.editable = false
		return
	_demora_salida.editable = true
	_espera_estaciones.editable = true
	_tren_pruebas.text = _identificador_tren(_tren_seleccionado)
	_demora_salida.set_value_no_signal(_tren_seleccionado.demora_salida_inicial)
	_espera_estaciones.set_value_no_signal(_tren_seleccionado.tiempo_parada_servicio)
	var factores: Dictionary = _tren_seleccionado.factores_prueba()
	_velocidad_prueba.set_value_no_signal(float(factores.get("velocidad", 1.0)))
	_aceleracion_prueba.set_value_no_signal(float(factores.get("aceleracion", 1.0)))
	_frenado_prueba.set_value_no_signal(float(factores.get("frenado", 1.0)))
	_mostrar_valores_prueba()
	if bool(_paneles_abiertos.get("switches", false)):
		_actualizar_panel_switches()


func _actualizar_panel_switches() -> void:
	if not bool(_paneles_abiertos.get("switches", false)):
		return
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		_limpiar_panel_switches()
		_estado_switches.text = "Seleccioná un tren para ver sus próximos desvíos."
		return
	var secciones: Array[Dictionary] = _tren_seleccionado.opciones_switch_proximos()
	if secciones.is_empty():
		_limpiar_panel_switches()
		_ocultar_indicador_switch()
		_switch_seleccionado = 0
		_estado_switches.text = "Sin switches antes de la próxima estación."
		_mostrar_mas_switches.visible = false
		return
	var firma_partes: Array[String] = []
	for seccion_firma: Dictionary in secciones:
		for opcion_firma: Variant in seccion_firma.get("opciones", []):
			firma_partes.append("%d:%s" % [int(seccion_firma.get("nodo_id", 0)), str((opcion_firma as Dictionary).get("segmento", ""))])
	var firma: String = "|".join(firma_partes)
	var mantiene_seleccion := false
	for seccion_seleccion: Dictionary in secciones:
		mantiene_seleccion = mantiene_seleccion or int(seccion_seleccion.get("nodo_id", 0)) == _switch_seleccionado
	if _switch_seleccionado != 0 and not mantiene_seleccion:
		_switch_seleccionado = 0
		_ocultar_indicador_switch()
	if firma != _firma_switches:
		_limpiar_panel_switches()
		_firma_switches = firma
		_construir_controles_switches(secciones)
	_actualizar_controles_switches(secciones)
	var pendientes := false
	for seccion_estado: Dictionary in secciones:
		for opcion_estado: Variant in seccion_estado.get("opciones", []):
			if str((opcion_estado as Dictionary).get("estado", "")) == "pendiente":
				pendientes = true
	_estado_switches.text = "Calculando opciones compatibles…" if pendientes else "Ramas que mantienen el itinerario a Bosques"
	_mostrar_mas_switches.visible = _tren_seleccionado.hay_mas_switches_disponibles()


func _limpiar_panel_switches() -> void:
	for hijo: Node in _lista_switches.get_children():
		hijo.queue_free()
	_botones_switch.clear()
	_titulos_switch.clear()
	_firma_switches = ""


func _construir_controles_switches(secciones: Array[Dictionary]) -> void:
	for seccion: Dictionary in secciones:
		var nodo_id: int = int(seccion.get("nodo_id", 0))
		var tarjeta := PanelContainer.new()
		tarjeta.add_theme_stylebox_override("panel", _estilo_tarjeta_switch())
		_lista_switches.add_child(tarjeta)
		var contenido := VBoxContainer.new()
		contenido.add_theme_constant_override("separation", 1)
		tarjeta.add_child(contenido)
		var titulo := Button.new()
		titulo.flat = true
		titulo.alignment = HORIZONTAL_ALIGNMENT_LEFT
		titulo.add_theme_font_size_override("font_size", 10)
		titulo.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75, 1.0))
		titulo.pressed.connect(_seleccionar_tarjeta_switch.bind(nodo_id))
		contenido.add_child(titulo)
		_titulos_switch[nodo_id] = titulo
		var grupo := ButtonGroup.new()
		grupo.allow_unpress = false
		for opcion: Dictionary in seccion.get("opciones", []):
			var boton := CheckButton.new()
			boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
			boton.add_theme_font_size_override("font_size", 10)
			boton.button_group = grupo
			boton.pressed.connect(_seleccionar_opcion_switch.bind(nodo_id, str(opcion.get("segmento", ""))))
			contenido.add_child(boton)
			_botones_switch["%d:%s" % [nodo_id, str(opcion.get("segmento", ""))]] = boton


func _actualizar_controles_switches(secciones: Array[Dictionary]) -> void:
	for seccion: Dictionary in secciones:
		var nodo_id: int = int(seccion.get("nodo_id", 0))
		var titulo: Button = _titulos_switch.get(nodo_id) as Button
		if titulo != null:
			var activa: String = _nombre_corto_switch(str(seccion.get("segmento_elegido", "")))
			titulo.text = ("▸ " if nodo_id == _switch_seleccionado else "") + "AGUJA %d  ·  %.0f m  ·  %s" % [nodo_id, float(seccion.get("distancia_m", 0.0)), activa]
		for opcion: Dictionary in seccion.get("opciones", []):
			var boton: CheckButton = _botones_switch.get("%d:%s" % [nodo_id, str(opcion.get("segmento", ""))]) as CheckButton
			if boton == null:
				continue
			var estado: String = str(opcion.get("estado", "pendiente"))
			var reservada: bool = _tren_seleccionado.opcion_switch_reservada_por_otro(nodo_id, str(opcion.get("segmento", "")))
			var seleccionada: bool = bool(opcion.get("seleccionada", false))
			var sufijo: String = " · Calculando" if estado == "pendiente" else (" · Reservada" if reservada else (" · Sin continuidad" if not bool(opcion.get("valida", false)) else ""))
			boton.text = _nombre_corto_switch(str(opcion.get("nombre", opcion.get("segmento", "")))) + sufijo
			boton.set_pressed_no_signal(seleccionada)
			boton.disabled = not bool(opcion.get("valida", false)) or reservada
			boton.add_theme_stylebox_override("normal", _estilo_opcion_switch(seleccionada, false))
			boton.add_theme_stylebox_override("hover", _estilo_opcion_switch(seleccionada, true))
			boton.add_theme_stylebox_override("disabled", _estilo_opcion_switch(false, false, true))
			boton.tooltip_text = "Calculando la continuidad a Bosques" if estado == "pendiente" else ("Reservada por otra formación" if reservada else ("No permite completar el itinerario hasta Bosques" if boton.disabled else "Aplicar esta ruta al tren seleccionado"))


func _seleccionar_opcion_switch(nodo_id: int, segmento: String) -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	if not _tren_seleccionado.seleccionar_switch(nodo_id, segmento):
		_estado_switches.text = "No se aplicó: el desvío ya no conserva la ruta o la sección está ocupada."
		return
	_switch_seleccionado = nodo_id
	_mostrar_indicador_switch(nodo_id, segmento)
	_actualizar_panel_switches()


func _seleccionar_tarjeta_switch(nodo_id: int) -> void:
	_switch_seleccionado = nodo_id
	for seccion: Dictionary in _tren_seleccionado.opciones_switch_proximos():
		if int(seccion.get("nodo_id", 0)) == nodo_id:
			_mostrar_indicador_switch(nodo_id, str(seccion.get("segmento_elegido", "")))
			break
	_actualizar_panel_switches()


func _nombre_corto_switch(nombre: String) -> String:
	var partes: PackedStringArray = nombre.split(" · ")
	return partes[0] if not partes.is_empty() else nombre


func _estilo_tarjeta_switch() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.101961, 0.109804, 0.14902, 0.96)
	estilo.border_width_left = 1
	estilo.border_width_top = 1
	estilo.border_width_right = 1
	estilo.border_width_bottom = 1
	estilo.border_color = Color(0.38, 0.36, 0.32, 0.88)
	estilo.corner_radius_top_left = 3
	estilo.corner_radius_top_right = 3
	estilo.corner_radius_bottom_left = 3
	estilo.corner_radius_bottom_right = 3
	estilo.content_margin_left = 4
	estilo.content_margin_top = 3
	estilo.content_margin_right = 4
	estilo.content_margin_bottom = 3
	return estilo


func _estilo_opcion_switch(seleccionada: bool, hover: bool, deshabilitada: bool = false) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.18, 0.18, 0.22, 0.88) if hover else Color(0.11, 0.12, 0.16, 0.82)
	if seleccionada:
		estilo.bg_color = Color(0.19, 0.17, 0.13, 0.95)
		estilo.border_width_left = 2
		estilo.border_color = Color(1.0, 0.756863, 0.278431, 0.82)
	elif deshabilitada:
		estilo.bg_color = Color(0.07, 0.075, 0.1, 0.66)
		estilo.border_width_left = 1
		estilo.border_color = Color(0.25, 0.25, 0.25, 0.55)
	estilo.corner_radius_top_left = 2
	estilo.corner_radius_top_right = 2
	estilo.corner_radius_bottom_left = 2
	estilo.corner_radius_bottom_right = 2
	estilo.content_margin_left = 3
	estilo.content_margin_right = 3
	return estilo


func _obtener_red() -> Node:
	return get_tree().get_first_node_in_group("track_network")


func _mostrar_indicador_switch(nodo_id: int, segmento: String) -> void:
	var red: Node = _obtener_red()
	if red != null and red.has_method("mostrar_indicador_switch_hud"):
		red.call("mostrar_indicador_switch_hud", nodo_id, segmento)


func _ocultar_indicador_switch() -> void:
	var red: Node = _obtener_red()
	if red != null and red.has_method("ocultar_indicador_switch_hud"):
		red.call("ocultar_indicador_switch_hud")


func _mostrar_siguiente_bloque_switches() -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	_tren_seleccionado.ampliar_opciones_switch(2)
	_actualizar_panel_switches()


func _cambiar_tiempos_servicio(_valor: float) -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	_tren_seleccionado.configurar_tiempos_servicio(_demora_salida.value, _espera_estaciones.value)


func _on_tren_agregado(tren: Tren) -> void:
	_conectar_seleccion_tren(tren)


func _on_tren_eliminado(tren: Tren) -> void:
	if _tren_seleccionado != tren:
		return
	_tren_seleccionado = null
	_ocultar_indicador_switch()
	_switch_seleccionado = 0
	_actualizar_panel_pruebas()
	_limpiar_panel_switches()
	_estado_switches.text = "Seleccioná un tren para ver sus próximos desvíos."


func _on_ruta_actualizada(_destino: String, _distancia: float) -> void:
	if bool(_paneles_abiertos.get("switches", false)):
		_actualizar_panel_switches()


func _alternar_panel(id_panel: String) -> void:
	_paneles_abiertos[id_panel] = not bool(_paneles_abiertos.get(id_panel, false))
	_aplicar_estado_paneles()
	if id_panel == "switches" and _tren_seleccionado != null and is_instance_valid(_tren_seleccionado):
		_tren_seleccionado.activar_opciones_switch(bool(_paneles_abiertos[id_panel]))
		if bool(_paneles_abiertos[id_panel]):
			_actualizar_panel_switches()
		else:
			_ocultar_indicador_switch()
			_switch_seleccionado = 0
	elif id_panel == "pruebas" and bool(_paneles_abiertos[id_panel]):
		_actualizar_panel_pruebas()


func _aplicar_estado_paneles() -> void:
	_configurar_panel("pruebas", _panel_pruebas, _contenido_pruebas, _titulo_pruebas, "PRUEBAS DE MARCHA")
	_configurar_panel("switches", _panel_switches, _contenido_switches, _titulo_switches, "SWITCHES PRÓXIMOS")
	for id_panel: String in ["pruebas", "switches"]:
		var panel: PanelContainer = {"pruebas": _panel_pruebas, "switches": _panel_switches}[id_panel] as PanelContainer
		var alto: float = float(ALTURAS_PANELES[id_panel]) if bool(_paneles_abiertos[id_panel]) else ALTURA_PANEL_CERRADO
		panel.custom_minimum_size.y = alto


func _configurar_panel(id_panel: String, _panel: PanelContainer, contenido: VBoxContainer, titulo: Button, texto: String) -> void:
	var abierto: bool = bool(_paneles_abiertos.get(id_panel, false))
	titulo.text = ("▼ " if abierto else "▶ ") + texto
	for hijo: Node in contenido.get_children():
		if hijo != titulo:
			hijo.visible = abierto


func _cambiar_parametros_prueba(_valor: float) -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	_tren_seleccionado.establecer_factores_prueba(_velocidad_prueba.value, _aceleracion_prueba.value, _frenado_prueba.value)
	_mostrar_valores_prueba()


func _restablecer_parametros_prueba() -> void:
	_velocidad_prueba.set_value_no_signal(1.0)
	_aceleracion_prueba.set_value_no_signal(1.0)
	_frenado_prueba.set_value_no_signal(1.0)
	_cambiar_parametros_prueba(1.0)


func _mostrar_valores_prueba() -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		_valor_velocidad.text = "×1.0"
		_valor_aceleracion.text = "×1.0"
		_valor_frenado.text = "×1.0"
		return
	_valor_velocidad.text = "×%.1f · %.0f km/h" % [_velocidad_prueba.value, _tren_seleccionado.velocidad_maxima_efectiva_kmh()]
	_valor_aceleracion.text = "×%.1f · %.2f m/s²" % [_aceleracion_prueba.value, _tren_seleccionado.aceleracion_efectiva()]
	_valor_frenado.text = "×%.1f · %.2f m/s²" % [_frenado_prueba.value, _tren_seleccionado.desaceleracion_efectiva()]
