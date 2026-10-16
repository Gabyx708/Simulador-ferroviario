extends Node
class_name IndicadorEventos
## Efecto visual para los 3 eventos de GestorEventos, pensado para que se
## note desde la cámara normal (no sólo de cerca). No modifica `Tren` ni
## `Estacion`: sólo les cuelga nodos visuales como hijos, usando sus grupos
## públicos ("trenes"/"estaciones") para encontrarlos, el mismo patrón de
## lectura que ya usan los otros módulos de esta carpeta.
##
## Ubicación de cada efecto (pensada para que se note la diferencia, no
## sólo el color) -- los tres llevan una etiqueta flotante (Label3D) con el
## tipo y el tiempo restante, y desaparecen apenas termina el evento:
## - Falla eléctrica: chispas + luz amarilla arriba del tren afectado,
##   simulando el pantógrafo arqueando contra la catenaria. Por tren:
##   aparece cuando ESE tren entra a la zona, desaparece cuando reanuda.
##   Además, una baliza amarilla sobre la estación de origen del tramo
##   afectado (el tramo en sí no es un nodo navegable desde acá -- ver
##   docs/reporte_final.md -- así que se marca el punto de partida, visible
##   "a lo largo de la vía" porque el tren que pasa por ahí también se
##   enciende).
## - Piquete: humo + baliza naranja intermitente en la estación afectada,
##   no en un tren puntual -- el piquete bloquea el andén, no depende de
##   quién esté ahí. Dura mientras la zona esté activa.
## - Avería mecánica: humo gris + baliza roja intermitente sobre el tren
##   detenido. El efecto permanece mientras corre el plazo aleatorio de
##   retiro; la etiqueta indica si la avería sigue activa o si fue retirado.

var _gestor: GestorEventos
var _reloj: RelojSimulacion
var _controlador: SimulacionController
var _trenes: Dictionary = {}  ## id -> Tren
var _estaciones: Dictionary = {}  ## nombre -> Estacion
var _efectos_tren: Dictionary = {}  ## id_tren -> {"contenedor": Node3D, "etiqueta": Label3D, "id_evento": int}
var _efectos_estacion: Dictionary = {}  ## nombre_estacion -> {"contenedor": Node3D, "etiqueta": Label3D, "id_evento": int}
var _efectos_origen_tramo: Dictionary = {}  ## nombre_estacion_origen -> {"contenedor": Node3D, "etiqueta": Label3D, "id_evento": int}


func _ready() -> void:
	var nivel: Node = get_parent()
	_gestor = nivel.get_node_or_null("GestorEventos") as GestorEventos
	_reloj = nivel.get_node_or_null("RelojSimulacion") as RelojSimulacion
	_controlador = nivel.get_node_or_null("SimulacionController") as SimulacionController
	if _gestor == null or _controlador == null:
		return
	_gestor.evento_disparado.connect(_on_evento_disparado)
	_gestor.evento_finalizado.connect(_on_evento_finalizado)
	_gestor.tren_afectado_por_evento.connect(_on_tren_afectado)
	_controlador.tren_reanudo.connect(_on_tren_reanudo)
	_controlador.tren_eliminado.connect(_on_tren_eliminado)
	get_tree().node_added.connect(_on_nodo_agregado)
	call_deferred("_registrar_iniciales")


func _registrar_iniciales() -> void:
	for nodo: Node in get_tree().get_nodes_in_group("trenes"):
		if nodo is Tren:
			_registrar_tren(nodo as Tren)
	for nodo: Node in get_tree().get_nodes_in_group("estaciones"):
		if nodo is Estacion:
			var estacion: Estacion = nodo as Estacion
			_estaciones[estacion.nombre_estacion] = estacion


func _on_nodo_agregado(nodo: Node) -> void:
	if nodo is Tren:
		call_deferred("_intentar_registrar_tren", nodo.get_instance_id())


func _intentar_registrar_tren(instance_id: int) -> void:
	var nodo: Node = instance_from_id(instance_id) as Node
	if nodo is Tren and nodo.is_in_group("trenes"):
		_registrar_tren(nodo as Tren)


