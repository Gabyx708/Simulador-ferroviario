extends SceneTree
## Godot --headless --path . -s res://tools/test_hud_velocidad_simulacion.gd

const ESCENA := "res://levels/ramal_roca_main/ramal_roca_main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var raiz: Node = (load(ESCENA) as PackedScene).instantiate()
	root.add_child(raiz)
	await process_frame
	await process_frame
	var hud: CanvasLayer = raiz.get_node_or_null("HUD") as CanvasLayer
	var controlador: Node = raiz.get_node_or_null("SimulacionController")
	assert(hud != null, "El nivel debe instanciar el HUD")
	assert(controlador != null, "El nivel debe exponer SimulacionController")
	var slider: HSlider = hud.get_node("Paneles/PanelPruebas/Margen/Contenido/VelocidadSimulacion") as HSlider
	var etiqueta: Label = hud.get_node("Paneles/PanelPruebas/Margen/Contenido/ValorVelocidadSimulacion") as Label
	assert(slider.editable, "El control global debe funcionar sin tren seleccionado")

	for factor: float in [0.5, 1.0, 2.0, 4.5, 10.0]:
		slider.value = factor
		await process_frame
		assert(is_equal_approx(float(controlador.call("obtener_velocidad_simulacion")), factor), "El slider debe aplicar ×%.1f" % factor)
		assert(etiqueta.text == "×%.1f" % factor, "La etiqueta debe reflejar ×%.1f" % factor)

	slider.value = 0.0
	await process_frame
	assert(is_zero_approx(float(controlador.call("obtener_velocidad_simulacion"))), "Cero debe pausar globalmente")
	assert(etiqueta.text == "Pausada", "Cero debe mostrar Pausada")
	controlador.call("establecer_velocidad_simulacion", 2.0)
	await process_frame
	assert(is_equal_approx(slider.value, 2.0), "La señal del controlador debe sincronizar el slider")

	controlador.call("establecer_velocidad_simulacion", 1.0)
	print("OK: slider global de velocidad del HUD sincronizado")
	quit()
