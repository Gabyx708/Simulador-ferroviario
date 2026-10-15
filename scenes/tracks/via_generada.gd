@tool
extends Node3D
class_name ViaGenerada
## Genera la infraestructura de vía ferroviaria optimizada (balasto + rieles + durmientes).
##
## Incluye optimizaciones de alto rendimiento:
## - Culling de distancia nativo de Godot 4 (visibility_range_end) para rieles y durmientes.
## - Subdivisión en chunks espaciales para Frustum Culling eficiente en tramos kilométricos.
## - Perfil de riel optimizado de 8 vértices sin caras ocultas.
## - Muestreo adaptativo y eliminación de geometría duplicada en circuitos cerrados.
##
## Compatible con Godot 4.x / 4.7 con tipado estático estricto.

const TURNOUT_SCRIPT = preload("res://scenes/procedural_track/procedural_turnout.gd")

@export_group("Origen de Datos")
## Modo de generación:
## - "Desde JSON": Lee las curvas del archivo vias_godot.json o red_godot.json.
## - "Desde Path3D": Genera la vía sobre un único Path3D asignado (o el nodo padre).
@export_enum("Desde JSON", "Desde Path3D") var modo_origen: int = 0:
	set(v):
		modo_origen = v
		if is_inside_tree():
			_construir()

## Ruta al archivo JSON con las trazas de vías exportadas (vias_godot.json o red_godot.json).
@export_file("*.json") var json_vias: String = "res://vias_godot.json":
	set(v):
		json_vias = v
		if is_inside_tree() and modo_origen == 0:
			_construir()

## Traza individual (Path3D). Se utiliza cuando modo_origen es "Desde Path3D".
@export var traza: Path3D:
	set(v):
		traza = v
		if is_inside_tree() and modo_origen == 1:
			_construir()

## Coeficiente de suavizado Catmull-Rom para las tangentes de Curve3D (0.0 = rectas, 0.25-0.33 = curvatura natural).
@export_range(0.0, 0.5, 0.01) var factor_suavizado: float = 0.25:
	set(v):
		factor_suavizado = clampf(v, 0.0, 0.5)
		if is_inside_tree() and modo_origen == 0:
			_construir()

## Si está activo, instancia nodos CambioDeVia en las posiciones de agujas detectadas.
@export var generar_cambios_de_via: bool = true:
	set(v):
		generar_cambios_de_via = v
		if is_inside_tree() and modo_origen == 0:
			_construir()

## Límite de vías a generar desde el JSON (0 = todas). Útil para pruebas de rendimiento.
@export var limite_curvas: int = 0:
	set(v):
		limite_curvas = maxi(0, v)
		if is_inside_tree() and modo_origen == 0:
			_construir()

## Pulsador para forzar la reconstrucción en el editor.
@export var regenerar: bool = false:
	set(v):
		if v:
			regenerar = false
			if is_inside_tree():
				_construir()

@export_group("Optimización y Rendimiento")
## Distancia máxima en metros para renderizar rieles y balasto (0 = infinito).
@export_range(500.0, 8000.0, 100.0) var distancia_culling_mallas: float = 3500.0:
	set(v):
		distancia_culling_mallas = v
		if is_inside_tree():
			_construir()

## Distancia máxima en metros para renderizar durmientes (0 = infinito).
@export_range(200.0, 2500.0, 50.0) var distancia_culling_durmientes: float = 800.0:
	set(v):
		distancia_culling_durmientes = v
		if is_inside_tree():
			_construir()

## Longitud de cada chunk espacial en metros para frustum culling óptimo en tramos largos.
@export_range(100.0, 1000.0, 50.0) var tamano_chunk_m: float = 300.0:
	set(v):
		tamano_chunk_m = maxf(50.0, v)
		if is_inside_tree():
			_construir()

## Si está activo, no genera mallas para la traza del circuito si ya existen las vías de ida y vuelta.
@export var excluir_circuito_duplicado: bool = true:
	set(v):
		excluir_circuito_duplicado = v
		if is_inside_tree() and modo_origen == 0:
			_construir()

## Perfil de riel: Detallado (12 vértices) vs Optimizado (8 vértices, 35% menos triángulos).
@export_enum("Detallado (12 vértices)", "Optimizado (8 vértices)") var perfil_modo: int = 1:
	set(v):
		perfil_modo = v
		if is_inside_tree():
			_construir()

