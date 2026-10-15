@tool
class_name ShowcaseSwitches
extends Node3D
## Controlador del Laboratorio de Aparatos de Vía (5 Tipos Básicos: A, B, C, D, E).
## Controla 5 bahías con escenas autocontenidas de switches y extremos flexibles
## Path3D editables directamente en el editor de Godot (cero huecos, continuidad G1).

const _SwitchTipoAScene = preload("res://scenes/switches/switch_tipo_a.tscn")
const _SwitchTipoBScene = preload("res://scenes/switches/switch_tipo_b.tscn")
const _SwitchTipoCScene = preload("res://scenes/switches/switch_tipo_c.tscn")
const _SwitchTipoDScene = preload("res://scenes/switches/switch_tipo_d.tscn")
const _SwitchTipoEScene = preload("res://scenes/switches/switch_tipo_e.tscn")
const _CarroScript = preload("res://levels/showcase_switches/carro_prueba.gd")

@export_group("Materiales")
@export var material_riel: Material = null
@export var material_balasto: Material = null
@export var material_durmiente: Material = null
@export var material_metal: Material = null

@export_group("Generación")
@export var regenerar: bool = false:
	set(v):
		if v:
			regenerar = false
			if is_inside_tree():
				reconstruir_geometria_bahias()

# Referencias a los aparatos de vía
var to_a: ProceduralTurnout = null
var to_b: ProceduralSymmetricalTurnout = null
var to_c: ProceduralCrossing = null
var to_d: ProceduralCrossover = null
var to_e: ProceduralScissorsCrossover = null

# Referencias a los carros de prueba
var carro_a: Node = null
var carro_b: Node = null
var carro_c: Node = null
var carro_d: Node = null
var carro_e: Node = null

# Referencias de HUD y Cámara
@export var camara: Camera3D = null
@export var hud: Control = null

# Dimensiones generales
const Z_TALON_ENTRADA: float = -15.0


func _ready() -> void:
	_asegurar_materiales()
	_enlazar_bahias()
	if not Engine.is_editor_hint():
		_conectar_senales()
		call_deferred("_inicializar_carros")


func _asegurar_materiales() -> void:
	if material_riel == null:
		material_riel = ProceduralTrackProfile.obtener_material_defecto("riel")
	if material_balasto == null:
		material_balasto = ProceduralTrackProfile.obtener_material_defecto("balasto")
	if material_durmiente == null:
		material_durmiente = ProceduralTrackProfile.obtener_material_defecto("durmiente")
	if material_metal == null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.22, 0.24, 1.0)
		mat.metallic = 0.85
		mat.roughness = 0.35
		material_metal = mat


## Enlaza las referencias a los nodos de las 5 bahías existentes en el árbol de escena.
func _enlazar_bahias() -> void:
	to_a = get_node_or_null("Bahia_1_Tipo_A/DesvioEstandar_A") as ProceduralTurnout
	to_b = get_node_or_null("Bahia_2_Tipo_B/DesvioSimetrico_B") as ProceduralSymmetricalTurnout
	to_c = get_node_or_null("Bahia_3_Tipo_C/DiamondCrossing_C") as ProceduralCrossing
	to_d = get_node_or_null("Bahia_4_Tipo_D/Crossover_D") as ProceduralCrossover
	to_e = get_node_or_null("Bahia_5_Tipo_E/Bretelle_E") as ProceduralScissorsCrossover

	carro_a = get_node_or_null("Bahia_1_Tipo_A/CarroPrueba_A")
	carro_b = get_node_or_null("Bahia_2_Tipo_B/CarroPrueba_B")
	carro_c = get_node_or_null("Bahia_3_Tipo_C/CarroPrueba_C")
	carro_d = get_node_or_null("Bahia_4_Tipo_D/CarroPrueba_D")
	carro_e = get_node_or_null("Bahia_5_Tipo_E/CarroPrueba_E")

	# Si no están en la escena (fallback si la escena se instancia vacía), construirlas
	if to_a == null or to_b == null or to_c == null or to_d == null or to_e == null:
		construir_bahias()
	else:
		reconstruir_geometria_bahias()


