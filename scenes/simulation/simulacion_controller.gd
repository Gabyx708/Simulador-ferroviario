extends Node
class_name SimulacionController
## Fachada pública de una simulación ferroviaria por nivel.
## Observa grupos y señales publicadas: no consulta rutas, switches ni reservas.

signal tren_agregado(datos_tren: Dictionary)
signal tren_eliminado(id_tren: int)
signal tren_actualizado(datos_tren: Dictionary)
signal tren_llego_estacion(id_tren: int, datos_estacion: Dictionary)
signal tren_reanudo(id_tren: int)
signal tren_finalizo(id_tren: int, resultado: String)
signal estacion_actualizada(datos_estacion: Dictionary)
signal resumen_global_actualizado(datos_resumen: Dictionary)
signal velocidad_simulacion_cambiada(factor: float)

var _trenes: Dictionary = {}
var _estaciones: Dictionary = {}
var _siguiente_id_tren: int = 1
var _concurrencia_maxima: int = 0
var _recorridos_finalizados_total: int = 0
var _factor_velocidad_simulacion: float = 1.0
var _factor_antes_de_pausa: float = 1.0
var _escala_engine_previa: float = 1.0
@export_range(0.0, 600.0, 1.0) var tolerancia_horario_s: float = 120.0
var _metricas: MetricasServicio


func _ready() -> void:
	_metricas = MetricasServicio.new(get_parent().get_node_or_null("RelojSimulacion") as RelojSimulacion)
	_metricas.tolerancia_s = tolerancia_horario_s
	_escala_engine_previa = Engine.time_scale
	_factor_velocidad_simulacion = Engine.time_scale
	if Engine.time_scale > 0.0:
		_factor_antes_de_pausa = Engine.time_scale
	if not get_tree().node_added.is_connected(_on_nodo_agregado):
		get_tree().node_added.connect(_on_nodo_agregado)
	call_deferred("_registrar_grupos_iniciales")


func _exit_tree() -> void:
	Engine.time_scale = _escala_engine_previa
	if get_tree() != null and get_tree().node_added.is_connected(_on_nodo_agregado):
		get_tree().node_added.disconnect(_on_nodo_agregado)


func _registrar_grupos_iniciales() -> void:
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			_registrar_tren(nodo as Tren)
	for nodo: Node in get_tree().get_nodes_in_group("estaciones"):
		if nodo is Estacion:
			_registrar_estacion(nodo as Estacion)
	_actualizar_concurrencia()
	_emitir_resumen_global()


func _on_nodo_agregado(nodo: Node) -> void:
	# Los grupos se agregan desde _ready() de Tren/Estacion, por eso se difiere
	# un frame sin asumir el orden de carga de cada escena.
	if nodo is Tren or nodo is Estacion:
		call_deferred("_intentar_registrar_nodo", nodo.get_instance_id())


func _intentar_registrar_nodo(instance_id: int) -> void:
	var nodo: Node = instance_from_id(instance_id) as Node
	if nodo == null or not is_instance_valid(nodo):
		return
	if nodo is Tren and nodo.is_in_group("trenes"):
		_registrar_tren(nodo as Tren)
	elif nodo is Estacion and nodo.is_in_group("estaciones"):
		_registrar_estacion(nodo as Estacion)


func _registrar_tren(tren: Tren) -> void:
	if tren == null or not is_instance_valid(tren) or tren.esta_eliminado():
		return
	var id: int = tren.obtener_id_operativo()
	if id <= 0:
		id = _siguiente_id_tren
		_siguiente_id_tren += 1
		tren.asignar_id_operativo(id)
	else:
		_siguiente_id_tren = maxi(_siguiente_id_tren, id + 1)
	if _trenes.has(id):
		return
	_trenes[id] = tren
	_metricas.registrar_tren(tren)
	_conectar_tren(tren, id)
	_actualizar_concurrencia()
	tren_agregado.emit(tren.obtener_resumen_operativo())
	_emitir_resumen_global()