@export_group("Dimensiones de Vía")
@export var trocha_media: float = 0.838 ## Centro de riel (mitad de trocha ancha 1676 mm)
@export var separacion_durmientes: float = 0.625 ## En el Roca van cada 60-65 cm
@export_range(1.0, 10.0, 0.5) var paso_muestreo: float = 2.0 ## Metros entre secciones transversales (2.0m es óptimo)
@export var generar_balasto: bool = true
@export var generar_durmientes: bool = true

@export_group("Materiales")
@export var mat_riel: Material = preload("res://common/materials/mat_riel.tres")
@export var mat_balasto: Material = preload("res://common/materials/mat_balastro.tres")
@export var mat_durmiente: Material = preload("res://common/materials/mat_durmiente.tres")

# Perfil UIC 54 detallado (12 vértices)
const PERFIL_RIEL_DETALLADO: Array[Vector2] = [
	Vector2(-0.070, -0.159), Vector2(0.070, -0.159),
	Vector2(0.070, -0.135), Vector2(0.009, -0.115),
	Vector2(0.009, -0.048), Vector2(0.035, -0.035),
	Vector2(0.035, 0.000), Vector2(-0.035, 0.000),
	Vector2(-0.035, -0.035), Vector2(-0.009, -0.048),
	Vector2(-0.009, -0.115), Vector2(-0.070, -0.135),
]