## Reconstruye la geometría 3D de los 5 aparatos respetando sus curvas y ediciones de usuario.
func reconstruir_geometria_bahias() -> void:
	_asegurar_materiales()
	if to_a != null:
		_asignar_materiales(to_a)
		to_a.construir_geometria()
	if to_b != null:
		_asignar_materiales(to_b)
		to_b.construir_geometria()
	if to_c != null:
		_asignar_materiales(to_c)
		to_c.construir_geometria()
	if to_d != null:
		_asignar_materiales(to_d)
		to_d.construir_geometria()
	if to_e != null:
		_asignar_materiales(to_e)
		to_e.construir_geometria()


func _asignar_materiales(aparato: BaseTurnout) -> void:
	if material_riel != null: aparato.material_riel = material_riel
	if material_balasto != null: aparato.material_balasto = material_balasto
	if material_durmiente != null: aparato.material_durmiente = material_durmiente
	if material_metal != null: aparato.material_metal = material_metal


## Construye programáticamente las 5 bahías (utilizado si la escena no posee los nodos hijos).
func construir_bahias() -> void:
	for c: Node in get_children():
		if c.name.begins_with("Bahia_"):
			remove_child(c)
			c.queue_free()

	_asegurar_materiales()
	_construir_bahia_tipo_a()
	_construir_bahia_tipo_b()
	_construir_bahia_tipo_c()
	_construir_bahia_tipo_d()
	_construir_bahia_tipo_e()


# -----------------------------------------------------------------------------
# BAHÍA 1: DESVÍO ESTÁNDAR (TIPO A)
# -----------------------------------------------------------------------------
func _construir_bahia_tipo_a() -> void:
	var nodo_bahia: Node3D = Node3D.new()
	nodo_bahia.name = "Bahia_1_Tipo_A"
	add_child(nodo_bahia)

	var x_base: float = -16.0
	_crear_rotulo_3d(nodo_bahia, Vector3(x_base - 1.0, 3.8, -4.0), "BAHÍA 1: DESVÍO ESTÁNDAR (TIPO A)\n[Recta Principal + Curva Asimétrica]")

	to_a = _SwitchTipoAScene.instantiate() as ProceduralTurnout
	to_a.name = "DesvioEstandar_A"
	to_a.position = Vector3(x_base, 0.0, Z_TALON_ENTRADA)
	_asignar_materiales(to_a)
	nodo_bahia.add_child(to_a)
	to_a.construir_geometria()

	carro_a = _CarroScript.new()
	carro_a.name = "CarroPrueba_A"
	nodo_bahia.add_child(carro_a)


# -----------------------------------------------------------------------------
# BAHÍA 2: DESVÍO SIMÉTRICO EN Y (TIPO B)
# -----------------------------------------------------------------------------
func _construir_bahia_tipo_b() -> void:
	var nodo_bahia: Node3D = Node3D.new()
	nodo_bahia.name = "Bahia_2_Tipo_B"
	add_child(nodo_bahia)

	var x_base: float = 0.0
	_crear_rotulo_3d(nodo_bahia, Vector3(x_base, 3.8, -5.0), "BAHÍA 2: DESVÍO SIMÉTRICO EN Y (TIPO B)\n[Bifurcación Equilátera (+/- θ/2)]")

	to_b = _SwitchTipoBScene.instantiate() as ProceduralSymmetricalTurnout
	to_b.name = "DesvioSimetrico_B"
	to_b.position = Vector3(x_base, 0.0, Z_TALON_ENTRADA)
	_asignar_materiales(to_b)
	nodo_bahia.add_child(to_b)
	to_b.construir_geometria()

	carro_b = _CarroScript.new()
	carro_b.name = "CarroPrueba_B"
	nodo_bahia.add_child(carro_b)


# -----------------------------------------------------------------------------
# BAHÍA 3: DIAMOND CROSSING (TIPO C)
# -----------------------------------------------------------------------------
func _construir_bahia_tipo_c() -> void:
	var nodo_bahia: Node3D = Node3D.new()
	nodo_bahia.name = "Bahia_3_Tipo_C"
	add_child(nodo_bahia)

	var x_centro: float = 14.0
	_crear_rotulo_3d(nodo_bahia, Vector3(x_centro, 4.2, 0.0), "BAHÍA 3: DIAMOND CROSSING (TIPO C)\n[Cruce de Vías en X a Nivel (15°)]")

	to_c = _SwitchTipoCScene.instantiate() as ProceduralCrossing
	to_c.name = "DiamondCrossing_C"
	to_c.position = Vector3(x_centro, 0.0, 0.0)
	_asignar_materiales(to_c)
	nodo_bahia.add_child(to_c)
	to_c.construir_geometria()

	carro_c = _CarroScript.new()
	carro_c.name = "CarroPrueba_C"
	nodo_bahia.add_child(carro_c)


