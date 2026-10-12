extends VBoxContainer
class_name PanelMetricas
## Panel 2 de NavegacionPaneles: métricas de sólo lectura para comparar el
## impacto de los eventos entre sí (objetivo del proyecto) y ver de un
## vistazo cómo está la flota. Los listados despliegan información de
## SimulacionController, RelojSimulacion, EstadisticasRetraso y GestorEventos.
##
## Layout en una sola columna de ancho completo (KPIs arriba, gráficas,
## tablas abajo) en vez de 2 columnas lado a lado: con nombres de estación
## largos ("Darío Santillán y Maximiliano Kosteki") y el modal en 1280×720,
## dos columnas angostas obligaban a cortar texto. El modal ya scrollea
## vertical, así que una columna ancha es más robusta.
##
## Pensado para que Persona 3 lo extienda: `_actualizar()` es el único punto
## de refresco, `_calcular_kpis()` es una función pura (testeable sin
## simulación real). Los selectores conservan la estación o tren elegido al
## refrescar; la tabla de llegadas corresponde únicamente a esa formación.
## El historial del gráfico de evolución se conserva en un buffer acotado.

const COLOR_TEXTO: Color = Color(0.82, 0.84, 0.90, 1.0)
const COLOR_TEXTO_SUAVE: Color = Color(0.60, 0.63, 0.70, 1.0)
const COLOR_ACENTO: Color = Color(1.0, 0.756863, 0.278431, 1.0)
const COLOR_FILA_FONDO: Color = Color(0.14, 0.145, 0.18, 0.85)
const COLOR_OK: Color = Color(0.45, 0.85, 0.55, 1.0)
const COLOR_ADVERTENCIA: Color = Color(0.95, 0.80, 0.15, 1.0)
const COLOR_ERROR: Color = Color(0.9, 0.35, 0.35, 1.0)
const INTERVALO_REFRESCO_S: float = 0.5
const TAMANO_FUENTE_DETALLE: int = 14
## Techo del buffer de muestras para el gráfico de evolución -- ventana
## móvil de los últimos N refrescos (a 0.5s cada uno, 600 = 5 minutos
## reales de muestreo; a velocidad de simulación alta cubre mucho más
## tiempo simulado todavía). Se descartan las muestras más viejas.
const MAX_MUESTRAS_EVOLUCION: int = 600

var _controlador: SimulacionController
var _reloj: RelojSimulacion
var _estadisticas: EstadisticasRetraso
var _gestor: GestorEventos

var _tarjetas_kpi: Dictionary = {}  ## clave -> Label (valor dentro de la tarjeta)
var _tabla_eventos: GridContainer
var _selector_estacion: OptionButton
var _resumen_estacion: Label
var _selector_tren: OptionButton
var _detalle_tren: Dictionary = {}
var _grafico_barras: GraficoBarras
var _grafico_linea: GraficoLinea

var _tiempo_desde_refresco: float = 0.0
var _muestras_evolucion: Array[Vector2] = []
var _marcas_eventos: Array[Dictionary] = []  ## [{tiempo_s, color}]


## Mismo riesgo que en panel_control_simulacion.gd: `current_scene` puede no
## estar asignado todavía cuando este panel entra al árbol. Se resuelve
## subiendo por los ancestros hasta encontrar al que tiene SimulacionController.
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
		_estadisticas = nivel.get_node_or_null("EstadisticasRetraso") as EstadisticasRetraso
		_gestor = nivel.get_node_or_null("GestorEventos") as GestorEventos

	var raiz: VBoxContainer = self
	raiz.add_theme_constant_override("separation", 14)
	raiz.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_construir_kpis(raiz)
	raiz.add_child(HSeparator.new())
	_construir_datos_globales(raiz)
	raiz.add_child(HSeparator.new())
	_construir_espera_estacion(raiz)
	raiz.add_child(HSeparator.new())
	_construir_horarios(raiz)
	raiz.add_child(HSeparator.new())
	_construir_comparacion_eventos(raiz)
	raiz.add_child(HSeparator.new())
	_construir_evolucion(raiz)
	raiz.add_child(HSeparator.new())
	_construir_tabla_eventos(raiz)

	if _gestor != null:
		_gestor.evento_disparado.connect(_on_evento_disparado)
		_gestor.evento_finalizado.connect(func(_d: Dictionary) -> void: _actualizar())

	_actualizar()


func _process(delta: float) -> void:
	_tiempo_desde_refresco += delta
	if _tiempo_desde_refresco < INTERVALO_REFRESCO_S:
		return
	_tiempo_desde_refresco = 0.0
	_actualizar()


func _on_evento_disparado(evento: Dictionary) -> void:
	var color: Color = _color_tipo_evento(int(evento.get("tipo", -1)))
	_marcas_eventos.append({"tiempo_s": _reloj.tiempo_simulado_s() if _reloj != null else 0.0, "color": color})
	_actualizar()


func _actualizar() -> void:
	if _controlador == null:
		return
	var trenes: Array[Dictionary] = _controlador.obtener_trenes()
	var kpis: Dictionary = _calcular_kpis(trenes)
	_actualizar_kpis(kpis)
	_registrar_muestra_evolucion(kpis)
	_actualizar_comparacion_eventos()
	_actualizar_tabla_eventos()
	_actualizar_datos_globales()
	_actualizar_espera_estacion()
	_actualizar_horarios()


