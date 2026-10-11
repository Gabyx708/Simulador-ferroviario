extends Control
class_name PanelMetricas
## Panel 2 de NavegacionPaneles: métricas de sólo lectura para comparar el
## impacto de los eventos entre sí (objetivo del proyecto). Dos tablas --
## por tren y por evento -- más una fila de totales arriba. Sin controles:
## sólo lee SimulacionController, EstadisticasRetraso y GestorEventos.
##
## Pensado para que Persona 3 lo extienda: `_actualizar()` es el único punto
## de refresco y cada tabla se reconstruye entera desde los datos públicos,
## así que agregar una columna o una fila nueva no requiere tocar estado
## acumulado en este script.

const COLOR_TEXTO: Color = Color(0.82, 0.84, 0.90, 1.0)
const COLOR_TEXTO_SUAVE: Color = Color(0.60, 0.63, 0.70, 1.0)
const COLOR_ACENTO: Color = Color(1.0, 0.756863, 0.278431, 1.0)
const COLOR_FILA_FONDO: Color = Color(0.14, 0.145, 0.18, 0.85)
const INTERVALO_REFRESCO_S: float = 0.5

var _controlador: SimulacionController
var _estadisticas: EstadisticasRetraso
var _gestor: GestorEventos

var _etiqueta_totales: Label
var _tabla_trenes: GridContainer
var _tabla_eventos: GridContainer

var _tiempo_desde_refresco: float = 0.0


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
		_estadisticas = nivel.get_node_or_null("EstadisticasRetraso") as EstadisticasRetraso
		_gestor = nivel.get_node_or_null("GestorEventos") as GestorEventos

	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 10)
	raiz.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(raiz)

	_construir_encabezado(raiz)
	raiz.add_child(HSeparator.new())
	_construir_tabla_trenes(raiz)
	raiz.add_child(HSeparator.new())
	_construir_tabla_eventos(raiz)

	_actualizar()


func _process(delta: float) -> void:
	_tiempo_desde_refresco += delta
	if _tiempo_desde_refresco < INTERVALO_REFRESCO_S:
		return
	_tiempo_desde_refresco = 0.0
	_actualizar()


func _actualizar() -> void:
	_actualizar_totales()
	_actualizar_tabla_trenes()
	_actualizar_tabla_eventos()


## --- Encabezado: totales ---

func _construir_encabezado(padre: VBoxContainer) -> void:
	var titulo := Label.new()
	titulo.text = "MÉTRICAS"
	titulo.add_theme_font_size_override("font_size", 14)
	titulo.add_theme_color_override("font_color", COLOR_ACENTO)
	padre.add_child(titulo)
	_etiqueta_totales = Label.new()
	_etiqueta_totales.add_theme_font_size_override("font_size", 12)
	_etiqueta_totales.add_theme_color_override("font_color", COLOR_TEXTO)
	_etiqueta_totales.autowrap_mode = TextServer.AUTOWRAP_WORD
	padre.add_child(_etiqueta_totales)


func _actualizar_totales() -> void:
	if _etiqueta_totales == null or _controlador == null:
		return
	var suma_retraso: float = 0.0
	var cantidad_con_retraso_medido: int = 0
	var incompletos: int = 0
	var pasajeros_totales: int = 0
	var pasajeros_demorados: int = 0
	for tren: Dictionary in _controlador.obtener_trenes():
		var estado: int = int(tren.get("estado", -1))
		if estado == Tren.EstadoOperacion.INCOMPLETO:
			incompletos += 1
			continue
		if estado == Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES:
			continue
		var retraso: float = float(tren.get("retraso_s", 0.0))
		var pasajeros: int = int(tren.get("pasajeros", 0))
		suma_retraso += retraso
		cantidad_con_retraso_medido += 1
		pasajeros_totales += pasajeros
		if retraso > 0.0:
			pasajeros_demorados += pasajeros
	var promedio: float = (suma_retraso / cantidad_con_retraso_medido) if cantidad_con_retraso_medido > 0 else 0.0
	_etiqueta_totales.text = "Demora promedio de flota activa: %s  ·  Pasajeros con demora: %d / %d  ·  Incompletos: %d" % [
		_formatear_duracion(promedio), pasajeros_demorados, pasajeros_totales, incompletos,
	]


## --- Tabla por tren ---

const COLUMNAS_TRENES: Array[String] = ["Tren", "Estado", "Próxima estación", "Velocidad", "Retraso", "Estaciones", "Pasajeros"]


