@tool
extends Node3D
class_name TrackGeometry
## Generador procedural de infraestructura 3D ferroviaria (Rieles, Balasto y Durmientes).
##
## Diseñado para desacoplar la pesada generación geométrica del grafo topológico (TrackNetwork).
## Utiliza cálculo analítico directo de normales (evitando algoritmos O(V^2) de SurfaceTool)
## y culling granular por chunks espaciales situados en sus coordenadas métricas reales.
##
## Compatible con Godot 4.x / 4.7 con tipado estático estricto.

@export_group("Materiales")
## Material aplicado a los perfiles de los rieles.
@export var material_riel: Material = preload("res://common/materials/mat_riel.tres"):
	set(v):
		if material_riel == v:
			return
		material_riel = v
		_actualizar_materiales()

## Material aplicado a la cama de balasto.
@export var material_balasto: Material = preload("res://common/materials/mat_balastro.tres"):
	set(v):
		if material_balasto == v:
			return
		material_balasto = v
		_actualizar_materiales()

## Material aplicado a los durmientes.
@export var material_durmiente: Material = preload("res://common/materials/mat_durmiente.tres"):
	set(v):
		if material_durmiente == v:
			return
		material_durmiente = v
		_actualizar_materiales()

@export_group("Control de Generación")
## Si está activo, genera la geometría 3D automáticamente al abrir la escena en el editor.
@export var generar_en_editor: bool = true:
	set(v):
		if generar_en_editor == v:
			return
		generar_en_editor = v
		if Engine.is_editor_hint() and is_inside_tree():
			if generar_en_editor:
				call_deferred("construir_geometria")
			else:
				limpiar(true)

## Si está activo, genera la geometría automáticamente al iniciar el juego en runtime.
@export var generar_en_juego: bool = true

## Evita generar la red serializada antes de que TrackNetwork termine de reconstruirla.
var _red_lista: bool = false
## Caché incremental: seg_id -> huella (curva + rango útil) de la malla construida.
var _cache_tramos: Dictionary = {}
## Cola de construcción progresiva: la carga inicial no bloquea un frame entero.
var _cola_construccion: Array[String] = []
var _construyendo: bool = false
var _mallas_generadas: int = 0
var _mallas_reusadas: int = 0
var _cortados: int = 0
var _absorbidos: int = 0
var _t_inicio_construccion: int = 0
## Distingue una limpieza pedida por el usuario de la pérdida transitoria de
## nodos temporales que puede ocurrir al cambiar de escena en el editor.
var _limpieza_manual: bool = false
## Presupuesto de milisegundos de construcción de mallas por frame.
@export_range(2.0, 32.0, 1.0) var presupuesto_frame_ms: float = 8.0
const PRESUPUESTO_FRAME_MS: int = 8

## Límite de segmentos a generar (0 = toda la red disponible).
@export var limite_segmentos: int = 0:
	set(v):
		if limite_segmentos == v:
			return
		limite_segmentos = v
		if is_inside_tree() and (not Engine.is_editor_hint() or generar_en_editor):
			call_deferred("construir_geometria")

## Pulsador: Generar o reconstruir la malla 3D de rieles, balasto y durmientes.
@export var boton_generar_mallas: bool = false:
	set(v):
		if v:
			boton_generar_mallas = false
			_red_lista = true
			construir_geometria()

## Pulsador: Limpiar todas las mallas generadas liberando memoria.
@export var boton_limpiar_mallas: bool = false:
	set(v):
		if v:
			boton_limpiar_mallas = false
			limpiar(true)

## Pulsador: Forzar regeneración completa de la red y su geometría 3D.
@export var regenerar: bool = false:
	set(v):
		if v:
			regenerar = false
			_red_lista = true
			var red: TrackNetwork = get_parent() as TrackNetwork
			if red != null and red.has_method("cargar_red"):
				red.cargar_red()
			else:
				construir_geometria()

@export_group("Optimización y Culling")
## Si está activo, el culling de distancia se aplica visualmente dentro del editor 3D.
## Al desactivarlo, se visualiza la red completa en el editor sin importar la distancia de la cámara.
@export var culling_en_editor: bool = true:
	set(v):
		if culling_en_editor == v:
			return
		culling_en_editor = v
		_actualizar_culling_en_vivo()