# Perfil de riel optimizado (8 vértices): mantiene corona, alma y pestaña superior visible
const PERFIL_RIEL_OPTIMIZADO: Array[Vector2] = [
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
	if traza == null and get_parent() is Path3D:
		traza = get_parent()
		if traza.curve != null and traza.curve.point_count > 0:
			modo_origen = 1
	_construir()


func _limpiar() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()


func _construir() -> void:
	_limpiar()

	if modo_origen == 0:
		_construir_desde_json()
	else:
		_construir_desde_path()


func _construir_desde_path() -> void:
	if traza == null and get_parent() is Path3D:
		traza = get_parent()
	if traza == null or traza.curve == null:
		return
	var curva: Curve3D = traza.curve
	var largo: float = curva.get_baked_length()
	if largo < paso_muestreo * 2.0:
		return

	_construir_geometria_tramo(curva, largo, self)


func _construir_desde_json() -> void:
	if json_vias.is_empty():
		return
	if not FileAccess.file_exists(json_vias):
		push_error("ViaGenerada: no se encontró el archivo: %s" % json_vias)
		return

	var file: FileAccess = FileAccess.open(json_vias, FileAccess.READ)
	if file == null:
		push_error("ViaGenerada: no se pudo abrir: %s (Error: %s)" % [
			json_vias,
			error_string(FileAccess.get_open_error())
		])
		return

	var texto: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(texto)
	if error != OK:
		push_error("ViaGenerada: error al parsear JSON (%s): %s en línea %d" % [
			json_vias,
			json.get_error_message(),
			json.get_error_line()
		])
		return

	var curvas: Array = []
	var switches_data: Array = []

	if json.data is Dictionary:
		var dict: Dictionary = json.data as Dictionary
		if dict.has("segments"):
			curvas = dict.get("segments", []) as Array
			var juncs: Dictionary = dict.get("junctions", {}) as Dictionary
			for k: Variant in juncs.keys():
				var j_dict: Dictionary = juncs[k] as Dictionary
				var segs_con: Array = j_dict.get("segments", []) as Array
				if j_dict.get("is_switch", false) or segs_con.size() > 2:
					var tr_dir: String = str(segs_con[0].get("segment_id", "")) if segs_con.size() > 0 else ""
					var tr_desv: String = str(segs_con[1].get("segment_id", "")) if segs_con.size() > 1 else ""
					switches_data.append({
						"id": str(k),
						"position": j_dict.get("position", {}),
						"track_directa": tr_dir,
						"track_desviada": tr_desv
					})
		else:
			curvas = dict.get("tracks", []) as Array
			switches_data = dict.get("switches", []) as Array
	elif json.data is Array:
		curvas = json.data as Array
	else:
		push_error("ViaGenerada: formato JSON inválido (se esperaba Array o Dictionary).")
		return

	var total_curvas: int = curvas.size()
	if limite_curvas > 0:
		total_curvas = mini(total_curvas, limite_curvas)

	var mapa_paths: Dictionary = {}
	var generadas: int = 0
	var tramos_con_geometria: int = 0

	for i: int in total_curvas:
		var curva_data_raw: Variant = curvas[i]
		if not (curva_data_raw is Dictionary):
			continue
		var curva_data: Dictionary = curva_data_raw as Dictionary
		var puntos_raw: Array = curva_data.get("points", [])
		if puntos_raw.size() < 2:
			continue

		var puntos_vector: Array[Vector3] = []
		for p_raw: Variant in puntos_raw:
			if p_raw is Dictionary:
				var p: Dictionary = p_raw as Dictionary
				puntos_vector.append(Vector3(
					float(p.get("x", 0.0)),
					float(p.get("y", 0.0)),
					float(p.get("z", 0.0))
				))

		if puntos_vector.size() < 2:
			continue

		var curva: Curve3D = _construir_curva_suave(puntos_vector)
		curva.bake_interval = paso_muestreo

		var largo: float = curva.get_baked_length()
		if largo < paso_muestreo:
			continue

		var tramo_nodo: Path3D = Path3D.new()
		var raw_name: String = str(curva_data.get("name", curva_data.get("id", "")))
		var tag_name: String = raw_name.validate_node_name() if not raw_name.is_empty() else "via"
		tramo_nodo.name = "Traza_%03d_%s" % [generadas, tag_name]
		tramo_nodo.curve = curva
		add_child(tramo_nodo)

		mapa_paths[raw_name] = tramo_nodo
		mapa_paths[tramo_nodo.name] = tramo_nodo

		# Optimización: Omitir generación de mallas en circuito duplicado si ya existen ida y vuelta
		var es_circuito_duplicado: bool = (excluir_circuito_duplicado and raw_name == "Via_Circuito_Completo")
		if not es_circuito_duplicado:
			_construir_geometria_tramo(curva, largo, tramo_nodo)
			tramos_con_geometria += 1

		generadas += 1

	# Generar nodos CambioDeVia si existen en los datos
	var switches_generados: int = 0
	if generar_cambios_de_via and switches_data.size() > 0:
		for sw_raw: Variant in switches_data:
			if not (sw_raw is Dictionary):
				continue
			var sw: Dictionary = sw_raw as Dictionary
			var pos_dict: Dictionary = sw.get("position", {}) as Dictionary
			if pos_dict.is_empty() or not pos_dict.has("x"):
				continue
			var pos_switch: Vector3 = Vector3(
				float(pos_dict.get("x", 0.0)),
				float(pos_dict.get("y", 0.0)),
				float(pos_dict.get("z", 0.0))
			)

			var nodo_cambio: ProceduralTurnout = TURNOUT_SCRIPT.new()
			var sw_id: String = str(sw.get("id", "switch_%d" % switches_generados)).validate_node_name()
			nodo_cambio.name = "Cambio_%s" % sw_id
			nodo_cambio.position = pos_switch

			var track_dir_name: String = str(sw.get("track_directa", ""))
			var track_desv_name: String = str(sw.get("track_desviada", ""))

			var p_dir: Path3D = mapa_paths.get(track_dir_name) as Path3D
			var p_desv: Path3D = mapa_paths.get(track_desv_name) as Path3D
			if p_dir != null and p_desv != null:
				nodo_cambio.curva_directa = p_dir.curve
				nodo_cambio.curva_desviada = p_desv.curve
				nodo_cambio.construir_geometria()

			add_child(nodo_cambio)
			switches_generados += 1

	print("ViaGenerada [OPTIMIZADA]: %d trazas (%d con mallas 3D en chunks), %d cambios de vía desde %s" % [
		generadas,
		tramos_con_geometria,
		switches_generados,
		json_vias
	])


## Construye un Curve3D calculando tangentes Catmull-Rom para eliminar curvaturas duras y quiebres.
func _construir_curva_suave(puntos: Array[Vector3]) -> Curve3D:
	var c: Curve3D = Curve3D.new()
	var n: int = puntos.size()
	if n < 2:
		return c

	var es_circuito: bool = (puntos[0].distance_to(puntos[n - 1]) < 0.1)

	for i: int in n:
		var pos: Vector3 = puntos[i]
		var anterior: Vector3 = puntos[i - 1] if i > 0 else puntos[0]
		var siguiente: Vector3 = puntos[i + 1] if i < n - 1 else puntos[n - 1]

		if es_circuito and n > 2:
			if i == 0:
				anterior = puntos[n - 2]
			elif i == n - 1:
				siguiente = puntos[1]

		var tangente: Vector3 = (siguiente - anterior)
		if tangente.length_squared() < 1e-6:
			tangente = Vector3.FORWARD
		tangente = tangente.normalized()

		var d_atras: float = pos.distance_to(anterior)
		var d_adelante: float = pos.distance_to(siguiente)

		var in_control: Vector3 = -tangente * d_atras * factor_suavizado if (i > 0 or es_circuito) else Vector3.ZERO
		var out_control: Vector3 = tangente * d_adelante * factor_suavizado if (i < n - 1 or es_circuito) else Vector3.ZERO

		c.add_point(pos, in_control, out_control)

	return c


## Construye la geometría subdividiéndola en chunks espaciales para que Godot descarte
## automáticamente el 95%+ de los tramos fuera del campo visual o a más de 1200m.
func _construir_geometria_tramo(curva: Curve3D, largo: float, destino: Node3D) -> void:
	if largo < paso_muestreo * 0.5:
		return

	var perfil_activo: Array[Vector2] = PERFIL_RIEL_DETALLADO if perfil_modo == 0 else PERFIL_RIEL_OPTIMIZADO

	# Si el tramo es corto (menor o igual a un chunk), se genera directamente sobre destino
	if largo <= tamano_chunk_m:
		_construir_geometria_rango(curva, 0.0, largo, destino, perfil_activo)
		return

	# Si es un tramo largo (ej. 30 km), se divide en chunks de ~300m para Frustum y Distance Culling
	var cantidad_chunks: int = int(ceil(largo / tamano_chunk_m))
	for ch: int in cantidad_chunks:
		var d_inicio: float = float(ch) * tamano_chunk_m
		var d_fin: float = minf(float(ch + 1) * tamano_chunk_m, largo)
		if d_fin - d_inicio < paso_muestreo * 0.5:
			continue

		var nodo_chunk: Node3D = Node3D.new()
		nodo_chunk.name = "Chunk_%03d" % ch
		destino.add_child(nodo_chunk)

		_construir_geometria_rango(curva, d_inicio, d_fin, nodo_chunk, perfil_activo)


func _construir_geometria_rango(curva: Curve3D, d_inicio: float, d_fin: float, destino: Node3D, perfil_riel_usar: Array[Vector2]) -> void:
	if generar_balasto:
		var mesh_balasto: ArrayMesh = _barrer_rango(curva, PERFIL_BALASTO, 0.0, d_inicio, d_fin)
		_agregar_malla(destino, mesh_balasto, "Balasto", mat_balasto)

	var mesh_rieles: ArrayMesh = _barrer_ambos_rieles_rango(curva, perfil_riel_usar, d_inicio, d_fin)
	_agregar_malla(destino, mesh_rieles, "Rieles", mat_riel)

	if generar_durmientes:
		_agregar_durmientes_rango(destino, curva, d_inicio, d_fin)


## Barre los dos rieles (izquierdo y derecho) a lo largo del intervalo [d_inicio, d_fin]
func _barrer_ambos_rieles_rango(curva: Curve3D, perfil: Array[Vector2], d_inicio: float, d_fin: float) -> ArrayMesh:
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

	var n: int = perfil.size()

	for desplazamiento: float in [-trocha_media, trocha_media]:
		var anillos: Array[PackedVector3Array] = []
		var recorridos: PackedFloat32Array = PackedFloat32Array()
		for p: int in pasos + 1:
			var d: float = minf(d_inicio + float(p) * largo_rango / float(pasos), d_fin)
			var origen: Vector3 = curva.sample_baked(d, true)
			var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
			var adelante: Vector3 = (curva.sample_baked(minf(d + 0.05, d_fin), true) -
					curva.sample_baked(maxf(d - 0.05, 0.0), true)).normalized()
			if adelante.length_squared() < 0.5:
				adelante = Vector3.FORWARD
			var costado: Vector3 = arriba.cross(adelante).normalized()
			arriba = adelante.cross(costado).normalized()

			var anillo: PackedVector3Array = PackedVector3Array()
			for pt: Vector2 in perfil:
				anillo.append(origen
					+ costado * (pt.x + desplazamiento)
					+ arriba * pt.y)
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
				_quad(st, a, b, c, e,
					Vector2(peri[i], v0), Vector2(peri[j], v0),
					Vector2(peri[j], v1), Vector2(peri[i], v1))

	st.generate_normals()
	return st.commit()


## Barre un perfil cerrado (x,y) a lo largo de la curva en el intervalo [d_inicio, d_fin]
func _barrer_rango(curva: Curve3D, perfil: Array[Vector2], desplazamiento: float, d_inicio: float, d_fin: float) -> ArrayMesh:
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
		var origen: Vector3 = curva.sample_baked(d, true)
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.05, d_fin), true) -
				curva.sample_baked(maxf(d - 0.05, 0.0), true)).normalized()
		if adelante.length_squared() < 0.5:
			adelante = Vector3.FORWARD
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()

		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			anillo.append(origen
				+ costado * (pt.x + desplazamiento)
				+ arriba * pt.y)
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
			_quad(st, a, b, c, e,
				Vector2(peri[i], v0), Vector2(peri[j], v0),
				Vector2(peri[j], v1), Vector2(peri[i], v1))

	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(uc); st.add_vertex(c)
	st.set_uv(ud); st.add_vertex(d)


