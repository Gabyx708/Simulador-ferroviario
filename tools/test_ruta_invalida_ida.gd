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
	var errores: Array[String] = []
	tren.ruta_error.connect(func(motivo: String) -> void: errores.append(motivo))
	tren.call("_actualizar_ruta_servicio")

	assert(tren.ruta_invalida(), "Un override imposible debe marcar ruta inválida")
	assert(tren.esta_detenido(), "Un override imposible debe inmovilizar el tren")
	assert(tren.proxima_estacion_nombre() == "Hipólito Yrigoyen", "El diagnóstico debe conservar la estación pendiente")
	assert(tren.invertir_sentido == sentido_inicial, "Un servicio sólo ida no puede invertir el sentido operativo")
	assert(errores.size() == 1, "El incidente debe emitir ruta_error una sola vez")
	tren.call("_actualizar_ruta_servicio")
	assert(errores.size() == 1, "La replanificación bloqueada no debe duplicar ruta_error")
	print("OK: override inválido detenido sin reversa operativa")
	quit()
