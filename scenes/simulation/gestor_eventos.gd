extends Node
class_name GestorEventos
## Dispara y resuelve los 3 eventos de dominio del servicio ferroviario:
## falla eléctrica, piquete y desperfecto mecánico. Todo pasa por los
## comandos ya existentes de `SimulacionController` -- este módulo no toca
## `Tren`, `TrackNetwork` ni reservas directamente.
##
## Falla eléctrica y piquete son "zonas activas": mientras el evento dura,
## CUALQUIER tren que entre a la estación/tramo afectado se detiene por el
## TIEMPO RESTANTE del evento (no una duración fija desde que entra, y no
## sólo los trenes que ya estaban ahí al disparar). El efecto en los trenes
## que vienen detrás de uno detenido es automático: lo da la reserva FIFO de
## `TrackNetwork` que ya existe, no hace falta programarlo acá.
##
## Desperfecto mecánico es un evento de un único tren, inmediato y
## definitivo (`finalizar_tren_incompleto`); no es una zona.
##
## Alcance de cada zona -- detectado sólo con señales públicas de Tren:
## - Piquete (estación puntual): se aplica en `llego_a_estacion` cuando el
##   nombre de la estación coincide con la zona activa.
## - Falla eléctrica (tramo): se aplica en `salio_de_estacion` cuando el
##   nombre de la estación de origen coincide con la zona activa -- el tramo
##   se identifica por su estación de salida, no hay otra forma pública de
##   nombrar "el tramo entre A y B".
##
## Cada evento disparado se registra en `_eventos` (id único -> Dictionary)
## y acumula su propio impacto (trenes afectados, retraso total) a medida
## que ocurre -- pensado para comparar eventos entre sí, que es el objetivo
## del proyecto. El retraso se atribuye escuchando
## `EstadisticasRetraso.retraso_tramo_sumado`: cuando un tren recién entró a
## una zona queda con una "atribución pendiente", y el próximo tramo que
## complete (sea 0 o no) se suma al evento que lo afectó y cierra la espera.

signal evento_disparado(datos: Dictionary)
signal evento_finalizado(datos: Dictionary)
## Un tren puntual entró a una zona activa. Distinto de evento_disparado
## (que es sobre la zona, no sobre un tren) -- lo necesita IndicadorEventos
## para saber recién en este momento a qué tren colgarle el efecto visual,
## ya que al disparar una zona todavía no se sabe qué tren va a entrar.
signal tren_afectado_por_evento(id_tren: int, tipo: TipoEvento)

enum TipoEvento { FALLA_ELECTRICA, PIQUETE, DESPERFECTO_MECANICO }

## Un color por evento, consistente para quien construya el panel/ícono.
const COLOR_FALLA_ELECTRICA: Color = Color(0.95, 0.80, 0.15)  ## amarillo
const COLOR_PIQUETE: Color = Color(0.95, 0.55, 0.10)          ## naranja
const COLOR_DESPERFECTO_MECANICO: Color = Color(0.85, 0.15, 0.15)  ## rojo

@export var duracion_falla_electrica_s: float = 90.0
@export var duracion_piquete_s: float = 120.0
## Teclas de debug F1/F2/F3, sólo en build de debug y nunca si hay un campo
## de texto con foco (ver _unhandled_input). Provisorio hasta que el panel
## de control dispare eventos por su cuenta.
@export var teclas_debug_activas: bool = true

@export_group("Disparo aleatorio")
## Eventos promedio por hora SIMULADA (no real). Se evalúa como probabilidad
## continua por segundo simulado (prob_por_hora/3600 * delta), así que el
## valor es directamente la frecuencia esperada, no hace falta convertir
## nada a mano. 0.0 desactiva ese tipo de evento aleatorio.
## Desactivado por defecto: el disparo es manual (debug o panel de control).
## El código queda listo por si se quiere complementar más adelante.
@export var aleatorio_activo: bool = false
@export_range(0.0, 20.0, 0.1) var falla_electrica_por_hora: float = 2.0
@export_range(0.0, 20.0, 0.1) var piquete_por_hora: float = 2.0
@export_range(0.0, 20.0, 0.1) var desperfecto_por_hora: float = 0.5