## --- Cálculo puro (testeable sin simulación real: toma una lista de
## snapshots con la misma forma que SimulacionController.obtener_trenes()) ---
##
## "Pasajeros afectados" incluye a los trenes DETENIDO_POR_EVENTO y
## ESPERANDO_RESERVA aunque su retraso_s todavía sea 0 -- EstadisticasRetraso
## mide llegada a llegada, así que un tren recién detenido o bloqueado por la
## reserva de otro tren (p.ej. uno frenado por un evento más adelante) recién
## actualiza retraso_s cuando llega a destino, pero sus pasajeros YA están
## sufriendo el impacto en este momento. El detalle por tren conserva el
## retraso_s medido por eventos separado de la demora respecto del horario.
static func _calcular_kpis(trenes: Array[Dictionary]) -> Dictionary:
	var a_tiempo: int = 0
	var retrasados: int = 0
	var detenidos: int = 0
	var incompletos: int = 0
	var activos: int = 0
	var suma_retraso: float = 0.0
	var cantidad_con_retraso_medido: int = 0
	var suma_retraso_demorados: float = 0.0
	var demora_maxima_s: float = 0.0
	var id_tren_demora_maxima: int = -1
	var pasajeros_totales: int = 0
	var pasajeros_afectados: int = 0
	for tren: Dictionary in trenes:
		var estado: int = int(tren.get("estado", -1))
		if estado == Tren.EstadoOperacion.INCOMPLETO:
			incompletos += 1
			continue
		if estado in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA]:
			continue
		activos += 1
		var retraso: float = float(tren.get("retraso_s", 0.0))
		var pasajeros: int = int(tren.get("pasajeros", 0))
		suma_retraso += retraso
		cantidad_con_retraso_medido += 1
		pasajeros_totales += pasajeros
		if retraso > demora_maxima_s:
			demora_maxima_s = retraso
			id_tren_demora_maxima = int(tren.get("id", -1))
		var bloqueado: bool = estado in [Tren.EstadoOperacion.DETENIDO_POR_EVENTO, Tren.EstadoOperacion.ESPERANDO_RESERVA]
		if bloqueado:
			detenidos += 1
			pasajeros_afectados += pasajeros
		elif retraso > 0.0:
			retrasados += 1
			pasajeros_afectados += pasajeros
			suma_retraso_demorados += retraso
		else:
			a_tiempo += 1
	var demora_promedio: float = (suma_retraso / cantidad_con_retraso_medido) if cantidad_con_retraso_medido > 0 else 0.0
	var retraso_promedio_demorados: float = (suma_retraso_demorados / retrasados) if retrasados > 0 else 0.0
	var puntualidad_pct: float = (100.0 * a_tiempo / activos) if activos > 0 else 100.0
	var pct_afectados: float = (100.0 * pasajeros_afectados / pasajeros_totales) if pasajeros_totales > 0 else 0.0
	return {
		"activos": activos, "a_tiempo": a_tiempo, "retrasados": retrasados,
		"detenidos": detenidos, "incompletos": incompletos,
		"demora_promedio_s": demora_promedio,
		"retraso_promedio_demorados_s": retraso_promedio_demorados,
		"puntualidad_pct": puntualidad_pct,
		"demora_maxima_s": demora_maxima_s, "id_tren_demora_maxima": id_tren_demora_maxima,
		"pasajeros_totales": pasajeros_totales, "pasajeros_afectados": pasajeros_afectados,
		"pct_pasajeros_afectados": pct_afectados,
	}


## --- KPIs: tarjetas grandes arriba ---

func _construir_kpis(padre: VBoxContainer) -> void:
	var fila1 := HBoxContainer.new()
	fila1.add_theme_constant_override("separation", 12)
	padre.add_child(fila1)
	_agregar_tarjeta_kpi(fila1, "puntualidad", "PUNTUALIDAD POR HORARIO", "Trenes en tiempo / servicios activos con horario. Se actualiza en cada llegada y puede recuperarse.")
	_agregar_tarjeta_kpi(fila1, "retraso_demorados", "RETRASO ACUMULADO PROMEDIO", "Promedio de retraso_s entre trenes con retraso acumulado medido. Conserva el impacto histórico de los eventos, aunque recuperen puntualidad.")
	_agregar_tarjeta_kpi(fila1, "demora_maxima", "DEMORA ACUMULADA MÁXIMA", "El mayor retraso_s acumulado entre servicios activos y el tren que lo tiene.")

	var fila2 := HBoxContainer.new()
	fila2.add_theme_constant_override("separation", 12)
	padre.add_child(fila2)
	_agregar_tarjeta_kpi(fila2, "incompletos", "INCOMPLETOS", "Trenes que quedaron con el servicio interrumpido (avería o ruta sin continuación) y no van a completar su recorrido.")
	_agregar_tarjeta_kpi(fila2, "pasajeros", "PASAJEROS AFECTADOS", "Pasajeros a bordo de trenes retrasados o detenidos (por evento o esperando vía), sobre el total de pasajeros en viaje ahora.")
	_agregar_tarjeta_kpi(fila2, "eventos", "EVENTOS OCURRIDOS", "Cantidad total de eventos disparados hasta ahora, desglosados por tipo (falla eléctrica · piquete · avería).")