func _registrar_tren(tren: Tren) -> void:
	if tren == null or not is_instance_valid(tren):
		return
	var id: int = tren.obtener_id_operativo()
	if id <= 0:
		call_deferred("_registrar_tren", tren)
		return
	_trenes[id] = tren


## --- Reacciones a eventos ---

func _on_evento_disparado(datos: Dictionary) -> void:
	var id_evento: int = int(datos.get("id", -1))
	match int(datos.get("tipo", -1)):
		GestorEventos.TipoEvento.FALLA_ELECTRICA:
			_agregar_efecto_origen_tramo(str(datos.get("clave", "")), id_evento)
		GestorEventos.TipoEvento.PIQUETE:
			_agregar_efecto_estacion(str(datos.get("clave", "")), id_evento)
		GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			_agregar_efecto_tren(int(datos.get("id_tren", -1)), TipoEfecto.AVERIA, id_evento)


func _on_evento_finalizado(datos: Dictionary) -> void:
	match int(datos.get("tipo", -1)):
		GestorEventos.TipoEvento.PIQUETE:
			_quitar_efecto_estacion(str(datos.get("clave", "")))
		GestorEventos.TipoEvento.FALLA_ELECTRICA:
			_quitar_efecto_origen_tramo(str(datos.get("clave", "")))


func _on_tren_afectado(id_tren: int, tipo: int) -> void:
	if tipo != GestorEventos.TipoEvento.FALLA_ELECTRICA:
		return
	var id_evento: int = -1
	for e: Dictionary in _gestor.obtener_zonas_activas():
		if int(e.get("tipo", -1)) == GestorEventos.TipoEvento.FALLA_ELECTRICA and (e.get("trenes_afectados", {}) as Dictionary).has(id_tren):
			id_evento = int(e["id"])
			break
	_agregar_efecto_tren(id_tren, TipoEfecto.FALLA_ELECTRICA, id_evento)


func _on_tren_reanudo(id_tren: int) -> void:
	_quitar_efecto_tren(id_tren)


func _on_tren_eliminado(id_tren: int) -> void:
	_efectos_tren.erase(id_tren)
	_trenes.erase(id_tren)


## --- Etiquetas: se actualizan en vivo con el tiempo restante ---

func _process(_delta: float) -> void:
	if _gestor == null or _reloj == null:
		return
	var ahora: float = _reloj.tiempo_simulado_s()
	for registro: Dictionary in _efectos_tren.values():
		_actualizar_etiqueta(registro, ahora)
	for registro: Dictionary in _efectos_estacion.values():
		_actualizar_etiqueta(registro, ahora)
	for registro: Dictionary in _efectos_origen_tramo.values():
		_actualizar_etiqueta(registro, ahora)


func _actualizar_etiqueta(registro: Dictionary, ahora: float) -> void:
	var etiqueta: Label3D = registro.get("etiqueta") as Label3D
	if etiqueta == null or not is_instance_valid(etiqueta):
		return
	var id_evento: int = int(registro.get("id_evento", -1))
	var evento: Dictionary = {}
	for e: Dictionary in _gestor.obtener_historial():
		if int(e.get("id", -1)) == id_evento:
			evento = e
			break
	if evento.is_empty():
		return
	var tipo: int = int(evento.get("tipo", -1))
	if tipo == GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
		etiqueta.text = "%s · activa" % GestorEventos.nombre_tipo(tipo) if bool(evento.get("activo", false)) else "%s · retiro" % GestorEventos.nombre_tipo(tipo)
		return
	var restante: int = maxi(0, roundi(float(evento.get("fin_s", 0.0)) - ahora))
	etiqueta.text = "%s · %ds restantes" % [GestorEventos.nombre_tipo(tipo), restante]


## --- Alta/baja de efectos ---

enum TipoEfecto { FALLA_ELECTRICA, AVERIA }

