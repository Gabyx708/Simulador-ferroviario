@tool
extends Node3D
class_name PathGenerador
## Generador procedural de trazas ferroviarias (Path3D) y cambios de vía (CambioDeVia).
##
## Lee vias_godot.json y construye la red ferroviaria completa con curvatura
## continua Catmull-Rom (eliminando ángulos y quiebres duros) y soporte de
## múltiples vías y bifurcaciones/agujas.
##
## Ejecutable en el editor (@tool) para previsualización en tiempo real.
## Compatible con Godot 4.x / 4.7 con tipado estático estricto.

const TURNOUT_SCRIPT = preload("res://scenes/procedural_track/procedural_turnout.gd")

@export_group("Origen de Datos")
## Ruta al archivo JSON con los datos de las curvas de las vías.
@export_file("*.json") var json_path: String = "res://vias_godot.json":
	set(v):
		json_path = v
		if is_inside_tree():
			cargar_vias()

## Intervalo métrico de muestreo para la interpolación de la curva (Curve3D.bake_interval).
@export_range(0.5, 50.0, 0.5, "or_greater") var bake_interval: float = 5.0:
	set(v):
		bake_interval = maxf(0.1, v)
		if is_inside_tree():
			_actualizar_bake_interval()

## Coeficiente de suavizado Catmull-Rom para las tangentes de Curve3D (0.0 = rectas, 0.25-0.33 = curvatura natural).
@export_range(0.0, 0.5, 0.01) var factor_suavizado: float = 0.25:
	set(v):
		factor_suavizado = clampf(v, 0.0, 0.5)
		if is_inside_tree():
			cargar_vias()

@export_group("Cambios de Vía")
## Si está activo, instancia nodos CambioDeVia en las posiciones de agujas detectadas.
@export var generar_cambios_de_via: bool = true:
	set(v):
		generar_cambios_de_via = v
		if is_inside_tree():
			cargar_vias()

@export_group("Editor")
## Si está activo, asigna owner a los nodos generados para que aparezcan en el árbol de escenas del editor.
@export var mostrar_en_arbol_editor: bool = false:
	set(v):
		mostrar_en_arbol_editor = v
		if is_inside_tree():
			cargar_vias()

## Pulsador para forzar la recarga del archivo JSON y reconstruir las vías en el editor.
@export var regenerar: bool = false:
	set(v):
		if v:
			regenerar = false
			if is_inside_tree():
				cargar_vias()


func _ready() -> void:
	cargar_vias()


func _limpiar() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()


func _actualizar_bake_interval() -> void:
	for c: Node in get_children():
		if c is Path3D:
			var p: Path3D = c as Path3D
			if p.curve != null:
				p.curve.bake_interval = bake_interval


func cargar_vias() -> void:
	_limpiar()

	if json_path.is_empty():
		return

	if not FileAccess.file_exists(json_path):
		push_error("PathGenerador: no se encontró el archivo: %s" % json_path)
		return

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("PathGenerador: no se pudo abrir: %s (Error: %s)" % [
			json_path,
			error_string(FileAccess.get_open_error())
		])
		return

	var texto: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(texto)
	if error != OK:
		push_error("PathGenerador: error al parsear JSON (%s): %s en línea %d" % [
			json_path,
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
		push_error("PathGenerador: formato JSON inválido (se esperaba Array o Dictionary).")
		return

	var contador_vias: int = 0
	var root_owner: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var mapa_paths: Dictionary = {}

	for curva_data_raw: Variant in curvas:
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

		var path: Path3D = Path3D.new()
		var raw_name: String = str(curva_data.get("name", ""))
		var tag_name: String = raw_name.validate_node_name() if not raw_name.is_empty() else "via"
		path.name = "Via_%03d_%s" % [contador_vias, tag_name]

		var curve: Curve3D = _construir_curva_suave(puntos_vector)
		curve.bake_interval = bake_interval
		path.curve = curve

		add_child(path)
		mapa_paths[raw_name] = path
		mapa_paths[path.name] = path

		if Engine.is_editor_hint() and mostrar_en_arbol_editor and root_owner != null:
			path.owner = root_owner

		contador_vias += 1

	# Generar nodos CambioDeVia si existen en el JSON
	var contador_switches: int = 0
	if generar_cambios_de_via and switches_data.size() > 0:
		for sw_raw: Variant in switches_data:
			if not (sw_raw is Dictionary):
				continue
			var sw: Dictionary = sw_raw as Dictionary
			var pos_dict: Dictionary = sw.get("position", {}) as Dictionary
			var pos_switch: Vector3 = Vector3(
				float(pos_dict.get("x", 0.0)),
				float(pos_dict.get("y", 0.0)),
				float(pos_dict.get("z", 0.0))
			)

			var nodo_cambio: ProceduralTurnout = TURNOUT_SCRIPT.new()
			var sw_id: String = str(sw.get("id", "switch_%d" % contador_switches)).validate_node_name()
			nodo_cambio.name = "Cambio_%s" % sw_id
			nodo_cambio.position = pos_switch

			# Vincular trazas directa y desviada
			var track_dir_name: String = str(sw.get("track_directa", ""))
			var track_desv_name: String = str(sw.get("track_desviada", ""))

			var p_dir: Path3D = mapa_paths.get(track_dir_name) as Path3D
			var p_desv: Path3D = mapa_paths.get(track_desv_name) as Path3D
			if p_dir != null and p_desv != null:
				nodo_cambio.curva_directa = p_dir.curve
				nodo_cambio.curva_desviada = p_desv.curve
				nodo_cambio.construir_geometria()

			add_child(nodo_cambio)

			if Engine.is_editor_hint() and mostrar_en_arbol_editor and root_owner != null:
				nodo_cambio.owner = root_owner

			contador_switches += 1

	print("PathGenerador: Se generaron %d vías (Path3D) y %d cambios de vía desde %s" % [
		contador_vias,
		contador_switches,
		json_path
	])


## Construye un Curve3D calculando tangentes Catmull-Rom para eliminar curvas duras y quiebres.
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