func _agregar_tarjeta_kpi(fila: HBoxContainer, clave: String, titulo_texto: String, tooltip: String) -> void:
	var tarjeta := PanelContainer.new()
	tarjeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tarjeta.tooltip_text = tooltip
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FILA_FONDO
	estilo.set_corner_radius_all(8)
	estilo.content_margin_left = 12
	estilo.content_margin_right = 12
	estilo.content_margin_top = 8
	estilo.content_margin_bottom = 8
	tarjeta.add_theme_stylebox_override("panel", estilo)
	fila.add_child(tarjeta)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 2)
	tarjeta.add_child(columna)

	var titulo := Label.new()
	titulo.text = titulo_texto
	titulo.add_theme_font_size_override("font_size", 10)
	titulo.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	titulo.autowrap_mode = TextServer.AUTOWRAP_WORD
	columna.add_child(titulo)

	var valor := Label.new()
	valor.text = "—"
	valor.add_theme_font_size_override("font_size", 15)
	valor.add_theme_color_override("font_color", COLOR_ACENTO)
	valor.autowrap_mode = TextServer.AUTOWRAP_WORD
	columna.add_child(valor)
	_tarjetas_kpi[clave] = valor


func _actualizar_kpis(kpis: Dictionary) -> void:
	if not _tarjetas_kpi.has("puntualidad"):
		return
	(_tarjetas_kpi["puntualidad"] as Label).text = "%.0f%% (%d/%d)" % [
		float(kpis.get("puntualidad_pct", 100.0)), int(kpis.get("a_tiempo", 0)), int(kpis.get("activos", 0)),
	]
	var retrasados: int = int(kpis.get("retrasados", 0))
	(_tarjetas_kpi["retraso_demorados"] as Label).text = "%s (%d tren%s)" % [
		_formatear_duracion(float(kpis.get("retraso_promedio_demorados_s", 0.0))), retrasados, "" if retrasados == 1 else "es",
	] if retrasados > 0 else "— (0 demorados)"
	var demora_maxima: float = float(kpis.get("demora_maxima_s", 0.0))
	var id_demora_maxima: int = int(kpis.get("id_tren_demora_maxima", -1))
	(_tarjetas_kpi["demora_maxima"] as Label).text = "%s (Tren %d)" % [_formatear_duracion(demora_maxima), id_demora_maxima] if demora_maxima > 0.0 else "—"
	(_tarjetas_kpi["incompletos"] as Label).text = str(int(kpis.get("incompletos", 0)))

	var pasajeros_afectados: int = int(kpis.get("pasajeros_afectados", 0))
	var pasajeros_totales: int = int(kpis.get("pasajeros_totales", 0))
	(_tarjetas_kpi["pasajeros"] as Label).text = "%d de %d (%.0f%%)" % [pasajeros_afectados, pasajeros_totales, float(kpis.get("pct_pasajeros_afectados", 0.0))]
	if _gestor != null:
		var historial: Array[Dictionary] = _gestor.obtener_historial()
		var por_tipo: Dictionary = {}
		for evento: Dictionary in historial:
			var tipo: int = int(evento.get("tipo", -1))
			por_tipo[tipo] = int(por_tipo.get(tipo, 0)) + 1
		(_tarjetas_kpi["eventos"] as Label).text = "%d (%d · %d · %d)" % [
			historial.size(),
			int(por_tipo.get(GestorEventos.TipoEvento.FALLA_ELECTRICA, 0)),
			int(por_tipo.get(GestorEventos.TipoEvento.PIQUETE, 0)),
			int(por_tipo.get(GestorEventos.TipoEvento.DESPERFECTO_MECANICO, 0)),
		]


## Datos globales de servicio; conserva las métricas históricas de eventos.
func _construir_datos_globales(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("DATOS GLOBALES DEL RECORRIDO"))
	var fila: HBoxContainer = HBoxContainer.new()
	fila.add_theme_constant_override("separation", 12)
	padre.add_child(fila)
	_agregar_tarjeta_kpi(fila, "transportados", "PASAJEROS TRANSPORTADOS", "Total de embarques. En viaje: pasajeros a bordo. Completados: viajes de pasajeros que ya descendieron. Interrumpidos: pasajeros en trenes incompletos.")
	_agregar_tarjeta_kpi(fila, "finalizados", "RECORRIDOS FINALIZADOS", "Recorridos completos: salir de una terminal, llegar a la otra y regresar a la terminal de origen.")
	_agregar_tarjeta_kpi(fila, "simultaneos", "TRENES EN SIMULTÁNEO", "Servicios activos, incluidos los detenidos en estación o por evento. Excluye finalizados, incompletos y eliminados. Pico histórico de trenes, no de pasajeros.")
	var fila2: HBoxContainer = HBoxContainer.new()
	fila2.add_theme_constant_override("separation", 12)
	padre.add_child(fila2)
	_agregar_tarjeta_kpi(fila2, "incompletos_evento", "INCOMPLETOS POR EVENTO TERMINAL", "Los desperfectos definitivos se distinguen de las interrupciones por falta de ruta.")
	_agregar_tarjeta_kpi(fila2, "espera_global", "ESPERA GLOBAL DE PASAJEROS", "Promedio de la espera actual de todas las estaciones. Cada estación tiene el mismo peso; las que no tienen pasajeros en espera aportan cero.")
	_agregar_tarjeta_kpi(fila2, "tasa_demora", "TASA DE DEMORA POR HORARIO", "Trenes atrasados / servicios activos con horario. La demora promedio incluye los que están en tiempo con demora cero; se recalcula en cada llegada y puede disminuir.")


