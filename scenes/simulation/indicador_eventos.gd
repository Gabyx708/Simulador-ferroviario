extends Node
class_name IndicadorEventos
## Efecto visual mínimo para los 3 eventos de GestorEventos -- pensado para
## probar a ojo mientras no existe el panel de Persona 2. No modifica `Tren`
## ni `Estacion`: sólo les cuelga un `GPUParticles3D` como hijo visual,
## usando sus grupos públicos ("trenes"/"estaciones") para encontrarlos, el
## mismo patrón de lectura que ya usan los otros módulos de esta carpeta.
##
## Ubicación de cada efecto (pensada para que se note la diferencia, no
## sólo el color):
## - Falla eléctrica: chispas arriba del tren afectado, simulando el
##   pantógrafo arqueando contra la catenaria. Por tren: aparece cuando ESE
##   tren entra a la zona, desaparece cuando reanuda.
## - Piquete: humo negro/naranja en la estación afectada, no en un tren
##   puntual -- el piquete bloquea el andén, no depende de quién esté ahí.
##   Dura mientras la zona esté activa.
## - Desperfecto mecánico: humo gris saliendo del tren roto. Permanente,
##   como el evento mismo (se va solo si el tren se elimina del todo).

var _gestor: GestorEventos
var _controlador: SimulacionController
var _trenes: Dictionary = {}  ## id -> Tren
var _estaciones: Dictionary = {}  ## nombre -> Estacion
var _efectos_tren: Dictionary = {}  ## id_tren -> GPUParticles3D
var _efectos_estacion: Dictionary = {}  ## nombre_estacion -> GPUParticles3D


func _ready() -> void:
	var nivel: Node = get_parent()
	_gestor = nivel.get_node_or_null("GestorEventos") as GestorEventos
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
	match int(datos.get("tipo", -1)):
		GestorEventos.TipoEvento.PIQUETE:
			_agregar_efecto_estacion(str(datos.get("clave", "")))
		GestorEventos.TipoEvento.DESPERFECTO_MECANICO:
			_agregar_efecto_tren(int(datos.get("id_tren", -1)), false, Color(0.45, 0.45, 0.45, 0.75))


func _on_evento_finalizado(datos: Dictionary) -> void:
	if int(datos.get("tipo", -1)) == GestorEventos.TipoEvento.PIQUETE:
		_quitar_efecto_estacion(str(datos.get("clave", "")))


func _on_tren_afectado(id_tren: int, tipo: int) -> void:
	if tipo == GestorEventos.TipoEvento.FALLA_ELECTRICA:
		_agregar_efecto_tren(id_tren, true, GestorEventos.COLOR_FALLA_ELECTRICA)


func _on_tren_reanudo(id_tren: int) -> void:
	_quitar_efecto_tren(id_tren)


func _on_tren_eliminado(id_tren: int) -> void:
	_efectos_tren.erase(id_tren)
	_trenes.erase(id_tren)


## --- Alta/baja de efectos ---

func _agregar_efecto_tren(id_tren: int, es_chispa: bool, color: Color) -> void:
	if id_tren <= 0 or _efectos_tren.has(id_tren):
		return
	var tren: Tren = _trenes.get(id_tren) as Tren
	if tren == null or not is_instance_valid(tren):
		return
	var particulas: GPUParticles3D = _crear_particulas(color, es_chispa)
	particulas.position = Vector3(0.0, 3.2, 0.0) if es_chispa else Vector3(0.0, 1.0, 0.0)
	tren.add_child(particulas)
	_efectos_tren[id_tren] = particulas


func _quitar_efecto_tren(id_tren: int) -> void:
	var particulas: GPUParticles3D = _efectos_tren.get(id_tren) as GPUParticles3D
	if particulas != null and is_instance_valid(particulas):
		particulas.queue_free()
	_efectos_tren.erase(id_tren)


func _agregar_efecto_estacion(nombre: String) -> void:
	if nombre.is_empty() or _efectos_estacion.has(nombre):
		return
	var estacion: Estacion = _estaciones.get(nombre) as Estacion
	if estacion == null or not is_instance_valid(estacion):
		return
	var particulas: GPUParticles3D = _crear_particulas(Color(0.22, 0.13, 0.08, 0.85), false)
	particulas.position = Vector3(0.0, 1.5, 0.0)
	estacion.add_child(particulas)
	_efectos_estacion[nombre] = particulas


func _quitar_efecto_estacion(nombre: String) -> void:
	var particulas: GPUParticles3D = _efectos_estacion.get(nombre) as GPUParticles3D
	if particulas != null and is_instance_valid(particulas):
		particulas.queue_free()
	_efectos_estacion.erase(nombre)


## --- Partículas procedurales, sin assets externos ---

func _crear_particulas(color: Color, es_chispa: bool) -> GPUParticles3D:
	var particulas: GPUParticles3D = GPUParticles3D.new()
	particulas.amount = 28 if es_chispa else 14
	particulas.lifetime = 0.35 if es_chispa else 2.5
	particulas.emitting = true

	var malla: QuadMesh = QuadMesh.new()
	malla.size = Vector2(0.06, 0.06) if es_chispa else Vector2(0.6, 0.6)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if es_chispa:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	malla.material = material
	particulas.draw_pass_1 = malla

	var proceso: ParticleProcessMaterial = ParticleProcessMaterial.new()
	proceso.direction = Vector3(0.0, 0.0, 0.0) if es_chispa else Vector3(0.0, 1.0, 0.0)
	proceso.spread = 180.0 if es_chispa else 20.0
	proceso.initial_velocity_min = 1.2 if es_chispa else 0.25
	proceso.initial_velocity_max = 2.6 if es_chispa else 0.55
	proceso.gravity = Vector3(0.0, -4.0, 0.0) if es_chispa else Vector3(0.0, 0.5, 0.0)
	proceso.scale_min = 0.6
	proceso.scale_max = 1.5
	proceso.color = color
	particulas.process_material = proceso

	return particulas
