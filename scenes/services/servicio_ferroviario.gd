@tool
extends Node
class_name ServicioFerroviario
## Define el orden operacional de las paradas de un servicio. La geometría de
## los Path3D no interviene: cada Estacion ya conserva su tramo y su offset.

@export_group("Paradas del servicio")
## Andenes en sentido Constitución -> Bosques. Puede contener dos nodos con el
## mismo nombre visible cuando la ida y la vuelta usan vías diferentes.
@export var paradas: Array[NodePath] = []
@export_range(0, 999, 1) var indice_parada_inicial: int = 0
## Al completar la última parada el tren queda detenido: no inicia el retorno.
@export var solo_ida: bool = false
## Completa una ida y una vuelta, en lugar de repetir indefinidamente el servicio.
@export var finalizar_al_volver: bool = false
## Derecha/izquierda mirando hacia la primera parada (Constitución).
@export var separar_vias_por_sentido: bool = false
## Usa el sentido configurado en cada Path3D para elegir una vía compatible.
@export var usar_sentido_de_vias: bool = true

@export_group("Horario previsto")
@export_range(1.0, 200.0, 1.0) var velocidad_horario_kmh: float = 50.0
@export_range(1.0, 3.0, 0.001) var factor_tiempo_horario: float = 1.123
## Segundos de marcha por tramo; vacío estima desde la distancia entre estaciones.
@export var tiempos_tramos_ida_s: PackedFloat32Array = PackedFloat32Array()
@export var tiempos_tramos_vuelta_s: PackedFloat32Array = PackedFloat32Array()
@export_range(0.0, 600.0, 1.0) var tiempo_maniobra_terminal_s: float = 30.0

@export_group("Itinerarios forzados")
## JSON opcional: {"0>1": ["seg_10", "seg_11"]}. Cada clave identifica los
## índices consecutivos de paradas; la lista sustituye el cálculo automático.
@export_multiline var overrides_json: String = ""

## Estado compartido por las formaciones que consultan la misma continuidad.
## Una rama sólo calcula la llegada inmediata; desde la próxima estación este
## caché evita repetir quince búsquedas iguales hasta Bosques por cada opción.
var _continuidad_cache: Dictionary = {}
var _validacion_ida_cache: Dictionary = {}
## Una formación por intervalo entre estaciones, con reservas direccionales.
var _propietarios_intervalos_servicio: Dictionary = {}
var _intervalos_por_tren: Dictionary = {}
var _cola_intervalos_servicio: Array[Dictionary] = []


func _ready() -> void:
	if not Engine.is_editor_hint() and separar_vias_por_sentido:
		call_deferred("_configurar_destinos_andenes")


func _obtener_red_ferroviaria() -> Node:
	var raiz: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if raiz != null:
		var red_escena: Node = raiz.find_child("TrackNetwork", true, false)
		if red_escena != null:
			return red_escena
	# Los tests y las vistas previas pueden instanciar el nivel sin marcarlo
	# como `current_scene`; en ese caso se busca desde el árbol completo.
	return get_tree().root.find_child("TrackNetwork", true, false)


## La demanda de cada andén lateral acompaña a la vía que lo sirve.
func _configurar_destinos_andenes() -> void:
	for indice: int in paradas.size():
		var estacion: Estacion = obtener_parada(indice) as Estacion
		if estacion == null:
			continue
		if indice == 0 or indice == paradas.size() - 1:
			# En las cabeceras el tren puede invertir la marcha en el mismo andén.
			# Ambas plataformas deben admitir pasajeros para el sentido de salida.
			estacion.destino_anden_a = Estacion.DestinoAnden.AMBOS
			estacion.destino_anden_b = Estacion.DestinoAnden.AMBOS
			continue
		if not estacion.incluir_anden_b_pasajeros:
			estacion.destino_anden_a = Estacion.DestinoAnden.BOSQUES
			continue
		var vecino: Node3D = obtener_parada(indice - 1 if indice > 0 else 1) as Node3D
		var a: Node3D = estacion.get_node_or_null("AndenA") as Node3D
		var b: Node3D = estacion.get_node_or_null("AndenB") as Node3D
		if vecino == null or a == null or b == null:
			continue
		var hacia_constitucion: Vector3 = vecino.global_position - estacion.global_position if indice > 0 else estacion.global_position - vecino.global_position
		hacia_constitucion.y = 0.0
		var derecha: Vector3 = hacia_constitucion.normalized().cross(Vector3.UP)
		var a_derecha: bool = a.global_position.dot(derecha) > b.global_position.dot(derecha)
		estacion.destino_anden_a = Estacion.DestinoAnden.BOSQUES if a_derecha else Estacion.DestinoAnden.CONSTITUCION
		estacion.destino_anden_b = Estacion.DestinoAnden.CONSTITUCION if a_derecha else Estacion.DestinoAnden.BOSQUES