func _actualizar_datos_globales() -> void:
	var datos: Dictionary = _controlador.obtener_resumen_global()
	(_tarjetas_kpi["transportados"] as Label).text = "%d total\nEn viaje: %d\nCompletados: %d\nInterrumpidos: %d" % [
		int(datos["pasajeros_transportados"]), int(datos["pasajeros_en_viaje"]),
		int(datos["pasajeros_recorrido_completado"]), int(datos["pasajeros_interrumpidos"]),
	]
	(_tarjetas_kpi["finalizados"] as Label).text = str(int(datos["trenes_finalizados"]))
	(_tarjetas_kpi["simultaneos"] as Label).text = "%d actuales\nPico: %d" % [int(datos["trenes_activos"]), int(datos["concurrencia_maxima"])]
	var por_evento: int = int(datos["trenes_incompletos_evento"])
	(_tarjetas_kpi["incompletos_evento"] as Label).text = "%d por evento\n%d por otras causas" % [por_evento, int(datos["trenes_incompletos"]) - por_evento]
	(_tarjetas_kpi["incompletos"] as Label).text = str(int(datos["trenes_incompletos"]))
	(_tarjetas_kpi["espera_global"] as Label).text = "Tiempo de espera actual: %s" % _formatear_tiempo_exacto(float(datos["espera_promedio_actual_s"]))
	(_tarjetas_kpi["tasa_demora"] as Label).text = "%.1f%% (%d/%d)\nPromedio: %s" % [
		float(datos["tasa_demora_pct"]), int(datos["trenes_atrasados"]), int(datos["trenes_con_horario"]),
		_formatear_tiempo_exacto(float(datos["demora_promedio_s"])),
	]
	var con_horario: int = int(datos["trenes_con_horario"])
	if con_horario > 0:
		(_tarjetas_kpi["puntualidad"] as Label).text = "%.0f%% (%d/%d)" % [
			100.0 - float(datos["tasa_demora_pct"]), con_horario - int(datos["trenes_atrasados"]), con_horario,
		]


func _construir_espera_estacion(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("ESPERA DE PASAJEROS POR ESTACIÓN"))
	_selector_estacion = OptionButton.new()
	_selector_estacion.item_selected.connect(func(_indice: int) -> void: _actualizar_espera_estacion())
	padre.add_child(_selector_estacion)
	_resumen_estacion = _crear_celda("", TAMANO_FUENTE_DETALLE)
	_resumen_estacion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	padre.add_child(_resumen_estacion)


func _actualizar_espera_estacion() -> void:
	var estaciones: Array[Dictionary] = _controlador.obtener_estaciones()
	var opciones: Array[Dictionary] = []
	for estacion: Dictionary in estaciones:
		opciones.append({"id": str(estacion["id"]), "nombre": str(estacion["nombre"])})
	_sincronizar_selector(_selector_estacion, opciones, "Sin estaciones")
	if estaciones.is_empty():
		_resumen_estacion.text = "No hay estaciones registradas."
		return
	var id: String = str(_selector_estacion.get_item_metadata(_selector_estacion.selected))
	for estacion: Dictionary in estaciones:
		if str(estacion["id"]) != id:
			continue
		var muestra: int = int(estacion.get("pasajeros_con_espera", 0))
		_resumen_estacion.text = "Tiempo de espera actual: %s\nPasajeros en espera: %d\nEspera promedio hasta abordar: %s" % [
			_formatear_tiempo_exacto(float(estacion.get("espera_promedio_actual_s", 0.0))),
			int(estacion["pasajeros_esperando"]),
			_formatear_tiempo_exacto(float(estacion.get("espera_promedio_s", 0.0))) if muestra > 0 else "Sin embarques",
		]
		break


const COLUMNAS_HORARIOS: Array[String] = ["Estación", "Destino", "Llegada prevista", "Llegada real", "Puntualidad"]


func _construir_horarios(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("HORARIO PREVISTO Y LLEGADAS POR TREN"))
	_selector_tren = OptionButton.new()
	_selector_tren.item_selected.connect(func(_indice: int) -> void: _actualizar_horarios())
	padre.add_child(_selector_tren)
	_detalle_tren = _construir_detalle_tren(padre)


func _actualizar_horarios() -> void:
	var horarios: Array[Dictionary] = _controlador.obtener_horarios()
	var opciones: Array[Dictionary] = []
	for horario: Dictionary in horarios:
		var id_tren: int = int(horario["id_tren"])
		opciones.append({"id": id_tren, "nombre": "Tren %d" % id_tren})
	_sincronizar_selector(_selector_tren, opciones, "Sin trenes")
	if horarios.is_empty():
		(_detalle_tren["resumen"] as Label).text = "No hay trenes registrados."
		(_detalle_tren["referencia"] as Label).hide()
		(_detalle_tren["scroll"] as ScrollContainer).hide()
		_vaciar_filas(_detalle_tren["tabla"] as GridContainer, COLUMNAS_HORARIOS.size())
		return
	var id: int = int(_selector_tren.get_item_metadata(_selector_tren.selected))
	for horario: Dictionary in horarios:
		if int(horario["id_tren"]) != id:
			continue
		var datos: Dictionary = horario.duplicate()
		var actual: Dictionary = _controlador.obtener_tren(id)
		if not actual.is_empty():
			datos.merge(actual, true)
		_actualizar_resumen_tren(_detalle_tren, datos)
		_actualizar_llegadas_tren(_detalle_tren, horario["visitas"] as Array)
		break