## Tamaño de cada chunk espacial en metros para Frustum y Distance Culling granular.
@export_range(100.0, 1000.0, 50.0) var tamano_chunk_m: float = 350.0:
	set(v):
		var nuevo: float = maxf(50.0, v)
		if is_equal_approx(tamano_chunk_m, nuevo):
			return
		tamano_chunk_m = nuevo
		if is_inside_tree() and (not Engine.is_editor_hint() or generar_en_editor):
			call_deferred("construir_geometria")

## Distancia máxima en metros para renderizar rieles y balasto (0 = infinito).
## Al modificar este valor en el Inspector, el culling se actualiza al instante en el viewport 3D.
@export_range(0.0, 8000.0, 50.0) var distancia_culling_mallas: float = 2500.0:
	set(v):
		if is_equal_approx(distancia_culling_mallas, v):
			return
		distancia_culling_mallas = v
		_actualizar_culling_en_vivo()

## Distancia máxima en metros para renderizar durmientes (0 = infinito).
## Al modificar este valor en el Inspector, el culling se actualiza al instante en el viewport 3D.
@export_range(0.0, 2500.0, 25.0) var distancia_culling_durmientes: float = 600.0:
	set(v):
		if is_equal_approx(distancia_culling_durmientes, v):
			return
		distancia_culling_durmientes = v
		_actualizar_culling_en_vivo()

## Si está activo, las mallas se desvanecen (transparencia) al alcanzar la distancia de
## culling. Con miles de instancias esto encarece mucho el render; por defecto se usa
## culling DURO (sin fade) para que el editor fluya al mover la cámara.
@export var usar_fade_culling: bool = false:
	set(v):
		if usar_fade_culling == v:
			return
		usar_fade_culling = v
		_actualizar_culling_en_vivo()

## Paso métrico de muestreo longitudinal para rieles y balasto.
@export_range(1.0, 6.0, 0.5) var paso_muestreo: float = 3.0:
	set(v):
		var nuevo: float = clampf(v, 0.5, 10.0)
		if is_equal_approx(paso_muestreo, nuevo):
			return
		paso_muestreo = nuevo
		if is_inside_tree() and (not Engine.is_editor_hint() or generar_en_editor):
			call_deferred("construir_geometria")

# Perfiles geométricos de extrusión
const PERFIL_RIEL: Array[Vector2] = [
	Vector2(-0.035, 0.000), Vector2(0.035, 0.000),
	Vector2(0.035, -0.035), Vector2(0.012, -0.050),
	Vector2(0.060, -0.150), Vector2(-0.060, -0.150),
	Vector2(-0.012, -0.050), Vector2(-0.035, -0.035),
]

const PERFIL_BALASTO: Array[Vector2] = [
	Vector2(-2.65, -0.66), Vector2(2.65, -0.66),
	Vector2(1.95, -0.30), Vector2(-1.95, -0.30),
]


func _ready() -> void:
	add_to_group("track_geometry")
	set_process(true)
	var red: TrackNetwork = get_parent() as TrackNetwork
	if red != null and not red.red_cargada.is_connected(_on_red_cargada):
		red.red_cargada.connect(_on_red_cargada)
	# TrackNetwork es el dueño de la reconstrucción. Sus hijos reciben _ready antes
	# que él y no deben dibujar los Path3D serializados de la escena.
	call_deferred("_recuperar_geometria_editor")


func _enter_tree() -> void:
	# Al cambiar de pestaña, Godot puede desmontar y volver a montar la escena.
	# Las mallas son temporales y deben reconstruirse si el editor las descartó.
	call_deferred("_recuperar_geometria_editor")


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or not generar_en_editor or _limpieza_manual:
		return
	var red: TrackNetwork = get_parent() as TrackNetwork
	if red == null or red.paths.is_empty() or _construyendo or get_child_count() > 0:
		return
	_recuperar_geometria_editor()


func _recuperar_geometria_editor() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint() or not generar_en_editor or _limpieza_manual:
		return
	var red: TrackNetwork = get_parent() as TrackNetwork
	if red == null or red.paths.is_empty() or _construyendo or get_child_count() > 0:
		return
	_red_lista = true
	construir_geometria()