var _controlador: SimulacionController
var _reloj: RelojSimulacion
var _estadisticas: EstadisticasRetraso
var _siguiente_evento_id: int = 1
var _eventos: Dictionary = {}  ## id_evento (int) -> Dictionary
var _zonas_estacion: Dictionary = {}  ## nombre_estacion -> id_evento
var _zonas_tramo: Dictionary = {}  ## nombre_estacion_origen -> id_evento
var _tipo_activo_por_tren: Dictionary = {}  ## id_tren -> TipoEvento
var _atribucion_pendiente: Dictionary = {}  ## id_tren -> id_evento
var _trenes_conectados: Dictionary = {}


func _ready() -> void:
	var nivel: Node = get_parent()
	_controlador = nivel.get_node_or_null("SimulacionController") as SimulacionController
	_reloj = nivel.get_node_or_null("RelojSimulacion") as RelojSimulacion
	_estadisticas = nivel.get_node_or_null("EstadisticasRetraso") as EstadisticasRetraso
	if _estadisticas != null:
		_estadisticas.retraso_tramo_sumado.connect(_on_retraso_tramo_sumado)
	get_tree().node_added.connect(_on_nodo_agregado)
	# Mismo motivo que en EstadisticasRetraso: en el mismo lote de
	# instanciación los trenes todavía no corrieron su propio _ready(), así
	# que el escaneo inicial tiene que ser diferido.
	call_deferred("_registrar_trenes_iniciales")


func _registrar_trenes_iniciales() -> void:
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			_conectar_tren(nodo as Tren)


func _process(delta: float) -> void:
	if _reloj == null:
		return
	var ahora: float = _reloj.tiempo_simulado_s()
	_expirar_zonas(_zonas_estacion, ahora)
	_expirar_zonas(_zonas_tramo, ahora)
	if aleatorio_activo:
		# `delta` ya viene escalado por Engine.time_scale (el mismo mecanismo
		# que usa RelojSimulacion), así que es directamente tiempo simulado:
		# no hace falta pasar por _reloj para esta cuenta.
		_evaluar_disparo_aleatorio(falla_electrica_por_hora, delta, _disparar_falla_electrica_aleatoria)
		_evaluar_disparo_aleatorio(piquete_por_hora, delta, _disparar_piquete_aleatorio)
		_evaluar_disparo_aleatorio(desperfecto_por_hora, delta, _disparar_desperfecto_aleatorio)


func _evaluar_disparo_aleatorio(eventos_por_hora: float, delta_simulado: float, disparar: Callable) -> void:
	if eventos_por_hora <= 0.0:
		return
	var probabilidad_este_frame: float = (eventos_por_hora / 3600.0) * delta_simulado
	if randf() < probabilidad_este_frame:
		disparar.call()


func _disparar_falla_electrica_aleatoria() -> void:
	var nombre: String = _estacion_al_azar()
	if not nombre.is_empty():
		disparar_falla_electrica(nombre)


func _disparar_piquete_aleatorio() -> void:
	var nombre: String = _estacion_al_azar()
	if not nombre.is_empty():
		disparar_piquete(nombre)


func _disparar_desperfecto_aleatorio() -> void:
	var id: int = _tren_al_azar()
	if id > 0:
		disparar_desperfecto_mecanico(id, "Desperfecto mecánico (aleatorio)")


func _estacion_al_azar() -> String:
	if _controlador == null:
		return ""
	var estaciones: Array[Dictionary] = _controlador.obtener_estaciones()
	return str(estaciones[randi() % estaciones.size()].get("nombre", "")) if not estaciones.is_empty() else ""