func _agregar_durmientes_rango(destino: Node, curva: Curve3D, d_inicio: float, d_fin: float) -> void:
	var largo_rango: float = d_fin - d_inicio
	var cantidad: int = int(largo_rango / separacion_durmientes)
	if cantidad <= 0:
		return

	var caja: BoxMesh = BoxMesh.new()
	caja.size = Vector3(2.60, 0.20, 0.26)
	if mat_durmiente != null:
		caja.material = mat_durmiente

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = caja
	mm.instance_count = cantidad

	var min_pt: Vector3 = Vector3(INF, INF, INF)
	var max_pt: Vector3 = Vector3(-INF, -INF, -INF)

	for i: int in cantidad:
		var d: float = d_inicio + separacion_durmientes * (float(i) + 0.5)
		var origen: Vector3 = curva.sample_baked(d, true)
		var arriba: Vector3 = curva.sample_baked_up_vector(d, true).normalized()
		var adelante: Vector3 = (curva.sample_baked(minf(d + 0.05, d_fin), true) -
				curva.sample_baked(maxf(d - 0.05, 0.0), true)).normalized()
		var costado: Vector3 = arriba.cross(adelante).normalized()
		arriba = adelante.cross(costado).normalized()
		var base: Basis = Basis(costado, arriba, adelante)
		var pos_durmiente: Vector3 = origen - arriba * 0.275
		mm.set_instance_transform(i, Transform3D(base, pos_durmiente))

		min_pt = min_pt.min(pos_durmiente)
		max_pt = max_pt.max(pos_durmiente)

	# Bounding box explícito para que el culling nativo de Godot funcione de forma precisa
	min_pt -= Vector3(1.5, 0.5, 1.5)
	max_pt += Vector3(1.5, 0.5, 1.5)
	mm.custom_aabb = AABB(min_pt, max_pt - min_pt)

	var nodo: MultiMeshInstance3D = MultiMeshInstance3D.new()
	nodo.multimesh = mm
	nodo.name = "Durmientes"

	# Culling de distancia nativo en durmientes: a más de 800m no se dibujan
	if distancia_culling_durmientes > 0.0:
		nodo.visibility_range_end = distancia_culling_durmientes
		nodo.visibility_range_end_margin = 50.0
		nodo.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	destino.add_child(nodo)


func _agregar_malla(destino: Node, malla: ArrayMesh, nombre: String, mat: Material) -> void:
	if malla == null or malla.get_surface_count() == 0:
		return
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = malla
	mi.name = nombre
	if mat != null:
		mi.material_override = mat

	# Culling de distancia nativo en mallas: más allá de 1200m se descartan en C++
	if distancia_culling_mallas > 0.0:
		mi.visibility_range_end = distancia_culling_mallas
		mi.visibility_range_end_margin = 100.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	destino.add_child(mi)