func _conectar_tren(tren: Tren, id: int) -> void:
	_conectar_si_hace_falta(tren.estado_operacion_cambiado, _on_tren_estado.bind(id))
	_conectar_si_hace_falta(tren.llego_a_estacion, _on_tren_llego_estacion.bind(id))
	_conectar_si_hace_falta(tren.salio_de_estacion, _on_tren_salio_estacion.bind(id))
	_conectar_si_hace_falta(tren.recorrido_finalizado, _on_tren_finalizado.bind(id))
	_conectar_si_hace_falta(tren.recorrido_incompleto, _on_tren_incompleto.bind(id))
	_conectar_si_hace_falta(tren.pasajeros_cambiados, _on_tren_pasajeros_cambiados.bind(id))
	_conectar_si_hace_falta(tren.ruta_actualizada, _on_tren_ruta_actualizada.bind(id))
	_conectar_si_hace_falta(tren.eliminado, _on_tren_eliminado.bind(id))
	_conectar_si_hace_falta(tren.evento_temporal_finalizado, _on_evento_temporal_finalizado.bind(id))


func _conectar_si_hace_falta(senal: Signal, destino: Callable) -> void:
	if not senal.is_connected(destino):
		senal.connect(destino)


func _registrar_estacion(estacion: Estacion) -> void:
	if estacion == null or not is_instance_valid(estacion):
		return
	var id: String = _id_estacion(estacion)
	if _estaciones.has(id):
		return
	_estaciones[id] = estacion
	_conectar_si_hace_falta(estacion.pasajeros_actualizados, _on_estacion_pasajeros_actualizados.bind(id))
	_conectar_si_hace_falta(estacion.ingreso_pasajeros_cambiado, _on_estacion_ingreso_pasajeros_cambiado.bind(id))
	estacion_actualizada.emit(_resumen_estacion(estacion))
	_emitir_resumen_global()


func _id_estacion(estacion: Estacion) -> String:
	return str(estacion.obtener_id_edicion()) if estacion.has_method("obtener_id_edicion") else str(estacion.name)


func _resumen_estacion(estacion: Estacion) -> Dictionary:
	var datos: Dictionary = {
		"id": _id_estacion(estacion),
		"nombre": estacion.nombre_estacion,
		"activa": estacion.activa,
		"ingreso_pasajeros_habilitado": estacion.ingreso_pasajeros_habilitado,
		"pasajeros_esperando": estacion.pasajeros_esperando,
		"pasajeros_saliendo": estacion.pasajeros_saliendo,
		"pasajeros_subidos_total": estacion.pasajeros_subidos_total,
		"pasajeros_bajados_total": estacion.pasajeros_bajados_total,
	}
	datos.merge(estacion.obtener_metricas_espera(), true)
	return datos


func _resumen_tren(tren: Tren) -> Dictionary:
	var datos: Dictionary = tren.obtener_resumen_operativo()
	if _metricas != null:
		datos.merge(_metricas.obtener_puntualidad(tren.obtener_id_operativo()), true)
	return datos


func obtener_trenes() -> Array[Dictionary]:
	_limpiar_referencias_inactivas()
	var resultado: Array[Dictionary] = []
	var ids: Array = _trenes.keys()
	ids.sort()
	for id: int in ids:
		var tren: Tren = _trenes[id] as Tren
		if tren != null and is_instance_valid(tren):
			resultado.append(_resumen_tren(tren))
	return resultado


func obtener_tren(id_tren: int) -> Dictionary:
	_limpiar_referencias_inactivas()
	var tren: Tren = _trenes.get(id_tren) as Tren
	return _resumen_tren(tren) if tren != null and is_instance_valid(tren) else {}


func obtener_horarios() -> Array[Dictionary]:
	return _metricas.obtener_horarios() if _metricas != null else []


func obtener_estaciones() -> Array[Dictionary]:
	var resultado: Array[Dictionary] = []
	var ids: Array = _estaciones.keys()
	ids.sort()
	for id: String in ids:
		var estacion: Estacion = _estaciones[id] as Estacion
		if estacion != null and is_instance_valid(estacion):
			resultado.append(_resumen_estacion(estacion))
	return resultado


