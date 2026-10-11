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
