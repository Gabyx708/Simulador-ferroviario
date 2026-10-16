extends Control
class_name NavegacionPaneles
## Botones redondos, abajo-centro, que abren/cierran un panel tipo
## "bottom sheet" sobre la simulación.
##
## FilaBotones, ContenedorPanel y los 4 Button (BotonControl, BotonMetricas,
## BotonEstaciones, BotonTrenes) son nodos reales de hud.tscn -- visibles y
## editables en el editor -- en vez de crearse por código. Este script sólo
## resuelve lo que de verdad necesita cálculo en tiempo real: el tamaño del
## panel abierto según el viewport (_actualizar_tamano_panel), el ancho de la
## fila de botones según cuántos hay, el contenido de cada panel y el estado
## visual activo/inactivo de cada botón.
##
## No contiene lógica de simulación: sólo instancia la escena del panel
## correspondiente y la muestra/oculta. Paleta compartida con el resto del
## HUD (ver hud.gd _estilo_boton_minimalista): panel oscuro, acento ámbar.

signal estacion_seleccionada(estacion: Estacion)

const COLOR_FONDO_PANEL: Color = Color(0.098, 0.106, 0.145, 0.97)
const COLOR_BORDE: Color = Color(1.0, 0.756863, 0.278431, 0.55)
const COLOR_BOTON: Color = Color(0.11, 0.12, 0.16, 0.95)
const COLOR_BOTON_HOVER: Color = Color(0.17, 0.165, 0.12, 0.98)
const COLOR_BOTON_ACTIVO: Color = Color(1.0, 0.756863, 0.278431, 0.92)
const COLOR_TEXTO: Color = Color(0.82, 0.84, 0.90, 1.0)
const COLOR_ACENTO: Color = Color(1.0, 0.756863, 0.278431, 1.0)
const COLOR_BACKDROP: Color = Color(0.0, 0.0, 0.0, 0.55)
const DIAMETRO_BOTON: float = 56.0

## Alto reservado para la fila de botones -- hud.tscn ya trae los offsets
## calculados a mano a partir de esta constante (ver FilaBotones y
## ContenedorPanel ahí); _ready() los vuelve a fijar desde acá así que, si
## este valor cambia, no hace falta tocar el .tscn a mano.
const ALTO_NAVEGACION: float = 74.0
const ANCHO_PANEL: float = 420.0
const ALTO_MAX_PANEL: float = 460.0
const DURACION_ANIM: float = 0.18

## Paneles que se abren como "bottom sheet" chico (por defecto) vs. como
## modal grande centrado (3/4 de pantalla) -- Métricas necesita más espacio
## para tablas, el formulario de control no.
const PANELES_MODAL: Array[String] = ["metricas"]
const MODAL_ANCHO_PCT: float = 0.82
const MODAL_ALTO_PCT: float = 0.82

## Asignadas desde afuera (hud.tscn) una vez que existan las escenas reales.
@export var escena_panel_control: PackedScene
@export var escena_panel_metricas: PackedScene
@export var escena_panel_estaciones: PackedScene
@export var escena_panel_trenes: PackedScene

var _contenedor_panel: Control
var _fila_botones: HBoxContainer
var _botones: Dictionary = {}  ## clave -> Button
var _panel_actual: Control = null
var _clave_actual: String = ""
var _tween_actual: Tween


func _ready() -> void:
	# set_anchors_preset conserva el tamaño "aparente" que el control ya
	# tuviera antes de la llamada (no lo resetea a ocupar todo el padre), así
	# que hay que forzar los offsets a 0 a mano -- si no, el nodo queda más
	# chico que el viewport real y todo lo anclado adentro (los botones,
	# "abajo-centro") termina desplazado hacia arriba-izquierda.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_contenedor_panel = get_node("ContenedorPanel") as Control
	_contenedor_panel.offset_bottom = -(ALTO_NAVEGACION + 24.0)
	_actualizar_tamano_panel()
	get_viewport().size_changed.connect(_actualizar_tamano_panel)

	_fila_botones = get_node("FilaBotones") as HBoxContainer
	_fila_botones.offset_top = -12.0 - ALTO_NAVEGACION

	_conectar_boton("control")
	_conectar_boton("metricas")
	_conectar_boton("estaciones")
	_conectar_boton("trenes")
	var ancho_botones: float = _fila_botones.get_combined_minimum_size().x
	_fila_botones.offset_left = -ancho_botones / 2.0
	_fila_botones.offset_right = ancho_botones / 2.0


