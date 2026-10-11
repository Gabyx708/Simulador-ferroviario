extends CanvasLayer
## Selector de formaciones disponible desde el HUD. Reutiliza la señal de
## selección normal, por lo que cámara y tablero siempre cambian juntos.

@onready var _lista: VBoxContainer = %ContenidoListaTrenes
@onready var _panel_trenes: PanelContainer = $Paneles/SelectorTrenes
@onready var _contenido_trenes: VBoxContainer = $Paneles/SelectorTrenes/Margen/Contenido
@onready var _titulo_trenes: Button = $Paneles/SelectorTrenes/Margen/Contenido/Titulo
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
@onready var _agregar_tren: Button = %AgregarTren
@onready var _lista_switches: VBoxContainer = %ListaSwitches
@onready var _estado_switches: Label = %EstadoSwitches
@onready var _mostrar_mas_switches: Button = %MostrarMasSwitches
@onready var _panel_switches: PanelContainer = $Paneles/PanelSwitches
@onready var _contenido_switches: VBoxContainer = $Paneles/PanelSwitches/Margen/Contenido
@onready var _titulo_switches: Button = $Paneles/PanelSwitches/Margen/Contenido/Titulo
@onready var _demora_salida: SpinBox = %DemoraSalida
@onready var _espera_estaciones: SpinBox = %EsperaEstaciones
@onready var _nivel: Node = get_tree().current_scene
var _botones: Dictionary = {}
var _tren_seleccionado: Tren
var _botones_switch: Dictionary = {}
var _titulos_switch: Dictionary = {}
var _firma_switches: String = ""
var _paneles_abiertos: Dictionary = {"trenes": false, "pruebas": false, "switches": false}
const ALTURA_PANEL_CERRADO := 28.0
const SEPARACION_PANELES := 6.0
const ALTURAS_PANELES := {"trenes": 145.0, "pruebas": 245.0, "switches": 230.0}


func _ready() -> void:
	_velocidad_prueba.value_changed.connect(_cambiar_parametros_prueba)
	_aceleracion_prueba.value_changed.connect(_cambiar_parametros_prueba)
	_frenado_prueba.value_changed.connect(_cambiar_parametros_prueba)
	_restablecer.pressed.connect(_restablecer_parametros_prueba)
	_agregar_tren.pressed.connect(_agregar_formacion)
	_demora_salida.value_changed.connect(_cambiar_tiempos_servicio)
	_espera_estaciones.value_changed.connect(_cambiar_tiempos_servicio)
	_titulo_trenes.pressed.connect(_alternar_panel.bind("trenes"))
	_titulo_pruebas.pressed.connect(_alternar_panel.bind("pruebas"))
	_titulo_switches.pressed.connect(_alternar_panel.bind("switches"))
	_mostrar_mas_switches.pressed.connect(_mostrar_siguiente_bloque_switches)
	if _nivel != null and _nivel.has_signal("tren_agregado"):
		_nivel.connect("tren_agregado", _on_tren_agregado)
	_actualizar_panel_pruebas()
	_aplicar_estado_paneles()
	call_deferred("_construir_lista")


func _construir_lista() -> void:
	for hijo: Node in _lista.get_children():
		hijo.queue_free()
	_botones.clear()
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			var tren := nodo as Tren
			var boton := Button.new()
			boton.text = tren.name
			boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
			boton.add_theme_font_size_override("font_size", 8)
			boton.tooltip_text = "Seleccionar %s" % tren.name
			boton.pressed.connect(_seleccionar_tren.bind(tren))
			_lista.add_child(boton)
			_botones[tren] = boton
			var al_seleccionar: Callable = _marcar_seleccion.bind(tren)
			if not tren.seleccionado.is_connected(al_seleccionar):
				tren.seleccionado.connect(al_seleccionar)
			if not tren.eliminado.is_connected(_construir_lista):
				tren.eliminado.connect(_construir_lista)
	_actualizar_estado_agregar()


func _seleccionar_tren(tren: Tren) -> void:
	if is_instance_valid(tren):
		tren.seleccionado.emit()


func _marcar_seleccion(tren: Tren) -> void:
	if _tren_seleccionado != null and is_instance_valid(_tren_seleccionado) and _tren_seleccionado != tren:
		_tren_seleccionado.activar_opciones_switch(false)
	_tren_seleccionado = tren
	if tren != null and is_instance_valid(tren):
		tren.activar_opciones_switch(bool(_paneles_abiertos.get("switches", false)))
	for candidato: Tren in _botones.keys():
		var boton := _botones[candidato] as Button
		if is_instance_valid(boton):
			boton.text = ("▶ " if candidato == tren else "") + candidato.name
	if bool(_paneles_abiertos.get("pruebas", false)):
		_actualizar_panel_pruebas()
	if tren != null and is_instance_valid(tren):
		if not tren.opciones_switch_cambiadas.is_connected(_actualizar_panel_switches):
			tren.opciones_switch_cambiadas.connect(_actualizar_panel_switches)
		if not tren.ruta_actualizada.is_connected(_on_ruta_actualizada):
			tren.ruta_actualizada.connect(_on_ruta_actualizada)