func obtener_estacion(id_estacion: String) -> Dictionary:
	var estacion: Estacion = _estaciones.get(id_estacion) as Estacion
	return _resumen_estacion(estacion) if estacion != null and is_instance_valid(estacion) else {}


func obtener_resumen_global() -> Dictionary:
	_limpiar_referencias_inactivas()
	var pasajeros_esperando: int = 0
	var pasajeros_transportados: int = 0
	var pasajeros_completados: int = 0
	var espera_actual_total: float = 0.0
	var estaciones: Array[Dictionary] = obtener_estaciones()
	for estacion: Dictionary in estaciones:
		pasajeros_esperando += int(estacion.get("pasajeros_esperando", 0))
		pasajeros_transportados += int(estacion.get("pasajeros_subidos_total", 0))
		pasajeros_completados += int(estacion.get("pasajeros_bajados_total", 0))
		espera_actual_total += float(estacion.get("espera_promedio_actual_s", 0.0))
	var pasajeros_en_viaje: int = 0
	var activos: int = 0
	var incompletos: int = 0
	var incompletos_evento: int = 0
	var pasajeros_interrumpidos: int = 0
	var atrasados: int = 0
	var con_horario: int = 0
	var demora_total: float = 0.0
	for tren: Dictionary in obtener_trenes():
		var estado: int = int(tren.get("estado", -1))
		if estado in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA, Tren.EstadoOperacion.INCOMPLETO]:
			continue
		activos += 1
		pasajeros_en_viaje += int(tren.get("pasajeros", 0))
		if bool(tren.get("horario_disponible", false)):
			con_horario += 1
			demora_total += float(tren.get("retraso_horario_s", 0.0))
			if bool(tren.get("atrasado", false)):
				atrasados += 1
	if _metricas != null:
		for tren: Dictionary in _metricas.obtener_resultados():
			var estado: int = int(tren.get("estado", -1))
			if estado == Tren.EstadoOperacion.INCOMPLETO:
				incompletos += 1
				pasajeros_interrumpidos += int(tren.get("pasajeros", 0))
				if str(tren.get("causa_resultado", "")) == "evento_terminal":
					incompletos_evento += 1
	return {
		"pasajeros_esperando": pasajeros_esperando,
		"pasajeros_en_viaje": pasajeros_en_viaje,
		"pasajeros_transportados": pasajeros_transportados,
		"pasajeros_recorrido_completado": pasajeros_completados,
		"pasajeros_interrumpidos": pasajeros_interrumpidos,
		"trenes_activos": activos,
		"trenes_finalizados": _recorridos_finalizados_total,
		"trenes_incompletos": incompletos,
		"trenes_incompletos_evento": incompletos_evento,
		"trenes_atrasados": atrasados,
		"trenes_con_horario": con_horario,
		"tasa_demora_pct": 100.0 * atrasados / con_horario if con_horario > 0 else 0.0,
		"demora_promedio_s": demora_total / con_horario if con_horario > 0 else 0.0,
		"espera_promedio_actual_s": espera_actual_total / estaciones.size() if not estaciones.is_empty() else 0.0,
		"concurrencia_maxima": _concurrencia_maxima,
	}


## Alta pública: la geometría y la cola siguen siendo responsabilidad del
## nivel, mientras este controlador sólo publica un resultado estable.
func agregar_tren() -> Dictionary:
	var nivel: Node = get_parent()
	if nivel == null or not nivel.has_method("agregar_tren"):
		return {"ok": false, "en_cola": false, "tren": {}, "motivo": "El nivel no admite despacho de trenes."}
	var cola_antes: int = int(nivel.call("trenes_en_cola")) if nivel.has_method("trenes_en_cola") else 0
	var tren: Tren = nivel.call("agregar_tren") as Tren
	if tren != null:
		_registrar_tren(tren)
		return {"ok": true, "en_cola": false, "tren": tren.obtener_resumen_operativo(), "motivo": ""}
	var cola_despues: int = int(nivel.call("trenes_en_cola")) if nivel.has_method("trenes_en_cola") else cola_antes
	if cola_despues > cola_antes:
		return {"ok": true, "en_cola": true, "tren": {}, "motivo": "Tren agregado a la cola de despacho."}
	return {"ok": false, "en_cola": false, "tren": {}, "motivo": "No hay un puesto de instancia disponible."}


