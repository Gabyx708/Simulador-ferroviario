extends Control
class_name PanelControlSimulacion
## Panel 1 de NavegacionPaneles: reloj, estado de flota, velocidad/pausa,
## generar eventos y feedback de impacto. Sólo lee/llama la API pública de
## SimulacionController, RelojSimulacion y GestorEventos -- nunca Tren
## directo, a propósito (ver docs/instrucciones.md).
##
## Construido por código, mismo patrón que navegacion_paneles.gd y que ya
## usa hud.gd para el panel de switches.
##
## Objetivo del proyecto a tener presente: comparar el impacto de distintos
## eventos. Por eso el feedback muestra trenes afectados + retraso total de
## cada uno, no sólo que "pasó algo".

const COLOR_TEXTO: Color = Color(0.82, 0.84, 0.90, 1.0)
const COLOR_TEXTO_SUAVE: Color = Color(0.60, 0.63, 0.70, 1.0)
const COLOR_ACENTO: Color = Color(1.0, 0.756863, 0.278431, 1.0)
const COLOR_OK: Color = Color(0.45, 0.85, 0.55, 1.0)
const COLOR_ERROR: Color = Color(0.9, 0.35, 0.35, 1.0)
const COLOR_FILA_FONDO: Color = Color(0.14, 0.145, 0.18, 0.85)
const INTERVALO_REFRESCO_S: float = 0.5

var _controlador: SimulacionController
var _reloj: RelojSimulacion
var _gestor: GestorEventos

var _etiqueta_fecha: Label
var _etiqueta_flota: Label
var _etiqueta_demora_promedio: Label
var _boton_pausa: Button
var _slider_velocidad: HSlider
var _etiqueta_velocidad: Label
var _opcion_tipo: OptionButton
var _opcion_objetivo: OptionButton
var _spin_duracion: SpinBox
var _etiqueta_duracion: Label
var _boton_disparar: Button
var _etiqueta_mensaje: Label
var _lista_feedback: VBoxContainer

var _tiempo_desde_refresco: float = 0.0


## `get_tree().current_scene` puede no estar asignado todavía cuando este
## panel entra al árbol (mismo riesgo documentado en hud.gd). En vez de
## depender de eso, sube por los ancestros hasta encontrar al que tiene
## `SimulacionController` como hijo -- funciona en el juego real y en los
## tests headless, que nunca pasan por `change_scene_to_*`.
func _resolver_nivel() -> Node:
	var candidato: Node = get_tree().current_scene
	if candidato != null and candidato.get_node_or_null("SimulacionController") != null:
		return candidato
	var ancestro: Node = get_parent()
	while ancestro != null:
		if ancestro.get_node_or_null("SimulacionController") != null:
			return ancestro
		ancestro = ancestro.get_parent()
	return null


func _ready() -> void:
	custom_minimum_size = Vector2(0, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var nivel: Node = _resolver_nivel()
	if nivel != null:
		_controlador = nivel.get_node_or_null("SimulacionController") as SimulacionController
		_reloj = nivel.get_node_or_null("RelojSimulacion") as RelojSimulacion
		_gestor = nivel.get_node_or_null("GestorEventos") as GestorEventos

	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 10)
	raiz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(raiz)

	_construir_encabezado(raiz)
	raiz.add_child(HSeparator.new())
	_construir_flota(raiz)
	raiz.add_child(HSeparator.new())
	_construir_velocidad(raiz)
	raiz.add_child(HSeparator.new())
	_construir_formulario_evento(raiz)
	raiz.add_child(HSeparator.new())
	_construir_feedback(raiz)

	if _controlador != null:
		_controlador.velocidad_simulacion_cambiada.connect(func(_f: float) -> void: _actualizar_velocidad())
	if _gestor != null:
		_gestor.evento_disparado.connect(func(_d: Dictionary) -> void: _actualizar_feedback())
		_gestor.evento_finalizado.connect(func(_d: Dictionary) -> void: _actualizar_feedback())

	_actualizar_todo()


func _process(delta: float) -> void:
	_tiempo_desde_refresco += delta
	if _tiempo_desde_refresco < INTERVALO_REFRESCO_S:
		return
	_tiempo_desde_refresco = 0.0
	_actualizar_todo()


func _actualizar_todo() -> void:
	_actualizar_fecha()
	_actualizar_flota()
	_actualizar_velocidad()
	_actualizar_objetivos()
	_actualizar_feedback()


## --- Encabezado: fecha/hora ---