func _construir_tabla_trenes(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("POR TREN"))
	_tabla_trenes = GridContainer.new()
	_tabla_trenes.columns = COLUMNAS_TRENES.size()
	_tabla_trenes.add_theme_constant_override("h_separation", 18)
	_tabla_trenes.add_theme_constant_override("v_separation", 4)
	padre.add_child(_tabla_trenes)
	for texto: String in COLUMNAS_TRENES:
		_tabla_trenes.add_child(_crear_celda_encabezado(texto))


func _actualizar_tabla_trenes() -> void:
	if _tabla_trenes == null or _controlador == null:
		return
	_vaciar_filas(_tabla_trenes, COLUMNAS_TRENES.size())
	for tren: Dictionary in _controlador.obtener_trenes():
		var id: int = int(tren.get("id", 0))
		var retraso: float = float(tren.get("retraso_s", 0.0))
		var estaciones: int = _estadisticas.obtener_estaciones_recorridas(id) if _estadisticas != null else 0
		var velocidad: float = float(tren.get("velocidad_kmh", 0.0))
		_tabla_trenes.add_child(_crear_celda(str(tren.get("nombre", "Tren %d" % id))))
		_tabla_trenes.add_child(_crear_celda(str(tren.get("estado_nombre", "—"))))
		_tabla_trenes.add_child(_crear_celda(str(tren.get("estacion_proxima", "—"))))
		_tabla_trenes.add_child(_crear_celda("%d km/h" % roundi(velocidad)))
		_tabla_trenes.add_child(_crear_celda(_formatear_duracion(retraso) if retraso > 0.0 else "—"))
		_tabla_trenes.add_child(_crear_celda(str(estaciones)))
		_tabla_trenes.add_child(_crear_celda(str(int(tren.get("pasajeros", 0)))))


## --- Tabla por evento ---

func _construir_tabla_eventos(padre: VBoxContainer) -> void:
	padre.add_child(_crear_titulo_seccion("POR EVENTO"))
	_tabla_eventos = GridContainer.new()
	_tabla_eventos.columns = 4
	_tabla_eventos.add_theme_constant_override("h_separation", 14)
	_tabla_eventos.add_theme_constant_override("v_separation", 3)
	padre.add_child(_tabla_eventos)
	for texto: String in ["Tipo", "Objetivo", "Trenes afectados", "Retraso total"]:
		_tabla_eventos.add_child(_crear_celda_encabezado(texto))


func _actualizar_tabla_eventos() -> void:
	if _tabla_eventos == null or _gestor == null:
		return
	_vaciar_filas(_tabla_eventos, 4)
	var historial: Array[Dictionary] = _gestor.obtener_historial()
	if historial.is_empty():
		var vacio := _crear_celda("Sin eventos todavía.")
		vacio.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
		_tabla_eventos.add_child(vacio)
		for _i: int in range(3):
			_tabla_eventos.add_child(_crear_celda(""))
		return
	for evento: Dictionary in historial:
		var tipo: int = int(evento.get("tipo", -1))
		var objetivo: String = str(evento.get("clave", ""))
		if tipo == GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			objetivo = "Tren %d" % int(evento.get("id_tren", -1))
		var trenes_afectados: Dictionary = evento.get("trenes_afectados", {})
		var retraso_total: float = float(evento.get("retraso_total_s", 0.0))
		_tabla_eventos.add_child(_crear_celda(GestorEventos.nombre_tipo(tipo)))
		_tabla_eventos.add_child(_crear_celda(objetivo))
		_tabla_eventos.add_child(_crear_celda(str(trenes_afectados.size())))
		_tabla_eventos.add_child(_crear_celda(_formatear_duracion(retraso_total) if retraso_total > 0.0 else "—"))


## --- Utilidades ---

## `free()` inmediato, no `queue_free()`: esto se llama varias veces por
## refresco (una tabla, luego la otra) y un borrado diferido deja ambas
## generaciones de filas coexistiendo como hijos hasta el próximo frame,
## así que una lectura inmediata después de actualizar vería datos viejos.
func _vaciar_filas(tabla: GridContainer, columnas: int) -> void:
	var hijos: Array[Node] = tabla.get_children()
	for i: int in range(columnas, hijos.size()):
		hijos[i].free()


func _crear_titulo_seccion(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 11)
	etiqueta.add_theme_color_override("font_color", COLOR_ACENTO)
	return etiqueta


func _crear_celda_encabezado(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 10)
	etiqueta.add_theme_color_override("font_color", COLOR_TEXTO_SUAVE)
	return etiqueta


func _crear_celda(texto: String) -> Label:
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 11)
	etiqueta.add_theme_color_override("font_color", COLOR_TEXTO)
	etiqueta.clip_text = true
	return etiqueta


func _formatear_duracion(segundos: float) -> String:
	if segundos < 60.0:
		return "%ds" % roundi(segundos)
	return "%d min" % roundi(segundos / 60.0)
