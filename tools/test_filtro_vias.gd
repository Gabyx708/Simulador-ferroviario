extends SceneTree
## Prueba unitaria e integradora para:
## 1. Identificación y filtrado de vías IDA (0), VUELTA (1) y USO COMÚN (2).
## 2. Ruteo inteligente por sentido (IDA usa IDA + USO COMÚN; VUELTA usa VUELTA + USO COMÚN).
## 3. Conmutación inteligente de switches según el sentido del tren.
## 4. Detección de conflicto / cesión de paso entre trenes.
## 5. Maniobra de apartar de vía tras 30s de obstrucción y retorno posterior.

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== INICIANDO TEST FILTRO VIAS Y COMPORTAMIENTO INTELIGENTE ===")
	var escena: PackedScene = load(ESCENA)
	assert(escena != null, "No se pudo cargar ramal_roca_main.tscn")
	var raiz: Node = escena.instantiate()
	root.add_child(raiz)
	await create_timer(0.1).timeout

	var red: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	assert(red != null, "No existe TrackNetwork")

	# -------------------------------------------------------------
	# 1. Comprobación de segmentos por sentido en la red cargada
	# -------------------------------------------------------------
	var count_ida: int = 0
	var count_vuelta: int = 0
	var count_comun: int = 0

	for seg_id: String in red.paths.keys():
		var path: Path3D = red.paths[seg_id] as Path3D
		var uso: int = int(path.get("uso_direccion")) if "uso_direccion" in path else 0
		match uso:
			0:
				count_ida += 1
				assert(red.segmento_permite_sentido(seg_id, true) == true, "Vía IDA debe permitir sentido IDA")
				assert(red.segmento_permite_sentido(seg_id, false) == false, "Vía IDA NO debe permitir sentido VUELTA")
			1:
				count_vuelta += 1
				assert(red.segmento_permite_sentido(seg_id, true) == false, "Vía VUELTA NO debe permitir sentido IDA")
				assert(red.segmento_permite_sentido(seg_id, false) == true, "Vía VUELTA debe permitir sentido VUELTA")
			2:
				count_comun += 1
				assert(red.segmento_permite_sentido(seg_id, true) == true, "Vía USO COMUN debe permitir sentido IDA")
				assert(red.segmento_permite_sentido(seg_id, false) == true, "Vía USO COMUN debe permitir sentido VUELTA")

	print("Estadísticas de vías en red:")
	print(" - Vías IDA: %d" % count_ida)
	print(" - Vías VUELTA: %d" % count_vuelta)
	print(" - Vías USO COMÚN: %d" % count_comun)
	assert(count_ida > 0, "Deben existir vías de IDA")
	assert(count_vuelta > 0, "Deben existir vías de VUELTA")
	assert(count_comun > 0, "Deben existir vías de USO COMUN")

	# -------------------------------------------------------------
	# 2. Planificación de ruta respetando el sentido
	# -------------------------------------------------------------
	var servicio: ServicioFerroviario = raiz.find_child("ServicioConstitucionBosques", true, false) as ServicioFerroviario
	assert(servicio != null, "No existe ServicioConstitucionBosques")
	var tren: Tren = raiz.find_child("TrenCSR", true, false) as Tren
	assert(tren != null, "No existe TrenCSR")
	var traza_salida_ida: Path3D = tren.traza
	var p1: Node = servicio.obtener_parada(1)
	var traza_p1: Path3D = p1.get("traza") as Path3D
	assert(traza_p1 != null)

	var ruta_ida: Dictionary = red.planificar_ruta(traza_salida_ida.name, 10.0, false, traza_p1.name, 50.0, [], {}, true)
	assert(bool(ruta_ida.get("ok", false)), "La planificación de IDA debe tener éxito")
	var segs_ida: Array = ruta_ida.get("segmentos", [])
	for s_id: Variant in segs_ida:
		assert(red.segmento_permite_sentido(str(s_id), true), "Todos los tramos de la ruta IDA deben permitir IDA o USO COMUN: %s falló" % str(s_id))
	assert(segs_ida.size() > 2, "La ruta de prueba debe tener un tramo intermedio")
	var intermedio: EditableTrackSegment = red.get_segment_path(str(segs_ida[segs_ida.size() / 2])) as EditableTrackSegment
	assert(intermedio != null)
	var uso_original: int = intermedio.uso_direccion
	intermedio.uso_direccion = EditableTrackSegment.UsoDireccion.VUELTA
	var ruta_prohibida: Dictionary = red.planificar_ruta(traza_salida_ida.name, 10.0, false, traza_p1.name, 50.0, [], {}, true)
	if bool(ruta_prohibida.get("ok", false)):
		assert(not (ruta_prohibida.get("segmentos", []) as Array).has(intermedio.name), "El planificador no puede atravesar una vía VUELTA en IDA")
	var override_prohibido: Array[String] = []
	for sid: Variant in segs_ida:
		override_prohibido.append(str(sid))
	assert(not bool(red.planificar_ruta(traza_salida_ida.name, 10.0, false, traza_p1.name, 50.0, override_prohibido, {}, true).get("ok", false)), "Un override no puede saltar la restricción de sentido")
	intermedio.uso_direccion = uso_original

	print("OK: Planificación de ruta respeta sentidos estrictamente (IDA: %d tramos permitidos)." % segs_ida.size())
	var claypole: Node = servicio.obtener_parada(11)
	var candidatos_claypole: Array[Dictionary] = tren._candidatos_estacion_servicio(claypole, red, true)
	var ruta_claypole_valida: bool = false
	for candidato_claypole: Dictionary in candidatos_claypole:
		var segmento_claypole: String = str(candidato_claypole.get("segmento", ""))
		if bool(ruta_desde_calzada.get("ok", false)):
			ruta_claypole_valida = true
			for sid: Variant in ruta_desde_calzada.get("segmentos", []):
				assert(red.segmento_permite_sentido(str(sid), true), "El enlace Calzada-Claypole debe usar sólo vías IDA o comunes")
			break
	assert(ruta_claypole_valida, "Debe existir una ruta IDA válida entre Rafael Calzada y Claypole")
	var origenes_lomas_ida: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(7), red, true)
	var destinos_temperley_ida: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(8), red, true)
	assert(origenes_lomas_ida.size() == 2 and destinos_temperley_ida.size() == 1)
	var sin_override_lomas: Array[String] = []
	var indice_previo: int = tren._indice_servicio
	tren._indice_servicio = 7
	var continuidad_lomas: Array[Dictionary] = tren._candidatos_con_continuidad_terminal(red, origenes_lomas_ida, "seg_143", 1.0, false, sin_override_lomas)
	assert(continuidad_lomas.size() == 1 and str(continuidad_lomas[0].get("segmento", "")) == "seg_541", "Lomas debe descartar el ramal IDA sin continuidad hacia Temperley")
	var candidatos_yrigoyen_ida: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(1), red, true)
	tren._indice_servicio = 1
	var continuidad_yrigoyen: Array[Dictionary] = tren._candidatos_con_continuidad_terminal(red, candidatos_yrigoyen_ida, "seg_591", 1.0, false, sin_override_lomas)
	assert(continuidad_yrigoyen.size() == 1 and str(continuidad_yrigoyen[0].get("segmento", "")) == "seg_441", "El tren debe escoger en Yrigoyen la vía que llega a Bosques")
	var velocidad_previa: float = tren._vel
	tren._vel = 0.0
	var continuidad_reinicio: Array[Dictionary] = tren._candidatos_con_continuidad_terminal(red, candidatos_yrigoyen_ida, "seg_587", 100.0, true, sin_override_lomas)
	assert(continuidad_reinicio.size() == 1 and str(continuidad_reinicio[0].get("segmento", "")) == "seg_441", "La nueva IDA debe poder invertir la orientación local del Path3D en Constitución")
	tren._vel = velocidad_previa
	tren._indice_servicio = indice_previo
	var candidatos_bosques_vuelta: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(15), red, false)
	var maniobra_bosques_valida: bool = false
	for candidato_bosques: Dictionary in candidatos_bosques_vuelta:
		var destino_bosques: String = str(candidato_bosques.get("segmento", ""))
		for invertido: bool in [false, true]:
			var maniobra: Dictionary = red.planificar_ruta("seg_617", 100.0, invertido, destino_bosques, float(candidato_bosques.get("offset", 0.0)), [], {}, false, true)
			if bool(maniobra.get("ok", false)):
				maniobra_bosques_valida = true
				for paso: Variant in (maniobra.get("segmentos", []) as Array).slice(1):
					assert(red.segmento_permite_sentido(str(paso), false), "La maniobra a la vía de regreso sólo puede ocupar vías VUELTA o comunes")
				break
		if maniobra_bosques_valida:
			break
	assert(maniobra_bosques_valida, "Bosques necesita conexión física a un andén de VUELTA")
	var candidatos_const_ida: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(0), red, true)
	var maniobra_const_valida: bool = false
	for c_const: Dictionary in candidatos_const_ida:
		for inv_const: bool in [false, true]:
			var ruta_const: Dictionary = red.planificar_ruta("seg_468", 100.0, inv_const, str(c_const.get("segmento", "")), float(c_const.get("offset", 0.0)))
			if bool(ruta_const.get("ok", false)):
				maniobra_const_valida = true
				assert(red.segmento_permite_sentido(str(c_const.get("segmento", "")), true), "La maniobra debe terminar en vía de IDA o común")
				break
		if maniobra_const_valida:
			break
	assert(maniobra_const_valida, "Constitución necesita conexión física entre la llegada y un andén de IDA")
	var nueva_ida_posible: bool = false
	for c_const: Dictionary in candidatos_const_ida:
		for c_yr: Dictionary in tren._candidatos_estacion_servicio(servicio.obtener_parada(1), red, true):
			for inv_c: bool in [false, true]:
				var salida_const: Dictionary = red.planificar_ruta(str(c_const.get("segmento", "")), float(c_const.get("offset", 0.0)), inv_c, str(c_yr.get("segmento", "")), float(c_yr.get("offset", 0.0)), [], {}, true)
				if bool(salida_const.get("ok", false)):
					nueva_ida_posible = true
	assert(nueva_ida_posible, "El andén de IDA en Constitución debe enlazar con Yrigoyen")
	var candidatos_dario: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(2), red, false)
	var candidatos_gerli: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(3), red, false)
	assert(not candidatos_gerli.is_empty() and not candidatos_dario.is_empty())
	var ruta_gerli_dario: Dictionary = red.planificar_ruta(str(candidatos_gerli[0].get("segmento", "")), float(candidatos_gerli[0].get("offset", 0.0)), false, str(candidatos_dario[0].get("segmento", "")), float(candidatos_dario[0].get("offset", 0.0)), [], {}, false)
	assert(bool(ruta_gerli_dario.get("ok", false)), "Gerli debe permitir una salida VUELTA desde el extremo correcto")
	for indice_vuelta: int in range(15, 0, -1):
		var origenes_vuelta: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(indice_vuelta), red, false)
		var destinos_vuelta: Array[Dictionary] = tren._candidatos_estacion_servicio(servicio.obtener_parada(indice_vuelta - 1), red, false)
		var conexion_vuelta: bool = false
		for origen_vuelta: Dictionary in origenes_vuelta:
			for destino_vuelta: Dictionary in destinos_vuelta:
				for invertido_vuelta: bool in [false, true]:
					var ruta_vuelta: Dictionary = red.planificar_ruta(str(origen_vuelta.get("segmento", "")), float(origen_vuelta.get("offset", 0.0)), invertido_vuelta, str(destino_vuelta.get("segmento", "")), float(destino_vuelta.get("offset", 0.0)), [], {}, false)
					if bool(ruta_vuelta.get("ok", false)):
						conexion_vuelta = true
						break
				if conexion_vuelta:
					break
			if conexion_vuelta:
				break
		assert(conexion_vuelta, "Falta continuidad de VUELTA entre estaciones %d y %d" % [indice_vuelta, indice_vuelta - 1])

	# -------------------------------------------------------------
	# 3. Comprobación de get_switch_target con sentido (desvíos de punta)
	# -------------------------------------------------------------
	var switches_probados: int = 0
	for node_id: int in red.aparatos_de_via.keys():
		var ap: BaseTurnout = red.aparatos_de_via[node_id] as BaseTurnout
		if ap == null or ap.via_comun_id.is_empty() or ap.via_directa_id.is_empty() or ap.via_desviada_id.is_empty():
			continue
		
		# Probar entrada de punta desde la vía común hacia las dos ramas
		var opciones: Array[Dictionary] = [
			{"segment_id": ap.via_directa_id},
			{"segment_id": ap.via_desviada_id}
		]
		
		var target_ida: Dictionary = red.get_switch_target(node_id, opciones, ap.via_comun_id, true)
		var target_vuelta: Dictionary = red.get_switch_target(node_id, opciones, ap.via_comun_id, false)
		
		var sid_ida: String = str(target_ida.get("segment_id", ""))
		var sid_vuelta: String = str(target_vuelta.get("segment_id", ""))
		
		if red.segmento_permite_sentido(ap.via_directa_id, true) or red.segmento_permite_sentido(ap.via_desviada_id, true):
			assert(red.segmento_permite_sentido(sid_ida, true), "Switch %d debe elegir rama de IDA" % node_id)
		if red.segmento_permite_sentido(ap.via_directa_id, false) or red.segmento_permite_sentido(ap.via_desviada_id, false):
			assert(red.segmento_permite_sentido(sid_vuelta, false), "Switch %d debe elegir rama de VUELTA" % node_id)
			
		switches_probados += 1
		if switches_probados >= 30:
			break

	print("OK: Conmutación de switches inteligente según sentido verificada (%d switches evaluados)." % switches_probados)
	var switch_conmutado_por_tren: bool = false
	var tren_prueba_id: int = 9000001
	for node_id: int in red.aparatos_de_via.keys():
		var aparato_prueba: BaseTurnout = red.aparatos_de_via[node_id] as BaseTurnout
		if aparato_prueba == null or aparato_prueba.via_directa_id.is_empty() or not red.segmento_permite_sentido(aparato_prueba.via_directa_id, true):
			continue
		if not red.solicitar_reserva_seccion(tren_prueba_id, aparato_prueba.via_directa_id, node_id, 0.0, 100.0):
			red.liberar_reservas_tren(tren_prueba_id)
			continue
		red.set_switch_target(node_id, aparato_prueba.via_directa_id, tren_prueba_id)
		assert(str(red.switch_states.get(node_id, "")) == aparato_prueba.via_directa_id, "La aguja reservada debe conmutar a la vía elegida")
		red.liberar_reservas_tren(tren_prueba_id)
		switch_conmutado_por_tren = true
		break
	assert(switch_conmutado_por_tren, "Debe poder reservarse y conmutarse al menos una aguja")
	var solo_vuelta: String = ""
	for sid: String in red.paths.keys():
		if not red.segmento_permite_sentido(sid, true):
			solo_vuelta = sid
			break
	assert(not solo_vuelta.is_empty())
	var opciones_prohibidas: Array[Dictionary] = [{"segment_id": solo_vuelta}]
	assert(red.get_switch_target(0, opciones_prohibidas, "", true).is_empty(), "Sin rama compatible la aguja no debe devolver una vía prohibida")

	# -------------------------------------------------------------
	# 4. Prueba de apartar de vía y retorno
	# -------------------------------------------------------------
	tren = raiz.find_child("TrenCSR", true, false) as Tren
	assert(tren != null, "No existe TrenCSR")
	
	# Verificar métodos de tren
	assert(tren.has_method("apartar_de_via_para_ceder_paso"), "Tren debe poseer método apartar_de_via_para_ceder_paso")
	assert(tren.has_method("es_sentido_ida"), "Tren debe poseer método es_sentido_ida")

	print("Comprobando mecánica de apartar de vía (desplazamiento lateral)...")
	# Simular llamada de ceder el paso
	tren.apartar_de_via_para_ceder_paso(null)
	assert(tren.get("_apartado_de_via") == true, "Tren debe marcar _apartado_de_via = true")
	assert(tren.get("_desplazamiento_lateral_objetivo") > 4.0, "Objetivo lateral debe ser mayor a 4m (despeje de gálibo)")
	
	# Simular un paso de proceso para desplazamiento lateral
	tren._process(0.5)
	var desp_actual: float = float(tren.get("_desplazamiento_lateral_actual"))
	assert(desp_actual > 0.0, "El tren debe comenzar a desplazarse lateralmente: actual = %f" % desp_actual)

	# Simular que el tren que pasaba ya pasó y el tren retorna a la vía
	tren._desplazamiento_lateral_objetivo = 0.0
	tren._desplazamiento_lateral_actual = 0.02
	tren._procesar_espera_y_retorno_apartado(0.1)
	assert(tren.get("_apartado_de_via") == false, "Tren debe reincorporarse a la vía")
	assert(tren.get("_desplazamiento_lateral_actual") == 0.0, "Desplazamiento lateral debe ser 0 al reincorporarse")

	print("OK: Mecánica de apartado lateral y retorno completada con éxito.")

	# El umbral de 30 s usa reloj real, aunque la simulación avance varios segundos.
	var obstructor: Tren = null
	for nodo_tren: Node in get_nodes_in_group("trenes"):
		var candidato_tren: Tren = nodo_tren as Tren
		if candidato_tren != null and candidato_tren != tren:
			if obstructor == null:
				obstructor = candidato_tren
			else:
				candidato_tren._apartado_de_via = true
				candidato_tren._desplazamiento_lateral_actual = 4.8
	assert(obstructor != null)
	var traza_prueba: Path3D = red.get_segment_path("seg_690")
	assert(traza_prueba != null and traza_prueba.curve.get_baked_length() > 300.0)
	tren.traza = traza_prueba
	tren._avance = 100.0
	tren.invertir_sentido = false
	tren._detenido = false
	tren._vel = 0.0
	obstructor.traza = traza_prueba
	obstructor._avance = 110.0 + obstructor.obtener_largo_formacion()
	obstructor.invertir_sentido = false
	obstructor._vel = 0.0
	assert((tren._detectar_conflicto_proximo(0.0, red).get("tren") as Tren) == obstructor, "Debe detectar una formación delante en la misma vía")
	tren._inicio_espera_bloqueo_ms = Time.get_ticks_msec() - 29000
	tren._process(5.0)
	assert(not obstructor._apartado_de_via, "Cinco segundos de simulación no deben completar una espera de 30 s reales")
	tren._inicio_espera_bloqueo_ms = Time.get_ticks_msec() - 31000
	tren._process(0.1)
	assert(obstructor._apartado_de_via, "A los 30 s reales el tren detenido debe apartarse")
	obstructor._process(2.0)
	assert(obstructor._desplazamiento_lateral_objetivo > 4.0, "El tren apartado debe esperar hasta que pase la cola del otro tren")
	obstructor._apartado_de_via = false
	obstructor.traza = red.get_segment_path("seg_72")
	obstructor._avance = 10.0
	obstructor.apartar_de_via_para_ceder_paso(tren)
	assert(is_finite(obstructor._odometro_retorno_apartado) and obstructor._odometro_retorno_apartado > tren._odometro_ferroviario, "Un obstructor en la vía siguiente también debe poder regresar tras el paso")
	print("OK: Detección de obstrucción y umbral de 30 s reales verificados.")

	print("\n=== TODOS LOS TESTS COMPLETADOS SATISFACTORIAMENTE ===")
	quit(0)