func _on_red_cargada(_total_segmentos: int, _total_uniones: int) -> void:
	_red_lista = true
	if (Engine.is_editor_hint() and generar_en_editor) or (!Engine.is_editor_hint() and generar_en_juego):
		call_deferred("construir_geometria")


## Elimina todas las mallas generadas.
func limpiar(manual: bool = false) -> void:
	_limpieza_manual = manual
	_cache_tramos.clear()
	for c: Node in get_children():
		remove_child(c)
		# La geometría se regenera en el mismo frame que la red.
		# La eliminación inmediata evita conservar rieles de la generación anterior.
		c.free()


## Construye la infraestructura 3D a partir de los Path3D provistos por TrackNetwork.
##
## Es INCREMENTAL: cada tramo guarda una huella (curva + rango útil) y sólo se
## re-construye si cambió. Antes se liberaban y regeneraban las 566 mallas
## completas en cada edición (~1.9 s de congelamiento por edición).
func construir_geometria() -> void:
	_limpieza_manual = false
	var red: TrackNetwork = get_parent() as TrackNetwork
	if red == null:
		push_warning("TrackGeometry: El nodo padre no es de tipo TrackNetwork.")
		return

	if not _red_lista and not red.paths.is_empty():
		_red_lista = true

	if not _red_lista:
		return

	var paths_dict: Dictionary = red.paths
	if paths_dict.is_empty():
		return

	var mallas_generadas: int = 0
	var mallas_reusadas: int = 0
	var segmentos_cortados: int = 0
	var segmentos_absorbidos: int = 0
	if _construyendo:
		return
	_cola_construccion.clear()
	for k: Variant in paths_dict.keys():
		_cola_construccion.append(str(k))
	_construyendo = true
	_mallas_generadas = 0
	_mallas_reusadas = 0
	_cortados = 0
	_absorbidos = 0
	_t_inicio_construccion = Time.get_ticks_msec()
	_procesar_cola_geometria()


## Procesa la cola de construcción con presupuesto de frame: la carga inicial deja de
## bloquear el editor (antes eran ~1,8 s en un solo frame).
func _procesar_cola_geometria() -> void:
	var t_frame: int = Time.get_ticks_msec()
	while not _cola_construccion.is_empty():
		if Time.get_ticks_msec() - t_frame >= PRESUPUESTO_FRAME_MS:
			break
		var seg_id: String = _cola_construccion.pop_front()
		_construir_tramo_de_cola(seg_id)
	if not _cola_construccion.is_empty():
		call_deferred("_procesar_cola_geometria")
		return
	_construyendo = false
	# Limpiar la caché de tramos que ya no existen en la red.
	var red_actual: TrackNetwork = get_parent() as TrackNetwork
	if red_actual != null:
		for seg_id: String in _cache_tramos.keys():
			if not red_actual.paths.has(seg_id):
				_descartar_geo(seg_id)
				_cache_tramos.erase(seg_id)
	print("TrackGeometry: %d tramos visibles (%d reusados), %d cortados, %d absorbidos en %d ms." % [
		_mallas_generadas, _mallas_reusadas, _cortados, _absorbidos,
		Time.get_ticks_msec() - _t_inicio_construccion
	])


