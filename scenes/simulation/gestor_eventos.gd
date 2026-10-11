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

signal evento_disparado(datos: Dictionary)
signal evento_finalizado(datos: Dictionary)

enum TipoEvento { FALLA_ELECTRICA, PIQUETE, DESPERFECTO_MECANICO }

## Un color por evento, consistente para quien construya el panel/ícono
## (Persona 2). Persona 5 sólo expone el dato; no dibuja nada.
const COLOR_FALLA_ELECTRICA: Color = Color(0.95, 0.80, 0.15)  ## amarillo
const COLOR_PIQUETE: Color = Color(0.95, 0.55, 0.10)          ## naranja
const COLOR_DESPERFECTO_MECANICO: Color = Color(0.85, 0.15, 0.15)  ## rojo

@export var duracion_falla_electrica_s: float = 90.0
@export var duracion_piquete_s: float = 120.0
## Provisorio: teclas 1/2/3 disparan eventos de prueba sobre objetivos fijos,
## para probar sin esperar el panel de Persona 2. Pensado para desactivarse
## cuando ese panel exista.
@export var teclas_debug_activas: bool = true

@export_group("Disparo aleatorio")
## Eventos promedio por hora SIMULADA (no real). Se evalúa como probabilidad
## continua por segundo simulado (prob_por_hora/3600 * delta), así que el
## valor es directamente la frecuencia esperada, no hace falta convertir
## nada a mano. 0.0 desactiva ese tipo de evento aleatorio.
## Desactivado por defecto: por ahora el disparo es manual (vía teclas de
## debug o, más adelante, el panel de Persona 2). Se puede prender desde el
## Inspector si en algún momento se quiere complementar con disparo
## automático; el código queda listo pero no se usa por ahora.
@export var aleatorio_activo: bool = false
@export_range(0.0, 20.0, 0.1) var falla_electrica_por_hora: float = 2.0
@export_range(0.0, 20.0, 0.1) var piquete_por_hora: float = 2.0
@export_range(0.0, 20.0, 0.1) var desperfecto_por_hora: float = 0.5

var _controlador: SimulacionController
var _reloj: RelojSimulacion
var _zonas_estacion: Dictionary = {}  ## nombre_estacion -> {tipo, fin_s, motivo}
var _zonas_tramo: Dictionary = {}  ## nombre_estacion_origen -> {tipo, fin_s, motivo}
var _tipo_activo_por_tren: Dictionary = {}  ## id_tren -> TipoEvento
var _historial: Array[Dictionary] = []
var _trenes_conectados: Dictionary = {}


func _ready() -> void:
	var nivel: Node = get_parent()
	_controlador = nivel.get_node_or_null("SimulacionController") as SimulacionController
	_reloj = nivel.get_node_or_null("RelojSimulacion") as RelojSimulacion
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
		if float(zonas[clave]["fin_s"]) <= ahora:
			vencidas.append(clave)
	for clave: String in vencidas:
		var zona: Dictionary = zonas[clave]
		zonas.erase(clave)
		evento_finalizado.emit(zona)


func _unhandled_input(evento: InputEvent) -> void:
	if not teclas_debug_activas or not (evento is InputEventKey) or not evento.pressed or evento.echo:
		return
	var tecla: InputEventKey = evento as InputEventKey
	match tecla.keycode:
		KEY_1:
			var nombre: String = _primera_estacion_disponible()
			if not nombre.is_empty():
				print("[GestorEventos][debug] falla eléctrica en tramo que sale de '%s'" % nombre)
				disparar_falla_electrica(nombre)
		KEY_2:
			var nombre2: String = _primera_estacion_disponible()
			if not nombre2.is_empty():
				print("[GestorEventos][debug] piquete en '%s'" % nombre2)
				disparar_piquete(nombre2)
		KEY_3:
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
	var zona: Dictionary = {
		"tipo": tipo, "clave": clave, "motivo": motivo,
		"inicio_s": ahora, "fin_s": ahora + duracion_s, "duracion_s": duracion_s,
	}
	zonas[clave] = zona
	_registrar_historial(zona)
	evento_disparado.emit(zona)
	return {"ok": true, "motivo": ""}


## Alcance: un único tren. Definitivo, no es zona ni se reanuda.
func disparar_desperfecto_mecanico(id_tren: int, motivo: String = "Desperfecto mecánico") -> bool:
	if _controlador == null:
		return false
	var ok: bool = _controlador.finalizar_tren_incompleto(id_tren, motivo)
	if ok:
		_tipo_activo_por_tren[id_tren] = TipoEvento.DESPERFECTO_MECANICO
		var zona: Dictionary = {
			"tipo": TipoEvento.DESPERFECTO_MECANICO, "clave": "tren_%d" % id_tren,
			"motivo": motivo, "id_tren": id_tren,
		}
		_registrar_historial(zona)
		evento_disparado.emit(zona)
	return ok


func _registrar_historial(zona: Dictionary) -> void:
	_historial.append(zona.duplicate())


func obtener_historial() -> Array[Dictionary]:
	return _historial.duplicate()


## Color a mostrar para un tren con evento activo, o Color.TRANSPARENT si
## no tiene ninguno. Persona 2 lo usa para pintar la fila en el panel; este
## módulo no dibuja nada.
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
		_aplicar_zona_a_tren(id, _zonas_tramo[nombre])


func _on_llego_a_estacion(_datos_tren: Dictionary, datos_estacion: Dictionary, id: int) -> void:
	# Salió de la zona de tramo en la que pudiera haber entrado; el color de
	# "tramo" no sigue aplicando una vez que llegó.
	if _tipo_activo_por_tren.get(id) == TipoEvento.FALLA_ELECTRICA:
		_tipo_activo_por_tren.erase(id)
	var nombre: String = str(datos_estacion.get("nombre", ""))
	if _zonas_estacion.has(nombre):
		_aplicar_zona_a_tren(id, _zonas_estacion[nombre])


func _aplicar_zona_a_tren(id: int, zona: Dictionary) -> void:
	if _reloj == null or _controlador == null:
		return
	var restante: float = float(zona["fin_s"]) - _reloj.tiempo_simulado_s()
	if restante <= 0.0:
		return
	if _controlador.detener_tren_temporalmente(id, str(zona["motivo"]), restante):
		_tipo_activo_por_tren[id] = int(zona["tipo"])


func _on_tren_eliminado(id: int) -> void:
	_tipo_activo_por_tren.erase(id)
	_trenes_conectados.erase(id)
