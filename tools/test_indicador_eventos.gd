extends SceneTree
## Godot --headless --path . -s res://tools/test_indicador_eventos.gd

const MAX_FRAMES: int = 3000

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var nivel: Node = (load("res://levels/ramal_roca_main/ramal_roca_main.tscn") as PackedScene).instantiate()
	root.add_child(nivel)
	await create_timer(0.3, true, false, true).timeout
	var controlador: SimulacionController = nivel.get_node("SimulacionController")
	var gestor: GestorEventos = nivel.get_node("GestorEventos")
	controlador.establecer_velocidad_simulacion(40.0)

	# --- 1) Piquete: efecto en la ESTACIÓN, no en un tren puntual. Se usa
	#         Yrigoyen (primera parada, siempre alcanzada rápido) en vez de
	#         Banfield: con los 4 trenes iniciales convergiendo en la zona
	#         Lanús-Escalada-Banfield, el sistema de reservas de switches
	#         puede trabarlos sin que ninguno llegue nunca (fragilidad
	#         conocida de esa zona, no relacionada a este test). ---
	var estaciones_nivel: Node = nivel.find_child("EstacionYrigoyen", true, false)
	assert(estaciones_nivel != null, "Debe existir el nodo EstacionYrigoyen en el nivel")
	assert(_contar_particulas(estaciones_nivel) == 0, "No debe haber efecto antes de disparar")

	var r: Dictionary = gestor.disparar_piquete("Hipólito Yrigoyen", 280.0)
	assert(bool(r["ok"]), "Piquete debe aceptarse: %s" % str(r))
	assert(_contar_particulas(estaciones_nivel) == 1, "El piquete debe agregar un efecto de partículas a la estación")
	# Poll hasta que _process() reemplace el placeholder "...", en vez de
	# adivinar cuántos frames hacen falta.
	if not await _esperar_hasta(func() -> bool:
		var et: Label3D = _buscar_etiqueta(estaciones_nivel)
		return et != null and et.text != "..."
	, "la etiqueta del piquete se actualiza con el tiempo restante"):
		quit(1); return
	var etiqueta_piquete: Label3D = _buscar_etiqueta(estaciones_nivel)
	assert(etiqueta_piquete != null, "El piquete debe agregar una etiqueta 3D con el tiempo restante")
	assert(etiqueta_piquete.text.contains("Incidente en estación") and etiqueta_piquete.text.contains("restantes"),
		"La etiqueta del incidente debe mostrar tipo y tiempo restante: '%s'" % etiqueta_piquete.text)
	print("OK parcial: incidente en estación agrega efecto de partículas y etiqueta 3D")

	# Esperar a que el piquete se venza y el efecto desaparezca.
	if not await _esperar_hasta(func() -> bool: return _contar_particulas(estaciones_nivel) == 0, "el efecto de piquete desaparece al vencer"):
		quit(1); return
	print("OK parcial: el efecto de piquete desaparece cuando vence la zona")

	# --- 2) Falla eléctrica: chispas en el TREN que entra al tramo, no en
	#         la estación. Con un tren nuevo para no depender del timing de
	#         los 4 iniciales. ---
	# Duración amplia (no 60s): agregar el tren, esperar a que lo registre y
	# a que llegue a Constitución para que la zona lo atrape toma un rato
	# real de simulación -- con una duración corta la zona puede estar a
	# punto de vencer justo cuando el tren recién es atrapado, y el efecto
	# se crea y se borra casi en el mismo frame (bookkeeping limpiado antes
	# de que el assert llegue a mirarlo, aunque los nodos todavía no se
	# hayan liberado del todo por el queue_free diferido).
	var r2: Dictionary = gestor.disparar_falla_electrica("Plaza Constitución", 300.0)
	assert(bool(r2["ok"]), "Falla eléctrica debe aceptarse: %s" % str(r2))
	var nuevos_ids: Array = []
	controlador.tren_agregado.connect(func(datos_tren: Dictionary) -> void: nuevos_ids.append(int(datos_tren.get("id", -1))))
	controlador.agregar_tren()
	if not await _esperar_hasta(func() -> bool: return not nuevos_ids.is_empty(), "nuevo tren registrado"):
		quit(1); return
	var id_nuevo: int = int(nuevos_ids[0])
	if not await _esperar_hasta(func() -> bool: return int(controlador.obtener_tren(id_nuevo).get("estado", -1)) == Tren.EstadoOperacion.DETENIDO_POR_EVENTO, "falla eléctrica detiene al tren nuevo"):
		quit(1); return
	var nodo_tren_nuevo: Node = _buscar_tren_por_id(nivel, id_nuevo)
	assert(nodo_tren_nuevo != null, "Debe poder encontrarse el nodo del tren nuevo")
	assert(_contar_particulas(nodo_tren_nuevo) == 1, "La falla eléctrica debe agregar chispas al tren afectado")
	# Poll en vez de un número fijo de frames: más robusto que adivinar
	# cuántos frames hacen falta para que _process() actualice el texto.
	if not await _esperar_hasta(func() -> bool:
		var et: Label3D = _buscar_etiqueta(nodo_tren_nuevo)
		return et != null and et.text != "..."
	, "la etiqueta del tren con falla eléctrica se actualiza con el tiempo restante"):
		quit(1); return
	var etiqueta_falla: Label3D = _buscar_etiqueta(nodo_tren_nuevo)
	assert(etiqueta_falla != null and etiqueta_falla.text.contains("Falla eléctrica"),
		"La etiqueta del tren con falla eléctrica debe mostrar el tipo: '%s'" % (etiqueta_falla.text if etiqueta_falla != null else "(ninguna)"))
	var estacion_origen: Node = _buscar_estacion_por_nombre(nivel, "Plaza Constitución")
	assert(estacion_origen != null and _buscar_etiqueta(estacion_origen) != null,
		"La falla eléctrica también debe marcar la estación de origen del tramo (sin forma barata de resolver el segmento de vía real)")
	print("OK parcial: falla eléctrica agrega chispas + etiqueta al tren, y una baliza en la estación de origen del tramo")

	# --- 3) Desperfecto mecánico: humo en el tren, permanente. ---
	var tren: Tren = nivel.find_child("TrenCSR", true, false) as Tren
	var id: int = tren.obtener_id_operativo()
	assert(_contar_particulas(tren) == 0, "No debe haber efecto antes del desperfecto")
	assert(gestor.disparar_desperfecto_mecanico(id, "Prueba visual"))
	assert(_contar_particulas(tren) == 1, "El desperfecto debe agregar humo al tren")
	if not await _esperar_hasta(func() -> bool:
		var et: Label3D = _buscar_etiqueta(tren)
		return et != null and et.text != "..."
	, "la etiqueta de la avería se actualiza"):
		quit(1); return
	var etiqueta_averia: Label3D = _buscar_etiqueta(tren)
	assert(etiqueta_averia != null and etiqueta_averia.text.contains("activa"),
		"La etiqueta debe indicar que la avería sigue activa: '%s'" % (etiqueta_averia.text if etiqueta_averia != null else "(ninguna)"))
	print("OK: la avería agrega humo y etiqueta mientras mantiene detenido al tren")

	nivel.queue_free()
	await process_frame
	print("OK: test_indicador_eventos completo")
	quit()