## Construye (o reusa) la malla de un tramo. Extraído para poder procesarlo en cola.
func _construir_tramo_de_cola(seg_id: String) -> void:
	var red: TrackNetwork = get_parent() as TrackNetwork
	if red == null:
		return
	var paths_dict: Dictionary = red.paths
	if not paths_dict.has(seg_id):
		return
	if limite_segmentos > 0 and _mallas_generadas >= limite_segmentos:
		return
	# El editor puede liberar un Path3D mientras la geometría se reconstruye:
	# leerlo directo abortaba toda la generación con "cast a freed object".
	if not is_instance_valid(paths_dict[seg_id]):
		return
	var p: Path3D = paths_dict[seg_id] as Path3D
	if p == null or p.curve == null:
		return
	if red.has_method("es_segmento_reemplazado_por_switch") and red.es_segmento_reemplazado_por_switch(seg_id):
		_descartar_geo(seg_id)
		_cache_tramos.erase(seg_id)
		return
	var largo: float = p.curve.get_baked_length()
	if largo < paso_muestreo:
		_descartar_geo(seg_id)
		_cache_tramos.erase(seg_id)
		return
	# Un tramo puede tener DOS aparatos (uno en cada punta): se dibuja cada
	# intervalo de vía plena por separado, así no colapsa a "absorbido".
	var rangos: Array[Vector2] = []
	if red.has_method("obtener_rangos_utiles_tramo"):
		rangos = red.obtener_rangos_utiles_tramo(seg_id) as Array[Vector2]
	else:
		rangos.append(Vector2(0.0, largo))
	var utiles: Array[Vector2] = []
	for r: Vector2 in rangos:
		if r.y - r.x >= paso_muestreo:
			utiles.append(r)
	if utiles.is_empty():
		_absorbidos += 1
		_descartar_geo(seg_id)
		_cache_tramos.erase(seg_id)
		return
	if utiles.size() > 1 or utiles[0].x > 0.5 or utiles[0].y < largo - 0.5:
		_cortados += 1
	var huella: int = _huella_tramo(p.curve, utiles)
	if _cache_tramos.get(seg_id, -1) == huella and get_node_or_null("Geo_%s" % seg_id) != null:
		_mallas_reusadas += 1
		return
	_descartar_geo(seg_id)
	var nodo_segmento: Node3D = Node3D.new()
	nodo_segmento.name = "Geo_%s" % seg_id
	add_child(nodo_segmento)
	for r2: Vector2 in utiles:
		_construir_geometria_tramo(p.curve, largo, nodo_segmento, r2.x, r2.y)
	_cache_tramos[seg_id] = huella
	_mallas_generadas += 1


## Huella de un tramo: forma de la curva + rango útil de vía plena.
func _huella_tramo(c: Curve3D, rangos: Array[Vector2]) -> int:
	var h: int = hash(c.point_count) ^ hash(rangos.size())
	for r: Vector2 in rangos:
		# Se cuantiza el rango a 25 cm: una deriva de milímetros en el corte no debe
		# invalidar la malla (era el costo dominante de cada edición).
		h = hash(h ^ hash(Vector2(snappedf(r.x, 0.25), snappedf(r.y, 0.25))))
	for i: int in c.point_count:
		h = hash(h ^ hash(c.get_point_position(i)) ^ hash(c.get_point_in(i)) ^ hash(c.get_point_out(i)))
	return h


## Libera el nodo de malla de un tramo si existe.
func _descartar_geo(seg_id: String) -> void:
	var n: Node = get_node_or_null("Geo_%s" % seg_id)
	if n != null:
		remove_child(n)
		n.free()


## Elimina la infraestructura 3D de un tramo específico liberando su memoria inmediatamente.
func eliminar_geometria_tramo(seg_id: String) -> void:
	_descartar_geo(seg_id)
	_cache_tramos.erase(seg_id)


## Actualiza la infraestructura 3D de un único tramo en tiempo real (por ejemplo, al editarlo interactivamente).
func actualizar_geometria_tramo(seg_id: String) -> void:
	var red: TrackNetwork = get_parent() as TrackNetwork
	if red == null:
		return
	var paths_dict: Dictionary = red.paths
	if not paths_dict.has(seg_id):
		return
	if not is_instance_valid(paths_dict[seg_id]):
		return

	var p: Path3D = paths_dict[seg_id] as Path3D
	if p == null or p.curve == null:
		return

	# Eliminar malla previa del tramo si existe
	_descartar_geo(seg_id)
	_cache_tramos.erase(seg_id)
	if red.has_method("es_segmento_reemplazado_por_switch") and red.es_segmento_reemplazado_por_switch(seg_id):
		return

	var largo: float = p.curve.get_baked_length()
	if largo < paso_muestreo:
		return

	var rangos: Array[Vector2] = []
	if red.has_method("obtener_rangos_utiles_tramo"):
		rangos = red.obtener_rangos_utiles_tramo(seg_id) as Array[Vector2]
	else:
		rangos.append(Vector2(0.0, largo))
	var utiles: Array[Vector2] = []
	for r: Vector2 in rangos:
		if r.y - r.x >= paso_muestreo:
			utiles.append(r)
	if utiles.is_empty():
		_cache_tramos.erase(seg_id)
		return
	var nodo_segmento: Node3D = Node3D.new()
	nodo_segmento.name = "Geo_%s" % seg_id
	add_child(nodo_segmento)
	for r2: Vector2 in utiles:
		_construir_geometria_tramo(p.curve, largo, nodo_segmento, r2.x, r2.y)
	_cache_tramos[seg_id] = _huella_tramo(p.curve, utiles)