func _actualizar_tamano_panel() -> void:
	var pantalla: Vector2 = get_viewport().get_visible_rect().size
	var ancho: float = minf(ANCHO_PANEL, maxf(1.0, pantalla.x - 32.0))
	var alto: float = minf(ALTO_MAX_PANEL, maxf(1.0, pantalla.y + _contenedor_panel.offset_bottom - 12.0))
	_contenedor_panel.offset_left = -ancho / 2.0
	_contenedor_panel.offset_right = ancho / 2.0
	_contenedor_panel.offset_top = _contenedor_panel.offset_bottom - alto


## El botón, su icono y su tooltip ya existen como nodo real en hud.tscn
## (FilaBotones/Boton<Clave>) -- acá sólo se conecta la interacción y se fija
## el estado visual inicial.
func _conectar_boton(clave: String) -> void:
	var boton: Button = _fila_botones.get_node("Boton" + clave.capitalize()) as Button
	boton.pressed.connect(_alternar.bind(clave))
	_aplicar_estilo_boton(boton, false)
	_botones[clave] = boton


func _aplicar_estilo_boton(boton: Button, activo: bool) -> void:
	var normal := _estilo_circular(COLOR_BOTON_ACTIVO if activo else COLOR_BOTON)
	var hover := _estilo_circular(COLOR_BOTON_ACTIVO if activo else COLOR_BOTON_HOVER)
	boton.add_theme_stylebox_override("normal", normal)
	boton.add_theme_stylebox_override("hover", hover)
	boton.add_theme_stylebox_override("pressed", hover)
	boton.add_theme_stylebox_override("hover_pressed", hover)
	boton.add_theme_stylebox_override("focus", _estilo_foco_circular())
	var color_icono: Color = Color(0.1, 0.09, 0.05, 1.0) if activo else COLOR_TEXTO
	boton.add_theme_color_override("icon_normal_color", color_icono)
	boton.add_theme_color_override("icon_hover_color", color_icono)
	boton.add_theme_color_override("icon_pressed_color", color_icono)
	boton.add_theme_color_override("icon_focus_color", color_icono)


func _estilo_circular(color: Color) -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = color
	estilo.set_corner_radius_all(int(DIAMETRO_BOTON / 2.1))
	estilo.border_width_left = 1
	estilo.border_width_top = 1
	estilo.border_width_right = 1
	estilo.border_width_bottom = 1
	estilo.border_color = COLOR_BORDE
	estilo.shadow_size = 6
	estilo.shadow_color = Color(0, 0, 0, 0.35)
	return estilo


func _estilo_foco_circular() -> StyleBoxFlat:
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color.TRANSPARENT
	estilo.set_corner_radius_all(int(DIAMETRO_BOTON / 2.1))
	estilo.set_border_width_all(2)
	estilo.border_color = COLOR_ACENTO
	return estilo


func _alternar(clave: String) -> void:
	if _clave_actual == clave:
		_cerrar_panel()
		return
	_cerrar_panel()
	_clave_actual = clave
	_aplicar_estilo_boton(_botones[clave] as Button, true)
	var contenido: Control = _instanciar_contenido(clave)
	if clave in PANELES_MODAL:
		_panel_actual = _construir_modal(contenido)
		add_child(_panel_actual)
		# El fondo del modal ocupa toda la pantalla. Mantener la fila de accesos
		# rápidos al frente para que siga visible y reciba clics.
		move_child(_fila_botones, get_child_count() - 1)
		_animar_apertura_modal(_panel_actual)
	else:
		_panel_actual = _envolver_en_hoja(contenido)
		_contenedor_panel.add_child(_panel_actual)
		_animar_apertura(_panel_actual)