# -----------------------------------------------------------------------------
# BAHÍA 4: ESCAPE EN H / CROSSOVER (TIPO D)
# -----------------------------------------------------------------------------
func _construir_bahia_tipo_d() -> void:
	var nodo_bahia: Node3D = Node3D.new()
	nodo_bahia.name = "Bahia_4_Tipo_D"
	add_child(nodo_bahia)

	var x_centro: float = 30.0
	_crear_rotulo_3d(nodo_bahia, Vector3(x_centro, 4.2, -6.0), "BAHÍA 4: ESCAPE EN H / CROSSOVER (TIPO D)\n[Enlace entre 2 Vías Paralelas con 2 Desvíos Sincronizados]")

	to_d = _SwitchTipoDScene.instantiate() as ProceduralCrossover
	to_d.name = "Crossover_D"
	to_d.position = Vector3(x_centro, 0.0, 0.0)
	_asignar_materiales(to_d)
	nodo_bahia.add_child(to_d)
	to_d.construir_geometria()

	carro_d = _CarroScript.new()
	carro_d.name = "CarroPrueba_D"
	nodo_bahia.add_child(carro_d)


# -----------------------------------------------------------------------------
# BAHÍA 5: ESCAPE DOBLE EN X / BRETELLE (TIPO E)
# -----------------------------------------------------------------------------
func _construir_bahia_tipo_e() -> void:
	var nodo_bahia: Node3D = Node3D.new()
	nodo_bahia.name = "Bahia_5_Tipo_E"
	add_child(nodo_bahia)

	var x_centro: float = 48.0
	_crear_rotulo_3d(nodo_bahia, Vector3(x_centro, 4.2, -6.0), "BAHÍA 5: ESCAPE DOBLE EN X / BRETELLE (TIPO E)\n[Scissors Crossover: 4 Desvíos + Diamante Central (3 Modos)]")

	to_e = _SwitchTipoEScene.instantiate() as ProceduralScissorsCrossover
	to_e.name = "Bretelle_E"
	to_e.position = Vector3(x_centro, 0.0, 0.0)
	_asignar_materiales(to_e)
	nodo_bahia.add_child(to_e)
	to_e.construir_geometria()

	carro_e = _CarroScript.new()
	carro_e.name = "CarroPrueba_E"
	nodo_bahia.add_child(carro_e)


# -----------------------------------------------------------------------------
# RUTAS DINÁMICAS PARA LOS CARROS DE PRUEBA
# -----------------------------------------------------------------------------
func _inicializar_carros() -> void:
	if carro_a != null and to_a != null:
		carro_a.reiniciar_posicion(_obtener_ruta_activa_a())
	if carro_b != null and to_b != null:
		carro_b.reiniciar_posicion(_obtener_ruta_activa_b())
	if carro_c != null and to_c != null:
		carro_c.reiniciar_posicion(_obtener_ruta_activa_c())
	if carro_d != null and to_d != null:
		carro_d.reiniciar_posicion(_obtener_ruta_activa_d())
	if carro_e != null and to_e != null:
		carro_e.reiniciar_posicion(_obtener_ruta_activa_e())


func _obtener_ruta_activa_a() -> Curve3D:
	if to_a != null:
		return to_a.obtener_trayectoria_completa_global()
	return null


func _obtener_ruta_activa_b() -> Curve3D:
	if to_b != null:
		return to_b.obtener_trayectoria_completa_global()
	return null


func _obtener_ruta_activa_c() -> Curve3D:
	if to_c != null:
		return to_c.obtener_trayectoria_completa_global()
	return null


func _obtener_ruta_activa_d() -> Curve3D:
	if to_d != null:
		return to_d.obtener_trayectoria_completa_global()
	return null


func _obtener_ruta_activa_e() -> Curve3D:
	if to_e != null:
		return to_e.obtener_trayectoria_completa_global()
	return null