func _construir_geometria_tramo(curva: Curve3D, largo: float, destino: Node3D, d_desde: float = 0.0, d_hasta: float = -1.0) -> void:
	var limite_inicio: float = clampf(d_desde, 0.0, largo)
	var limite_fin: float = clampf(d_hasta if d_hasta >= 0.0 else largo, 0.0, largo)
	if limite_fin - limite_inicio < paso_muestreo * 0.5:
		return

	var paso: float = maxf(50.0, tamano_chunk_m)
	var cantidad_chunks: int = int(ceil(largo / paso))
	cantidad_chunks = maxi(1, cantidad_chunks)

	for ch: int in cantidad_chunks:
		var raw_inicio: float = float(ch) * paso
		var raw_fin: float = minf(float(ch + 1) * paso, largo)
		var d_inicio: float = clampf(raw_inicio, limite_inicio, limite_fin)
		var d_fin: float = clampf(raw_fin, limite_inicio, limite_fin)
		if d_fin - d_inicio < paso_muestreo * 0.5:
			continue

		var d_centro: float = (d_inicio + d_fin) * 0.5
		var centro_chunk: Vector3 = curva.sample_baked(d_centro, true)

		var nodo_chunk: Node3D = Node3D.new()
		nodo_chunk.name = "Chunk_%03d" % ch
		nodo_chunk.position = centro_chunk
		destino.add_child(nodo_chunk)

		_construir_geometria_rango(curva, d_inicio, d_fin, centro_chunk, nodo_chunk)


func _construir_geometria_rango(curva: Curve3D, d_inicio: float, d_fin: float, centro_chunk: Vector3, destino: Node3D) -> void:
	var mesh_balasto: ArrayMesh = _barrer_rango(curva, PERFIL_BALASTO, 0.0, d_inicio, d_fin, centro_chunk)
	_agregar_malla(destino, mesh_balasto, "Balasto", material_balasto)

	var mesh_rieles: ArrayMesh = _barrer_ambos_rieles_rango(curva, d_inicio, d_fin, centro_chunk)
	_agregar_malla(destino, mesh_rieles, "Rieles", material_riel)

	_agregar_durmientes_rango(destino, curva, d_inicio, d_fin, centro_chunk)


## Extrusión rápida con cálculo analítico directo de normales centrada en el origen local del chunk.
func _barrer_ambos_rieles_rango(curva: Curve3D, d_inicio: float, d_fin: float, centro_chunk: Vector3) -> ArrayMesh:
	var largo_rango: float = d_fin - d_inicio
	var pasos: int = int(ceil(largo_rango / paso_muestreo))
	pasos = maxi(1, pasos)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var peri: PackedFloat32Array = PackedFloat32Array()
	var acc: float = 0.0
	for i: int in PERFIL_RIEL.size():
		peri.append(acc)
		acc += PERFIL_RIEL[i].distance_to(PERFIL_RIEL[(i + 1) % PERFIL_RIEL.size()])

	var n: int = PERFIL_RIEL.size()
	var trocha_media: float = 0.838

	for desplazamiento: float in [-trocha_media, trocha_media]:
		var anillos: Array[PackedVector3Array] = []
		var recorridos: PackedFloat32Array = PackedFloat32Array()

		for p: int in pasos + 1:
			var d: float = minf(d_inicio + float(p) * largo_rango / float(pasos), d_fin)
			var origen: Vector3 = curva.sample_baked(d, true) - centro_chunk
			var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
			var adelante: Vector3 = (curva.sample_baked(minf(d + 0.1, d_fin), true) -
					curva.sample_baked(maxf(d - 0.1, 0.0), true)).normalized()
			if adelante.length_squared() < 0.5:
				adelante = Vector3.FORWARD
			var costado: Vector3 = arriba.cross(adelante).normalized()
			arriba = adelante.cross(costado).normalized()

			var anillo: PackedVector3Array = PackedVector3Array()
			for pt: Vector2 in PERFIL_RIEL:
				anillo.append(origen + costado * (pt.x + desplazamiento) + arriba * pt.y)
			anillos.append(anillo)
			recorridos.append(d)

		for p: int in pasos:
			for i: int in n:
				var j: int = (i + 1) % n
				var a: Vector3 = anillos[p][i]
				var b: Vector3 = anillos[p][j]
				var c: Vector3 = anillos[p + 1][j]
				var e: Vector3 = anillos[p + 1][i]
				var v0: float = recorridos[p]
				var v1: float = recorridos[p + 1]

				# Cálculo analítico directo de normales: 0 ms de overhead
				var normal: Vector3 = (b - a).cross(c - a).normalized()
				st.set_normal(normal)
				st.set_uv(Vector2(peri[i], v0)); st.add_vertex(a)
				st.set_uv(Vector2(peri[j], v0)); st.add_vertex(b)
				st.set_uv(Vector2(peri[j], v1)); st.add_vertex(c)

				st.set_uv(Vector2(peri[i], v0)); st.add_vertex(a)
				st.set_uv(Vector2(peri[j], v1)); st.add_vertex(c)
				st.set_uv(Vector2(peri[i], v1)); st.add_vertex(e)

	return st.commit()