func obtener_continuidad(clave: String) -> Dictionary:
	return (_continuidad_cache.get(clave, {}) as Dictionary).duplicate()


func iniciar_continuidad(clave: String, propietario: int) -> Dictionary:
	var actual: Dictionary = obtener_continuidad(clave)
	if actual.is_empty():
		actual = {"estado": "pendiente", "propietario": propietario}
		_continuidad_cache[clave] = actual
	return actual.duplicate()


func actualizar_continuidad(clave: String, estado: Dictionary) -> void:
	_continuidad_cache[clave] = estado.duplicate()


func cancelar_continuidad_pendiente(clave: String, propietario: int) -> void:
	var actual: Dictionary = obtener_continuidad(clave)
	if str(actual.get("estado", "")) == "pendiente" and int(actual.get("propietario", 0)) == propietario:
		_continuidad_cache.erase(clave)


func limpiar_continuidad() -> void:
	_continuidad_cache.clear()


## Comprueba la configuración física de un servicio de ida antes de poner una
## formación en marcha. Los Path3D pueden estar desordenados: la validación usa
## el poste de Ida y la topología de TrackNetwork, nunca el orden del árbol.
func validar_configuracion_ida(red: Node) -> Dictionary:
	if not _validacion_ida_cache.is_empty():
		return _validacion_ida_cache.duplicate(true)
	var errores: Array[String] = []
	if red == null or not red.has_method("planificar_ruta"):
		errores.append("TrackNetwork no disponible")
	elif paradas.size() < 2:
		errores.append("El servicio requiere al menos dos paradas")
	else:
		for indice: int in paradas.size():
			var estacion: Node = obtener_parada(indice)
			if estacion == null or not ("traza" in estacion) or not (estacion.get("traza") is Path3D):
				errores.append("Parada %d sin traza" % indice)
				continue
			if not estacion.has_method("obtener_puntos_parada_multivia"):
				errores.append("Parada %d sin puntos de parada" % indice)
				continue
			var candidatos: Array = estacion.call("obtener_puntos_parada_multivia", red, true) as Array
			if candidatos.is_empty():
				errores.append("%s no tiene candidato para PosteParadaIda" % str(estacion.get("nombre_estacion")))
		for indice: int in range(paradas.size() - 1):
			var origen: Node = obtener_parada(indice)
			var destino: Node = obtener_parada(indice + 1)
			if origen == null or destino == null or not (origen.get("traza") is Path3D) or not (destino.get("traza") is Path3D):
				continue
			var traza_origen: Path3D = origen.get("traza") as Path3D
			var traza_destino: Path3D = destino.get("traza") as Path3D
			var offset_origen: float = float(origen.call("obtener_offset_parada", true))
			var offset_destino: float = float(destino.call("obtener_offset_parada", true))
			var directa: Dictionary = red.call("planificar_ruta", traza_origen.name, offset_origen, false, traza_destino.name, offset_destino) as Dictionary
			var invertida: Dictionary = red.call("planificar_ruta", traza_origen.name, offset_origen, true, traza_destino.name, offset_destino) as Dictionary
			if not bool(directa.get("ok", false)) and not bool(invertida.get("ok", false)):
				errores.append("Sin enlace de ida: %s → %s" % [str(origen.get("nombre_estacion")), str(destino.get("nombre_estacion"))])
	_validacion_ida_cache = {"ok": errores.is_empty(), "errores": errores}
	return _validacion_ida_cache.duplicate(true)


func invalidar_validacion_ida() -> void:
	_validacion_ida_cache.clear()


func cantidad_paradas() -> int:
	return paradas.size()


func obtener_parada(indice: int) -> Node:
	if indice < 0 or indice >= paradas.size():
		return null
	return get_node_or_null(paradas[indice])