func _agregar_efecto_tren(id_tren: int, tipo_efecto: TipoEfecto, id_evento: int) -> void:
	if id_tren <= 0 or _efectos_tren.has(id_tren):
		return
	var tren: Tren = _trenes.get(id_tren) as Tren
	if tren == null or not is_instance_valid(tren):
		return
	var es_chispa: bool = tipo_efecto == TipoEfecto.FALLA_ELECTRICA
	var color: Color = GestorEventos.COLOR_FALLA_ELECTRICA if es_chispa else GestorEventos.COLOR_DESPERFECTO_MECANICO
	var altura_particulas: float = 3.5 if es_chispa else 1.5
	var contenedor: Node3D = Node3D.new()
	contenedor.position = Vector3(0.0, altura_particulas, 0.0)
	tren.add_child(contenedor)
	contenedor.add_child(_crear_particulas(color if es_chispa else Color(0.45, 0.45, 0.45, 0.75), es_chispa))
	contenedor.add_child(_crear_luz_parpadeante(color))
	var etiqueta: Label3D = _crear_etiqueta()
	etiqueta.position = Vector3(0.0, altura_particulas + 1.6, 0.0)
	contenedor.add_child(etiqueta)
	_efectos_tren[id_tren] = {"contenedor": contenedor, "etiqueta": etiqueta, "id_evento": id_evento}


func _quitar_efecto_tren(id_tren: int) -> void:
	var registro: Dictionary = _efectos_tren.get(id_tren, {})
	var contenedor: Node3D = registro.get("contenedor") as Node3D
	if contenedor != null and is_instance_valid(contenedor):
		contenedor.queue_free()
	_efectos_tren.erase(id_tren)


func _agregar_efecto_estacion(nombre: String, id_evento: int) -> void:
	if nombre.is_empty() or _efectos_estacion.has(nombre):
		return
	var estacion: Estacion = _estaciones.get(nombre) as Estacion
	if estacion == null or not is_instance_valid(estacion):
		return
	var contenedor: Node3D = Node3D.new()
	contenedor.position = Vector3(0.0, 2.0, 0.0)
	estacion.add_child(contenedor)
	contenedor.add_child(_crear_particulas(Color(0.22, 0.13, 0.08, 0.9), false))
	contenedor.add_child(_crear_luz_parpadeante(GestorEventos.COLOR_PIQUETE))
	var etiqueta: Label3D = _crear_etiqueta()
	etiqueta.position = Vector3(0.0, 3.6, 0.0)
	contenedor.add_child(etiqueta)
	_efectos_estacion[nombre] = {"contenedor": contenedor, "etiqueta": etiqueta, "id_evento": id_evento}


func _quitar_efecto_estacion(nombre: String) -> void:
	var registro: Dictionary = _efectos_estacion.get(nombre, {})
	var contenedor: Node3D = registro.get("contenedor") as Node3D
	if contenedor != null and is_instance_valid(contenedor):
		contenedor.queue_free()
	_efectos_estacion.erase(nombre)


## Falla eléctrica es una zona de TRAMO, no de estación -- no hay forma
## barata de resolver el segmento de vía real desde acá (ver cabecera del
## archivo), así que se marca la estación de origen del tramo con una
## baliza propia (distinta de la del piquete: sin humo, sólo luz) para que
## se note "desde dónde" arranca la zona afectada.
func _agregar_efecto_origen_tramo(nombre: String, id_evento: int) -> void:
	if nombre.is_empty() or _efectos_origen_tramo.has(nombre):
		return
	var estacion: Estacion = _estaciones.get(nombre) as Estacion
	if estacion == null or not is_instance_valid(estacion):
		return
	var contenedor: Node3D = Node3D.new()
	contenedor.position = Vector3(0.0, 2.0, 0.0)
	estacion.add_child(contenedor)
	contenedor.add_child(_crear_luz_parpadeante(GestorEventos.COLOR_FALLA_ELECTRICA))
	var etiqueta: Label3D = _crear_etiqueta()
	etiqueta.position = Vector3(0.0, 1.6, 0.0)
	contenedor.add_child(etiqueta)
	_efectos_origen_tramo[nombre] = {"contenedor": contenedor, "etiqueta": etiqueta, "id_evento": id_evento}