func _instanciar_contenido(clave: String) -> Control:
	var escena: PackedScene = null
	match clave:
		"control":
			escena = escena_panel_control
		"metricas":
			escena = escena_panel_metricas
		"estaciones":
			escena = escena_panel_estaciones
		"trenes":
			escena = escena_panel_trenes
	if escena != null:
		var contenido: Control = escena.instantiate() as Control
		if contenido is PanelEstaciones:
			contenido.estacion_elegida.connect(_on_estacion_elegida)
		if contenido.has_signal("cierre_solicitado"):
			contenido.connect("cierre_solicitado", _cerrar_panel)
		return contenido
	var etiqueta := Label.new()
	etiqueta.text = "Panel no disponible"
	etiqueta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	etiqueta.add_theme_color_override("font_color", COLOR_TEXTO)
	etiqueta.add_theme_font_size_override("font_size", 14)
	return etiqueta


func _on_estacion_elegida(estacion: Estacion) -> void:
	if not is_instance_valid(estacion):
		return
	_cerrar_panel()
	estacion_seleccionada.emit(estacion)


## Modal grande centrado (ver PANELES_MODAL): fondo oscurecido clickeable
## (cierra el panel) + tarjeta de MODAL_ANCHO_PCT x MODAL_ALTO_PCT de la
## pantalla, con su propio título y botón "✕" -- los botones redondos
## quedan tapados mientras el modal está abierto, así que necesita su
## propio cierre explícito.
func _construir_modal(contenido: Control) -> Control:
	var raiz := Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.offset_left = 0.0
	raiz.offset_top = 0.0
	raiz.offset_right = 0.0
	raiz.offset_bottom = 0.0

	var fondo := Button.new()
	fondo.name = "FondoModal"
	fondo.flat = true
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fondo.offset_left = 0.0
	fondo.offset_top = 0.0
	fondo.offset_right = 0.0
	fondo.offset_bottom = 0.0
	fondo.focus_mode = Control.FOCUS_NONE
	var estilo_fondo := StyleBoxFlat.new()
	estilo_fondo.bg_color = COLOR_BACKDROP
	fondo.add_theme_stylebox_override("normal", estilo_fondo)
	fondo.add_theme_stylebox_override("hover", estilo_fondo)
	fondo.add_theme_stylebox_override("pressed", estilo_fondo)
	fondo.add_theme_stylebox_override("focus", estilo_fondo)
	fondo.pressed.connect(_cerrar_panel)
	raiz.add_child(fondo)

	var margen_h: float = (1.0 - MODAL_ANCHO_PCT) / 2.0
	var margen_v: float = (1.0 - MODAL_ALTO_PCT) / 2.0
	var tarjeta := PanelContainer.new()
	tarjeta.anchor_left = margen_h
	tarjeta.anchor_right = 1.0 - margen_h
	tarjeta.anchor_top = margen_v
	tarjeta.anchor_bottom = 1.0 - margen_v
	tarjeta.offset_left = 0.0
	tarjeta.offset_top = 0.0
	tarjeta.offset_right = 0.0
	tarjeta.offset_bottom = 0.0
	var estilo_tarjeta := StyleBoxFlat.new()
	estilo_tarjeta.bg_color = COLOR_FONDO_PANEL
	estilo_tarjeta.border_width_top = 1
	estilo_tarjeta.border_width_left = 1
	estilo_tarjeta.border_width_right = 1
	estilo_tarjeta.border_width_bottom = 1
	estilo_tarjeta.border_color = COLOR_BORDE
	estilo_tarjeta.set_corner_radius_all(12)
	estilo_tarjeta.content_margin_left = 20
	estilo_tarjeta.content_margin_right = 20
	estilo_tarjeta.content_margin_top = 16
	estilo_tarjeta.content_margin_bottom = 16
	estilo_tarjeta.shadow_size = 16
	estilo_tarjeta.shadow_color = Color(0, 0, 0, 0.5)
	tarjeta.add_theme_stylebox_override("panel", estilo_tarjeta)
	raiz.add_child(tarjeta)
	raiz.set_meta("tarjeta", tarjeta)

	var columna := VBoxContainer.new()
	columna.add_theme_constant_override("separation", 10)
	tarjeta.add_child(columna)

	var encabezado := HBoxContainer.new()
	columna.add_child(encabezado)
	var titulo := Label.new()
	titulo.text = "MÉTRICAS"
	titulo.add_theme_font_size_override("font_size", 16)
	titulo.add_theme_color_override("font_color", COLOR_ACENTO)
	titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encabezado.add_child(titulo)
	var boton_cerrar := Button.new()
	boton_cerrar.name = "BotonCerrarModal"
	boton_cerrar.text = "✕"
	boton_cerrar.tooltip_text = "Cerrar métricas"
	boton_cerrar.flat = true
	boton_cerrar.add_theme_font_size_override("font_size", 12)
	boton_cerrar.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75, 1.0))
	boton_cerrar.pressed.connect(_cerrar_panel)
	encabezado.add_child(boton_cerrar)
	columna.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columna.add_child(scroll)
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contenido)

	return raiz


