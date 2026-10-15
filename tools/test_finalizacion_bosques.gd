extends SceneTree
## Verifica el cierre físico de una formación al terminar el servicio en Bosques.
## Uso: godot --headless --path . -s res://tools/test_finalizacion_bosques.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(0.2).timeout
	var tren: Tren = raiz.find_child("TrenCSR", true, false) as Tren
	var red: TrackNetwork = raiz.find_child("TrackNetwork", true, false) as TrackNetwork
	var servicio: ServicioFerroviario = raiz.find_child("ServicioConstitucionBosques", true, false) as ServicioFerroviario
	assert(tren != null and red != null and servicio != null, "La escena debe resolver tren, red y servicio")

	tren.set_process(false)
	var finalizaciones: Array[int] = []
	var cambios_final: Array[int] = []
	tren.recorrido_finalizado.connect(func(_datos: Dictionary) -> void: finalizaciones.append(1))
	tren.estado_operacion_cambiado.connect(func(datos: Dictionary) -> void:
		if int(datos.get("estado", -1)) == Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES:
			cambios_final.append(1)
	)
	var bosques: Estacion = servicio.obtener_parada(servicio.cantidad_paradas() - 1) as Estacion
	assert(bosques != null, "Bosques debe existir")
	tren.pasajeros_actuales = 24
	tren.capacidad_pasajeros = 80
	tren.cantidad_pasajeros_por_tanda = 80
	tren.set("_espera", 0.2)
	await tren._procesar_pasajeros_parada(bosques, true, 1.0, 0.2)
	assert(tren.pasajeros_actuales == 0, "La terminal debe desembarcar a todos los pasajeros")

	# Reservar un recurso conocido y comprobar que el cierre lo libera.
	var segmento: String = str(tren.traza.name)
	assert(red.solicitar_reserva_seccion(tren.get_instance_id(), segmento, 0, 0.0, 1.0), "La reserva de prueba debe concederse")
	tren.set("_indice_servicio", servicio.cantidad_paradas() - 1)
	tren.set("_direccion_servicio", 1)
	tren.call("_finalizar_servicio_en_terminal")

	assert(tren.servicio_finalizado(), "Bosques debe cerrar el servicio")
	assert(tren.esta_detenido(), "La formación finalizada queda detenida")
	assert(not tren.visible, "La formación finalizada queda oculta")
	assert(is_zero_approx(tren.velocidad_actual()), "La velocidad final debe ser cero")
	assert(is_zero_approx(tren.distancia_a_proxima_estacion()), "La distancia publicada en Bosques debe ser cero")
	assert(tren.obtener_estado_operacion() == Tren.EstadoOperacion.FINALIZADO_EN_BOSQUES, "Bosques debe publicar su estado final")
	var controlador: SimulacionController = raiz.get_node("SimulacionController")
	assert(not controlador.detener_tren_temporalmente(tren.obtener_id_operativo(), "Evento", 1.0))
	assert(not controlador.reanudar_tren(tren.obtener_id_operativo()))
	assert(not controlador.finalizar_tren_incompleto(tren.obtener_id_operativo(), "Evento"))
	assert(finalizaciones.size() == 1, "La finalización debe emitirse una sola vez")
	assert(cambios_final.size() == 1, "La transición a Bosques finalizado debe emitirse una sola vez")
	tren.call("_finalizar_servicio_en_terminal")
	assert(finalizaciones.size() == 1, "Un tren ya finalizado no debe emitir la finalización otra vez")
	assert(cambios_final.size() == 1, "Un tren ya finalizado no debe duplicar su cambio de estado")
	assert(not red.segmento_reservado(segmento), "La terminal no debe conservar reservas")
	for coche_raw: Node in tren.get_children():
		var coche := coche_raw as Node3D
		if coche == null:
			continue
		var selector := coche.get_node_or_null("SelectorClic") as Area3D
		if selector != null:
			assert(not selector.input_ray_pickable, "Los coches finales no deben poder seleccionarse")
	print("OK: finalización en Bosques libera recursos y oculta la formación")
	quit()