func _construir_encabezado(padre: VBoxContainer) -> void:
	_etiqueta_fecha = Label.new()
	_etiqueta_fecha.add_theme_font_size_override("font_size", 20)
	_etiqueta_fecha.add_theme_color_override("font_color", COLOR_ACENTO)
	_etiqueta_fecha.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	padre.add_child(_etiqueta_fecha)


func _actualizar_fecha() -> void:
	if _etiqueta_fecha == null:
		return
	if _reloj == null:
		_etiqueta_fecha.text = "—"
		return
	var fecha: Dictionary = _reloj.fecha_hora_simulada()
	_etiqueta_fecha.text = "Día %d · %02d:%02d" % [int(fecha.get("dia", 1)), int(fecha.get("hora", 0)), int(fecha.get("minuto", 0))]


## --- Estado de flota + demora promedio ---

func _construir_flota(padre: VBoxContainer) -> void:
	var titulo := _crear_titulo_seccion("FLOTA")
	padre.add_child(titulo)
	_etiqueta_flota = Label.new()
	_etiqueta_flota.add_theme_font_size_override("font_size", 12)
	_etiqueta_flota.add_theme_color_override("font_color", COLOR_TEXTO)
	_etiqueta_flota.autowrap_mode = TextServer.AUTOWRAP_WORD
	padre.add_child(_etiqueta_flota)
	_etiqueta_demora_promedio = Label.new()
	_etiqueta_demora_promedio.add_theme_font_size_override("font_size", 12)
	_etiqueta_demora_promedio.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	padre.add_child(_etiqueta_demora_promedio)


func _actualizar_flota() -> void:
	if _etiqueta_flota == null or _controlador == null:
		return
	var trenes: Array[Dictionary] = _controlador.obtener_trenes()
	var a_tiempo: int = 0
	var retrasados: int = 0
	var detenidos_evento: int = 0
	var incompletos: int = 0
	var activos: int = 0
	var suma_retraso: float = 0.0
	var cantidad_con_retraso_medido: int = 0
	for tren: Dictionary in trenes:
		var estado: int = int(tren.get("estado", -1))
		if estado == Tren.EstadoOperacion.INCOMPLETO:
			incompletos += 1
			continue
		if estado == Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES:
			continue
		activos += 1
		var retraso: float = float(tren.get("retraso_s", 0.0))
		suma_retraso += retraso
		cantidad_con_retraso_medido += 1
		if estado == Tren.EstadoOperacion.DETENIDO_POR_EVENTO:
			detenidos_evento += 1
		elif retraso > 0.0:
			retrasados += 1
		else:
			a_tiempo += 1
	_etiqueta_flota.text = "Activos: %d  ·  A tiempo: %d  ·  Retrasados: %d  ·  Detenidos: %d  ·  Incompletos: %d" % [activos, a_tiempo, retrasados, detenidos_evento, incompletos]
	var promedio: float = (suma_retraso / cantidad_con_retraso_medido) if cantidad_con_retraso_medido > 0 else 0.0
	_etiqueta_demora_promedio.text = "Demora promedio de flota activa: %s" % _formatear_duracion(promedio)


## --- Velocidad global + pausa ---

func _construir_velocidad(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("VELOCIDAD DE SIMULACIÓN"))
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	padre.add_child(fila)

	_boton_pausa = Button.new()
	_boton_pausa.text = "⏸"
	_boton_pausa.custom_minimum_size = Vector2(36, 28)
	_boton_pausa.pressed.connect(_on_pausa_pressed)
	fila.add_child(_boton_pausa)

	_slider_velocidad = HSlider.new()
	_slider_velocidad.min_value = 0.0
	_slider_velocidad.max_value = 10.0
	_slider_velocidad.step = 0.5
	_slider_velocidad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_velocidad.value_changed.connect(_on_velocidad_cambiada)
	fila.add_child(_slider_velocidad)

	_etiqueta_velocidad = Label.new()
	_etiqueta_velocidad.custom_minimum_size = Vector2(68, 0)
	_etiqueta_velocidad.add_theme_color_override("font_color", COLOR_TEXTO)
	_etiqueta_velocidad.add_theme_font_size_override("font_size", 12)
	fila.add_child(_etiqueta_velocidad)


func _actualizar_velocidad() -> void:
	if _controlador == null or _slider_velocidad == null:
		return
	var factor: float = _controlador.obtener_velocidad_simulacion()
	_slider_velocidad.set_value_no_signal(clampf(factor, _slider_velocidad.min_value, _slider_velocidad.max_value))
	_etiqueta_velocidad.text = "Pausada" if is_zero_approx(factor) else "×%.1f" % factor
	_boton_pausa.text = "▶" if is_zero_approx(factor) else "⏸"