func agregar_tren_en_bosques() -> Dictionary:
	var nivel: Node = get_parent()
	if nivel == null or not nivel.has_method("agregar_tren_en_bosques"):
		return {"ok": false, "en_cola": false, "tren": {}, "motivo": "El nivel no admite despacho de trenes en Bosques."}
	var cola_antes: int = int(nivel.call("trenes_bosques_en_cola")) if nivel.has_method("trenes_bosques_en_cola") else 0
	var tren: Tren = nivel.call("agregar_tren_en_bosques") as Tren
	if tren != null:
		_registrar_tren(tren)
		return {"ok": true, "en_cola": false, "tren": tren.obtener_resumen_operativo(), "motivo": ""}
	var cola_despues: int = int(nivel.call("trenes_bosques_en_cola")) if nivel.has_method("trenes_bosques_en_cola") else cola_antes
	if cola_despues > cola_antes:
		return {"ok": true, "en_cola": true, "tren": {}, "motivo": "Tren agregado a la cola de despacho de Bosques."}
	return {"ok": false, "en_cola": false, "tren": {}, "motivo": "No hay un puesto de instancia disponible en Bosques."}


func seleccionar_tren(id_tren: int) -> bool:
	var tren: Tren = _trenes.get(id_tren) as Tren
	if tren == null or not is_instance_valid(tren) or tren.esta_eliminado():
		return false
	tren.seleccionado.emit()
	return true


func eliminar_tren(id_tren: int) -> bool:
	var tren: Tren = _trenes.get(id_tren) as Tren
	if tren == null or not is_instance_valid(tren) or tren.esta_eliminado():
		return false
	tren.eliminar()
	return true


func establecer_velocidad_simulacion(factor: float) -> bool:
	if not is_finite(factor) or factor < 0.0:
		return false
	if factor == _factor_velocidad_simulacion:
		return true
	if factor > 0.0:
		_factor_antes_de_pausa = factor
	_factor_velocidad_simulacion = factor
	Engine.time_scale = factor
	velocidad_simulacion_cambiada.emit(factor)
	return true


func pausar_simulacion() -> void:
	establecer_velocidad_simulacion(0.0)


func reanudar_simulacion() -> void:
	if esta_pausada():
		establecer_velocidad_simulacion(_factor_antes_de_pausa)


func obtener_velocidad_simulacion() -> float:
	return _factor_velocidad_simulacion


func esta_pausada() -> bool:
	return _factor_velocidad_simulacion == 0.0


## Habilita o bloquea el ingreso de pasajeros en todas las plataformas del nombre indicado.
func establecer_ingreso_pasajeros_estacion(nombre_estacion: String, habilitado: bool) -> bool:
	if nombre_estacion.strip_edges().is_empty():
		return false
	var encontrada: bool = false
	for estacion: Estacion in _estaciones.values():
		if not is_instance_valid(estacion) or estacion.nombre_estacion != nombre_estacion:
			continue
		estacion.establecer_ingreso_pasajeros_habilitado(habilitado)
		encontrada = true
	return encontrada


func detener_tren_temporalmente(id_tren: int, motivo: String, duracion_s: float) -> bool:
	var tren: Tren = _trenes.get(id_tren) as Tren
	return tren.detener_por_evento(motivo, duracion_s) if is_instance_valid(tren) else false


## Detiene un tren por avería conservando sus reservas hasta que el gestor
## finalice el incidente. El tren no se reanuda por temporizador propio.
func detener_tren_por_averia(id_tren: int, motivo: String) -> bool:
	var tren: Tren = _trenes.get(id_tren) as Tren
	return tren.detener_por_averia(motivo) if is_instance_valid(tren) else false


func reanudar_tren(id_tren: int) -> bool:
	var tren: Tren = _trenes.get(id_tren) as Tren
	return tren.reanudar_por_evento() if is_instance_valid(tren) else false