func _actualizar_panel_pruebas() -> void:
	var disponible: bool = _tren_seleccionado != null and is_instance_valid(_tren_seleccionado)
	_panel_pruebas.modulate.a = 1.0 if disponible else 0.55
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
	_tren_pruebas.text = _tren_seleccionado.name
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
		_estado_switches.text = "Sin switches antes de la próxima estación."
		_mostrar_mas_switches.visible = false
		return
	var firma_partes: Array[String] = []
	for seccion_firma: Dictionary in secciones:
		for opcion_firma: Variant in seccion_firma.get("opciones", []):
			firma_partes.append("%d:%s" % [int(seccion_firma.get("nodo_id", 0)), str((opcion_firma as Dictionary).get("segmento", ""))])
	var firma: String = "|".join(firma_partes)
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
		var titulo := Label.new()
		titulo.add_theme_font_size_override("font_size", 8)
		titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lista_switches.add_child(titulo)
		_titulos_switch[int(seccion.get("nodo_id", 0))] = titulo
		for opcion: Dictionary in seccion.get("opciones", []):
			var boton := Button.new()
			boton.alignment = HORIZONTAL_ALIGNMENT_LEFT
			boton.add_theme_font_size_override("font_size", 8)
			boton.pressed.connect(_seleccionar_opcion_switch.bind(int(seccion.get("nodo_id", 0)), str(opcion.get("segmento", ""))))
			_lista_switches.add_child(boton)
			_botones_switch["%d:%s" % [int(seccion.get("nodo_id", 0)), str(opcion.get("segmento", ""))]] = boton


func _actualizar_controles_switches(secciones: Array[Dictionary]) -> void:
	for seccion: Dictionary in secciones:
		var nodo_id: int = int(seccion.get("nodo_id", 0))
		var titulo: Label = _titulos_switch.get(nodo_id) as Label
		if titulo != null:
			titulo.text = "Aguja %d · %.0f m · vía actual %s" % [nodo_id, float(seccion.get("distancia_m", 0.0)), str(seccion.get("segmento_elegido", ""))]
		for opcion: Dictionary in seccion.get("opciones", []):
			var boton: Button = _botones_switch.get("%d:%s" % [nodo_id, str(opcion.get("segmento", ""))]) as Button
			if boton == null:
				continue
			var estado: String = str(opcion.get("estado", "pendiente"))
			var reservada: bool = _tren_seleccionado.opcion_switch_reservada_por_otro(nodo_id, str(opcion.get("segmento", "")))
			var sufijo: String = " · calculando" if estado == "pendiente" else (" · reservada" if reservada else "")
			boton.text = ("✓ " if bool(opcion.get("seleccionada", false)) else "") + str(opcion.get("nombre", opcion.get("segmento", ""))) + sufijo
			boton.disabled = not bool(opcion.get("valida", false)) or reservada
			boton.tooltip_text = "Calculando la continuidad a Bosques" if estado == "pendiente" else ("Reservada por otra formación" if reservada else ("No permite completar el itinerario hasta Bosques" if boton.disabled else "Aplicar esta ruta al tren seleccionado"))


func _seleccionar_opcion_switch(nodo_id: int, segmento: String) -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	if not _tren_seleccionado.seleccionar_switch(nodo_id, segmento):
		_estado_switches.text = "No se aplicó: el desvío ya no conserva la ruta o la sección está ocupada."
		return
	_actualizar_panel_switches()


func _mostrar_siguiente_bloque_switches() -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	_tren_seleccionado.ampliar_opciones_switch(2)
	_actualizar_panel_switches()


func _cambiar_tiempos_servicio(_valor: float) -> void:
	if _tren_seleccionado == null or not is_instance_valid(_tren_seleccionado):
		return
	_tren_seleccionado.configurar_tiempos_servicio(_demora_salida.value, _espera_estaciones.value)


func _agregar_formacion() -> void:
	if _nivel == null or not _nivel.has_method("agregar_tren"):
		return
	var tren: Variant = _nivel.call("agregar_tren")
	if tren is Tren:
		_construir_lista()
		_marcar_seleccion(tren as Tren)
	elif _nivel.has_method("trenes_en_cola"):
		_actualizar_estado_agregar()


func _on_tren_agregado(_tren: Tren) -> void:
	_construir_lista()
	_actualizar_estado_agregar()


func _actualizar_estado_agregar() -> void:
	if _nivel != null and _nivel.has_method("trenes_en_cola"):
		var en_cola: int = int(_nivel.call("trenes_en_cola"))
		_agregar_tren.text = "En cola (%d)" % en_cola if en_cola > 0 else "+ Agregar tren en Constitución"


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
	elif id_panel == "pruebas" and bool(_paneles_abiertos[id_panel]):
		_actualizar_panel_pruebas()


func _aplicar_estado_paneles() -> void:
	_configurar_panel("trenes", _panel_trenes, _contenido_trenes, _titulo_trenes, "TRENES")
	_configurar_panel("pruebas", _panel_pruebas, _contenido_pruebas, _titulo_pruebas, "PRUEBAS DE MARCHA")
	_configurar_panel("switches", _panel_switches, _contenido_switches, _titulo_switches, "SWITCHES PRÓXIMOS")
	for id_panel: String in ["trenes", "pruebas", "switches"]:
		var panel: PanelContainer = {"trenes": _panel_trenes, "pruebas": _panel_pruebas, "switches": _panel_switches}[id_panel] as PanelContainer
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