func _on_pausa_pressed() -> void:
	if _controlador == null:
		return
	if _controlador.esta_pausada():
		_controlador.reanudar_simulacion()
	else:
		_controlador.pausar_simulacion()
	_actualizar_velocidad()


func _on_velocidad_cambiada(valor: float) -> void:
	if _controlador == null:
		return
	if not _controlador.establecer_velocidad_simulacion(valor):
		_actualizar_velocidad()


## --- Formulario: generar evento ---

func _construir_formulario_evento(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("GENERAR EVENTO"))

	_opcion_tipo = OptionButton.new()
	_opcion_tipo.add_item("Falla eléctrica (tramo)", 0)
	_opcion_tipo.add_item("Piquete (estación)", 1)
	_opcion_tipo.add_item("Avería (tren)", 2)
	_opcion_tipo.item_selected.connect(func(_i: int) -> void: _actualizar_objetivos())
	padre.add_child(_opcion_tipo)

	_opcion_objetivo = OptionButton.new()
	padre.add_child(_opcion_objetivo)

	var fila_duracion := HBoxContainer.new()
	fila_duracion.add_theme_constant_override("separation", 8)
	padre.add_child(fila_duracion)
	_etiqueta_duracion = Label.new()
	_etiqueta_duracion.text = "Duración (s):"
	_etiqueta_duracion.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	_etiqueta_duracion.add_theme_font_size_override("font_size", 12)
	fila_duracion.add_child(_etiqueta_duracion)
	_spin_duracion = SpinBox.new()
	_spin_duracion.min_value = 5.0
	_spin_duracion.max_value = 600.0
	_spin_duracion.step = 5.0
	_spin_duracion.value = 120.0
	_spin_duracion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_duracion.add_child(_spin_duracion)

	_boton_disparar = Button.new()
	_boton_disparar.text = "Disparar evento"
	_boton_disparar.pressed.connect(_on_disparar_pressed)
	padre.add_child(_boton_disparar)

	_etiqueta_mensaje = Label.new()
	_etiqueta_mensaje.autowrap_mode = TextServer.AUTOWRAP_WORD
	_etiqueta_mensaje.add_theme_font_size_override("font_size", 11)
	padre.add_child(_etiqueta_mensaje)


## Repuebla el combo de objetivo según el tipo elegido: estaciones para los
## eventos de zona, trenes activos para la avería. Se llama al cambiar el
## tipo y en cada refresco periódico (la lista de trenes puede cambiar).
func _actualizar_objetivos() -> void:
	if _opcion_objetivo == null or _opcion_tipo == null or _controlador == null:
		return
	var tipo: int = _opcion_tipo.get_selected_id()
	var texto_previo: String = _opcion_objetivo.get_item_text(_opcion_objetivo.selected) if _opcion_objetivo.selected >= 0 else ""
	_opcion_objetivo.clear()
	_etiqueta_duracion.visible = tipo != 2
	_spin_duracion.visible = tipo != 2

	if tipo == 2:
		for tren: Dictionary in _controlador.obtener_trenes():
			var estado: int = int(tren.get("estado", -1))
			if estado in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.INCOMPLETO]:
				continue
			_opcion_objetivo.add_item(str(tren.get("nombre", "Tren %d" % int(tren.get("id", 0)))), int(tren.get("id", 0)))
	else:
		var i: int = 0
		for estacion: Dictionary in _controlador.obtener_estaciones():
			var nombre: String = str(estacion.get("nombre", ""))
			_opcion_objetivo.add_item(nombre, i)
			if nombre == texto_previo:
				_opcion_objetivo.select(_opcion_objetivo.item_count - 1)
			i += 1


func _on_disparar_pressed() -> void:
	if _gestor == null or _opcion_tipo == null or _opcion_objetivo.item_count == 0:
		_mostrar_mensaje("No hay objetivos disponibles todavía.", false)
		return
	var tipo: int = _opcion_tipo.get_selected_id()
	var indice: int = _opcion_objetivo.selected
	if indice < 0:
		_mostrar_mensaje("Elegí un objetivo.", false)
		return

	if tipo == 2:
		var id_tren: int = _opcion_objetivo.get_item_id(indice)
		var ok: bool = _gestor.disparar_desperfecto_mecanico(id_tren)
		_mostrar_mensaje("Avería aplicada." if ok else "No se pudo aplicar: el tren ya no está activo.", ok)
	else:
		var nombre: String = _opcion_objetivo.get_item_text(indice)
		var resultado: Dictionary
		if tipo == 0:
			resultado = _gestor.disparar_falla_electrica(nombre, _spin_duracion.value)
		else:
			resultado = _gestor.disparar_piquete(nombre, _spin_duracion.value)
		var ok2: bool = bool(resultado.get("ok", false))
		_mostrar_mensaje("Evento disparado." if ok2 else str(resultado.get("motivo", "Rechazado.")), ok2)
	_actualizar_feedback()
	_actualizar_objetivos()