func finalizar_tren_incompleto(id_tren: int, motivo: String) -> bool:
	var tren: Tren = _trenes.get(id_tren) as Tren
	return tren.finalizar_incompleto(motivo) if is_instance_valid(tren) else false


func _on_evento_temporal_finalizado(_datos: Dictionary, id: int) -> void:
	tren_reanudo.emit(id)


func _on_tren_estado(datos_tren: Dictionary, _id: int) -> void:
	_publicar_actualizacion(datos_tren)


func _on_tren_llego_estacion(datos_tren: Dictionary, datos_estacion: Dictionary, id: int) -> void:
	if bool(datos_estacion.get("es_terminal", false)) and not bool(datos_estacion.get("inicio_servicio", false)):
		_recorridos_finalizados_total += 1
	_publicar_actualizacion(datos_tren)
	tren_llego_estacion.emit(id, datos_estacion)


func _on_tren_salio_estacion(datos_tren: Dictionary, _datos_estacion: Dictionary, id: int) -> void:
	_publicar_actualizacion(datos_tren)
	tren_reanudo.emit(id)


func _on_tren_finalizado(datos_tren: Dictionary, id: int) -> void:
	_publicar_actualizacion(datos_tren)
	tren_finalizo.emit(id, str(datos_tren.get("resultado", "finalizado")))


func _on_tren_incompleto(datos_tren: Dictionary, _motivo: String, id: int) -> void:
	_publicar_actualizacion(datos_tren)
	tren_finalizo.emit(id, str(datos_tren.get("resultado", "incompleto")))


func _on_tren_pasajeros_cambiados(_actuales: int, _capacidad: int, _suben: int, _bajan: int, _intercambio: bool, id: int) -> void:
	_publicar_actualizacion(obtener_tren(id))


func _on_tren_ruta_actualizada(_destino: String, _distancia: float, id: int) -> void:
	_publicar_actualizacion(obtener_tren(id))


func _on_tren_eliminado(id: int) -> void:
	if not _trenes.has(id):
		return
	_trenes.erase(id)
	tren_eliminado.emit(id)
	_emitir_resumen_global()


func _on_estacion_pasajeros_actualizados(estacion: Estacion, id: String) -> void:
	if estacion == null or not is_instance_valid(estacion):
		return
	_estaciones[id] = estacion
	estacion_actualizada.emit(_resumen_estacion(estacion))
	_emitir_resumen_global()


func _on_estacion_ingreso_pasajeros_cambiado(_habilitado: bool, id: String) -> void:
	var estacion: Estacion = _estaciones.get(id) as Estacion
	if estacion == null or not is_instance_valid(estacion):
		return
	estacion_actualizada.emit(_resumen_estacion(estacion))
	_emitir_resumen_global()


func _publicar_actualizacion(datos_tren: Dictionary) -> void:
	if datos_tren.is_empty():
		return
	if _metricas != null:
		_metricas.actualizar_datos(datos_tren)
		datos_tren.merge(_metricas.obtener_puntualidad(int(datos_tren.get("id", 0))), true)
	_actualizar_concurrencia()
	tren_actualizado.emit(datos_tren)
	_emitir_resumen_global()


func _actualizar_concurrencia() -> void:
	var activos: int = 0
	for tren: Dictionary in obtener_trenes():
		if int(tren.get("estado", -1)) not in [Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, Tren.EstadoOperacion.FINALIZADO_IDA_VUELTA, Tren.EstadoOperacion.INCOMPLETO]:
			activos += 1
	_concurrencia_maxima = maxi(_concurrencia_maxima, activos)


func _emitir_resumen_global() -> void:
	resumen_global_actualizado.emit(obtener_resumen_global())


func _limpiar_referencias_inactivas() -> void:
	var para_borrar: Array[int] = []
	for id: int in _trenes:
		var tren: Tren = _trenes[id] as Tren
		if tren == null or not is_instance_valid(tren):
			para_borrar.append(id)
	for id: int in para_borrar:
		_trenes.erase(id)