func _barrer_rango(curva: Curve3D, perfil: Array[Vector2], desplazamiento: float, d_inicio: float, d_fin: float, centro_chunk: Vector3) -> ArrayMesh:
	var largo_rango: float = d_fin - d_inicio
	var pasos: int = int(ceil(largo_rango / paso_muestreo))
	pasos = maxi(1, pasos)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var peri: PackedFloat32Array = PackedFloat32Array()
	var acc: float = 0.0
	for i: int in perfil.size():
		peri.append(acc)
		acc += perfil[i].distance_to(perfil[(i + 1) % perfil.size()])

	var anillos: Array[PackedVector3Array] = []
	var recorridos: PackedFloat32Array = PackedFloat32Array()

	for p: int in pasos + 1:
		var d: float = minf(d_inicio + float(p) * largo_rango / float(pasos), d_fin)
		var origen: Vector3 = curva.sample_baked(d, true) - centro_chunk
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.1, d_fin), true) -
				curva.sample_baked(maxf(d - 0.1, 0.0), true)).normalized()
		if adelante.length_squared() < 0.5:
			adelante = Vector3.FORWARD
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()

		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(origen + costado * (pt.x + desplazamiento) + arriba * pt.y)
		anillos.append(anillo)
		recorridos.append(d)

	var n: int = perfil.size()
	for p: int in pasos:
		for i: int in n:
			var j: int = (i + 1) % n
			var a: Vector3 = anillos[p][i]
			var b: Vector3 = anillos[p][j]
			var c: Vector3 = anillos[p + 1][j]
			var e: Vector3 = anillos[p + 1][i]
			var v0: float = recorridos[p]
			var v1: float = recorridos[p + 1]

			var normal: Vector3 = (b - a).cross(c - a).normalized()
			st.set_normal(normal)
			st.set_uv(Vector2(peri[i], v0)); st.add_vertex(a)
			st.set_uv(Vector2(peri[j], v0)); st.add_vertex(b)
			st.set_uv(Vector2(peri[j], v1)); st.add_vertex(c)

			st.set_uv(Vector2(peri[i], v0)); st.add_vertex(a)
			st.set_uv(Vector2(peri[j], v1)); st.add_vertex(c)
			st.set_uv(Vector2(peri[i], v1)); st.add_vertex(e)

	return st.commit()