# -----------------------------------------------------------------------------
# CONTROL Y CONMUTACIÓN
# -----------------------------------------------------------------------------
func conmutar_desvio(tipo: String) -> void:
	match tipo:
		"tipo_a":
			if to_a != null:
				to_a.conmutar()
				if hud != null: hud.actualizar_estado_a(to_a.aguja_desviada)
				if carro_a != null and not carro_a.en_movimiento:
					carro_a.reiniciar_posicion(_obtener_ruta_activa_a())
		"tipo_b":
			if to_b != null:
				to_b.conmutar()
				if hud != null: hud.actualizar_estado_b(to_b.ruta_derecha)
				if carro_b != null and not carro_b.en_movimiento:
					carro_b.reiniciar_posicion(_obtener_ruta_activa_b())
		"tipo_c":
			if to_c != null:
				to_c.conmutar()
				if hud != null: hud.actualizar_estado_c(to_c.via_b_activa)
				if carro_c != null and not carro_c.en_movimiento:
					carro_c.reiniciar_posicion(_obtener_ruta_activa_c())
		"tipo_d":
			if to_d != null:
				to_d.conmutar()
				if hud != null: hud.actualizar_estado_d(to_d.ruta_cruzada)
				if carro_d != null and not carro_d.en_movimiento:
					carro_d.reiniciar_posicion(_obtener_ruta_activa_d())
		"tipo_e":
			if to_e != null:
				to_e.conmutar()
				if hud != null: hud.actualizar_estado_e(int(to_e.modo_ruta))
				if carro_e != null and not carro_e.en_movimiento:
					carro_e.reiniciar_posicion(_obtener_ruta_activa_e())


func lanzar_tren(tipo: String) -> void:
	match tipo:
		"tipo_a":
			if carro_a != null:
				carro_a.asignar_curva_y_lanzar(_obtener_ruta_activa_a())
		"tipo_b":
			if carro_b != null:
				carro_b.asignar_curva_y_lanzar(_obtener_ruta_activa_b())
		"tipo_c":
			if carro_c != null:
				carro_c.asignar_curva_y_lanzar(_obtener_ruta_activa_c())
		"tipo_d":
			if carro_d != null:
				carro_d.asignar_curva_y_lanzar(_obtener_ruta_activa_d())
		"tipo_e":
			if carro_e != null:
				carro_e.asignar_curva_y_lanzar(_obtener_ruta_activa_e())
		"todos":
			lanzar_tren("tipo_a")
			lanzar_tren("tipo_b")
			lanzar_tren("tipo_c")
			lanzar_tren("tipo_d")
			lanzar_tren("tipo_e")


func _conectar_senales() -> void:
	if hud == null:
		return

	hud.conmutar_solicitado.connect(conmutar_desvio)
	hud.lanzar_tren_solicitado.connect(lanzar_tren)

	if camara != null:
		hud.vista_solicitada.connect(func(clave: String) -> void: camara.enfocar_vista(clave))

	if to_a != null:
		to_a.estado_cambiado.connect(func(st: bool) -> void: if hud != null: hud.actualizar_estado_a(st))
	if to_b != null:
		to_b.estado_cambiado.connect(func(st: bool) -> void: if hud != null: hud.actualizar_estado_b(st))
	if to_c != null:
		to_c.estado_cambiado.connect(func(st: bool) -> void: if hud != null: hud.actualizar_estado_c(st))
	if to_d != null:
		to_d.estado_cambiado.connect(func(st: bool) -> void: if hud != null: hud.actualizar_estado_d(st))
	if to_e != null:
		to_e.estado_cambiado.connect(func(modo: int) -> void: if hud != null: hud.actualizar_estado_e(modo))


# -----------------------------------------------------------------------------
# HELPERS DE ROTULACIÓN
# -----------------------------------------------------------------------------
func _crear_rotulo_3d(padre: Node3D, pos: Vector3, texto: String) -> void:
	var lbl: Label3D = Label3D.new()
	lbl.name = "Rotulo3D"
	lbl.text = texto
	lbl.position = pos
	lbl.font_size = 36
	lbl.outline_size = 10
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.modulate = Color(0.95, 0.95, 1.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	padre.add_child(lbl)