func _buscar_tren_por_id(nivel: Node, id_buscado: int) -> Node:
	for nodo: Node in nivel.get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren and (nodo as Tren).obtener_id_operativo() == id_buscado:
			return nodo
	return null


func _contar_particulas(nodo: Node) -> int:
	var total: int = 0
	for hijo: Node in nodo.get_children():
		if hijo is GPUParticles3D:
			total += 1
		total += _contar_particulas(hijo)
	return total


## Busca específicamente la etiqueta que agrega IndicadorEventos (por
## nombre): Estacion ya tiene su propio Label3D con el nombre de la
## estación, y una búsqueda genérica por tipo encontraría ese primero.
func _buscar_etiqueta(nodo: Node) -> Label3D:
	for hijo: Node in nodo.get_children():
		if hijo is Label3D and hijo.name == "EtiquetaIndicadorEvento":
			return hijo as Label3D
		var encontrada: Label3D = _buscar_etiqueta(hijo)
		if encontrada != null:
			return encontrada
	return null


func _buscar_estacion_por_nombre(nivel: Node, nombre: String) -> Node:
	for nodo: Node in nivel.get_tree().get_nodes_in_group("estaciones"):
		if nodo is Estacion and str((nodo as Estacion).nombre_estacion) == nombre:
			return nodo
	return null


func _esperar_hasta(condicion: Callable, descripcion: String) -> bool:
	for i in range(MAX_FRAMES):
		if bool(condicion.call()):
			return true
		if i % 500 == 0:
			print("... esperando: %s (frame %d/%d)" % [descripcion, i, MAX_FRAMES])
		await process_frame
	printerr("FAIL: se agotó el tope de frames esperando '%s'" % descripcion)
	return false
