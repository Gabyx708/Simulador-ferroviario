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

@export_group("Itinerarios forzados")
## JSON opcional: {"0>1": ["seg_10", "seg_11"]}. Cada clave identifica los
## índices consecutivos de paradas; la lista sustituye el cálculo automático.
@export_multiline var overrides_json: String = ""

## Estado compartido por las formaciones que consultan la misma continuidad.
## Una rama sólo calcula la llegada inmediata; desde la próxima estación este
## caché evita repetir quince búsquedas iguales hasta Bosques por cada opción.
var _continuidad_cache: Dictionary = {}
var _validacion_ida_cache: Dictionary = {}


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


func es_terminal(indice: int) -> bool:
	return indice == 0 or indice == paradas.size() - 1


func finaliza_en(indice: int, direccion: int) -> bool:
	return solo_ida and direccion > 0 and indice == paradas.size() - 1


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