func _construir_detalle_tren(padre: VBoxContainer) -> Dictionary:
	var contenido: VBoxContainer = VBoxContainer.new()
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenido.add_theme_constant_override("separation", 10)
	padre.add_child(contenido)
	var resumen: Label = _crear_celda("", TAMANO_FUENTE_DETALLE)
	resumen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contenido.add_child(resumen)
	var referencia: Label = _crear_celda("Llegadas desde el inicio del recorrido (minutos:segundos).", TAMANO_FUENTE_DETALLE)
	referencia.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	referencia.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	contenido.add_child(referencia)
	var tabla: GridContainer = GridContainer.new()
	tabla.columns = COLUMNAS_HORARIOS.size()
	tabla.add_theme_constant_override("h_separation", 18)
	tabla.add_theme_constant_override("v_separation", 8)
	var scroll: ScrollContainer = _agregar_tabla_desplazable(contenido, tabla)
	for columna: String in COLUMNAS_HORARIOS:
		tabla.add_child(_crear_celda_encabezado(columna, TAMANO_FUENTE_DETALLE))
	return {"resumen": resumen, "referencia": referencia, "scroll": scroll, "tabla": tabla}


func _actualizar_resumen_tren(fila: Dictionary, datos: Dictionary) -> void:
	var estado: int = int(datos.get("estado", -1))
	var nombre_estado: String = str(NOMBRES_ESTADO.get(estado, "Desconocido"))
	if bool(datos.get("eliminado", false)):
		nombre_estado += " (eliminado)"
	var puntualidad: String = str(datos.get("puntualidad_nombre", "Sin horario"))
	if bool(datos.get("atrasado", false)):
		puntualidad += " · " + _formatear_tiempo_exacto(float(datos.get("retraso_horario_s", 0.0)))
	var resumen: Label = fila["resumen"] as Label
	resumen.text = "Estado: %s\nRecorrido: %s\nPróxima estación: %s\nPasajeros a bordo: %d / %d\nRetraso acumulado: %s\nHorario: %s" % [
		nombre_estado,
		"Constitución → Bosques" if str(datos.get("sentido", "ida")) == "ida" else "Bosques → Constitución",
		str(datos.get("estacion_proxima", "—")),
		int(datos.get("pasajeros", 0)), int(datos.get("capacidad", 0)),
		_formatear_tiempo_exacto(float(datos.get("retraso_s", 0.0))), puntualidad,
	]
	var con_horario: bool = bool(datos.get("horario_disponible", false))
	if con_horario:
		resumen.text += "\nTiempo total previsto: %s\nTiempo transcurrido: %s" % [
			_formatear_tiempo_exacto(float(datos.get("tiempo_previsto_total_s", 0.0))),
			_formatear_tiempo_exacto(float(datos.get("tiempo_recorrido_s", 0.0))),
		]
	(fila["referencia"] as Label).visible = con_horario
	(fila["scroll"] as ScrollContainer).visible = con_horario


func _actualizar_llegadas_tren(fila: Dictionary, visitas: Array) -> void:
	var tabla: GridContainer = fila["tabla"] as GridContainer
	_vaciar_filas(tabla, COLUMNAS_HORARIOS.size())
	for visita: Dictionary in visitas:
		var real: float = float(visita["llegada_real_s"])
		var retraso: float = float(visita["retraso_s"])
		tabla.add_child(_crear_celda(str(visita["nombre"]), TAMANO_FUENTE_DETALLE))
		tabla.add_child(_crear_celda("Bosques" if str(visita["sentido"]) == "ida" else "Constitución", TAMANO_FUENTE_DETALLE))
		tabla.add_child(_crear_celda(_formatear_tiempo_exacto(float(visita["llegada_prevista_s"])), TAMANO_FUENTE_DETALLE))
		tabla.add_child(_crear_celda(_formatear_tiempo_exacto(real) if real >= 0.0 else "Pendiente", TAMANO_FUENTE_DETALLE))
		var atraso: bool = retraso > _controlador.tolerancia_horario_s
		var texto: String = "Pendiente" if real < 0.0 else ("Atrasado +%s" % _formatear_tiempo_exacto(retraso) if atraso else "En tiempo")
		var celda: Label = _crear_celda(texto, TAMANO_FUENTE_DETALLE)
		celda.add_theme_color_override("font_color", COLOR_ADVERTENCIA if atraso else COLOR_TEXTO_SUAVE)
		tabla.add_child(celda)