func _tren_al_azar() -> int:
	if _controlador == null:
		return -1
	var activos: Array[Dictionary] = []
	for datos: Dictionary in _controlador.obtener_trenes():
		if int(datos.get("estado", -1)) not in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.INCOMPLETO]:
			activos.append(datos)
	return int(activos[randi() % activos.size()].get("id", -1)) if not activos.is_empty() else -1


func _expirar_zonas(zonas: Dictionary, ahora: float) -> void:
	var vencidas: Array = []
	for clave: String in zonas:
		var id_evento: int = int(zonas[clave])
		var evento: Dictionary = _eventos.get(id_evento, {})
		if evento.is_empty() or float(evento.get("fin_s", 0.0)) <= ahora:
			vencidas.append(clave)
	for clave: String in vencidas:
		var id_evento: int = int(zonas[clave])
		zonas.erase(clave)
		if _eventos.has(id_evento):
			_eventos[id_evento]["activo"] = false
			evento_finalizado.emit(_eventos[id_evento])


## Teclas F1/F2/F3: sólo en build de debug, nunca si hay un campo de texto
## con foco (que se coma la tecla sin querer mientras alguien escribe en el
## formulario del panel de control).
func _unhandled_input(evento: InputEvent) -> void:
	if not teclas_debug_activas or not OS.is_debug_build():
		return
	if not (evento is InputEventKey) or not evento.pressed or evento.echo:
		return
	var foco: Control = get_viewport().gui_get_focus_owner()
	if foco is LineEdit or foco is TextEdit or foco is SpinBox:
		return
	var tecla: InputEventKey = evento as InputEventKey
	match tecla.keycode:
		KEY_F1:
			var nombre: String = _primera_estacion_disponible()
			if not nombre.is_empty():
				print("[GestorEventos][debug] falla eléctrica en tramo que sale de '%s'" % nombre)
				disparar_falla_electrica(nombre)
		KEY_F2:
			var nombre2: String = _primera_estacion_disponible()
			if not nombre2.is_empty():
				print("[GestorEventos][debug] piquete en '%s'" % nombre2)
				disparar_piquete(nombre2)
		KEY_F3:
			var id: int = _primer_tren_activo()
			if id > 0:
				print("[GestorEventos][debug] desperfecto mecánico en tren id=%d" % id)
				disparar_desperfecto_mecanico(id)


func _primera_estacion_disponible() -> String:
	if _controlador == null:
		return ""
	var estaciones: Array[Dictionary] = _controlador.obtener_estaciones()
	return str(estaciones[0].get("nombre", "")) if not estaciones.is_empty() else ""


func _primer_tren_activo() -> int:
	if _controlador == null:
		return -1
	for datos: Dictionary in _controlador.obtener_trenes():
		if int(datos.get("estado", -1)) not in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.INCOMPLETO]:
			return int(datos.get("id", -1))
	return -1


## --- Disparo de eventos ---

## Alcance: tramo (identificado por su estación de salida). No apila: si ya
## hay una falla eléctrica activa en ese tramo, se rechaza.
func disparar_falla_electrica(estacion_origen_tramo: String, duracion_s: float = -1.0) -> Dictionary:
	return _disparar_zona(_zonas_tramo, estacion_origen_tramo, TipoEvento.FALLA_ELECTRICA,
		"Falla eléctrica", duracion_s if duracion_s > 0.0 else duracion_falla_electrica_s)


## Alcance: una estación puntual. No apila.
func disparar_piquete(estacion: String, duracion_s: float = -1.0) -> Dictionary:
	return _disparar_zona(_zonas_estacion, estacion, TipoEvento.PIQUETE,
		"Piquete", duracion_s if duracion_s > 0.0 else duracion_piquete_s)


