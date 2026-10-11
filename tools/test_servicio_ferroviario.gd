extends SceneTree
## Verifica las 16 paradas físicas y los 15 enlaces topológicos del servicio.
## Uso: godot --headless --path . -s res://tools/test_servicio_ferroviario.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"
const ITINERARIO := [
	"Plaza Constitución", "Hipólito Yrigoyen", "Darío Santillán y Maximiliano Kosteki",
	"Gerli", "Lanús", "Remedios de Escalada", "Banfield", "Lomas de Zamora",
	"Temperley", "José Mármol", "Rafael Calzada", "Claypole", "Ing. Dante Ardigó",
	"Florencio Varela", "Estanislao S. Zeballos", "Bosques",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var escena: PackedScene = load(ESCENA)
	assert(escena != null, "No se pudo cargar ramal_roca_main.tscn")
	var raiz: Node = escena.instantiate()
	root.add_child(raiz)
	# La escena editada puede usar una espera inicial de un segundo. Inspeccionar
	# el origen antes de ese límite evita depender del orden exacto de frames.
	await create_timer(0.2).timeout

	var servicio: ServicioFerroviario = raiz.find_child("ServicioConstitucionBosques", true, false) as ServicioFerroviario
	assert(servicio != null, "No existe ServicioConstitucionBosques")
	assert(servicio.cantidad_paradas() == ITINERARIO.size(), "El servicio debe contener las 16 estaciones físicas")
	assert(servicio.solo_ida, "Constitución–Bosques debe configurarse como servicio de ida")
	assert(servicio.finaliza_en(ITINERARIO.size() - 1, 1), "Bosques debe ser el final operativo del servicio")
	assert(not servicio.finaliza_en(0, 1), "Constitución no debe finalizar el servicio de ida")
	for indice: int in ITINERARIO.size():
		var parada: Node = servicio.obtener_parada(indice)
		assert(parada != null, "La parada %d debe resolver su NodePath" % indice)
		assert(str(parada.get("nombre_estacion")) == ITINERARIO[indice], "Orden incorrecto en %d" % indice)
		assert(parada.get("traza") is Path3D, "%s debe estar anclada a un Path3D" % ITINERARIO[indice])

	var red: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	assert(red != null, "No existe TrackNetwork")
	var validacion_servicio: Dictionary = servicio.validar_configuracion_ida(red)
	assert(bool(validacion_servicio.get("ok", false)), "La geometría editada debe conservar las 16 paradas de ida: %s" % str(validacion_servicio.get("errores", [])))
	var tren: Tren = raiz.find_child("TrenCSR", true, false) as Tren
	assert(tren != null, "No existe TrenCSR")
	assert(tren.esta_detenido(), "El tren debe iniciar detenido en Plaza Constitución")
	assert(tren.proxima_estacion_nombre() == "Plaza Constitución", "La parada inicial debe ser Plaza Constitución")
	assert(tren.traza != null, "El tren inicial debe conservar una vía de salida configurada")
	assert(tren.itinerario_estaciones() == ITINERARIO, "El HUD debe recibir el itinerario completo al inicio")
	assert(tren.capacidad_pasajeros > 0, "Las formaciones de Constitución deben admitir pasajeros")
	assert(tren.cantidad_pasajeros_por_tanda > 0, "Las formaciones deben tener intercambio de pasajeros habilitado")
	var estacion_prueba: Estacion = servicio.obtener_parada(0) as Estacion
	assert(estacion_prueba != null, "La estación de prueba debe ser una Estacion")
	# El intercambio también debe ocurrir en la parada de origen, no recién en
	# Yrigoyen. Se inyecta demanda sólo en memoria para no alterar la escena.
	estacion_prueba.pasajeros_esperando = 20
	await create_timer(0.35).timeout
	assert(tren.pasajeros_actuales > 0, "El tren debe embarcar pasajeros durante la espera en Constitución")
	var candidatos: Array[Dictionary] = estacion_prueba.obtener_puntos_parada_multivia(red, true)
	assert(not candidatos.is_empty(), "La estación debe resolver al menos una vía de parada")
	for candidato: Dictionary in candidatos:
		assert(candidato.has("offset") and candidato.has("punto_global"), "Cada vía debe tener una proyección métrica del poste")
	for indice: int in ITINERARIO.size() - 1:
		var origen: Node = servicio.obtener_parada(indice)
		var destino: Node = servicio.obtener_parada(indice + 1)
		var traza_origen := origen.get("traza") as Path3D
		var traza_destino := destino.get("traza") as Path3D
		var offset_origen: float = origen.obtener_offset_parada(true)
		var offset_destino: float = destino.obtener_offset_parada(true)
		var ruta: Dictionary = red.planificar_ruta(traza_origen.name, offset_origen, false, traza_destino.name, offset_destino)
		var alternativa: Dictionary = red.planificar_ruta(traza_origen.name, offset_origen, true, traza_destino.name, offset_destino)
		assert(bool(ruta.get("ok", false)) or bool(alternativa.get("ok", false)), "No hay ruta transitable: %s → %s" % [ITINERARIO[indice], ITINERARIO[indice + 1]])
		if ITINERARIO[indice] == "Lomas de Zamora":
			assert(bool(ruta.get("ok", false)), "Lomas → Temperley debe existir en sentido de ida, sin fallback inverso")
			var usados: Dictionary = {}
			var pasos: Array = ruta.get("pasos", []) as Array
			for paso_raw: Variant in pasos:
				var paso: Dictionary = paso_raw as Dictionary
				var sid: String = str(paso.get("segmento", ""))
				assert(not usados.has(sid), "Lomas → Temperley no puede repetir %s" % sid)
				usados[sid] = true
		var override_invalido: Array[String] = [traza_origen.name, "segmento_inexistente_prueba"]
		var ruta_invalida: Dictionary = red.planificar_ruta(traza_origen.name, offset_origen, false, traza_destino.name, offset_destino, override_invalido)
		assert(not bool(ruta_invalida.get("ok", false)), "Un override con un segmento inexistente debe rechazarse")
		assert(str(ruta_invalida.get("motivo", "")).contains("inexistente"), "El override inválido debe informar el motivo")

	# Regresión de marcha directa: desde ambos sentidos locales, un poste de
	# Lomas que está delante de la cabecera debe resolverse dentro del corredor
	# inmediato y sin consumir una aguja posterior.
	var lomas: Estacion = servicio.obtener_parada(7) as Estacion
	var candidatos_lomas: Array[Dictionary] = lomas.obtener_puntos_parada_multivia(red, true)
	var candidato_ancla: Dictionary = {}
	for candidato_lomas: Dictionary in candidatos_lomas:
		if candidato_lomas.get("traza") == lomas.traza:
			candidato_ancla = candidato_lomas
			break
	if candidato_ancla.is_empty() and not candidatos_lomas.is_empty():
		candidato_ancla = candidatos_lomas[0]
	assert(not candidato_ancla.is_empty(), "Lomas debe tener una proyección de parada")
	var traza_lomas: Path3D = candidato_ancla.get("traza") as Path3D
	var offset_lomas: float = float(candidato_ancla.get("offset", 0.0))
	var largo_lomas: float = traza_lomas.curve.get_baked_length()
	for inverso_local: bool in [false, true]:
		var inicio: float = minf(offset_lomas - 5.0, largo_lomas - 0.1) if not inverso_local else maxf(offset_lomas + 5.0, 0.1)
		if (not inverso_local and inicio < 0.0) or (inverso_local and inicio > largo_lomas):
			continue
		var corredor_lomas: Array[Dictionary] = red.obtener_corredor_inmediato(traza_lomas.name, inicio, inverso_local)
		var solo_candidato: Array[Dictionary] = []
		solo_candidato.append(candidato_ancla)
		var directos: Array = tren.call("_candidatos_adelante_en_corredor", solo_candidato, corredor_lomas) as Array
		assert(not directos.is_empty(), "El poste de Lomas debe quedar delante en su corredor local")
		var ruta_directa: Dictionary = tren.call("_ruta_directa_corredor", directos[0], corredor_lomas, inverso_local) as Dictionary
		assert(bool(ruta_directa.get("ok", false)), "La parada directa de Lomas debe construir ruta")
		assert(int(ruta_directa.get("cambios_aguja", -1)) == 0, "Lomas debe detenerse antes de una aguja posterior")

	var trenes: Array[Node] = get_nodes_in_group("trenes")
	assert(trenes.size() == 4, "La escena debe iniciar con cuatro trenes")
	var vias_iniciales: Dictionary = {}
	for tren_raw: Node in trenes:
		var tren_flotilla: Tren = tren_raw as Tren
		assert(tren_flotilla != null and tren_flotilla.traza != null, "Cada tren inicial debe estar sobre una vía")
		assert(not vias_iniciales.has(tren_flotilla.traza.name), "Los cuatro trenes deben ocupar vías distintas de Constitución")
		vias_iniciales[tren_flotilla.traza.name] = true
	assert(vias_iniciales.size() == 4, "Deben resolverse cuatro vías de salida distintas")
	var demoras_salida: Dictionary = {}
	for tren_raw: Node in trenes:
		var demora: float = (tren_raw as Tren).demora_salida_inicial
		demoras_salida[demora] = true
	assert(demoras_salida.size() > 1, "Los trenes deben tener demoras de salida individuales")
	var quinto: Variant = raiz.call("agregar_tren")
	assert(quinto == null, "El quinto tren debe esperar cuando las cuatro vías editables estén ocupadas")
	assert(int(raiz.call("trenes_en_cola")) == 1, "El HUD debe poder consultar el tren en cola")

	# Una sección ocupada conserva la cola FIFO: el segundo tren que espera
	# obtiene el recurso antes que un tercero aunque ambos reintenten luego.
	var segmento_prueba: String = ""
	for id_segmento: String in red.paths.keys():
		if not red.segmento_reservado(id_segmento):
			segmento_prueba = id_segmento
			break
	assert(not segmento_prueba.is_empty(), "Debe existir un segmento libre para probar reservas")
	assert(red.solicitar_reserva_seccion(900001, segmento_prueba, 0, 0.0, 30.0), "El primer tren debe reservar la sección")
	assert(not red.solicitar_reserva_seccion(900002, segmento_prueba, 0, 0.0, 30.0), "El segundo tren debe esperar")
	assert(not red.solicitar_reserva_seccion(900003, segmento_prueba, 0, 0.0, 30.0), "El tercero debe esperar detrás del segundo")
	red.liberar_reservas_tren(900001)
	assert(red.solicitar_reserva_seccion(900002, segmento_prueba, 0, 0.0, 30.0), "La solicitud FIFO más antigua debe pasar primero")
	assert(not red.solicitar_reserva_seccion(900003, segmento_prueba, 0, 0.0, 30.0), "El tercero no debe adelantar al segundo")
	red.liberar_reservas_tren(900002)
	assert(red.solicitar_reserva_seccion(900003, segmento_prueba, 0, 0.0, 30.0), "El tercero debe pasar al liberarse el recurso")
	red.liberar_reservas_tren(900003)
	# Tras la espera inicial, Plaza queda atendida y no vuelve a ser el destino.
	await create_timer(3.5).timeout
	assert(not tren.esta_detenido(), "El tren debe reanudar la marcha después de la espera en Plaza")
	assert(tren.proxima_estacion_nombre() == "Hipólito Yrigoyen", "La primera salida debe dirigirse a Yrigoyen")
	assert(tren.distancia_a_proxima_estacion() >= 0.0, "El tren debe publicar distancia a su próxima parada")
	assert(tren.itinerario_estaciones().front() == "Hipólito Yrigoyen", "El HUD debe descartar Plaza tras atenderla")
	print("OK: servicio Constitución → Bosques validado (%d paradas, %d enlaces)" % [ITINERARIO.size(), ITINERARIO.size() - 1])
	quit()