func siguiente_indice(indice: int, direccion: int) -> int:
	if paradas.is_empty():
		return -1
	return clampi(indice + direccion, 0, paradas.size() - 1)


## Reserva el tramo operacional entre dos paradas consecutivas. Un tren que ya
## espera en el intervalo conserva prioridad hasta que pueda entrar.
func reservar_intervalo_servicio(indice_origen: int, direccion: int, tren_id: int) -> bool:
	_asegurar_estado_intervalos()
	if tren_id <= 0 or direccion == 0 or indice_origen < 0 or indice_origen >= paradas.size():
		return false
	var indice_destino: int = siguiente_indice(indice_origen, direccion)
	if indice_destino == indice_origen:
		return false
	var clave: String = "%d>%d" % [indice_origen, indice_destino]
	var propietario: int = int(_propietarios_intervalos_servicio.get(clave, 0))
	if propietario == tren_id:
		_quitar_solicitud_intervalo(tren_id, clave)
		return true
	var indice_solicitud: int = _buscar_solicitud_intervalo(tren_id, clave)
	if indice_solicitud < 0:
		_cola_intervalos_servicio.append({"tren": tren_id, "clave": clave})
		indice_solicitud = _cola_intervalos_servicio.size() - 1
	if propietario != 0:
		return false
	for indice: int in range(indice_solicitud):
		if str(_cola_intervalos_servicio[indice].get("clave", "")) == clave:
			return false
	_propietarios_intervalos_servicio[clave] = tren_id
	_quitar_solicitud_intervalo(tren_id, clave)
	var intervalos: Array = _intervalos_por_tren.get(tren_id, []) as Array
	intervalos.append({"clave": clave, "liberar_en": INF})
	_intervalos_por_tren[tren_id] = intervalos
	return true


## El bloqueo se conserva hasta que la cola de la formación pasa la estación.
func registrar_llegada_intervalo_servicio(tren_id: int, indice_origen: int, indice_destino: int, odometro: float, largo_tren: float) -> void:
	_asegurar_estado_intervalos()
	var clave: String = "%d>%d" % [indice_origen, indice_destino]
	var intervalos: Array = _intervalos_por_tren.get(tren_id, []) as Array
	for intervalo_raw: Variant in intervalos:
		if not (intervalo_raw is Dictionary):
			continue
		var intervalo: Dictionary = intervalo_raw
		if str(intervalo.get("clave", "")) == clave:
			intervalo["liberar_en"] = odometro + maxf(0.0, largo_tren)
			return


## Libera intervalos cuya cola ya pasó y conserva los que aún ocupa el tren.
func actualizar_intervalos_servicio(tren_id: int, odometro: float) -> void:
	_asegurar_estado_intervalos()
	var intervalos: Array = _intervalos_por_tren.get(tren_id, []) as Array
	if intervalos.is_empty():
		return
	var restantes: Array = []
	for intervalo_raw: Variant in intervalos:
		if not (intervalo_raw is Dictionary):
			continue
		var intervalo: Dictionary = intervalo_raw
		var clave: String = str(intervalo.get("clave", ""))
		if odometro >= float(intervalo.get("liberar_en", INF)):
			if int(_propietarios_intervalos_servicio.get(clave, 0)) == tren_id:
				_propietarios_intervalos_servicio.erase(clave)
		else:
			restantes.append(intervalo)
	if restantes.is_empty():
		_intervalos_por_tren.erase(tren_id)
	else:
		_intervalos_por_tren[tren_id] = restantes


## Suelta los intervalos y solicitudes pendientes al eliminar o invalidar un tren.
func liberar_intervalos_servicio(tren_id: int) -> void:
	_asegurar_estado_intervalos()
	for intervalo_raw: Variant in _intervalos_por_tren.get(tren_id, []) as Array:
		if not (intervalo_raw is Dictionary):
			continue
		var intervalo: Dictionary = intervalo_raw
		var clave: String = str(intervalo.get("clave", ""))
		if int(_propietarios_intervalos_servicio.get(clave, 0)) == tren_id:
			_propietarios_intervalos_servicio.erase(clave)
	_intervalos_por_tren.erase(tren_id)
	for indice: int in range(_cola_intervalos_servicio.size() - 1, -1, -1):
		if int(_cola_intervalos_servicio[indice].get("tren", 0)) == tren_id:
			_cola_intervalos_servicio.remove_at(indice)


