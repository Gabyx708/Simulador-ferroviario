extends RefCounted
class_name ColaEsperaPasajeros
## Espera FIFO por tandas: conserva tiempos sin crear un nodo por pasajero.

var cantidad: int = 0
var _tandas: Array[Dictionary] = []
var _suma_llegadas: float = 0.0


func agregar(nuevos: int, instante_s: float) -> void:
	if nuevos <= 0:
		return
	_tandas.append({"cantidad": nuevos, "llegada_s": instante_s})
	cantidad += nuevos
	_suma_llegadas += nuevos * instante_s


## Devuelve la suma de los segundos que esperaron quienes están subiendo.
func retirar(pasajeros: int, instante_s: float) -> float:
	var restantes: int = mini(maxi(0, pasajeros), cantidad)
	var espera: float = 0.0
	while restantes > 0 and not _tandas.is_empty():
		var tanda: Dictionary = _tandas[0]
		var salen: int = mini(restantes, int(tanda["cantidad"]))
		var llegada: float = float(tanda["llegada_s"])
		espera += salen * maxf(0.0, instante_s - llegada)
		_suma_llegadas -= salen * llegada
		cantidad -= salen
		restantes -= salen
		tanda["cantidad"] = int(tanda["cantidad"]) - salen
		if int(tanda["cantidad"]) == 0:
			_tandas.pop_front()
	return espera


## Ediciones de capacidad/cantidades no son embarques: conserva primero a los más antiguos.
func ajustar_cantidad(nueva: int, instante_s: float) -> void:
	if nueva > cantidad:
		agregar(nueva - cantidad, instante_s)
	while cantidad > nueva and not _tandas.is_empty():
		var tanda: Dictionary = _tandas.back()
		var salen: int = mini(cantidad - nueva, int(tanda["cantidad"]))
		_suma_llegadas -= salen * float(tanda["llegada_s"])
		cantidad -= salen
		tanda["cantidad"] = int(tanda["cantidad"]) - salen
		if int(tanda["cantidad"]) == 0:
			_tandas.pop_back()


func espera_acumulada_actual(instante_s: float) -> float:
	return maxf(0.0, cantidad * instante_s - _suma_llegadas)