func _envolver_en_hoja(contenido: Control) -> Control:
	var hoja := PanelContainer.new()
	hoja.set_anchors_preset(Control.PRESET_FULL_RECT)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = COLOR_FONDO_PANEL
	estilo.border_width_top = 1
	estilo.border_width_left = 1
	estilo.border_width_right = 1
	estilo.border_width_bottom = 1
	estilo.border_color = COLOR_BORDE
	estilo.set_corner_radius_all(10)
	estilo.content_margin_left = 16
	estilo.content_margin_right = 16
	estilo.content_margin_top = 14
	estilo.content_margin_bottom = 14
	estilo.shadow_size = 10
	estilo.shadow_color = Color(0, 0, 0, 0.4)
	hoja.add_theme_stylebox_override("panel", estilo)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hoja.add_child(scroll)
	contenido.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contenido)
	return hoja


func _cerrar_panel() -> void:
	if _tween_actual != null and _tween_actual.is_valid():
		_tween_actual.kill()
	if _clave_actual != "" and _botones.has(_clave_actual):
		_aplicar_estilo_boton(_botones[_clave_actual] as Button, false)
	if _panel_actual != null and is_instance_valid(_panel_actual):
		_panel_actual.queue_free()
	_panel_actual = null
	_clave_actual = ""


func _animar_apertura(panel: Control) -> void:
	if _tween_actual != null and _tween_actual.is_valid():
		_tween_actual.kill()
	panel.modulate.a = 0.0
	panel.pivot_offset = Vector2(panel.size.x / 2.0, panel.size.y)
	panel.scale = Vector2(1.0, 0.92)
	_tween_actual = create_tween().set_parallel(true)
	_tween_actual.tween_property(panel, "modulate:a", 1.0, DURACION_ANIM)
	_tween_actual.tween_property(panel, "scale", Vector2.ONE, DURACION_ANIM).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Igual que _animar_apertura, pero para un modal: no tiene sentido que
## "crezca desde abajo" como el bottom sheet -- se desvanece el fondo
## completo y la tarjeta escala desde su propio centro, no desde el borde
## de la pantalla.
func _animar_apertura_modal(raiz: Control) -> void:
	if _tween_actual != null and _tween_actual.is_valid():
		_tween_actual.kill()
	var tarjeta: Control = raiz.get_meta("tarjeta", null) as Control
	raiz.modulate.a = 0.0
	_tween_actual = create_tween().set_parallel(true)
	_tween_actual.tween_property(raiz, "modulate:a", 1.0, DURACION_ANIM)
	if tarjeta != null:
		tarjeta.pivot_offset = tarjeta.size / 2.0
		tarjeta.scale = Vector2(0.96, 0.96)
		_tween_actual.tween_property(tarjeta, "scale", Vector2.ONE, DURACION_ANIM).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Para tests: clave del panel abierto actualmente, o "" si ninguno.
func panel_abierto() -> String:
	return _clave_actual