## Sólo modifica el menú si cambia la lista; los refrescos no cierran el popup.
func _sincronizar_selector(selector: OptionButton, opciones: Array[Dictionary], texto_vacio: String) -> void:
	var anterior: Variant = selector.get_item_metadata(selector.selected) if selector.selected >= 0 else null
	var cambio: bool = selector.item_count != opciones.size()
	if not cambio:
		for indice: int in opciones.size():
			if selector.get_item_metadata(indice) != opciones[indice]["id"] or selector.get_item_text(indice) != str(opciones[indice]["nombre"]):
				cambio = true
				break
	selector.disabled = opciones.is_empty()
	if opciones.is_empty():
		selector.clear()
		selector.text = texto_vacio
		return
	if not cambio:
		return
	selector.clear()
	var seleccionado: int = 0
	for indice: int in opciones.size():
		selector.add_item(str(opciones[indice]["nombre"]))
		selector.set_item_metadata(indice, opciones[indice]["id"])
		if opciones[indice]["id"] == anterior:
			seleccionado = indice
	selector.select(seleccionado)


static func _formatear_tiempo_exacto(segundos: float) -> String:
	var total: int = roundi(maxf(0.0, segundos))
	return "%d:%02d" % [int(total / 60), total % 60]


## --- Comparación de eventos: barras horizontales por tipo ---

func _construir_comparacion_eventos(padre: VBoxContainer) -> void:
	var titulo := _crear_titulo_seccion("COMPARACIÓN DE EVENTOS (pasajeros·minuto perdidos, por tipo)")
	titulo.tooltip_text = "Pasajeros·minuto perdidos = pasajeros a bordo × minutos de retraso que ese evento les generó. Para una avería: pasajeros a bordo × minutos estimados que les faltaban de viaje (estimación gruesa, no exacta). Trenes afectados y retraso total en segundos van como dato secundario junto a cada barra."
	padre.add_child(titulo)
	_grafico_barras = GraficoBarras.new()
	_grafico_barras.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padre.add_child(_grafico_barras)


func _actualizar_comparacion_eventos() -> void:
	if _grafico_barras == null or _gestor == null:
		return
	var por_tipo: Dictionary = {}  ## tipo -> {"pasajeros_minuto": float, "retraso": float, "trenes": Dictionary}
	for evento: Dictionary in _gestor.obtener_historial():
		var tipo: int = int(evento.get("tipo", -1))
		var entrada: Dictionary = por_tipo.get(tipo, {"pasajeros_minuto": 0.0, "retraso": 0.0, "trenes": {}})
		entrada["pasajeros_minuto"] = float(entrada["pasajeros_minuto"]) + float(evento.get("pasajeros_minuto_perdidos", 0.0))
		entrada["retraso"] = float(entrada["retraso"]) + float(evento.get("retraso_total_s", 0.0))
		for id_tren: int in (evento.get("trenes_afectados", {}) as Dictionary):
			(entrada["trenes"] as Dictionary)[id_tren] = true
		por_tipo[tipo] = entrada

	var datos: Array[Dictionary] = []
	for tipo: int in [GestorEventos.TipoEvento.FALLA_ELECTRICA, GestorEventos.TipoEvento.PIQUETE, GestorEventos.TipoEvento.DESPERFECTO_MECANICO]:
		var entrada: Dictionary = por_tipo.get(tipo, {"pasajeros_minuto": 0.0, "retraso": 0.0, "trenes": {}})
		datos.append({
			"label": GestorEventos.nombre_tipo(tipo),
			"valor": float(entrada["pasajeros_minuto"]),
			"color": _color_tipo_evento(tipo),
			"trenes": (entrada["trenes"] as Dictionary).size(),
			"retraso_total_s": float(entrada["retraso"]),
		})
	_grafico_barras.establecer_datos(datos)


## --- Evolución de la demora promedio en el tiempo simulado ---

func _construir_evolucion(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("EVOLUCIÓN DEL RETRASO ACUMULADO PROMEDIO (las líneas verticales marcan cada evento)"))
	_grafico_linea = GraficoLinea.new()
	_grafico_linea.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grafico_linea.custom_minimum_size = Vector2(0, 150)
	padre.add_child(_grafico_linea)


func _registrar_muestra_evolucion(kpis: Dictionary) -> void:
	if _reloj == null:
		return
	_muestras_evolucion.append(Vector2(_reloj.tiempo_simulado_s(), float(kpis.get("demora_promedio_s", 0.0))))
	while _muestras_evolucion.size() > MAX_MUESTRAS_EVOLUCION:
		_muestras_evolucion.pop_front()
	if _grafico_linea != null:
		_grafico_linea.establecer_datos(_muestras_evolucion, _marcas_eventos)


func _color_tipo_evento(tipo: int) -> Color:
	match tipo:
		GestorEventos.TipoEvento.FALLA_ELECTRICA:
			return GestorEventos.COLOR_FALLA_ELECTRICA
		GestorEventos.TipoEvento.PIQUETE:
			return GestorEventos.COLOR_PIQUETE
		GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			return GestorEventos.COLOR_DESPERFECTO_MECANICO
	return Color.GRAY


## --- Tabla por evento ---

const COLUMNAS_EVENTOS: Array[String] = ["Tipo", "Objetivo", "Hora simulada", "Duración", "Trenes afectados", "Retraso total", "Estado"]


func _construir_tabla_eventos(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("POR EVENTO"))
	_tabla_eventos = GridContainer.new()
	_tabla_eventos.columns = COLUMNAS_EVENTOS.size()
	_tabla_eventos.add_theme_constant_override("h_separation", 22)
	_tabla_eventos.add_theme_constant_override("v_separation", 6)
	_agregar_tabla_desplazable(padre, _tabla_eventos)
	for texto: String in COLUMNAS_EVENTOS:
		_tabla_eventos.add_child(_crear_celda_encabezado(texto))