func _mostrar_mensaje(texto: String, ok: bool) -> void:
	if _etiqueta_mensaje == null:
		return
	_etiqueta_mensaje.text = texto
	_etiqueta_mensaje.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_ERROR)


## --- Feedback: eventos activos + historial reciente, con impacto ---

func _construir_feedback(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("EVENTOS ACTIVOS Y RECIENTES"))
	_lista_feedback = VBoxContainer.new()
	_lista_feedback.add_theme_constant_override("separation", 4)
	padre.add_child(_lista_feedback)


func _actualizar_feedback() -> void:
	if _lista_feedback == null or _gestor == null:
		return
	# `free()` inmediato, no `queue_free()`: un borrado diferido deja la
	# generación vieja de filas coexistiendo con la nueva hasta el próximo
	# frame, así que una lectura inmediata después de refrescar (p.ej. tras
	# disparar un evento) podría encontrar una fila vieja con datos viejos.
	for hijo: Node in _lista_feedback.get_children():
		hijo.free()

	var historial: Array[Dictionary] = _gestor.obtener_historial()
	if historial.is_empty():
		var vacio := Label.new()
		vacio.text = "Sin eventos todavía."
		vacio.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
		vacio.add_theme_font_size_override("font_size", 11)
		_lista_feedback.add_child(vacio)
		return

	var ahora: float = _reloj.tiempo_simulado_s() if _reloj != null else 0.0
	var maximo_filas: int = 8
	for i: int in mini(maximo_filas, historial.size()):
		_lista_feedback.add_child(_crear_fila_evento(historial[i], ahora))


func _crear_fila_evento(evento: Dictionary, ahora: float) -> Control:
	var tipo: int = int(evento.get("tipo", -1))
	var color: Color = Color.GRAY
	match tipo:
		GestorEventos.TipoEvento.FALLA_ELECTRICA:
			color = GestorEventos.COLOR_FALLA_ELECTRICA
		GestorEventos.TipoEvento.PIQUETE:
			color = GestorEventos.COLOR_PIQUETE
		GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			color = GestorEventos.COLOR_DESPERFECTO_MECANICO

	var fila := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FILA_FONDO
	estilo.border_width_left = 3
	estilo.border_color = color
	estilo.content_margin_left = 8
	estilo.content_margin_right = 6
	estilo.content_margin_top = 4
	estilo.content_margin_bottom = 4
	estilo.corner_radius_top_right = 3
	estilo.corner_radius_bottom_right = 3
	fila.add_theme_stylebox_override("panel", estilo)

	var objetivo: String = str(evento.get("clave", ""))
	if tipo == GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
		objetivo = "Tren %d" % int(evento.get("id_tren", -1))

	var trenes_afectados: Dictionary = evento.get("trenes_afectados", {})
	var retraso_total: float = float(evento.get("retraso_total_s", 0.0))
	var activo: bool = bool(evento.get("activo", false))
	var estado_txt: String = ""
	if activo:
		var restante: float = float(evento.get("fin_s", 0.0)) - ahora
		estado_txt = " · %ds restantes" % maxi(0, roundi(restante))
	elif tipo == GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
		estado_txt = " · definitivo"
	else:
		estado_txt = " · finalizado"

	var etiqueta := Label.new()
	etiqueta.text = "%s · %s · %d tren%s · +%s%s" % [
		GestorEventos.nombre_tipo(tipo), objetivo, trenes_afectados.size(),
		"" if trenes_afectados.size() == 1 else "es",
		_formatear_duracion(retraso_total), estado_txt,
	]
	etiqueta.add_theme_color_override("font_color", COLOR_TEXTO)
	etiqueta.add_theme_font_size_override("font_size", 11)
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD
	fila.add_child(etiqueta)
	return fila


## --- Utilidades ---

func _crear_titulo_seccion(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 11)
	etiqueta.add_theme_color_override("font_color", COLOR_ACENTO)
	return etiqueta


func _formatear_duracion(segundos: float) -> String:
	if segundos < 60.0:
		return "%ds" % roundi(segundos)
	return "%d min" % roundi(segundos / 60.0)
