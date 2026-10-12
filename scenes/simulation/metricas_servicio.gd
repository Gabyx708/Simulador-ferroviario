extends RefCounted
class_name MetricasServicio
## Conserva horarios y resultados aunque una formación se quite de la escena.

var tolerancia_s: float = 1.0
var _reloj: RelojSimulacion
var _registros: Dictionary = {}


func _init(reloj: RelojSimulacion = null) -> void:
	_reloj = reloj


func _ahora() -> float:
	return _reloj.tiempo_simulado_s() if is_instance_valid(_reloj) else 0.0


func registrar_tren(tren: Tren) -> void:
	var id: int = tren.obtener_id_operativo()
	if _registros.has(id):
		return
	var horario: Array[Dictionary] = tren.obtener_horario_previsto()
	_registros[id] = {
		"inicio_s": _ahora(), "fin_s": -1.0, "datos": tren.obtener_resumen_operativo(),
		"horario": horario, "siguiente": 1, "desvio_s": 0.0, "llegadas": {},
		"estancia_final_s": tren.tiempo_parada_servicio,
	}
	if not horario.is_empty():
		(_registros[id]["llegadas"] as Dictionary)[0] = 0.0
	if int((_registros[id]["datos"] as Dictionary).get("estado", -1)) in [Tren.EstadoOperacion.INCOMPLETO, Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA]:
		_registros[id]["fin_s"] = _ahora()
	tren.llego_a_estacion.connect(_on_llegada.bind(id))
	tren.recorrido_finalizado.connect(_on_finalizado.bind(id))
	tren.recorrido_incompleto.connect(_on_incompleto.bind(id))
	tren.eliminado.connect(_on_eliminado.bind(id))


func actualizar_datos(datos: Dictionary) -> void:
	var id: int = int(datos.get("id", 0))
	if _registros.has(id):
		_registros[id]["datos"] = datos.duplicate()


func _on_llegada(datos: Dictionary, estacion: Dictionary, id: int) -> void:
	actualizar_datos(datos)
	var registro: Dictionary = _registros[id]
	var horario: Array[Dictionary] = registro["horario"]
	var siguiente: int = int(registro["siguiente"])
	if siguiente >= horario.size() or str(horario[siguiente]["id"]) != str(estacion.get("id", "")):
		return
	var transcurrido: float = _ahora() - float(registro["inicio_s"])
	(registro["llegadas"] as Dictionary)[siguiente] = transcurrido
	registro["desvio_s"] = transcurrido - float(horario[siguiente]["llegada_prevista_s"])
	registro["siguiente"] = siguiente + 1


func _on_finalizado(datos: Dictionary, id: int) -> void:
	actualizar_datos(datos)
	_registros[id]["fin_s"] = _ahora()


func _on_incompleto(datos: Dictionary, _motivo: String, id: int) -> void:
	_on_finalizado(datos, id)


func _on_eliminado(id: int) -> void:
	if float(_registros[id]["fin_s"]) < 0.0:
		_registros[id]["fin_s"] = _ahora()
	_registros[id]["eliminado"] = true


func obtener_puntualidad(id: int) -> Dictionary:
	if not _registros.has(id):
		return {}
	var registro: Dictionary = _registros[id]
	var horario: Array[Dictionary] = registro["horario"]
	if horario.is_empty():
		return {"puntualidad_nombre": "Sin horario", "horario_disponible": false}
	var fin: float = float(registro["fin_s"])
	var transcurrido: float = (fin if fin >= 0.0 else _ahora()) - float(registro["inicio_s"])
	var siguiente: int = int(registro["siguiente"])
	var retraso: float = maxf(0.0, float(registro["desvio_s"]))
	if fin < 0.0 and siguiente < horario.size():
		retraso = maxf(retraso, transcurrido - float(horario[siguiente]["llegada_prevista_s"]))
	var atrasado: bool = retraso > tolerancia_s
	return {
		"horario_disponible": true, "atrasado": atrasado,
		"puntualidad_nombre": "Atrasado" if atrasado else "En tiempo",
		"retraso_horario_s": retraso if atrasado else 0.0,
		"tiempo_recorrido_s": transcurrido,
		"tiempo_previsto_total_s": float(horario.back()["llegada_prevista_s"]) + float(registro["estancia_final_s"]),
		"llegada_proxima_prevista_s": float(horario[siguiente]["llegada_prevista_s"]) if siguiente < horario.size() else -1.0,
	}


func obtener_resultados() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for registro: Dictionary in _registros.values():
		var datos: Dictionary = registro["datos"]
		if int(datos.get("estado", -1)) in [Tren.EstadoOperacion.INCOMPLETO, Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA]:
			resultado.append(datos.duplicate())
	return resultado


func obtener_horarios() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	for id: int in _registros:
		var registro: Dictionary = _registros[id]
		var visitas: Array[Dictionary] = []
		var horario: Array[Dictionary] = registro["horario"]
		var llegadas: Dictionary = registro["llegadas"]
		for indice: int in horario.size():
			var visita: Dictionary = horario[indice].duplicate()
			visita["llegada_real_s"] = float(llegadas[indice]) if llegadas.has(indice) else -1.0
			visita["retraso_s"] = maxf(0.0, float(visita["llegada_real_s"]) - float(visita["llegada_prevista_s"])) if llegadas.has(indice) else 0.0
			visitas.append(visita)
		var datos: Dictionary = (registro["datos"] as Dictionary).duplicate()
		datos["id_tren"] = id
		datos["visitas"] = visitas
		datos["eliminado"] = bool(registro.get("eliminado", false))
		datos.merge(obtener_puntualidad(id), true)
		resultado.append(datos)
	return resultado