func _actualizar_tabla_eventos() -> void:
	if _tabla_eventos == null or _gestor == null:
		return
	_vaciar_filas(_tabla_eventos, COLUMNAS_EVENTOS.size())
	var historial: Array[Dictionary] = _gestor.obtener_historial()
	if historial.is_empty():
		var vacio := _crear_celda("Sin eventos todavía.")
		vacio.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
		_tabla_eventos.add_child(vacio)
		for _i: int in range(COLUMNAS_EVENTOS.size() - 1):
			_tabla_eventos.add_child(_crear_celda(""))
		return
	for evento: Dictionary in historial:
		var tipo: int = int(evento.get("tipo", -1))
		var objetivo: String = str(evento.get("clave", ""))
		if tipo == GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			objetivo = "Tren %d" % int(evento.get("id_tren", -1))
		var trenes_afectados: Dictionary = evento.get("trenes_afectados", {})
		var retraso_total: float = float(evento.get("retraso_total_s", 0.0))
		var duracion_s: float = float(evento.get("duracion_s", 0.0))
		var activo: bool = bool(evento.get("activo", false))

		var celda_tipo := _crear_celda(GestorEventos.nombre_tipo(tipo))
		celda_tipo.add_theme_color_override("font_color", _color_tipo_evento(tipo))
		_tabla_eventos.add_child(celda_tipo)
		_tabla_eventos.add_child(_crear_celda(objetivo))
		_tabla_eventos.add_child(_crear_celda(_hora_simulada_en(float(evento.get("inicio_s", 0.0)))))
		_tabla_eventos.add_child(_crear_celda(_formatear_duracion(duracion_s) if duracion_s > 0.0 else "—"))
		_tabla_eventos.add_child(_crear_celda(str(trenes_afectados.size())))
		_tabla_eventos.add_child(_crear_celda(_formatear_duracion(retraso_total) if retraso_total > 0.0 else "—"))
		var texto_estado: String = "Definitivo" if tipo == GestorEventos.TipoEvento.DESPERFECTO_MECANICO else ("Activo" if activo else "Finalizado")
		var celda_estado := _crear_celda(texto_estado)
		celda_estado.add_theme_color_override("font_color", COLOR_OK if (activo and tipo != GestorEventos.TipoEvento.DESPERFECTO_MECANICO) else COLOR_TEXTO_SUAVE)
		_tabla_eventos.add_child(celda_estado)


## --- Utilidades ---

## `free()` inmediato, no `queue_free()`: esto se llama varias veces por
## refresco (una tabla, luego la otra) y un borrado diferido deja ambas
## generaciones de filas coexistiendo como hijos hasta el próximo frame,
## así que una lectura inmediata después de actualizar vería datos viejos.
func _vaciar_filas(tabla: GridContainer, columnas: int) -> void:
	var hijos: Array[Node] = tabla.get_children()
	for i: int in range(columnas, hijos.size()):
		hijos[i].free()


func _agregar_tabla_desplazable(padre: VBoxContainer, tabla: GridContainer) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	padre.add_child(scroll)
	scroll.add_child(tabla)
	return scroll