func _disparar_zona(zonas: Dictionary, clave: String, tipo: TipoEvento, motivo: String, duracion_s: float) -> Dictionary:
	if clave.is_empty() or _reloj == null or _controlador == null:
		return {"ok": false, "motivo": "Datos insuficientes o controlador/reloj no disponibles."}
	if zonas.has(clave):
		return {"ok": false, "motivo": "Ya hay un evento activo en '%s'; no se apila." % clave}
	if duracion_s <= 0.0:
		return {"ok": false, "motivo": "Duración inválida."}

	var ahora: float = _reloj.tiempo_simulado_s()
	var id_evento: int = _siguiente_evento_id
	_siguiente_evento_id += 1
	var evento: Dictionary = {
		"id": id_evento, "tipo": tipo, "clave": clave, "motivo": motivo,
		"inicio_s": ahora, "fin_s": ahora + duracion_s, "duracion_s": duracion_s,
		"id_tren": -1, "trenes_afectados": {}, "retraso_total_s": 0.0, "activo": true,
	}
	_eventos[id_evento] = evento
	zonas[clave] = id_evento
	evento_disparado.emit(evento)
	return {"ok": true, "motivo": ""}


## Alcance: un único tren. Definitivo, no es zona ni se reanuda. No genera
## retraso adicional (el viaje termina ahí), así que su impacto es siempre
## "1 tren afectado, 0 de retraso" -- se registra igual para que aparezca
## en el historial y se pueda comparar cantidad de averías contra las otras.
func disparar_desperfecto_mecanico(id_tren: int, motivo: String = "Desperfecto mecánico") -> bool:
	if _controlador == null:
		return false
	var ok: bool = _controlador.finalizar_tren_incompleto(id_tren, motivo)
	if ok:
		_tipo_activo_por_tren[id_tren] = TipoEvento.DESPERFECTO_MECANICO
		var id_evento: int = _siguiente_evento_id
		_siguiente_evento_id += 1
		var evento: Dictionary = {
			"id": id_evento, "tipo": TipoEvento.DESPERFECTO_MECANICO,
			"clave": "tren_%d" % id_tren, "motivo": motivo,
			"inicio_s": _reloj.tiempo_simulado_s() if _reloj != null else 0.0,
			"fin_s": -1.0, "duracion_s": 0.0, "id_tren": id_tren,
			"trenes_afectados": {id_tren: true}, "retraso_total_s": 0.0, "activo": false,
		}
		_eventos[id_evento] = evento
		evento_disparado.emit(evento)
	return ok


## Todos los eventos disparados, más recientes primero, enriquecidos con
## `trenes_afectados` (Dictionary usado como set) y `retraso_total_s`.
func obtener_historial() -> Array[Dictionary]:
	var ids: Array = _eventos.keys()
	ids.sort()
	ids.reverse()
	var resultado: Array[Dictionary] = []
	for id_evento: int in ids:
		resultado.append((_eventos[id_evento] as Dictionary).duplicate())
	return resultado


## Sólo los eventos de zona todavía activos (no incluye desperfectos: son
## instantáneos, nunca quedan "activos" como zona).
func obtener_zonas_activas() -> Array[Dictionary]:
	var activos: Array[Dictionary] = []
	for evento: Dictionary in _eventos.values():
		if bool(evento.get("activo", false)):
			activos.append(evento.duplicate())
	return activos


static func nombre_tipo(tipo: TipoEvento) -> String:
	match tipo:
		TipoEvento.FALLA_ELECTRICA:
			return "Falla eléctrica"
		TipoEvento.PIQUETE:
			return "Piquete"
		TipoEvento.DESPERFECTO_MECANICO:
			return "Avería"
	return "Evento"


## Color a mostrar para un tren con evento activo, o Color.TRANSPARENT si
## no tiene ninguno. Este módulo no dibuja nada: expone el dato para que el
## panel/ícono lo use.
func color_evento_activo(id_tren: int) -> Color:
	if not _tipo_activo_por_tren.has(id_tren):
		return Color.TRANSPARENT
	match int(_tipo_activo_por_tren[id_tren]):
		TipoEvento.FALLA_ELECTRICA:
			return COLOR_FALLA_ELECTRICA
		TipoEvento.PIQUETE:
			return COLOR_PIQUETE
		TipoEvento.DESPERFECTO_MECANICO:
			return COLOR_DESPERFECTO_MECANICO
	return Color.TRANSPARENT