func _agregar_durmientes_rango(destino: Node, curva: Curve3D, d_inicio: float, d_fin: float, centro_chunk: Vector3) -> void:
	var largo_rango: float = d_fin - d_inicio
	var separacion: float = 0.65
	var cantidad: int = int(largo_rango / separacion)
	if cantidad <= 0:
		return

	var caja: BoxMesh = BoxMesh.new()
	caja.size = Vector3(2.60, 0.20, 0.26)
	if material_durmiente != null:
		caja.material = material_durmiente

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = caja
	mm.instance_count = cantidad

	var min_pt: Vector3 = Vector3(INF, INF, INF)
	var max_pt: Vector3 = Vector3(-INF, -INF, -INF)

	for i: int in cantidad:
		var d: float = d_inicio + separacion * (float(i) + 0.5)
		var origen: Vector3 = curva.sample_baked(d, true)
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.1, d_fin), true) -
				curva.sample_baked(maxf(d - 0.1, 0.0), true)).normalized()
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()
		var base: Basis = Basis(costado, arriba, adelante)
		var pos_durmiente: Vector3 = origen - arriba * 0.275 - centro_chunk
		mm.set_instance_transform(i, Transform3D(base, pos_durmiente))

		min_pt = min_pt.min(pos_durmiente)
		max_pt = max_pt.max(pos_durmiente)

	min_pt -= Vector3(1.5, 0.5, 1.5)
	max_pt += Vector3(1.5, 0.5, 1.5)
	mm.custom_aabb = AABB(min_pt, max_pt - min_pt)

	var nodo: MultiMeshInstance3D = MultiMeshInstance3D.new()
	nodo.multimesh = mm
	nodo.name = "Durmientes"

	_configurar_culling_durmiente(nodo)
	destino.add_child(nodo)


func _obtener_distancia_mallas_efectiva() -> float:
	if Engine.is_editor_hint() and not culling_en_editor:
		return 0.0
	return distancia_culling_mallas


func _obtener_distancia_durmientes_efectiva() -> float:
	if Engine.is_editor_hint() and not culling_en_editor:
		return 0.0
	return distancia_culling_durmientes


func _configurar_culling_malla(mi: MeshInstance3D) -> void:
	var dist: float = _obtener_distancia_mallas_efectiva()
	if dist > 0.0:
		mi.visibility_range_end = dist
		if usar_fade_culling:
			mi.visibility_range_end_margin = minf(100.0, dist * 0.15)
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			# Culling DURO: evita el render transparente por instancia (fade), que con
			# miles de mallas es el mayor costo de GPU al mover la cámara en el editor.
			mi.visibility_range_end_margin = 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	else:
		mi.visibility_range_end = 0.0
		mi.visibility_range_end_margin = 0.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _configurar_culling_durmiente(mmi: MultiMeshInstance3D) -> void:
	var dist: float = _obtener_distancia_durmientes_efectiva()
	if dist > 0.0:
		mmi.visibility_range_end = dist
		if usar_fade_culling:
			mmi.visibility_range_end_margin = minf(50.0, dist * 0.15)
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			mmi.visibility_range_end_margin = 0.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	else:
		mmi.visibility_range_end = 0.0
		mmi.visibility_range_end_margin = 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _actualizar_culling_en_vivo() -> void:
	for c: Node in get_children():
		_actualizar_culling_recursivo(c)


func _actualizar_culling_recursivo(nodo: Node) -> void:
	if nodo is MeshInstance3D:
		_configurar_culling_malla(nodo as MeshInstance3D)
	elif nodo is MultiMeshInstance3D:
		_configurar_culling_durmiente(nodo as MultiMeshInstance3D)

	for hijo: Node in nodo.get_children():
		_actualizar_culling_recursivo(hijo)


func _agregar_malla(destino: Node, malla: ArrayMesh, nombre: String, mat: Material) -> void:
	if malla == null or malla.get_surface_count() == 0:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = malla
	mi.name = nombre
	if mat != null:
		mi.material_override = mat

	_configurar_culling_malla(mi)
	destino.add_child(mi)


func _actualizar_materiales() -> void:
	for c: Node in get_children():
		_aplicar_material_recursivo(c)


func _aplicar_material_recursivo(nodo: Node) -> void:
	if nodo is MeshInstance3D:
		var mi: MeshInstance3D = nodo as MeshInstance3D
		if mi.name == "Balasto" and material_balasto != null:
			mi.material_override = material_balasto
		elif mi.name == "Rieles" and material_riel != null:
			mi.material_override = material_riel
	elif nodo is MultiMeshInstance3D:
		var mmi: MultiMeshInstance3D = nodo as MultiMeshInstance3D
		if mmi.name == "Durmientes" and mmi.multimesh != null and mmi.multimesh.mesh is BoxMesh:
			(mmi.multimesh.mesh as BoxMesh).material = material_durmiente

	for sub: Node in nodo.get_children():
		_aplicar_material_recursivo(sub)