func _crear_titulo_seccion(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	etiqueta.add_theme_font_size_override("font_size", 11)
	etiqueta.add_theme_color_override("font_color", COLOR_ACENTO)
	return etiqueta


func _crear_celda_encabezado(texto: String, tamano_fuente: int = 10) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", tamano_fuente)
	etiqueta.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	return etiqueta


## Sin clip_text: el ancho de cada columna del GridContainer ya se adapta al
## contenido más ancho de esa columna, y este panel usa una sola columna de
## ancho completo (ver comentario de cabecera) para que eso nunca se quede
## sin espacio -- cortar texto estaba explícitamente prohibido.
func _crear_celda(texto: String, tamano_fuente: int = 11) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", tamano_fuente)
	etiqueta.add_theme_color_override("font_color", COLOR_TEXTO)
	return etiqueta


const NOMBRES_ESTADO: Dictionary = {
	0: "En terminal",  # EN_TERMINAL_INICIAL
	1: "En marcha",  # EN_MARCHA
	2: "En estación",  # DETENIDO_EN_ESTACION
	3: "Esperando vía",  # ESPERANDO_RESERVA
	4: "Detenido por evento",  # DETENIDO_POR_EVENTO
	5: "Finalizado",  # FINALIZADO_EN_BOSQUES
	6: "Incompleto",  # INCOMPLETO
	7: "Ida y vuelta finalizada",
}


static func _formatear_duracion(segundos: float) -> String:
	if segundos < 60.0:
		return "%ds" % roundi(segundos)
	return "%d min" % roundi(segundos / 60.0)


## Convierte un timestamp de tiempo_simulado_s() a "Día N · HH:MM" usando los
## mismos parámetros públicos que RelojSimulacion (hora_inicial,
## minutos_simulados_por_segundo) -- no hay un método público para convertir
## un instante arbitrario (sólo "ahora"), así que se replica el cálculo acá
## en vez de tocar RelojSimulacion para un caso de uso de sólo lectura.
func _hora_simulada_en(tiempo_s: float) -> String:
	if _reloj == null:
		return "—"
	var minutos_totales: int = int(_reloj.hora_inicial) * 60 + int(tiempo_s * _reloj.minutos_simulados_por_segundo / 60.0)
	var dia: int = 1 + int(floor(float(minutos_totales) / 1440.0))
	var hora: int = int(floor(float(minutos_totales) / 60.0)) % 24
	var minuto: int = ((minutos_totales % 60) + 60) % 60
	return "Día %d · %02d:%02d" % [dia, hora, minuto]


## --- Gráficos propios, sin addons (Control._draw) ---

## Barras horizontales: una por tipo de evento, largo proporcional al
## retraso total que generó ese tipo.
class GraficoBarras extends Control:
	var datos: Array[Dictionary] = []  ## [{label, valor, color, trenes, retraso_total_s}]
	const ALTURA_BARRA: float = 28.0
	const SEPARACION: float = 10.0
	const ANCHO_ETIQUETA: float = 140.0

	func establecer_datos(d: Array[Dictionary]) -> void:
		datos = d
		custom_minimum_size.y = maxf(1.0, float(d.size())) * (ALTURA_BARRA + SEPARACION)
		queue_redraw()

	func _draw() -> void:
		if datos.is_empty():
			return
		var fuente: Font = ThemeDB.fallback_font
		var max_valor: float = 1.0
		for d: Dictionary in datos:
			max_valor = maxf(max_valor, float(d.get("valor", 0.0)))
		var ancho_disponible: float = maxf(40.0, size.x - ANCHO_ETIQUETA - 190.0)
		var y: float = 0.0
		for d: Dictionary in datos:
			var etiqueta: String = str(d.get("label", ""))
			var valor: float = float(d.get("valor", 0.0))
			var color: Color = d.get("color", Color.GRAY) as Color
			var trenes: int = int(d.get("trenes", 0))
			var retraso_total_s: float = float(d.get("retraso_total_s", 0.0))
			draw_string(fuente, Vector2(0.0, y + ALTURA_BARRA * 0.62), etiqueta, HORIZONTAL_ALIGNMENT_LEFT, ANCHO_ETIQUETA - 6.0, 12, PanelMetricas.COLOR_TEXTO)
			draw_rect(Rect2(ANCHO_ETIQUETA, y + 4.0, ancho_disponible, ALTURA_BARRA - 8.0), Color(1, 1, 1, 0.06), true)
			var largo: float = (valor / max_valor) * ancho_disponible
			if largo > 0.5:
				draw_rect(Rect2(ANCHO_ETIQUETA, y + 4.0, largo, ALTURA_BARRA - 8.0), color, true)
			var texto_valor: String = "%.0f pax·min · %d tren%s · %s retraso" % [valor, trenes, "" if trenes == 1 else "es", PanelMetricas._formatear_duracion(retraso_total_s)]
			draw_string(fuente, Vector2(ANCHO_ETIQUETA + largo + 8.0, y + ALTURA_BARRA * 0.62), texto_valor, HORIZONTAL_ALIGNMENT_LEFT, 180.0, 11, PanelMetricas.COLOR_TEXTO_SUAVE)
			y += ALTURA_BARRA + SEPARACION


## Línea de la demora promedio a lo largo del tiempo simulado, con marcas
## verticales en el instante en que se disparó cada evento.
class GraficoLinea extends Control:
	var muestras: Array[Vector2] = []
	var marcas: Array[Dictionary] = []

	func establecer_datos(m: Array[Vector2], mk: Array[Dictionary]) -> void:
		muestras = m
		marcas = mk
		queue_redraw()

	func _draw() -> void:
		var fuente: Font = ThemeDB.fallback_font
		if muestras.size() < 2:
			draw_string(fuente, Vector2(4.0, size.y / 2.0), "Esperando datos de la simulación...", HORIZONTAL_ALIGNMENT_LEFT, size.x, 11, PanelMetricas.COLOR_TEXTO_SUAVE)
			return
		var t_min: float = muestras[0].x
		var t_max: float = muestras[-1].x
		var rango_t: float = maxf(1.0, t_max - t_min)
		var v_max: float = 1.0
		for m: Vector2 in muestras:
			v_max = maxf(v_max, m.y)
		var alto_util: float = size.y - 18.0

		for marca: Dictionary in marcas:
			var t: float = float(marca.get("tiempo_s", 0.0))
			if t < t_min or t > t_max:
				continue
			var x: float = ((t - t_min) / rango_t) * size.x
			draw_line(Vector2(x, 0.0), Vector2(x, alto_util), marca.get("color", Color.GRAY) as Color, 2.0)

		var puntos := PackedVector2Array()
		for m: Vector2 in muestras:
			var x: float = ((m.x - t_min) / rango_t) * size.x
			var y: float = alto_util - (m.y / v_max) * alto_util
			puntos.append(Vector2(x, y))
		if puntos.size() >= 2:
			draw_polyline(puntos, PanelMetricas.COLOR_ACENTO, 2.0, true)

		draw_string(fuente, Vector2(4.0, size.y - 4.0), "Pico de demora promedio en la ventana visible: %s" % PanelMetricas._formatear_duracion(v_max), HORIZONTAL_ALIGNMENT_LEFT, size.x, 10, PanelMetricas.COLOR_TEXTO_SUAVE)