## Una escena viva puede conservar Nil en campos incorporados durante una recarga del script.
func _asegurar_estado_intervalos() -> void:
	if (
		typeof(_propietarios_intervalos_servicio) != TYPE_DICTIONARY
		or typeof(_intervalos_por_tren) != TYPE_DICTIONARY
		or typeof(_cola_intervalos_servicio) != TYPE_ARRAY
	):
		_propietarios_intervalos_servicio = {}
		_intervalos_por_tren = {}
		_cola_intervalos_servicio = []


func _buscar_solicitud_intervalo(tren_id: int, clave: String) -> int:
	for indice: int in _cola_intervalos_servicio.size():
		var solicitud: Dictionary = _cola_intervalos_servicio[indice]
		if int(solicitud.get("tren", 0)) == tren_id and str(solicitud.get("clave", "")) == clave:
			return indice
	return -1


func _quitar_solicitud_intervalo(tren_id: int, clave: String) -> void:
	var indice: int = _buscar_solicitud_intervalo(tren_id, clave)
	if indice >= 0:
		_cola_intervalos_servicio.remove_at(indice)


func es_terminal(indice: int) -> bool:
	return indice == 0 or indice == paradas.size() - 1


func finaliza_en(indice: int, direccion: int) -> bool:
	return (solo_ida and direccion > 0 and indice == paradas.size() - 1) or (not solo_ida and finalizar_al_volver and direccion < 0 and indice == 0)


## Selecciona la vía del lado indicado sin depender de la orientación de cada Path3D.
## Las playas de Constitución conservan sus accesos propios de terminal.
func filtrar_vias_sentido(estacion: Node, candidatos: Array[Dictionary], sentido_ida: bool) -> Array[Dictionary]:
	var configuradas: Dictionary = _filtrar_vias_por_sentido_configurado(candidatos, sentido_ida)
	if bool(configuradas.get("hay_asignacion", false)):
		return configuradas.get("candidatos", []) as Array[Dictionary]
	var estacion_datos: Estacion = estacion as Estacion
	if sentido_ida and estacion_datos != null and estacion_datos.usar_traza_como_via_ida:
		var candidatos_asignados: Array[Dictionary] = []
		for candidato: Dictionary in candidatos:
			if candidato.get("traza") == estacion_datos.traza:
				candidatos_asignados.append(candidato)
		return candidatos_asignados
	if not separar_vias_por_sentido:
		return candidatos
	if candidatos.size() < 2:
		return candidatos
	var indice: int = -1
	for i: int in paradas.size():
		if obtener_parada(i) == estacion:
			indice = i
			break
	if indice < 0 or not (estacion is Node3D):
		return candidatos
	var referencia: Node3D = obtener_parada(indice - 1 if indice > 0 else 1) as Node3D
	if referencia == null:
		return candidatos
	var hacia_constitucion: Vector3 = referencia.global_position - (estacion as Node3D).global_position if indice > 0 else (estacion as Node3D).global_position - referencia.global_position
	hacia_constitucion.y = 0.0
	var derecha: Vector3 = hacia_constitucion.normalized().cross(Vector3.UP)
	if derecha.length_squared() < 0.001:
		return []
	var grupo: Array[Dictionary] = vias_asignadas_a_sentido(estacion, candidatos, sentido_ida)
	# El itinerario usa la vía exterior del grupo: es la que está conectada al
	# corredor pasante. Las restantes siguen señalizadas y quedan disponibles
	# para futuras reglas de adelantamiento o de reserva.
	if grupo.is_empty():
		return grupo
	return [grupo.back() if sentido_ida else grupo.front()]


## El propio Path3D define su uso. Las vías comunes permiten ambos sentidos.
func _filtrar_vias_por_sentido_configurado(candidatos: Array[Dictionary], sentido_ida: bool) -> Dictionary:
	if not usar_sentido_de_vias:
		return {"hay_asignacion": false, "candidatos": candidatos}
	var permitidas: Array[Dictionary] = []
	var hay_asignacion: bool = false
	for candidato: Dictionary in candidatos:
		var via: Path3D = candidato.get("traza") as Path3D
		if via == null:
			continue
		if via.has_method("tiene_sentido_asignado") and bool(via.call("tiene_sentido_asignado")):
			hay_asignacion = true
		if not via.has_method("permite_sentido_servicio") or bool(via.call("permite_sentido_servicio", sentido_ida)):
			permitidas.append(candidato)
	return {"hay_asignacion": hay_asignacion, "candidatos": permitidas}


