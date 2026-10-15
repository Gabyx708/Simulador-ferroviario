extends SceneTree
## Verifica que un override imposible en un servicio sólo ida inmoviliza el
## tren sin intentar buscar el poste o el sentido de vuelta.
## Uso: godot --headless --path . -s res://tools/test_ruta_invalida_ida.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await create_timer(0.2).timeout
	var tren: Tren = raiz.find_child("TrenCSR", true, false) as Tren
	var servicio: ServicioFerroviario = raiz.find_child("ServicioConstitucionBosques", true, false) as ServicioFerroviario
	assert(tren != null and servicio != null, "La escena debe resolver tren y servicio")

	# Congelar la marcha antes de cambiar sólo el override de la prueba.
	tren.set_process(false)
	var sentido_inicial: bool = tren.invertir_sentido
	servicio.overrides_json = '{"0>1": ["segmento_inexistente_prueba"]}'
	tren.set("_indice_servicio", 1)
	tren.set("_objetivo_servicio_resuelto", {})
	tren.set("_indice_objetivo_resuelto", -1)
	tren.set("_ruta_invalida", false)
	tren.set("_error_ruta_emitido", false)
	tren.set("_detenido", false)
	tren.call("_establecer_estado", Tren.EstadoOperacion.EN_MARCHA)
	var errores: Array[String] = []
	var incompletos: Array[String] = []
	var cambios_incompleto: Array[int] = []
	tren.ruta_error.connect(func(motivo: String) -> void: errores.append(motivo))
	tren.recorrido_incompleto.connect(func(_datos: Dictionary, motivo: String) -> void: incompletos.append(motivo))
	tren.estado_operacion_cambiado.connect(func(datos: Dictionary) -> void:
		if int(datos.get("estado", -1)) == Tren.EstadoOperacion.INCOMPLETO:
			cambios_incompleto.append(1)
	)
	# _actualizar_ruta_servicio ahora reintenta unas cuantas veces antes de
	# invalidar (una falla de ruteo real en producción suele ser una aguja
	# momentáneamente ocupada por otro tren, no una desconexión permanente --
	# ver docs/reporte_final.md). Para un override roto a propósito como este,
	# los reintentos nunca van a resolver nada: hay que agotarlos a mano
	# llamando la función varias veces, igual que haría _process() real.
	for _i: int in range(25):
		tren.call("_actualizar_ruta_servicio")
		if tren.ruta_invalida():
			break

	assert(tren.ruta_invalida(), "Un override imposible debe marcar ruta inválida (agotados los reintentos)")
	assert(tren.esta_detenido(), "Un override imposible debe inmovilizar el tren")
	assert(tren.proxima_estacion_nombre() == "Hipólito Yrigoyen", "El diagnóstico debe conservar la estación pendiente")
	assert(tren.invertir_sentido == sentido_inicial, "Un servicio sólo ida no puede invertir el sentido operativo")
	assert(errores.size() == 1, "El incidente debe emitir ruta_error una sola vez")
	assert(tren.obtener_estado_operacion() == Tren.EstadoOperacion.INCOMPLETO, "Una ruta inválida debe publicar estado INCOMPLETO")
	assert(incompletos.size() == 1, "El recorrido incompleto debe emitirse una sola vez")
	assert(cambios_incompleto.size() == 1, "La transición a INCOMPLETO debe emitirse una sola vez")
	tren.call("_actualizar_ruta_servicio")
	assert(errores.size() == 1, "La replanificación bloqueada no debe duplicar ruta_error")
	assert(incompletos.size() == 1, "La replanificación bloqueada no debe duplicar recorrido_incompleto")
	assert(cambios_incompleto.size() == 1, "La replanificación bloqueada no debe duplicar el cambio de estado")
	print("OK: override inválido detenido sin reversa operativa")
	quit()
