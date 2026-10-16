extends RefCounted
class_name MetricasServicio
## Conserva horarios y resultados aunque una formación se quite de la escena.

var tolerancia_s: float = 120.0
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
	var inicio_s: float = _ahora()
	var horario: Array[Dictionary] = tren.obtener_horario_previsto()
	_registros[id] = {
		"inicio_s": inicio_s, "fin_s": -1.0, "datos": tren.obtener_resumen_operativo(),
		"horario": horario, "siguiente": 1, "desvio_s": 0.0, "llegadas": {},
		"inicio_tramo_s": inicio_s, "indice_inicio_tramo": 0,
		"estancia_final_s": tren.tiempo_parada_servicio,
	}
	if not horario.is_empty():
		(_registros[id]["llegadas"] as Dictionary)[0] = 0.0
	if int((_registros[id]["datos"] as Dictionary).get("estado", -1)) in [Tren.EstadoOperacion.INCOMPLETO, Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA]:
		_registros[id]["fin_s"] = _ahora()
	tren.llego_a_estacion.connect(_on_llegada.bind(id))
	tren.salio_de_estacion.connect(_on_salida.bind(id))
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
	# Sólo se registra una llegada que coincide con la próxima visita prevista;
	# así la tabla conserva el orden del servicio.
	if siguiente >= horario.size() or str(horario[siguiente]["id"]) != str(estacion.get("id", "")):
		return
	var ahora_s: float = _ahora()
	var transcurrido_ciclo_s: float = ahora_s - float(registro["inicio_s"])
	(registro["llegadas"] as Dictionary)[siguiente] = transcurrido_ciclo_s
	var indice_inicio_tramo: int = int(registro["indice_inicio_tramo"])
	var previsto_inicio_tramo_s: float = float(horario[indice_inicio_tramo]["llegada_prevista_s"])
	var previsto_llegada_s: float = float(horario[siguiente]["llegada_prevista_s"])
	var transcurrido_tramo_s: float = ahora_s - float(registro["inicio_tramo_s"])
	registro["desvio_s"] = transcurrido_tramo_s - (previsto_llegada_s - previsto_inicio_tramo_s)
	registro["siguiente"] = siguiente + 1

	# La puntualidad se mide por cada viaje entre cabeceras. Al llegar a Bosques
	# empieza una medición nueva para la vuelta; al llegar a Constitución, para
	# la próxima ida. La tabla del ciclo se reinicia al partir de la cabecera.
	if siguiente + 1 < horario.size():
		var sentido_actual: String = str(horario[siguiente].get("sentido", ""))
		var sentido_siguiente: String = str(horario[siguiente + 1].get("sentido", ""))
		if sentido_actual != sentido_siguiente:
			_reiniciar_retraso_tramo(registro, ahora_s, siguiente)
	elif siguiente == horario.size() - 1:
		# Última visita del ciclo: Constitución es el origen de la próxima ida.
		_reiniciar_retraso_tramo(registro, ahora_s, 0)


func _on_salida(datos: Dictionary, estacion: Dictionary, id: int) -> void:
	actualizar_datos(datos)
	if not _registros.has(id):
		return
	var registro: Dictionary = _registros[id]
	var horario: Array[Dictionary] = registro["horario"]
	var siguiente: int = int(registro["siguiente"])
	if horario.size() < 2 or siguiente < horario.size():
		return
	# Sólo una ruta de ida y vuelta que regresa al origen abre otro ciclo.
	# Una ruta de sólo ida o un tren finalizado conserva sus llegadas finales.
	var origen_id: String = str(horario.front().get("id", ""))
	var ultima: int = horario.size() - 1
	if str(horario.back().get("sentido", "")) != "vuelta" \
		or str(horario.back().get("id", "")) != origen_id \
		or str(estacion.get("id", "")) != origen_id:
		return
	var llegadas: Dictionary = registro["llegadas"]
	if not llegadas.has(ultima):
		return
	# La cabecera marca el minuto cero. Se usa su hora real de llegada para que
	# la espera antes de salir cuente al medir la llegada a la primera estación.
	var inicio_ciclo_s: float = float(registro["inicio_s"]) + float(llegadas[ultima])
	registro["inicio_s"] = inicio_ciclo_s
	registro["llegadas"] = {0: 0.0}
	registro["siguiente"] = 1
	registro["desvio_s"] = 0.0
	registro["inicio_tramo_s"] = inicio_ciclo_s
	registro["indice_inicio_tramo"] = 0
	registro["ciclo"] = int(registro.get("ciclo", 1)) + 1


func _reiniciar_retraso_tramo(registro: Dictionary, ahora_s: float, indice_inicio: int) -> void:
	registro["inicio_tramo_s"] = ahora_s
	registro["indice_inicio_tramo"] = indice_inicio
	registro["desvio_s"] = 0.0


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
		var indice_inicio_tramo: int = int(registro["indice_inicio_tramo"])
		var tiempo_desde_inicio_tramo_s: float = _ahora() - float(registro["inicio_tramo_s"])
		var tiempo_previsto_tramo_s: float = float(horario[siguiente]["llegada_prevista_s"]) - float(horario[indice_inicio_tramo]["llegada_prevista_s"])
		retraso = maxf(retraso, tiempo_desde_inicio_tramo_s - tiempo_previsto_tramo_s)
	var atrasado: bool = retraso > tolerancia_s
	return {
		"horario_disponible": true, "atrasado": atrasado,
		"ciclo_horario": int(registro.get("ciclo", 1)),
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