func _quitar_efecto_origen_tramo(nombre: String) -> void:
	var registro: Dictionary = _efectos_origen_tramo.get(nombre, {})
	var contenedor: Node3D = registro.get("contenedor") as Node3D
	if contenedor != null and is_instance_valid(contenedor):
		contenedor.queue_free()
	_efectos_origen_tramo.erase(nombre)


## --- Partículas, luz y etiqueta procedurales, sin assets externos ---

## El AABB por defecto que Godot calcula para un GPUParticles3D creado por
## código puede quedar más chico que el recorrido real de las partículas
## (sobre todo el humo, que sube con velocidad y gravedad propias) y
## Godot directamente no dibuja lo que cae fuera -- por eso se fija a mano,
## generoso, en vez de confiar en el default.
const _AABB_VISIBILIDAD: AABB = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))

func _crear_particulas(color: Color, es_chispa: bool) -> GPUParticles3D:
	var particulas: GPUParticles3D = GPUParticles3D.new()
	particulas.amount = 40 if es_chispa else 20
	particulas.lifetime = 0.5 if es_chispa else 3.0
	particulas.emitting = true
	particulas.visibility_aabb = _AABB_VISIBILIDAD

	var malla: QuadMesh = QuadMesh.new()
	# Tamaños grandes a propósito: a la escala de este mundo (tramos de
	# kilómetros, cámara casi siempre lejos) un efecto "realista" chico es
	# invisible en la práctica. Mejor que se note de sobra.
	malla.size = Vector2(0.5, 0.5) if es_chispa else Vector2(2.5, 2.5)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if es_chispa:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.0
	malla.material = material
	particulas.draw_pass_1 = malla

	var proceso: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proceso.direction = Vector3(0.0, 0.0, 0.0) if es_chispa else Vector3(0.0, 1.0, 0.0)
	proceso.spread = 180.0 if es_chispa else 20.0
	proceso.initial_velocity_min = 2.0 if es_chispa else 0.4
	proceso.initial_velocity_max = 4.5 if es_chispa else 0.9
	proceso.gravity = Vector3(0.0, -6.0, 0.0) if es_chispa else Vector3(0.0, 0.5, 0.0)
	proceso.scale_min = 0.8
	proceso.scale_max = 2.0
	proceso.color = color
	particulas.process_material = proceso

	return particulas


## Luz parpadeante del color del evento: a distancia (cámara normal, no
## pegada al modelo) una luz prendida/apagada se nota mucho más que una
## partícula chica. Se usa en los 3 tipos de evento, no sólo en la falla
## eléctrica como antes.
func _crear_luz_parpadeante(color: Color) -> OmniLight3D:
	var luz: OmniLight3D = OmniLight3D.new()
	luz.light_color = color
	luz.light_energy = 6.0
	luz.omni_range = 10.0
	# `self` (IndicadorEventos) ya está en el árbol; `luz` todavía no en el
	# momento en que se llama esta función, así que create_tween() tiene
	# que pedirse desde acá, no desde `luz`.
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.tween_property(luz, "light_energy", 1.0, 0.35)
	tween.tween_property(luz, "light_energy", 6.0, 0.35)
	return luz


## Etiqueta flotante con el tipo de evento y el tiempo restante, o el estado
## activo/retiro de una avería -- se actualiza en vivo desde _process().
## Billboard para que siempre mire a la cámara, sin importar el ángulo.
func _crear_etiqueta() -> Label3D:
	var etiqueta := Label3D.new()
	etiqueta.name = "EtiquetaIndicadorEvento"
	etiqueta.text = "..."
	etiqueta.font_size = 56
	etiqueta.outline_size = 12
	etiqueta.modulate = Color(1, 1, 1, 1)
	etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	etiqueta.no_depth_test = true
	etiqueta.pixel_size = 0.01
	return etiqueta