## --- Conexión a trenes ---

func _on_nodo_agregado(nodo: Node) -> void:
	if nodo is Tren:
		call_deferred("_intentar_conectar", nodo.get_instance_id())


func _intentar_conectar(instance_id: int) -> void:
	var nodo: Node = instance_from_id(instance_id) as Node
	if nodo is Tren and nodo.is_in_group("trenes"):
		_conectar_tren(nodo as Tren)


func _conectar_tren(tren: Tren) -> void:
	if tren == null or not is_instance_valid(tren):
		return
	var id: int = tren.obtener_id_operativo()
	if id <= 0:
		call_deferred("_conectar_tren", tren)
		return
	if _trenes_conectados.has(id):
		return
	_trenes_conectados[id] = tren
	tren.salio_de_estacion.connect(_on_salio_de_estacion.bind(id))
	tren.llego_a_estacion.connect(_on_llego_a_estacion.bind(id))
	tren.eliminado.connect(_on_tren_eliminado.bind(id))


func _on_salio_de_estacion(_datos_tren: Dictionary, datos_estacion: Dictionary, id: int) -> void:
	var nombre: String = str(datos_estacion.get("nombre", ""))
	if _zonas_tramo.has(nombre):
		_aplicar_zona_a_tren(id, int(_zonas_tramo[nombre]))


func _on_llego_a_estacion(_datos_tren: Dictionary, datos_estacion: Dictionary, id: int) -> void:
	# Salió de la zona de tramo en la que pudiera haber entrado; el color de
	# "tramo" no sigue aplicando una vez que llegó.
	if _tipo_activo_por_tren.get(id) == TipoEvento.FALLA_ELECTRICA:
		_tipo_activo_por_tren.erase(id)
	var nombre: String = str(datos_estacion.get("nombre", ""))
	if _zonas_estacion.has(nombre):
		_aplicar_zona_a_tren(id, int(_zonas_estacion[nombre]))


func _aplicar_zona_a_tren(id_tren: int, id_evento: int) -> void:
	if _reloj == null or _controlador == null or not _eventos.has(id_evento):
		return
	var evento: Dictionary = _eventos[id_evento]
	var restante: float = float(evento["fin_s"]) - _reloj.tiempo_simulado_s()
	if restante <= 0.0:
		return
	if _controlador.detener_tren_temporalmente(id_tren, str(evento["motivo"]), restante):
		_tipo_activo_por_tren[id_tren] = int(evento["tipo"])
		(evento["trenes_afectados"] as Dictionary)[id_tren] = true
		# Si el tren ya tenía una atribución pendiente de un evento anterior
		# que todavía no cerró su tramo, se pisa con esta -- no debería pasar
		# en la práctica (Tren rechaza un segundo detener_tren_temporalmente
		# mientras ya está DETENIDO_POR_EVENTO), pero de pasar, se atribuye
		# al evento más reciente, que es el que lo volvió a frenar.
		_atribucion_pendiente[id_tren] = id_evento
		tren_afectado_por_evento.emit(id_tren, int(evento["tipo"]))


## El tren completó un tramo (aporte puede ser 0.0). Si ese tramo arrancó
## siendo afectado por un evento de zona, el aporte se le atribuye a ese
## evento y se cierra la espera -- así el próximo tramo (ya sin evento) no
## se atribuye por error al mismo evento viejo.
func _on_retraso_tramo_sumado(id_tren: int, aporte_s: float) -> void:
	if not _atribucion_pendiente.has(id_tren):
		return
	var id_evento: int = int(_atribucion_pendiente[id_tren])
	_atribucion_pendiente.erase(id_tren)
	if _eventos.has(id_evento):
		var evento: Dictionary = _eventos[id_evento]
		evento["retraso_total_s"] = float(evento["retraso_total_s"]) + aporte_s


func _on_tren_eliminado(id: int) -> void:
	_tipo_activo_por_tren.erase(id)
	_atribucion_pendiente.erase(id)
	_trenes_conectados.erase(id)