## Devuelve todas las vías reservadas para un sentido. Esta es la fuente de
## verdad que usa la señalización: con 12, 4 y 2 vías genera 6/6, 2/2 y 1/1.
func vias_asignadas_a_sentido(estacion: Node, candidatos: Array[Dictionary], sentido_ida: bool) -> Array[Dictionary]:
	if candidatos.size() < 2 or not (estacion is Node3D):
		return candidatos
	var indice: int = -1
	for i: int in paradas.size():
		if obtener_parada(i) == estacion:
			indice = i
			break
	if indice < 0:
		return candidatos
	var referencia: Node3D = obtener_parada(indice - 1 if indice > 0 else 1) as Node3D
	if referencia == null:
		return candidatos
	var hacia_constitucion: Vector3 = referencia.global_position - (estacion as Node3D).global_position if indice > 0 else (estacion as Node3D).global_position - referencia.global_position
	hacia_constitucion.y = 0.0
	var derecha: Vector3 = hacia_constitucion.normalized().cross(Vector3.UP)
	if derecha.length_squared() < 0.001:
		return []
	var ordenados: Array[Dictionary] = candidatos.duplicate()
	ordenados.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("punto_global", (estacion as Node3D).global_position) as Vector3).dot(derecha) < (b.get("punto_global", (estacion as Node3D).global_position) as Vector3).dot(derecha)
	)
	var corte: int = ordenados.size() / 2
	# El lado derecho mirando hacia Bosques queda reservado para la ida; el
	# izquierdo para la vuelta.
	return ordenados.slice(corte, ordenados.size()) if sentido_ida else ordenados.slice(0, corte)


## Horario relativo al alta del tren. Se copia una vez antes de medir las llegadas.
func crear_horario_previsto(espera_s: float, demora_inicial_s: float = 0.0) -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	if paradas.size() < 2:
		return resultado
	var acumulado: float = 0.0
	var estancia: float = maxf(1.0, espera_s)
	for indice: int in paradas.size():
		if indice > 0:
			acumulado += estancia + _tiempo_tramo_horario(indice - 1, true)
			if indice == 1:
				acumulado += maxf(0.0, demora_inicial_s)
		resultado.append(_visita_horario(indice, "ida", acumulado))
	if not solo_ida:
		acumulado += tiempo_maniobra_terminal_s
		for indice: int in range(paradas.size() - 2, -1, -1):
			acumulado += estancia + _tiempo_tramo_horario(indice, false)
			resultado.append(_visita_horario(indice, "vuelta", acumulado))
	return resultado


func _visita_horario(indice: int, sentido: String, llegada_s: float) -> Dictionary:
	var estacion: Estacion = obtener_parada(indice) as Estacion
	return {
		"id": estacion.obtener_id_edicion() if estacion != null else str(paradas[indice]),
		"nombre": estacion.nombre_estacion if estacion != null else str(paradas[indice]),
		"indice": indice, "sentido": sentido, "llegada_prevista_s": llegada_s,
	}


func _tiempo_tramo_horario(indice: int, ida: bool) -> float:
	var tiempos: PackedFloat32Array = tiempos_tramos_ida_s if ida else tiempos_tramos_vuelta_s
	if indice < tiempos.size() and tiempos[indice] > 0.0:
		return tiempos[indice]
	var origen: Node3D = obtener_parada(indice) as Node3D
	var destino: Node3D = obtener_parada(indice + 1) as Node3D
	if origen == null or destino == null:
		return 0.0
	return origen.global_position.distance_to(destino.global_position) / maxf(velocidad_horario_kmh / 3.6, 0.1) * factor_tiempo_horario


func override_para(origen: int, destino: int) -> Array[String]:
	if overrides_json.strip_edges().is_empty():
		return []
	var json := JSON.new()
	if json.parse(overrides_json) != OK or not (json.data is Dictionary):
		push_warning("ServicioFerroviario: overrides_json no contiene un JSON válido.")
		return []
	var valores: Variant = (json.data as Dictionary).get("%d>%d" % [origen, destino], [])
	var resultado: Array[String] = []
	if valores is Array:
		for valor: Variant in valores:
			resultado.append(str(valor))
	return resultado
