@tool
class_name ProceduralTrackSegment
extends Path3D
## Generador de tramo de vía plena procedural basado en la especificación T:ANE.
## Extruye de forma continua la plataforma de balasto y los dos rieles Vignole,
## y distribuye durmientes individuales respetando zonas de exclusión en desvíos y cruces.

var _bloqueo_reconstruccion: bool = false
var _curva_sucia: bool = false
var _tiempo_sin_cambios: float = 0.0
const TIEMPO_DEBOUNCE: float = 0.12


@export_group("Dimensiones")
## Semitrocha en metros (distancia del centro al riel: 0.838m para trocha ancha Roca).
@export var trocha_media: float = ProceduralTrackProfile.TROCHA_MEDIA_DEFECTO:
	set(v):
		trocha_media = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Paso métrico de muestreo longitudinal para la extrusión de rieles y balasto.
@export_range(0.5, 5.0, 0.25) var paso_muestreo: float = 1.5:
	set(v):
		paso_muestreo = maxf(0.25, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Paso métrico entre durmientes consecutivos (típico 0.65m).
@export_range(0.4, 1.0, 0.05) var paso_durmientes: float = ProceduralTrackProfile.PASO_DURMIENTES:
	set(v):
		paso_durmientes = maxf(0.2, v)
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

## Si es verdadero, detecta automáticamente tramos hermanos a menos de 2.6m y recorta los durmientes interiores para evitar solapes.
@export var evitar_colision_durmientes: bool = true:
	set(v):
		evitar_colision_durmientes = v
		if is_inside_tree() and not _bloqueo_reconstruccion:
			construir_geometria()

@export_group("Materiales")
@export var material_riel: Material = null:
	set(v):
		material_riel = v
		_actualizar_materiales()

@export var material_balasto: Material = null:
	set(v):
		material_balasto = v
		_actualizar_materiales()

@export var material_durmiente: Material = null:
	set(v):
		material_durmiente = v
		_actualizar_materiales()

# Nodos visuales generados
@export_group("Generación")
## Permite forzar la regeneración de la malla desde el Inspector.
@export var regenerar: bool = false:
	set(v):
		if v:
			regenerar = false
			if is_inside_tree():
				_curva_sucia = false
				_cache_puntos_hash = 0
				construir_geometria()

var _cache_puntos_hash: int = 0
var _curva_conectada: Curve3D = null
var _mesh_balasto: MeshInstance3D = null
var _mesh_rieles: MeshInstance3D = null
var _multimesh_durmientes: MultiMeshInstance3D = null

# Zonas métricas [d_inicio, d_fin] donde se suprimen durmientes individuales
var _exclusiones_durmientes: Array[Vector2] = []


func _ready() -> void:
	if not curve_changed.is_connected(_on_path_curve_changed):
		curve_changed.connect(_on_path_curve_changed)
	_conectar_recurso_curva()

	_asegurar_materiales()
	_cache_puntos_hash = _obtener_hash_curva()
	construir_geometria()


func _exit_tree() -> void:
	if _curva_conectada != null and is_instance_valid(_curva_conectada):
		if _curva_conectada.changed.is_connected(_on_curve_resource_changed):
			_curva_conectada.changed.disconnect(_on_curve_resource_changed)
		_curva_conectada = null


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	if curve != null:
		var h: int = _obtener_hash_curva()
		if h != _cache_puntos_hash:
			_cache_puntos_hash = h
			_marcar_curva_sucia()

	if _curva_sucia:
		_tiempo_sin_cambios += delta
		if _tiempo_sin_cambios >= TIEMPO_DEBOUNCE:
			_curva_sucia = false
			construir_geometria()


func _marcar_curva_sucia() -> void:
	if not is_inside_tree() or _bloqueo_reconstruccion:
		return
	_curva_sucia = true
	_tiempo_sin_cambios = 0.0


func _obtener_hash_curva() -> int:
	if curve == null:
		return 0
	var h: int = curve.point_count
	for i in curve.point_count:
		var p: Vector3 = curve.get_point_position(i)
		var pi: Vector3 = curve.get_point_in(i)
		var po: Vector3 = curve.get_point_out(i)
		var t: float = curve.get_point_tilt(i)
		h = hash(h ^ hash(p) ^ hash(pi) ^ hash(po) ^ hash(t))
	return h


func _conectar_recurso_curva() -> void:
	if _curva_conectada != null and is_instance_valid(_curva_conectada):
		if _curva_conectada != curve:
			if _curva_conectada.changed.is_connected(_on_curve_resource_changed):
				_curva_conectada.changed.disconnect(_on_curve_resource_changed)
			_curva_conectada = null

	if curve != null and _curva_conectada == null:
		if not curve.changed.is_connected(_on_curve_resource_changed):
			curve.changed.connect(_on_curve_resource_changed)
		_curva_conectada = curve


func _on_path_curve_changed() -> void:
	_conectar_recurso_curva()
	_marcar_curva_sucia()


func _on_curve_resource_changed() -> void:
	_marcar_curva_sucia()


## Registra un rango longitudinal [d_inicio, d_fin] donde no se instanciarán durmientes individuales.
func agregar_exclusion_durmientes(d_inicio: float, d_fin: float) -> void:
	_exclusiones_durmientes.append(Vector2(minf(d_inicio, d_fin), maxf(d_inicio, d_fin)))


## Limpia las zonas de exclusión de durmientes.
func limpiar_exclusiones() -> void:
	_exclusiones_durmientes.clear()


## Limpia cualquier hijo MeshInstance3D o MultiMeshInstance3D huérfano o duplicado.
func _limpiar_huerfanos() -> void:
	var huerfanos: Array[Node] = []
	for c: Node in get_children():
		if c == _mesh_balasto or c == _mesh_rieles or c == _multimesh_durmientes:
			continue
		if c is MeshInstance3D or c is MultiMeshInstance3D:
			huerfanos.append(c)
	for c: Node in huerfanos:
		remove_child(c)
		c.queue_free()


## Asegura que los nodos visuales (Balasto, Rieles, Durmientes) existan como hijos reutilizables únicos.
func _asegurar_nodos_malla() -> void:
	if _mesh_balasto == null or not is_instance_valid(_mesh_balasto):
		_mesh_balasto = get_node_or_null("Balasto") as MeshInstance3D
		if _mesh_balasto == null:
			_mesh_balasto = MeshInstance3D.new()
			_mesh_balasto.name = "Balasto"
			add_child(_mesh_balasto)

	if _mesh_rieles == null or not is_instance_valid(_mesh_rieles):
		_mesh_rieles = get_node_or_null("Rieles") as MeshInstance3D
		if _mesh_rieles == null:
			_mesh_rieles = MeshInstance3D.new()
			_mesh_rieles.name = "Rieles"
			add_child(_mesh_rieles)

	if _multimesh_durmientes == null or not is_instance_valid(_multimesh_durmientes):
		_multimesh_durmientes = get_node_or_null("Durmientes") as MultiMeshInstance3D
		if _multimesh_durmientes == null:
			_multimesh_durmientes = MultiMeshInstance3D.new()
			_multimesh_durmientes.name = "Durmientes"
			add_child(_multimesh_durmientes)

	_limpiar_huerfanos()


## Limpia las mallas generadas y remueve nodos sobrantes.
func limpiar() -> void:
	if _mesh_balasto != null and is_instance_valid(_mesh_balasto):
		_mesh_balasto.mesh = null
	if _mesh_rieles != null and is_instance_valid(_mesh_rieles):
		_mesh_rieles.mesh = null
	if _multimesh_durmientes != null and is_instance_valid(_multimesh_durmientes):
		_multimesh_durmientes.multimesh = null
	_limpiar_huerfanos()


## Construye la geometría 3D de vía plena (balasto, rieles y durmientes).
func construir_geometria() -> void:
	if _bloqueo_reconstruccion:
		return
	_bloqueo_reconstruccion = true

	if curve == null or curve.point_count < 2:
		limpiar()
		_bloqueo_reconstruccion = false
		return

	var largo_total: float = curve.get_baked_length()
	if largo_total < paso_muestreo * 0.5:
		limpiar()
		_bloqueo_reconstruccion = false
		return

	_asegurar_materiales()
	_asegurar_nodos_malla()

	# 1. Cama de balasto continua
	var m_bal: ArrayMesh = _generar_malla_balasto(largo_total)
	if _mesh_balasto != null and is_instance_valid(_mesh_balasto):
		_mesh_balasto.mesh = m_bal
		_mesh_balasto.material_override = material_balasto

	# 2. Rieles continuos (ambos rieles en una sola malla optimizada)
	var m_rie: ArrayMesh = _generar_malla_rieles(largo_total)
	if _mesh_rieles != null and is_instance_valid(_mesh_rieles):
		_mesh_rieles.mesh = m_rie
		_mesh_rieles.material_override = material_riel

	# 3. Durmientes individuales en vía plena
	_generar_durmientes(largo_total)

	_cache_puntos_hash = _obtener_hash_curva()
	_bloqueo_reconstruccion = false



func _asegurar_materiales() -> void:
	if material_riel == null:
		material_riel = ProceduralTrackProfile.obtener_material_defecto("riel")
	if material_balasto == null:
		material_balasto = ProceduralTrackProfile.obtener_material_defecto("balasto")
	if material_durmiente == null:
		material_durmiente = ProceduralTrackProfile.obtener_material_defecto("durmiente")


func _actualizar_materiales() -> void:
	if _mesh_balasto != null and is_instance_valid(_mesh_balasto):
		_mesh_balasto.material_override = material_balasto
	if _mesh_rieles != null and is_instance_valid(_mesh_rieles):
		_mesh_rieles.material_override = material_riel
	if _multimesh_durmientes != null and is_instance_valid(_multimesh_durmientes) and _multimesh_durmientes.multimesh != null:
		_multimesh_durmientes.material_override = material_durmiente


## Extruye la sección trapezoidal de balasto a lo largo del spline.
func _generar_malla_balasto(largo: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pasos: int = int(ceil(largo / paso_muestreo))
	pasos = maxi(2, pasos)

	var anillos: Array[PackedVector3Array] = []
	var distancias: PackedFloat32Array = PackedFloat32Array()

	var perfil: Array[Vector2] = ProceduralTrackProfile.PERFIL_BALASTO

	# Perímetro UV transversal
	var uv_x: PackedFloat32Array = PackedFloat32Array()
	var acc: float = 0.0
	for i: int in perfil.size():
		uv_x.append(acc)
		acc += perfil[i].distance_to(perfil[(i + 1) % perfil.size()])

	for p: int in pasos + 1:
		var d: float = minf(float(p) * largo / float(pasos), largo)
		var t: Transform3D = _obtener_frame_en_distancia(d, largo)

		var anillo: PackedVector3Array = PackedVector3Array()
		for pt: Vector2 in perfil:
			var vert_local: Vector3 = Vector3(pt.x, pt.y, 0.0)
			anillo.append(t * vert_local)

		anillos.append(anillo)
		distancias.append(d)

	var n_pts: int = perfil.size()
	for p: int in pasos:
		var v0: float = distancias[p]
		var v1: float = distancias[p + 1]

		for i: int in n_pts:
			var j: int = (i + 1) % n_pts
			var a: Vector3 = anillos[p][i]
			var b: Vector3 = anillos[p][j]
			var c: Vector3 = anillos[p + 1][j]
			var e: Vector3 = anillos[p + 1][i]

			var norm: Vector3 = (b - a).cross(c - a).normalized()
			st.set_normal(norm)

			st.set_uv(Vector2(uv_x[i], v0))
			st.add_vertex(a)
			st.set_uv(Vector2(uv_x[j], v0))
			st.add_vertex(b)
			st.set_uv(Vector2(uv_x[j], v1))
			st.add_vertex(c)

			st.set_uv(Vector2(uv_x[i], v0))
			st.add_vertex(a)
			st.set_uv(Vector2(uv_x[j], v1))
			st.add_vertex(c)
			st.set_uv(Vector2(uv_x[i], v1))
			st.add_vertex(e)

	return st.commit()


## Extruye ambos rieles Vignole (izquierdo y derecho) en una sola malla optimizada.
func _generar_malla_rieles(largo: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var pasos: int = int(ceil(largo / paso_muestreo))
	pasos = maxi(2, pasos)

	var perfil: Array[Vector2] = ProceduralTrackProfile.PERFIL_RIEL

	# Perímetro UV transversal
	var uv_x: PackedFloat32Array = PackedFloat32Array()
	var acc: float = 0.0
	for i: int in perfil.size():
		uv_x.append(acc)
		acc += perfil[i].distance_to(perfil[(i + 1) % perfil.size()])

	# Generar para riel izquierdo (-trocha_media) y riel derecho (+trocha_media)
	for offset_riel: float in [-trocha_media, trocha_media]:
		var anillos: Array[PackedVector3Array] = []
		var distancias: PackedFloat32Array = PackedFloat32Array()

		for p: int in pasos + 1:
			var d: float = minf(float(p) * largo / float(pasos), largo)
			var t: Transform3D = _obtener_frame_en_distancia(d, largo)

			var anillo: PackedVector3Array = PackedVector3Array()
			for pt: Vector2 in perfil:
				var vert_local: Vector3 = Vector3(pt.x + offset_riel, pt.y, 0.0)
				anillo.append(t * vert_local)

			anillos.append(anillo)
			distancias.append(d)

		var n_pts: int = perfil.size()
		for p: int in pasos:
			var v0: float = distancias[p]
			var v1: float = distancias[p + 1]

			for i: int in n_pts:
				var j: int = (i + 1) % n_pts
				var a: Vector3 = anillos[p][i]
				var b: Vector3 = anillos[p][j]
				var c: Vector3 = anillos[p + 1][j]
				var e: Vector3 = anillos[p + 1][i]

				var norm: Vector3 = (b - a).cross(c - a).normalized()
				st.set_normal(norm)

				st.set_uv(Vector2(uv_x[i], v0))
				st.add_vertex(a)
				st.set_uv(Vector2(uv_x[j], v0))
				st.add_vertex(b)
				st.set_uv(Vector2(uv_x[j], v1))
				st.add_vertex(c)

				st.set_uv(Vector2(uv_x[i], v0))
				st.add_vertex(a)
				st.set_uv(Vector2(uv_x[j], v1))
				st.add_vertex(c)
				st.set_uv(Vector2(uv_x[i], v1))
				st.add_vertex(e)

	return st.commit()


## Instancia durmientes individuales periódicos utilizando MultiMeshInstance3D.
func _generar_durmientes(largo: float) -> void:
	if _multimesh_durmientes == null or not is_instance_valid(_multimesh_durmientes):
		return

	var total_durmientes: int = int(largo / paso_durmientes)
	if total_durmientes <= 0:
		_multimesh_durmientes.multimesh = null
		return

	# Filtrar los durmientes que caen dentro de alguna exclusión
	var posiciones_validas: Array[float] = []
	for i: int in total_durmientes:
		var d: float = (float(i) + 0.5) * paso_durmientes
		if not _esta_en_exclusion(d):
			posiciones_validas.append(d)

	if posiciones_validas.is_empty():
		_multimesh_durmientes.multimesh = null
		return

	# Detectar tramos hermanos adyacentes para evitar solapes de durmientes
	var hermanos_vias: Array[ProceduralTrackSegment] = []
	if evitar_colision_durmientes and get_parent() != null:
		for h: Node in get_parent().get_children():
			if h != self and h is ProceduralTrackSegment:
				var pts_h: ProceduralTrackSegment = h as ProceduralTrackSegment
				if pts_h.curve != null and pts_h.curve.point_count >= 2:
					hermanos_vias.append(pts_h)

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var caja_std: BoxMesh = BoxMesh.new()
	caja_std.size = ProceduralTrackProfile.TAMANO_DURMIENTE
	mm.mesh = caja_std
	mm.instance_count = posiciones_validas.size()

	for idx: int in posiciones_validas.size():
		var d: float = posiciones_validas[idx]
		var t: Transform3D = _obtener_frame_en_distancia(d, largo)
		var pos_durmiente: Vector3 = t.origin + t.basis.y * (-0.28)

		# Revisar si hay un tramo hermano demasiado cercano (< 2.58m de separación)
		var trim_izq: float = 0.0
		var trim_der: float = 0.0
		if not hermanos_vias.is_empty():
			for hv: ProceduralTrackSegment in hermanos_vias:
				var offset_cercano: float = hv.curve.get_closest_offset(t.origin)
				var p_cercano: Vector3 = hv.curve.sample_baked(offset_cercano)
				var dist_centros: float = t.origin.distance_to(p_cercano)
				if dist_centros < 2.58 and dist_centros > 0.01:
					var dir_a_vecino: Vector3 = p_cercano - t.origin
					var lado_dot: float = t.basis.x.dot(dir_a_vecino)
					var max_voladizo: float = maxf(trocha_media + 0.10, dist_centros * 0.5 - 0.06)
					var exceso: float = 1.30 - max_voladizo
					if exceso > 0.01:
						if lado_dot > 0.0:
							trim_der = maxf(trim_der, exceso)
						else:
							trim_izq = maxf(trim_izq, exceso)

		if trim_izq > 0.0 or trim_der > 0.0:
			var shift_x: float = (trim_izq - trim_der) * 0.5
			var scale_x: float = maxf(0.5, (2.60 - trim_izq - trim_der) / 2.60)
			var b_recortada: Basis = t.basis
			b_recortada.x = b_recortada.x * scale_x
			var t_durmiente: Transform3D = Transform3D(b_recortada, pos_durmiente + t.basis.x * shift_x)
			mm.set_instance_transform(idx, t_durmiente)
		else:
			var t_durmiente: Transform3D = Transform3D(t.basis, pos_durmiente)
			mm.set_instance_transform(idx, t_durmiente)

	_multimesh_durmientes.multimesh = mm
	_multimesh_durmientes.material_override = material_durmiente


func _esta_en_exclusion(d: float) -> bool:
	for exc: Vector2 in _exclusiones_durmientes:
		if d >= exc.x and d <= exc.y:
			return true
	return false


## Obtiene el Transform3D (origen, costado, arriba, adelante) a una distancia métrica dada.
func _obtener_frame_en_distancia(d: float, largo_max: float) -> Transform3D:
	var pos: Vector3 = curve.sample_baked(d, true)
	var fwd: Vector3 = Vector3.FORWARD

	if d <= 0.05 and curve.point_count >= 2 and curve.get_point_out(0).length_squared() > 1e-4:
		fwd = curve.get_point_out(0).normalized()
	elif d >= largo_max - 0.05 and curve.point_count >= 2 and curve.get_point_in(curve.point_count - 1).length_squared() > 1e-4:
		fwd = (-curve.get_point_in(curve.point_count - 1)).normalized()
	else:
		var delta: float = minf(0.2, maxf(0.01, largo_max * 0.2))
		var p_fwd: Vector3 = curve.sample_baked(minf(d + delta, largo_max), true)
		var p_bwd: Vector3 = curve.sample_baked(maxf(d - delta, 0.0), true)
		fwd = (p_fwd - p_bwd).normalized()

	if fwd.length_squared() < 0.5:
		fwd = Vector3.FORWARD

	var up: Vector3 = curve.sample_baked_up_vector(d, true).normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP

	var side: Vector3 = up.cross(fwd).normalized()
	if side.length_squared() < 0.5:
		side = Vector3.RIGHT
	up = fwd.cross(side).normalized()

	var frame_basis: Basis = Basis(side, up, fwd)
	return Transform3D(frame_basis, pos)
